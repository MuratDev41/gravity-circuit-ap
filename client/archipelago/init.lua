local log = require("archipelago.log")
local client = require("archipelago.client")
local game = require("archipelago.game")
local ui = require("archipelago.ui")
local mapexport = require("archipelago.mapexport")

local AP = { VERSION = "0.10.1" }

local RECONNECT_DELAY = 15

local wantConnected = false
local lastAttempt = -100

local function connect()
  local server, slot = ui.get("server"), ui.get("slot")
  if not slot or slot == "" then
    ui.push("Set your slot name first (F9).", "warn")
    ui.open = true
    return
  end
  wantConnected = true
  lastAttempt = love.timer.getTime()
  client.connect(server, slot, ui.get("password"))
end
ui.onConnect = connect

game.notify = ui.push

client.handlers.status = function(status, msg)
  if status == "disconnected" then
    ui.push(msg, "warn")
    if msg:find("refused", 1, true) or msg:find("Invalid server", 1, true) then wantConnected = false end
  elseif status == "connected" then
    ui.push(msg, "item")
  end
end
client.handlers.connected = function() game.onConnected() end
client.handlers.items = function() game.onItems() end
client.handlers.scouted = function()
  local shop = game.shop
  if shop and shop.activated and game.active and game.shopsanity() then game.hintShop(shop.type) end
end
client.handlers.deathlink = function(source, cause) game.receiveDeath(source, cause) end
client.handlers.print = function(text, msg)
  local t = msg.type
  if t == "ItemSend" or t == "ItemCheat" then
    -- received items are announced by the game layer; only show what we sent to others
    local item = msg.item or {}
    if item.player == client.slot and msg.receiving ~= client.slot then ui.push(text, "item") end
  elseif t == "Hint" then
    if msg.receiving == client.slot or (msg.item and msg.item.player == client.slot) then ui.push(text, "chat") end
  elseif t == "Chat" or t == "ServerChat" or t == "Goal" or t == "Countdown" or t == "Release" or t == "Collect"
    or t == nil then
    ui.push(text, "chat")
  end
end

local started = false
function AP.tick()
  if not started then
    started = true
    ui.loadConfig()
    log.info("Gravity Circuit Archipelago " .. AP.VERSION .. " loaded")
    if ui.autoconnect and ui.get("slot") ~= "" then connect() end
  end
  client.update()
  game.update()
  mapexport.update()
  if wantConnected and client.status == "disconnected" and love.timer.getTime() - lastAttempt > RECONNECT_DELAY then
    connect()
  end
end

local function overlayState()
  local done, total = game.counts()
  return {
    status = client.statusMsg,
    connected = client.isConnected(),
    active = game.active,
    done = done,
    total = total,
    warning = game.saveLoaded and game.warning or nil,
    locked = game.selectedStageLocked(),
    shop = game.shopInfo(),
  }
end

-- The game reassigns love.update/love.draw while it boots, so the real callbacks are kept in a side table
-- and wrappers are served through a metatable on `love` instead of being wrapped once.
local real = {}
local wrappers = {}

wrappers.update = function(...)
  if real.update then real.update(...) end
  local ok, err = pcall(AP.tick)
  if not ok then log.error("tick: " .. tostring(err)) end
end

wrappers.draw = function(...)
  if real.draw then real.draw(...) end
  local exported, exportErr = pcall(mapexport.draw)
  if not exported then log.error("map export: " .. tostring(exportErr)) end
  local ok, err = pcall(ui.draw, overlayState())
  if not ok then log.error("draw: " .. tostring(err)) end
end

wrappers.keypressed = function(...)
  local ok, handled = pcall(ui.keypressed, (...))
  if ok and handled then return end
  if real.keypressed then return real.keypressed(...) end
end

wrappers.keyreleased = function(...)
  if ui.open then return end
  if real.keyreleased then return real.keyreleased(...) end
end

wrappers.textinput = function(...)
  local ok, handled = pcall(ui.textinput, ...)
  if ok and handled then return end
  if real.textinput then return real.textinput(...) end
end

wrappers.quit = function(...)
  pcall(client.disconnect, true)
  if real.quit then return real.quit(...) end
end

function AP.install()
  if getmetatable(love) then
    log.error("love table already has a metatable; overlay disabled")
    return
  end
  for k in pairs(wrappers) do
    real[k] = rawget(love, k)
    rawset(love, k, nil)
  end
  setmetatable(love, {
    __index = function(_, k) return wrappers[k] end,
    __newindex = function(t, k, v)
      if wrappers[k] then real[k] = v else rawset(t, k, v) end
    end,
  })
  log.info("love callbacks intercepted")
end

return AP
