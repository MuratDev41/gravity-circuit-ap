local json = require("archipelago.json")
local log = require("archipelago.log")
local utf8 = require("utf8")

local UIX = {
  open = false,
  fields = {
    { key = "server",   label = "Server",   value = "archipelago.gg:38281" },
    { key = "slot",     label = "Slot",     value = "" },
    { key = "password", label = "Password", value = "", secret = true },
  },
  focus = 1,
  messages = {},
  autoconnect = true,
  transport = "auto",
}

local CONFIG = "archipelago/connection.json"
local MESSAGE_SECONDS = 9
local MAX_MESSAGES = 6
local STATUS_SECONDS = 6

local COLORS = {
  info = { 1, 1, 1 }, item = { 0.55, 1, 0.6 }, warn = { 1, 0.8, 0.35 },
  death = { 1, 0.45, 0.45 }, chat = { 0.7, 0.85, 1 },
}

-- Image font built from the game's dialogue font texture (last animation frame, 60px down).
-- Red/green/black become white/grey/black so the text can be tinted.
-- { character, x, y, width } from content/gfx/fonts/animated/dialogue_font.lua
local FONT_TEXTURE = "content/gfx/fonts/animated/dialogue_font-rgb-black-less-shaded.png"
local GLYPH_HEIGHT, SETTLED_FRAME_Y, SPACE_WIDTH = 10, 60, 5
local GLYPHS = {
  {"A",0,0,9}, {"B",9,0,9}, {"C",18,0,9}, {"D",27,0,9}, {"E",36,0,9}, {"F",45,0,9}, {"G",54,0,9}, {"H",63,0,9},
  {"I",73,0,7}, {"J",81,0,9}, {"K",90,0,9}, {"L",100,0,7}, {"M",108,0,9}, {"N",117,0,9}, {"O",126,0,9},
  {"P",135,0,9}, {"Q",144,0,9}, {"R",153,0,9}, {"S",162,0,9}, {"T",171,0,9}, {"U",180,0,9}, {"V",189,0,9},
  {"W",198,0,9}, {"X",207,0,9}, {"Y",216,0,9}, {"Z",225,0,9}, {"a",0,10,9}, {"b",9,10,9}, {"c",18,10,9},
  {"d",27,10,9}, {"e",36,10,9}, {"f",45,10,9}, {"g",54,10,9}, {"h",63,10,9}, {"i",74,10,5}, {"j",82,10,7},
  {"k",90,10,9}, {"l",100,10,6}, {"m",108,10,9}, {"n",117,10,9}, {"o",126,10,9}, {"p",135,10,9}, {"q",144,10,9},
  {"r",154,10,7}, {"s",162,10,9}, {"t",172,10,7}, {"u",180,10,9}, {"v",189,10,9}, {"w",198,10,9}, {"x",207,10,9},
  {"y",216,10,9}, {"z",225,10,9}, {"0",0,20,9}, {"1",10,20,7}, {"2",18,20,9}, {"3",27,20,9}, {"4",36,20,9},
  {"5",45,20,9}, {"6",54,20,9}, {"7",63,20,9}, {"8",72,20,9}, {"9",81,20,9}, {"!",90,20,7}, {"?",99,20,7},
  {"/",234,10,9}, {":",108,20,5}, {".",117,20,5}, {",",126,20,5}, {";",135,20,5}, {"-",144,20,9}, {"_",243,20,9},
  {"+",153,20,9}, {"*",162,20,9}, {"(",171,20,7}, {")",181,20,5}, {"[",190,20,8}, {"]",196,20,9},
  {"'",243,0,4}, {"$",206,20,9}, {"&",306,10,11}, {"%",317,10,9}, {"@",423,10,19},
  {">",396,10,9}, {"<",405,10,9}, {"|",414,10,9},
}
local SUBSTITUTE = { ['"'] = "'", ["`"] = "'", ["#"] = "No.", ["="] = "-", ["~"] = "-", ["^"] = "'",
                     ["{"] = "(", ["}"] = ")", ["\\"] = "/", ["\t"] = " " }

local font, fontFailed, hasGlyph = nil, false, { [" "] = true }
local fallbackFont = nil

