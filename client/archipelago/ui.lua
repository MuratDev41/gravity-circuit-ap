local json = require("archipelago.json")
local log = require("archipelago.log")

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
}

local CONFIG = "archipelago/connection.json"
local COLORS = {
  info = { 1, 1, 1 }, item = { 0.55, 1, 0.6 }, warn = { 1, 0.8, 0.35 },
  death = { 1, 0.45, 0.45 }, chat = { 0.7, 0.85, 1 },
}

local fontSmall, fontBig

function UIX.loadConfig()
  local s = love.filesystem.read(CONFIG)
  if not s then return end
  local ok, cfg = pcall(json.decode, s)
  if not ok or type(cfg) ~= "table" then return end
  for _, f in ipairs(UIX.fields) do
    if type(cfg[f.key]) == "string" then f.value = cfg[f.key] end
  end
  if cfg.autoconnect ~= nil then UIX.autoconnect = cfg.autoconnect and true or false end
end

function UIX.saveConfig()
  local cfg = { autoconnect = UIX.autoconnect }
  for _, f in ipairs(UIX.fields) do cfg[f.key] = f.value end
  love.filesystem.createDirectory("archipelago")
  love.filesystem.write(CONFIG, json.encode(cfg))
end

function UIX.get(key)
  for _, f in ipairs(UIX.fields) do if f.key == key then return f.value end end
end

function UIX.push(text, kind)
  table.insert(UIX.messages, { text = text, kind = kind or "info", time = love.timer.getTime() })
  while #UIX.messages > 8 do table.remove(UIX.messages, 1) end
  log.info("msg: " .. text)
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
    f.value = f.value:sub(1, -2)
  elseif key == "v" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
    local clip = love.system.getClipboardText() or ""
    f.value = f.value .. clip:gsub("[\r\n]", "")
  elseif key == "return" or key == "kpenter" then
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

local function fonts()
  if not fontSmall then
    fontSmall = love.graphics.newFont(14)
    fontBig = love.graphics.newFont(18)
  end
end

local function shadowText(text, x, y, color, alpha)
  love.graphics.setColor(0, 0, 0, 0.75 * alpha)
  love.graphics.print(text, x + 1, y + 1)
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  love.graphics.print(text, x, y)
end

function UIX.draw(state)
  fonts()
  love.graphics.push("all")
  love.graphics.setCanvas()
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setBlendMode("alpha")
  local W, H = love.graphics.getDimensions()

  love.graphics.setFont(fontSmall)
  local now = love.timer.getTime()
  local y = 8
  for _, m in ipairs(UIX.messages) do
    local age = now - m.time
    if age < 8 then
      local a = age < 7 and 1 or (8 - age)
      shadowText(m.text, 10, y, COLORS[m.kind] or COLORS.info, a)
      y = y + 18
    end
  end

  local color = state.connected and { 0.55, 1, 0.6 } or { 1, 0.7, 0.4 }
  local status = "AP: " .. state.status
  if state.active then status = status .. ("  |  %d/%d checks"):format(state.done, state.total) end
  status = status .. "  |  F9: connection"
  shadowText(status, 10, H - 22, color, 0.85)
  if state.warning then shadowText(state.warning, 10, H - 42, COLORS.warn, 0.95) end

  if state.shop then
    local SHOP_COLORS = {
      progression = { 0.78, 0.6, 1 }, useful = { 0.45, 0.75, 1 }, trap = { 1, 0.45, 0.45 },
      filler = { 0.92, 0.92, 0.92 }, done = { 0.7, 0.7, 0.7 },
    }
    love.graphics.setFont(fontBig)
    local label = state.shop.text
    if state.shop.kind == "progression" or state.shop.kind == "useful" or state.shop.kind == "trap" then
      label = label .. "  (" .. state.shop.kind .. ")"
    end
    local tw = fontBig:getWidth(label)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", (W - tw) / 2 - 12, 40, tw + 24, 34, 6, 6)
    shadowText(label, (W - tw) / 2, 47, SHOP_COLORS[state.shop.kind] or SHOP_COLORS.filler, 1)
  end

  if state.locked then
    love.graphics.setFont(fontBig)
    local tw = fontBig:getWidth(state.locked)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", (W - tw) / 2 - 10, H * 0.82 - 6, tw + 20, 32, 6, 6)
    shadowText(state.locked, (W - tw) / 2, H * 0.82, { 1, 0.45, 0.45 }, 1)
  end

  if UIX.open then
    love.graphics.setFont(fontBig)
    local pw, ph = 520, 230
    local px, py = (W - pw) / 2, (H - ph) / 2
    love.graphics.setColor(0.05, 0.06, 0.1, 0.92)
    love.graphics.rectangle("fill", px, py, pw, ph, 8, 8)
    love.graphics.setColor(0.4, 0.8, 1, 1)
    love.graphics.rectangle("line", px, py, pw, ph, 8, 8)
    shadowText("Archipelago connection", px + 16, py + 12, { 1, 1, 1 }, 1)
    love.graphics.setFont(fontSmall)
    for i, f in ipairs(UIX.fields) do
      local fy = py + 50 + (i - 1) * 40
      shadowText(f.label, px + 16, fy + 6, { 0.8, 0.8, 0.8 }, 1)
      love.graphics.setColor(i == UIX.focus and 0.2 or 0.12, 0.14, 0.2, 1)
      love.graphics.rectangle("fill", px + 110, fy, pw - 130, 28, 4, 4)
      local shown = f.secret and string.rep("*", #f.value) or f.value
      if i == UIX.focus and math.floor(now * 2) % 2 == 0 then shown = shown .. "_" end
      shadowText(shown, px + 118, fy + 6, { 1, 1, 1 }, 1)
    end
    shadowText("Tab: next field   Enter: connect   Ctrl+V: paste   Esc: close", px + 16, py + ph - 52, { 0.7, 0.7, 0.7 }, 1)
    shadowText(state.status, px + 16, py + ph - 28, color, 1)
  end

  love.graphics.pop()
end

return UIX
