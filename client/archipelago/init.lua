local log = require("archipelago.log")
local client = require("archipelago.client")
local game = require("archipelago.game")
local ui = require("archipelago.ui")
local mapexport = require("archipelago.mapexport")
local sprites = require("archipelago.sprites")
local burstlink = require("archipelago.burstlink")
local knockback = require("archipelago.knockback")
local palette = require("archipelago.palette")
local traps = require("archipelago.traps")
local markers = require("archipelago.markers")
local bosshp = require("archipelago.bosshp")
local music = require("archipelago.music")

local AP = { VERSION = "1.1.0" }

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
  client.transport = ui.transport
  client.connect(server, slot, ui.get("password"))
end
ui.onConnect = connect
ui.onDisconnect = function()
  wantConnected = false
  client.disconnect()
end
ui.onSettings = function(key)
  if key == "deathlink" then game.applyDeathLink() end
  if key == "burstlink" then burstlink.configure() end
  if key == "knockbacklink" then knockback.apply() end
  if key == "palette" then palette.configure() end
end
game.settings = ui.settings

game.notify = ui.push

client.handlers.status = function(status, msg)
  if status == "disconnected" then
    ui.push(msg, "warn")
    if not client.retry then wantConnected = false end
  elseif status == "connected" then
    ui.push(msg, "item")
  end
end
client.handlers.connected = function()
  game.onConnected()
  burstlink.onConnected()
  knockback.apply()
  palette.configure()
  music.configure()
end
client.handlers.storage = function(msg) burstlink.onStorage(msg) end
burstlink.game = game
burstlink.settings = ui.settings
knockback.game = game
knockback.settings = ui.settings
palette.settings = ui.settings
traps.game, traps.knockback, traps.burstlink, traps.palette = game, knockback, burstlink, palette
game.trapHandler = traps.apply
markers.game = game
bosshp.game = game
client.handlers.knockback = function(data) knockback.onBounce(data) end
client.handlers.items = function() game.onItems() end
client.handlers.scouted = function()
  local shop = game.shop
  if shop and shop.activated and game.active and game.shopsanity() then game.hintShop(shop.type) end
end
client.handlers.deathlink = function(source, cause) game.receiveDeath(source, cause) end
client.handlers.print = function(text, msg, colored)
  local shown = colored or text
  local t = msg.type
  if t == "ItemSend" or t == "ItemCheat" then
    -- received items are announced by the game layer; only show what we sent to others
    local item = msg.item or {}
    if item.player == client.slot and msg.receiving ~= client.slot then ui.push(shown, "item") end
  elseif t == "Hint" then
    if msg.receiving == client.slot or (msg.item and msg.item.player == client.slot) then ui.push(shown, "chat") end
  elseif t == "Chat" or t == "ServerChat" or t == "Goal" or t == "Countdown" or t == "Release" or t == "Collect"
    or t == nil then
    ui.push(shown, "chat")
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
  ui.connected = client.status ~= "disconnected"
  game.update()
  mapexport.update()
  sprites.update()
  burstlink.update()
  knockback.update()
  palette.update()
  traps.update()
  markers.update()
  bosshp.update()
  music.update()
  log.update()
  if wantConnected and client.retry and client.status == "disconnected"
    and love.timer.getTime() - lastAttempt > RECONNECT_DELAY then
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
    paused = game.isPaused(),
    info = (function()
      local lines = game.deathLinkInfo(knockback)
      lines[#lines + 1] = burstlink.info()
      return lines
    end)(),
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

wrappers.mousepressed = function(...)
  local ok, handled = pcall(ui.mousepressed, ...)
  if ok and handled then return end
  if real.mousepressed then return real.mousepressed(...) end
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
  pcall(log.flush)
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