local function buildGameFont()
  local src = love.image.newImageData(FONT_TEXTURE)
  local width = 1
  for _, g in ipairs(GLYPHS) do width = width + g[4] + 1 end
  width = width + SPACE_WIDTH + 1
  local strip = love.image.newImageData(width, GLYPH_HEIGHT)
  local x = 0
  local function separator()
    for y = 0, GLYPH_HEIGHT - 1 do strip:setPixel(x, y, 1, 0, 1, 1) end
    x = x + 1
  end
  local chars = { " " }
  separator()
  x = x + SPACE_WIDTH -- the space glyph stays transparent
  for _, g in ipairs(GLYPHS) do
    separator()
    local ch, gx, gy, gw = g[1], g[2], g[3] + SETTLED_FRAME_Y, g[4]
    for dx = 0, gw - 1 do
      for dy = 0, GLYPH_HEIGHT - 1 do
        local r, gr, b, a = src:getPixel(gx + dx, gy + dy)
        if a > 0.5 then
          if r > 0.5 then strip:setPixel(x + dx, dy, 1, 1, 1, 1)
          elseif gr > 0.5 then strip:setPixel(x + dx, dy, 0.72, 0.72, 0.72, 1)
          else strip:setPixel(x + dx, dy, 0, 0, 0, 1) end
        end
      end
    end
    x = x + gw
    chars[#chars + 1] = ch
    hasGlyph[ch] = true
  end
  separator()
  local f = love.graphics.newImageFont(strip, table.concat(chars), -1)
  f:setFilter("nearest", "nearest")
  f:setLineHeight(1.2)
  return f
end

local function getFont()
  if not font and not fontFailed then
    local ok, result = pcall(buildGameFont)
    if ok then
      font = result
    else
      fontFailed = true
      log.error("could not build the game font, using LÖVE's: " .. tostring(result))
    end
  end
  if font then return font, true end
  fallbackFont = fallbackFont or love.graphics.newFont(12)
  return fallbackFont, false
end

local function clean(text)
  text = tostring(text)
  if fontFailed then return text end
  local out = {}
  local ok = pcall(function()
    for _, code in utf8.codes(text) do
      local ch = utf8.char(code)
      if hasGlyph[ch] then out[#out + 1] = ch
      elseif SUBSTITUTE[ch] then out[#out + 1] = SUBSTITUTE[ch]
      elseif code < 32 then out[#out + 1] = " "
      else out[#out + 1] = "?" end
    end
  end)
  if not ok then return (text:gsub("[^%w%p ]", "?")) end
  return table.concat(out)
end

local function cleanColored(text)
  if type(text) ~= "table" then return clean(text) end
  local out = {}
  for i = 1, #text, 2 do
    out[i], out[i + 1] = text[i], clean(text[i + 1] or "")
  end
  return out
end

local function plainText(text)
  if type(text) ~= "table" then return text end
  local parts = {}
  for i = 2, #text, 2 do parts[#parts + 1] = text[i] end
  return table.concat(parts)
end

function UIX.loadConfig()
  local s = love.filesystem.read(CONFIG)
  if not s then return end
  local ok, cfg = pcall(json.decode, s)
  if not ok or type(cfg) ~= "table" then return end
  for _, f in ipairs(UIX.fields) do
    if type(cfg[f.key]) == "string" then f.value = cfg[f.key] end
  end
  if cfg.autoconnect ~= nil then UIX.autoconnect = cfg.autoconnect and true or false end
  if cfg.transport == "winhttp" or cfg.transport == "socket" or cfg.transport == "auto" then
    UIX.transport = cfg.transport
  end
end

function UIX.saveConfig()
  local cfg = { autoconnect = UIX.autoconnect, transport = UIX.transport }
  for _, f in ipairs(UIX.fields) do cfg[f.key] = f.value end
  love.filesystem.createDirectory("archipelago")
  love.filesystem.write(CONFIG, json.encode(cfg))
end

function UIX.get(key)
  for _, f in ipairs(UIX.fields) do if f.key == key then return f.value end end
end

-- text: string or LÖVE coloredtext
function UIX.push(text, kind)
  local colored = type(text) == "table" and cleanColored(text) or nil
  table.insert(UIX.messages, {
    text = colored or clean(text), plain = clean(plainText(text)), kind = kind or "info",
    time = love.timer.getTime(),
  })
  while #UIX.messages > MAX_MESSAGES * 2 do table.remove(UIX.messages, 1) end
  log.info("msg: " .. plainText(text))
end

UIX.onConnect = function() end

function UIX.keypressed(key)
  if key == "f9" then
    UIX.open = not UIX.open
    if love.keyboard.setTextInput then love.keyboard.setTextInput(true) end
    return true
  end
  if not UIX.open then return false end
  local f = UIX.fields[UIX.focus]
  if key == "escape" then
    UIX.open = false
  elseif key == "tab" or key == "down" then
    UIX.focus = UIX.focus % #UIX.fields + 1
  elseif key == "up" then
    UIX.focus = (UIX.focus - 2) % #UIX.fields + 1
  elseif key == "backspace" then
    local offset = utf8.offset(f.value, -1)
    f.value = offset and f.value:sub(1, offset - 1) or ""
  elseif key == "v" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
    local clip = love.system.getClipboardText() or ""
    f.value = f.value .. clip:gsub("[\r\n\t]", "")
  elseif key == "return" or key == "kpenter" then
    for _, field in ipairs(UIX.fields) do
      if not field.secret then field.value = field.value:gsub("^%s+", ""):gsub("%s+$", "") end
    end
    UIX.saveConfig()
    UIX.open = false
    UIX.onConnect()
  end
  return true
end

function UIX.textinput(t)
  if not UIX.open then return false end
  if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then return true end
  local f = UIX.fields[UIX.focus]
  f.value = f.value .. t
  return true
end

-- Drawn at half the game's pixel scale, so the text is smaller than the game's own.

local function shadowText(f, text, x, y, color, alpha, limit, align)
  local shadow = plainText(text)
  love.graphics.setColor(0, 0, 0, 0.6 * alpha)
  if limit then love.graphics.printf(shadow, x + 1, y + 1, limit, align or "left")
  else love.graphics.print(shadow, x + 1, y + 1) end
  if type(text) == "table" then
    love.graphics.setColor(1, 1, 1, alpha)
  else
    love.graphics.setColor(color[1], color[2], color[3], alpha)
  end
  if limit then love.graphics.printf(text, x, y, limit, align or "left")
  else love.graphics.print(text, x, y) end
end

local function lineCount(f, plain, limit)
  local _, lines = f:getWrap(plain, limit)
  return math.max(1, #lines)
end

local function panelBox(x, y, w, h, alpha)
  love.graphics.setColor(0.03, 0.04, 0.08, 0.82 * (alpha or 1))
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
end

local lastStatus, statusChanged = nil, -100

function UIX.draw(state)
  love.graphics.push("all")
  love.graphics.setCanvas()
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setBlendMode("alpha")
  local W, H = love.graphics.getDimensions()
  local f, gameFont = getFont()
  local scale = 1
  if gameFont then
    local gameScale = math.floor(math.min(W / (GAME_WIDTH or 400), H / (GAME_HEIGHT or 240)))
    scale = math.max(1, math.floor(gameScale / 2))
  end
  love.graphics.scale(scale)
  local VW, VH = W / scale, H / scale
  love.graphics.setFont(f)
  local lh = math.ceil(f:getHeight() * f:getLineHeight())
  local now = love.timer.getTime()

  if state.status ~= lastStatus then lastStatus, statusChanged = state.status, now end

  local margin = 4

  -- status and warning: top centre
  local topLimit = math.floor(VW * 0.7)
  local topX = math.floor((VW - topLimit) / 2)
  local ty = margin
  local showStatus = not state.connected or UIX.open or state.paused or now - statusChanged < STATUS_SECONDS
  if showStatus then
    local color = state.connected and { 0.55, 1, 0.6 } or { 1, 0.7, 0.4 }
    local status = "AP: " .. clean(state.status)
    if state.active then status = status .. ("  |  %d/%d checks"):format(state.done, state.total) end
    status = status .. "  |  F9: connection"
    shadowText(f, status, topX, ty, color, 0.9, topLimit, "center")
    ty = ty + lineCount(f, status, topLimit) * lh + 2
  end
  if state.warning then
    local text = clean(state.warning)
    shadowText(f, text, topX, ty, COLORS.warn, 0.95, topLimit, "center")
    ty = ty + lineCount(f, text, topLimit) * lh + 2
  end

  -- message log: bottom-left, growing upward
  local limit = math.floor(VW * 0.62)
  local y = VH - margin

  local visible = {}
  for i = #UIX.messages, 1, -1 do
    local m = UIX.messages[i]
    if now - m.time < MESSAGE_SECONDS and #visible < MAX_MESSAGES then visible[#visible + 1] = m end
  end
  for _, m in ipairs(visible) do
    local age = now - m.time
    local a = age < MESSAGE_SECONDS - 1 and 1 or (MESSAGE_SECONDS - age)
    local n = lineCount(f, m.plain, limit)
    y = y - n * lh - 1
    shadowText(f, m.text, margin, y, COLORS[m.kind] or COLORS.info, a, limit)
  end

  if state.shop then
    local SHOP_COLORS = {
      progression = { 0.69, 0.6, 0.94 }, useful = { 0.43, 0.55, 0.91 }, trap = { 0.98, 0.5, 0.45 },
      filler = { 0, 0.93, 0.93 }, done = { 0.7, 0.7, 0.7 },
    }
    local label = clean(state.shop.text)
    local tw = f:getWidth(label)
    panelBox((VW - tw) / 2 - 6, ty + 2, tw + 12, lh + 6)
    shadowText(f, label, (VW - tw) / 2, ty + 5, SHOP_COLORS[state.shop.kind] or SHOP_COLORS.filler, 1)
  end

  if state.locked then
    local text = clean(state.locked)
    local tw = f:getWidth(text)
    panelBox((VW - tw) / 2 - 6, VH * 0.82 - 3, tw + 12, lh + 6)
    shadowText(f, text, (VW - tw) / 2, VH * 0.82, { 1, 0.45, 0.45 }, 1)
  end

  if UIX.open then
    local pw = math.min(300, VW - 16)
    local fieldX, fieldW = 64, pw - 76
    local statusText = clean(state.status)
    local statusLines = lineCount(f, statusText, pw - 20)
    local ph = 30 + #UIX.fields * (lh + 8) + 18 + statusLines * lh + 8
    local px, py = math.floor((VW - pw) / 2), math.floor((VH - ph) / 2)
    panelBox(px, py, pw, ph, 1.1)
    love.graphics.setColor(0.4, 0.8, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 3, 3)
    shadowText(f, "Archipelago connection", px + 10, py + 8, { 1, 1, 1 }, 1)
    for i, field in ipairs(UIX.fields) do
      local fy = py + 28 + (i - 1) * (lh + 8)
      shadowText(f, field.label, px + 10, fy + 3, { 0.8, 0.8, 0.8 }, 1)
      love.graphics.setColor(i == UIX.focus and 0.22 or 0.12, i == UIX.focus and 0.26 or 0.14, 0.32, 1)
      love.graphics.rectangle("fill", px + fieldX, fy, fieldW, lh + 4, 2, 2)
      local shown = field.secret and string.rep("*", utf8.len(field.value) or #field.value) or clean(field.value)
      if i == UIX.focus and math.floor(now * 2) % 2 == 0 then shown = shown .. "_" end
      while f:getWidth(shown) > fieldW - 6 and #shown > 1 do shown = shown:sub(2) end
      shadowText(f, shown, px + fieldX + 3, fy + 3, { 1, 1, 1 }, 1)
    end
    local hy = py + 28 + #UIX.fields * (lh + 8)
    shadowText(f, "Tab: next  Enter: connect  Ctrl+V: paste  Esc: close", px + 10, hy, { 0.65, 0.65, 0.7 }, 1,
      pw - 20)
    local color = state.connected and { 0.55, 1, 0.6 } or { 1, 0.7, 0.4 }
    shadowText(f, statusText, px + 10, hy + 18, color, 1, pw - 20)
  end

  love.graphics.pop()
end

return UIX
