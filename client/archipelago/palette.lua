-- Palette randomizer. Every recoloured sprite goes through the game's colour swap shader: Shader.setColorSwapper
-- (deferred), setColorSwapperWithHaze and sendColorVectors (Kai, instant) send a 6-colour base palette and the
-- colours to draw it with. The colours sent are hue-rotated here, so shading stays the same and only the hue
-- changes. The rotations come from the seed name and slot, so a seed always looks the same.
--   kai: only Kai (base palette Colors.Sprites.kai: body, scarf, hurt flashes, after images).
--   everything: also enemies, bosses and NPCs, each palette with its own hue. UI swaps are left alone. Enemies
--     normally draw their raw art and only use the swap shader while flashing (bosses always do), so
--     alwaysUsePaletteShader is set on BaseObject; middleclass passes it down to every subclass.
--     NPCs (editorLoaded/npcs) draw raw art with no swap at all, and their PALETTE doesn't always
--     cover the art (the swap shader draws other colours black), so their draw is wrapped in a hue shader instead.
local client = require("archipelago.client")
local log = require("archipelago.log")
local bit = require("bit")

-- settings is replaced by the F9 panel's table; palette is "auto" (the YAML), "off", "kai" or "everything"
local P = { settings = { palette = "auto" } }

local SETTING_MODE = { off = 0, kai = 1, everything = 2 }
local MIN_SHIFT, SPAN = 40, 280 -- rotations stay between 40 and 320 degrees, so the change is visible

local installed = false
local forcedShader = false
local trapUntil, nextReroll = nil, 0
local TRAP_REROLL = 2
local hueShader, hueTried = nil, false
local wrappedNpcs = setmetatable({}, { __mode = "k" })
local nextScan = 0
local SCAN_SECONDS = 2
-- NPC classes by name. Kernel and the rescuable bots set their own swap shader (handled above); Prim and Nega
-- only swap their overlays, so their body is wrapped too.
local NPCS = {}
for name in ([[AMADEUS-BOT-DOG-NPC BALL-KID-BOT TECH-BOT-NPC GUARD-BOT-NPC LIBRARIAN-BOT-NPC MEDIC-BOT-NPC
  MIGHTY-BOT-NPC NURSE-BOT-NPC KERNEL-OPENING-STAGE-VER-NPC PRIM-BOT-NPC-PROP RESEACHER-BOT-MT-NPC SHOCKED-BOT-NPC
  SITTING-BOT-MT-NPC SOLDIER-BOT-A SOLDIER-BOT-B SOLDIER-BOT-C YUKI-BOT-DOG-NPC PRIM-BOT-NPC NEGA-CAPE-NPC]]):gmatch("%S+") do
  NPCS[name] = true
end

local HUE_GLSL = [[
extern float hue;
vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 h = rgb2hsv(c.rgb);
  h.x = fract(h.x + hue);
  return vec4(hsv2rgb(h), c.a) * color;
}
]]
local mode, seedHash, kaiShift = 0, 0, 0
local kaiBase = nil
local vectorShift = setmetatable({}, { __mode = "k" })
local cache = {}
local scratch = { {}, {}, {}, {}, {}, {} }

local function fnv(h, n)
  return bit.tobit(bit.bxor(h, n) * 16777619)
end

local function hashString(s, h)
  h = h or -2128831035
  for i = 1, #s do h = fnv(h, s:byte(i)) end
  return h
end

local function shiftFrom(h)
  return MIN_SHIFT + (h % SPAN + SPAN) % SPAN
end

local function byte(v)
  return math.floor((v or 0) * 255 + 0.5)
end

-- RGB (0..1) rotated by deg degrees of hue, in HSV.
local function rotate(r, g, b, deg)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local d = max - min
  if d < 1e-4 then return r, g, b end
  local h
  if max == r then h = ((g - b) / d) % 6
  elseif max == g then h = (b - r) / d + 2
  else h = (r - g) / d + 4 end
  h = (h + deg / 60) % 6
  local s, v = d / max, max
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v end
  return v, p, q
end

local function rotated(c, deg)
  local byShift = cache[deg]
  if not byShift then
    byShift = {}
    cache[deg] = byShift
  end
  local key = byte(c[1]) * 65536 + byte(c[2]) * 256 + byte(c[3])
  local out = byShift[key]
  if not out then
    local r, g, b = rotate(c[1], c[2], c[3], deg)
    out = { r, g, b }
    byShift[key] = out
  end
  return out
end

-- Hue for a non-Kai palette, from its colours when first seen.
local function paletteShift(active)
  local s = vectorShift[active]
  if s then return s end
  local h = seedHash
  for i = 1, 6 do
    local c = active[i]
    if type(c) == "table" then h = fnv(fnv(fnv(h, byte(c[1])), byte(c[2])), byte(c[3])) end
  end
  s = shiftFrom(h)
  vectorShift[active] = s
  return s
end

-- The colours to send instead of active, or active itself when this palette isn't randomized.
local function transform(base, active)
  if mode == 0 or type(active) ~= "table" then return active end
  local deg
  if rawequal(base, kaiBase) then
    deg = kaiShift
  elseif mode == 2 then
    deg = paletteShift(active)
  else
    return active
  end
  for i = 1, 6 do
    if type(active[i]) ~= "table" then return active end
  end
  for i = 1, 6 do
    local c, out = active[i], scratch[i]
    local rc = rotated(c, deg)
    out[1], out[2], out[3], out[4] = rc[1], rc[2], rc[3], c[4] or 1
  end
  return scratch
