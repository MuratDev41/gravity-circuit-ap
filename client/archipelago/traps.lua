-- Trap effects beyond Damage and Credit Leak (those stay in game.lua). game.lua's instant queue calls T.apply once
-- Kai is playable in a stage. The value of a timed trap is its length in seconds; timers run while not paused.
--   Knockback: a hit's knockback without damage. Burst Drain: empties the burst bar (with Burst Link, only the
--   bursts above the shared part). Palette: palette.lua re-rolls every hue. Pixelate: a screen shader through
--   GAMESTATE.applyShaderOnGameScreen. Earthquake: Camera shakes. Flip: GAMESTATE.flipScreen (Hash's attack).
local log = require("archipelago.log")

local T = { game = nil, knockback = nil, burstlink = nil, palette = nil }

local PIXEL_BLOCK = 4 -- game pixels per block
local QUAKE_INTERVAL = 0.25

local timers = { pixel = 0, quake = 0, flip = 0 }
local pixelShader, pixelTried = nil, false
local flipSet = false
local nextQuake = 0

local PIXEL_GLSL = [[
extern float block;
extern float gameWidth;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 size = love_ScreenSize.xy;
  vec2 b = vec2(block * size.x / gameWidth) / size;
  vec2 uv = (floor(tc / b) + 0.5) * b;
  return Texel(tex, uv) * color;
}
]]

local function shader()
  if not pixelTried then
    pixelTried = true
    local ok, s = pcall(love.graphics.newShader, PIXEL_GLSL)
    if ok then pixelShader = s else log.error("pixelate shader: " .. tostring(s)) end
  end
  return pixelShader
end

-- kind: the item kind from data.lua; item.gid: seconds for timed traps
function T.apply(kind, item, kai)
  if kind == "trapknock" then
    if T.knockback then T.knockback.knock(kai, love.math.random() < 0.5 and -1 or 1) end
  elseif kind == "trapburst" then
    if T.burstlink then T.burstlink.drain() end
  elseif kind == "trappalette" then
    if T.palette then T.palette.trap(item.gid) end
  elseif kind == "trappixel" then
    timers.pixel = timers.pixel + item.gid
  elseif kind == "trapquake" then
    timers.quake = timers.quake + item.gid
  elseif kind == "trapflip" then
    timers.flip = timers.flip + item.gid
  end
end

local function pixelate(on)
  local s = shader()
  if not (s and GAMESTATE) then return end
  if on then
    if GAMESTATE.applyShaderOnGameScreen == nil then
      s:send("block", PIXEL_BLOCK)
      s:send("gameWidth", GAME_WIDTH or 400)
      GAMESTATE.applyShaderOnGameScreen = s
    end
  elseif GAMESTATE.applyShaderOnGameScreen == s then
    GAMESTATE.applyShaderOnGameScreen = nil
  end
end

local function flip(on)
  if not GAMESTATE then return end
  if on and not flipSet then
    GAMESTATE.flipScreen = true
    flipSet = true
  elseif not on and flipSet then
    GAMESTATE.flipScreen = false
    flipSet = false
  end
end

local lastTime = nil
function T.update()
  local now = love.timer.getTime()
  local dt = lastTime and math.min(now - lastTime, 0.5) or 0
  lastTime = now
  local G = T.game
  local stage = G and G.active and G.currentStage and G.currentStage()
  local running = stage and stage ~= "HUB" and not G.isPaused()
  if not running then
    -- leaving a stage ends the screen effects; their time is kept for the next stage
    pixelate(false)
    flip(false)
    return
  end
  for k, v in pairs(timers) do timers[k] = math.max(0, v - dt) end
  pixelate(timers.pixel > 0)
  flip(timers.flip > 0)
  if timers.quake > 0 and Camera and Camera.startShake and now >= nextQuake then
    nextQuake = now + QUAKE_INTERVAL
    Camera:startShake(2, 2, 15, 0)
  end
end

return T
