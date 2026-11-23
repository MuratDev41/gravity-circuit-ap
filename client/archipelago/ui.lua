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
  -- shared with game.lua and burstlink.lua; "auto" follows the YAML
  settings = { deathlink = "auto", burstlink = "auto", knockbacklink = "auto" },
}

-- Rows of the F9 panel, in focus order.
local ROWS = {
  { kind = "field", field = 1 },
  { kind = "field", field = 2 },
  { kind = "field", field = 3 },
  { kind = "button" },
  { kind = "option", key = "deathlink", label = "DeathLink", values = { "auto", "on", "off" },
    names = { auto = "Use YAML", on = "On", off = "Off" },
    help = "Use YAML follows death_link in your YAML. Changes apply right away." },
  { kind = "option", key = "knockbacklink", label = "Knockback", values = { "auto", "on", "off" },
    names = { auto = "Use YAML", on = "On", off = "Off" },
    help = "Knockback Link: getting hit knocks back everyone with it on. Use YAML follows knockback_link." },
  { kind = "option", key = "burstlink", label = "Burst Link",
    values = { "auto", "off", "gravity_circuit", "silk_link" },
    names = { auto = "Use YAML", off = "Off", gravity_circuit = "Gravity Circuit", silk_link = "Silk Link" },
    help = "Shares your first 2 bursts with your team. Use YAML follows burst_link in your YAML." },
  { kind = "option", key = "autoconnect", label = "Auto-connect", bool = true,
    help = "Connect when the game starts." },
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
  if cfg.deathlink == "auto" or cfg.deathlink == "on" or cfg.deathlink == "off" then
    UIX.settings.deathlink = cfg.deathlink
  end
  if cfg.knockbacklink == "auto" or cfg.knockbacklink == "on" or cfg.knockbacklink == "off" then
    UIX.settings.knockbacklink = cfg.knockbacklink
  end
  if cfg.burstlink == "auto" or cfg.burstlink == "off" or cfg.burstlink == "gravity_circuit"
    or cfg.burstlink == "silk_link" then
    UIX.settings.burstlink = cfg.burstlink
  end
  if cfg.transport == "winhttp" or cfg.transport == "socket" or cfg.transport == "auto" then
    UIX.transport = cfg.transport
  end
end

function UIX.saveConfig()
  local cfg = { autoconnect = UIX.autoconnect, transport = UIX.transport, deathlink = UIX.settings.deathlink,
                burstlink = UIX.settings.burstlink, knockbacklink = UIX.settings.knockbacklink }
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
UIX.onDisconnect = function() end
UIX.onSettings = function() end
UIX.connected = false

local function optionValue(row)
  if row.bool then return UIX.autoconnect end
  return UIX.settings[row.key]
end

local function optionText(row)
  local v = optionValue(row)
  if row.bool then return v and "On" or "Off" end
  if row.names then return row.names[v] or tostring(v) end
  return tostring(v)
end

local function changeOption(row, dir)
  if row.bool then
    UIX.autoconnect = not UIX.autoconnect
  else
    local i = 1
    for k, v in ipairs(row.values) do if v == UIX.settings[row.key] then i = k end end
    UIX.settings[row.key] = row.values[(i - 1 + dir) % #row.values + 1]
  end
  UIX.saveConfig()
  UIX.onSettings(row.key)
end

local function trimFields()
  for _, field in ipairs(UIX.fields) do
    if not field.secret then field.value = field.value:gsub("^%s+", ""):gsub("%s+$", "") end
  end
end

local function pressButton()
  trimFields()
  UIX.saveConfig()
  if UIX.connected then
    UIX.onDisconnect()
  else
    UIX.open = false
    UIX.onConnect()
  end
end

function UIX.keypressed(key)
  if key == "f9" then
    UIX.open = not UIX.open
    if love.keyboard.setTextInput then love.keyboard.setTextInput(true) end
    return true
  end
  if not UIX.open then return false end
  local row = ROWS[UIX.focus]
  local f = row.kind == "field" and UIX.fields[row.field]
  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  if key == "escape" then
    UIX.open = false
  elseif (key == "tab" and not shift) or key == "down" then
    UIX.focus = UIX.focus % #ROWS + 1
  elseif key == "tab" or key == "up" then
    UIX.focus = (UIX.focus - 2) % #ROWS + 1
  elseif (key == "left" or key == "right") and row.kind == "option" then
    changeOption(row, key == "left" and -1 or 1)
  elseif key == "backspace" and f then
    local offset = utf8.offset(f.value, -1)
    f.value = offset and f.value:sub(1, offset - 1) or ""
  elseif key == "v" and f and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
    local clip = love.system.getClipboardText() or ""
    f.value = f.value .. clip:gsub("[\r\n\t]", "")
  elseif key == "return" or key == "kpenter" or (key == "space" and not f) then
    if row.kind == "option" then changeOption(row, 1) else pressButton() end
  end
  return true
end

function UIX.textinput(t)
  if not UIX.open then return false end
  if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then return true end
  local row = ROWS[UIX.focus]
  if row.kind == "field" then
    local f = UIX.fields[row.field]
    f.value = f.value .. t
  end
  return true
end

-- Hit boxes of the panel rows in screen pixels, filled when the panel is drawn.
local hits = {}

function UIX.mousepressed(x, y, button)
  if not UIX.open then return false end
  if button ~= 1 then return true end
  for _, h in ipairs(hits) do
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
      UIX.focus = h.row
      local row = ROWS[h.row]
      if row.kind == "option" then
        changeOption(row, (h.mid and x < h.mid) and -1 or 1)
      elseif row.kind == "button" then
        pressButton()
      end
      return true
    end
  end
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

local PANEL = {
  accent = { 0.4, 0.8, 1 }, label = { 0.75, 0.78, 0.85 }, dim = { 0.55, 0.57, 0.65 }, white = { 1, 1, 1 },
  good = { 0.55, 1, 0.6 }, bad = { 1, 0.7, 0.4 },
}

local function hit(row, x, y, w, h, scale, mid)
  hits[#hits + 1] = { row = row, x = x * scale, y = y * scale, w = w * scale, h = h * scale,
                      mid = mid and mid * scale }
end

function UIX.drawPanel(f, lh, VW, VH, scale, state, now)
  hits = {}
  local pad = 10
  local labelW = 0
  for _, r in ipairs(ROWS) do
    local text = r.kind == "field" and UIX.fields[r.field].label or r.label
    if text then labelW = math.max(labelW, f:getWidth(text)) end
  end
  labelW = labelW + 10
  local pw = math.min(math.max(320, labelW + 200), VW - 16)
  local rowH = lh + 6
  local fieldW = pw - pad * 2 - labelW
  local statusText = clean(state.status)
  local info = state.info or {}
  local statusLines = lineCount(f, statusText, pw - pad * 2)
  local row = ROWS[UIX.focus]
  local FIELD_HELP = "Enter: connect   Ctrl+V: paste"
  local help = row.help or (row.kind == "field" and FIELD_HELP or nil)
  local keys = "Up/Down: move   Left/Right: change   Enter: select   Esc: close"
  -- the box keeps one height: room for the longest help text, whatever is focused
  local helpMax = lineCount(f, FIELD_HELP, pw - pad * 2)
  for _, r in ipairs(ROWS) do
    if r.help then helpMax = math.max(helpMax, lineCount(f, r.help, pw - pad * 2)) end
  end
  local helpLines = helpMax + lineCount(f, keys, pw - pad * 2)
  local INFO_LINES = 2
  local infoLines = 0
  for _, line in ipairs(info) do infoLines = infoLines + lineCount(f, clean(line), pw - pad * 2) end
  local ph = 24 + (lh + 4) + 3 * (rowH + 3) + rowH + 10
    + (lh + 4) + (#ROWS - 4) * (rowH + 3) + 6
    + statusLines * lh + math.max(infoLines, INFO_LINES) * lh + 8 + helpLines * lh + 8
  local px, py = math.floor((VW - pw) / 2), math.floor((VH - ph) / 2)

  panelBox(px, py, pw, ph, 1.15)
  love.graphics.setColor(PANEL.accent[1], PANEL.accent[2], PANEL.accent[3], 1)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1, 3, 3)
  love.graphics.setColor(PANEL.accent[1], PANEL.accent[2], PANEL.accent[3], 0.18)
  love.graphics.rectangle("fill", px + 1, py + 1, pw - 2, lh + 8, 3, 3)
  shadowText(f, "Archipelago", px + pad, py + 5, PANEL.white, 1)
  local dot = state.connected and PANEL.good or PANEL.bad
  local short = state.connected and "Connected" or "Not connected"
  local sw = f:getWidth(short)
  love.graphics.setColor(dot[1], dot[2], dot[3], 1)
  love.graphics.circle("fill", px + pw - pad - sw - 7, py + 5 + lh / 2 - 1, 2.5)
  shadowText(f, short, px + pw - pad - sw, py + 5, dot, 1)

  local y = py + lh + 14
  local function header(text)
    shadowText(f, text, px + pad, y, PANEL.accent, 1)
    local tw = f:getWidth(text)
    love.graphics.setColor(PANEL.accent[1], PANEL.accent[2], PANEL.accent[3], 0.3)
    love.graphics.rectangle("fill", px + pad + tw + 6, y + math.floor(lh / 2), pw - pad * 2 - tw - 6, 1)
    y = y + lh + 4
  end
  local function rowBack(i, x, w)
    local focused = UIX.focus == i
    love.graphics.setColor(focused and 0.2 or 0.11, focused and 0.27 or 0.13, focused and 0.38 or 0.2, 1)
    love.graphics.rectangle("fill", x, y, w, rowH, 2, 2)
    if focused then
      love.graphics.setColor(PANEL.accent[1], PANEL.accent[2], PANEL.accent[3], 0.8)
      love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, rowH - 1, 2, 2)
    end
  end

  header("Connection")
  for i = 1, 3 do
    local field = UIX.fields[ROWS[i].field]
    shadowText(f, field.label, px + pad, y + 3, PANEL.label, 1)
    local fx = px + pad + labelW
    rowBack(i, fx, fieldW)
    local shown = field.secret and string.rep("*", utf8.len(field.value) or #field.value) or clean(field.value)
    if UIX.focus == i and math.floor(now * 2) % 2 == 0 then shown = shown .. "_" end
    while f:getWidth(shown) > fieldW - 8 and #shown > 1 do shown = shown:sub(2) end
    shadowText(f, shown, fx + 4, y + 3, PANEL.white, 1)
    hit(i, fx, y, fieldW, rowH, scale)
    y = y + rowH + 3
  end
  local label = UIX.connected and "Disconnect" or "Connect"
  local bw = f:getWidth(label) + 24
  local bx = px + pw - pad - bw
  rowBack(4, bx, bw)
  shadowText(f, label, bx + 12, y + 3, UIX.connected and PANEL.bad or PANEL.good, 1)
  hit(4, bx, y, bw, rowH, scale)
  y = y + rowH + 10

  header("Settings")
  for i = 5, #ROWS do
    local r = ROWS[i]
    shadowText(f, r.label, px + pad, y + 3, PANEL.label, 1)
    local ox, ow = px + pad + labelW, fieldW
    rowBack(i, ox, ow)
    local text = optionText(r)
    local arrow = UIX.focus == i and PANEL.accent or PANEL.dim
    shadowText(f, "<", ox + 5, y + 3, arrow, 1)
    shadowText(f, ">", ox + ow - 5 - f:getWidth(">"), y + 3, arrow, 1)
    shadowText(f, text, ox + math.floor((ow - f:getWidth(text)) / 2), y + 3, PANEL.white, 1)
    hit(i, ox, y, ow, rowH, scale, ox + ow / 2)
    y = y + rowH + 3
  end
  y = y + 6

  shadowText(f, statusText, px + pad, y, state.connected and PANEL.good or PANEL.bad, 1, pw - pad * 2)
  y = y + statusLines * lh
  for _, line in ipairs(info) do
    shadowText(f, clean(line), px + pad, y, PANEL.label, 1, pw - pad * 2)
    y = y + lineCount(f, clean(line), pw - pad * 2) * lh
  end
  y = y + math.max(INFO_LINES - infoLines, 0) * lh + 8
  if help then shadowText(f, help, px + pad, y, PANEL.dim, 1, pw - pad * 2) end
  y = y + helpMax * lh
  shadowText(f, keys, px + pad, y, PANEL.dim, 1, pw - pad * 2)
end

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

  if UIX.open then UIX.drawPanel(f, lh, VW, VH, scale, state, now) end

  love.graphics.pop()
end

return UIX