end

local function install()
  if installed then return end
  if not (Shader and Shader.setColorSwapper and Shader.sendColorVectors and Shader.pushColorSwapper and GFX) then
    return
  end
  kaiBase = Colors and Colors.Sprites and Colors.Sprites.kai
  local origSet = Shader.setColorSwapper
  local origHaze = Shader.setColorSwapperWithHaze
  local origSend = Shader.sendColorVectors
  local origPush = Shader.pushColorSwapper

  rawset(Shader, "setColorSwapper", function(self, base, active, ...)
    return origSet(self, base, transform(base, active), ...)
  end)
  if origHaze then
    rawset(Shader, "setColorSwapperWithHaze", function(self, base, active, ...)
      return origHaze(self, base, transform(base, active), ...)
    end)
  end
  rawset(Shader, "sendColorVectors", function(self, base, active, ...)
    return origSend(self, base, transform(base, active), ...)
  end)
  -- UI swaps (HUD, menus, shop slots) keep their colours: same as the game's pushColorSwapper, with the
  -- original setter
  rawset(Shader, "pushColorSwapper", function(self, l, ui, base, active, shift, max, highest, alpha)
    if not (ui and base and active) then
      return origPush(self, l, ui, base, active, shift, max, highest, alpha)
    end
    alpha = alpha or self.preparedTransparency or 1.0
    GFX:pushUI(l, origSet, self, base, active, shift or 0, max or 5,
      math.max(math.min(highest or 6, 6), 1), alpha)
    self.preparedTransparency = nil
  end)
  installed = true
  log.info("hook installed: palette randomizer")
end

function P.mode()
  local setting = P.settings.palette
  if SETTING_MODE[setting] then return SETTING_MODE[setting] end
  return tonumber(client.slotData and client.slotData.palette_randomizer) or 0
end

-- Picks the mode and hues for the connected seed. Called on connect and when the setting changes.
function P.configure()
  if trapUntil then return end -- applied when the trap ends
  local m = P.mode()
  if m ~= 0 and not client.seed then m = 0 end
  mode = m
  seedHash = hashString((client.seed or "") .. "\0" .. (client.slotName or ""))
  kaiShift = shiftFrom(fnv(seedHash, 0x4b4149))
  for k in pairs(vectorShift) do vectorShift[k] = nil end
  log.info(("palette: mode %d (setting %s), seed %s"):format(mode, tostring(P.settings.palette), tostring(client.seed)))
end

local function setHue(deg)
  love.graphics.setShader(hueShader)
  hueShader:send("hue", deg / 360)
end

local function npcShift(cls)
  local s = vectorShift[cls]
  if not s then
    s = shiftFrom(hashString(tostring(cls.name or ""), seedHash))
    vectorShift[cls] = s
  end
  return s
end

local function wrapNpc(cls)
  local draw = rawget(cls.__declaredMethods or {}, "draw")
  if not draw then return end
  wrappedNpcs[cls] = true
  cls.draw = function(self, ...)
    -- self.layer is a callable table (Layer:get)
    local l = mode == 2 and hueShader and self.layer and self.layer()
    if type(l) ~= "number" then return draw(self, ...) end
    GFX:push(l, setHue, npcShift(cls))
    local a, b = draw(self, ...)
    GFX:push(l, love.graphics.setShader)
    return a, b
  end
end

-- NPC classes can load with a stage, so the class tree is scanned again every few seconds.
local function scanNpcs(cls)
  for sub in pairs(cls.subclasses or {}) do
    if not wrappedNpcs[sub] and NPCS[sub.name] then wrapNpc(sub) end
    scanNpcs(sub)
  end
end

-- Enemies draw through the swap shader only in everything mode.
local function forceEnemyShader()
  local want = mode == 2
  if want == forcedShader or not BaseObject then return end
  BaseObject.alwaysUsePaletteShader = want or nil
  forcedShader = want
end

-- Palette Trap: everything, with new hues every few seconds, then back to the setting.
function P.trap(seconds)
  local now = love.timer.getTime()
  trapUntil = math.max(trapUntil or now, now) + seconds
  nextReroll = 0
end

local function updateTrap()
  if not trapUntil then return end
  local now = love.timer.getTime()
  if now >= trapUntil then
    trapUntil = nil
    P.configure()
  elseif now >= nextReroll then
    nextReroll = now + TRAP_REROLL
    mode = 2
    seedHash = love.math.random(0, 0x7fffffff)
    kaiShift = shiftFrom(fnv(seedHash, 0x4b4149))
    for k in pairs(vectorShift) do vectorShift[k] = nil end
  end
end

function P.update()
  install()
  updateTrap()
  forceEnemyShader()
  if mode == 2 and installed and BaseObject then
    if not hueTried then
      hueTried = true
      local ok, shader = pcall(love.graphics.newShader, HUE_GLSL)
      if ok then hueShader = shader else log.error("palette hue shader: " .. tostring(shader)) end
    end
    local now = love.timer.getTime()
    if now >= nextScan then
      nextScan = now + SCAN_SECONDS
      local ok, err = pcall(scanNpcs, BaseObject)
      if not ok then log.error("palette npc scan: " .. tostring(err)) end
    end
  end
end

return P
