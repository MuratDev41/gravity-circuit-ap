local json = require("archipelago.json")
local WS = require("archipelago.ws")
local log = require("archipelago.log")
local data = require("archipelago.data")

local CLIENT_VERSION = { major = 0, minor = 6, build = 0, class = "Version" }
local ITEMS_HANDLING_ALL = 7
local CLIENT_GOAL = 30

local C = {
  status = "disconnected",
  statusMsg = "Not connected",
  server = "",
  slotName = "",
  password = "",
  seed = nil,
  team = nil,
  slot = nil,
  players = {},   -- [slot] = { name, alias, game }
  slotData = {},
  items = {},     -- received NetworkItems in index order
  checked = {},   -- [locationId] = true, as known by the server
  scouted = {},   -- [locationId] = NetworkItem
  tags = {},
  dp = {},        -- [game] = { items = {[id] = name}, locations = {[id] = name} }
  handlers = {},
}

local socket = nil
local attempts = {}
local handshakeDone = false
local goalSent = false

local function emit(name, ...)
  local handler = C.handlers[name]
  if handler then
    local ok, err = pcall(handler, ...)
    if not ok then log.error("handler " .. name .. ": " .. tostring(err)) end
  end
end

local function setStatus(status, msg)
  C.status = status
  C.statusMsg = msg
  log.info("status: " .. status .. " - " .. msg)
  emit("status", status, msg)
end

local function sendCommands(list)
  if socket then socket:send(json.encode(json.array(list))) end
end

local function getUuid()
  local path = "archipelago/uuid.txt"
  local uuid = love.filesystem.read(path)
  if uuid and #uuid > 8 then return uuid end
  local hex = {}
  for i = 1, 16 do hex[i] = string.format("%02x", love.math.random(0, 255)) end
  uuid = table.concat(hex)
  love.filesystem.write(path, uuid)
  return uuid
end

local function startAttempt()
  local attempt = table.remove(attempts, 1)
  if not attempt then return false end
  socket = WS.new(attempt.host, attempt.port, attempt.secure)
  setStatus("connecting", ("Connecting to %s://%s:%d ..."):format(
    attempt.secure and "wss" or "ws", attempt.host, attempt.port))
  return true
end

-- Without a scheme, wss is tried first and ws second, like the official clients.
function C.connect(server, slotName, password)
  C.disconnect(true)
  C.server, C.slotName, C.password = server, slotName, password or ""
  local scheme, host, port = WS.parseUrl(server)
  if not host or host == "" or not port then
    setStatus("disconnected", "Invalid server address: " .. tostring(server))
    return
  end
  attempts = {}
  if scheme == "wss" or not scheme then attempts[#attempts + 1] = { host = host, port = port, secure = true } end
  if scheme == "ws" or not scheme then attempts[#attempts + 1] = { host = host, port = port, secure = false } end
  handshakeDone = false
  goalSent = false
  startAttempt()
end

function C.disconnect(silent)
  if socket then socket:close() end
  socket = nil
  attempts = {}
  if C.status ~= "disconnected" and not silent then
    setStatus("disconnected", "Disconnected")
  end
  C.status = "disconnected"
end

function C.isConnected()
  return C.status == "connected"
end

function C.playerName(slot)
  local player = C.players[slot]
  if player then return player.alias or player.name end
  if slot == 0 then return "Server" end
  return "Player " .. tostring(slot)
end

function C.playerGame(slot)
  local player = C.players[slot]
  return player and player.game
end

function C.itemName(id, slot)
  local game = slot and C.playerGame(slot) or data.GAME
  local package = C.dp[game]
  if package and package.items[id] then return package.items[id] end
  if game == data.GAME and data.itemNames[id] then return data.itemNames[id] end
  return "Item " .. tostring(id)
end

function C.locationName(id, slot)
  local game = slot and C.playerGame(slot) or data.GAME
  local package = C.dp[game]
  if package and package.locations[id] then return package.locations[id] end
  if game == data.GAME and data.locationNames[id] then return data.locationNames[id] end
  return "Location " .. tostring(id)
end

function C.checkLocations(ids)
  if not C.isConnected() or #ids == 0 then return end
  sendCommands({ { cmd = "LocationChecks", locations = json.array(ids) } })
end

function C.sendGoal()
  if not C.isConnected() or goalSent then return end
  goalSent = true
  sendCommands({ { cmd = "StatusUpdate", status = CLIENT_GOAL } })
end

function C.setDeathLink(enabled)
  local tags = json.array({})
  if enabled then tags[1] = "DeathLink" end
  C.tags = tags
  if C.isConnected() then sendCommands({ { cmd = "ConnectUpdate", tags = tags } }) end
end

function C.sendDeathLink(cause)
  if not C.isConnected() then return end
  sendCommands({ { cmd = "Bounce", tags = json.array({ "DeathLink" }),
                   data = { time = os.time(), source = C.slotName, cause = cause } } })
end

-- hint = 2 also creates hints for the scouted locations (only new ones are announced).
function C.scout(ids, hint)
  if not C.isConnected() or #ids == 0 then return end
  sendCommands({ { cmd = "LocationScouts", locations = json.array(ids), create_as_hint = hint or 0 } })
end

function C.setData(key, value)
  if not C.isConnected() then return end
  sendCommands({ { cmd = "Set", key = key, default = "", want_reply = false,
                   operations = json.array({ { operation = "replace", value = value } }) } })
end

local function renderPrintJSON(parts)
  local out = {}
  for _, part in ipairs(parts or {}) do
    local text = part.text or ""
    if part.type == "player_id" then
      text = C.playerName(tonumber(text))
    elseif part.type == "item_id" then
      text = C.itemName(tonumber(text), part.player)
    elseif part.type == "location_id" then
      text = C.locationName(tonumber(text), part.player)
    end
    out[#out + 1] = text
  end
  return table.concat(out)
end

local function onCommand(msg)
  local cmd = msg.cmd
  if cmd == "RoomInfo" then
    C.seed = msg.seed_name
    local games = json.array({})
    for _, game in ipairs(msg.games or {}) do games[#games + 1] = game end
    sendCommands({
      { cmd = "GetDataPackage", games = games },
      {
        cmd = "Connect", password = C.password, game = data.GAME, name = C.slotName, uuid = getUuid(),
        version = CLIENT_VERSION, items_handling = ITEMS_HANDLING_ALL, tags = json.array({}), slot_data = true,
      },
    })
  elseif cmd == "DataPackage" then
    for game, package in pairs((msg.data and msg.data.games) or {}) do
      local names = { items = {}, locations = {} }
      for name, id in pairs(package.item_name_to_id or {}) do names.items[id] = name end
      for name, id in pairs(package.location_name_to_id or {}) do names.locations[id] = name end
      C.dp[game] = names
    end
  elseif cmd == "Connected" then
    handshakeDone = true
    C.team, C.slot = msg.team, msg.slot
    C.slotData = msg.slot_data or {}
    C.players = {}
    for _, player in ipairs(msg.players or {}) do
      C.players[player.slot] = { name = player.name, alias = player.alias }
    end
    for slot, info in pairs(msg.slot_info or {}) do
      local s = tonumber(slot)
      C.players[s] = C.players[s] or { name = info.name }
      C.players[s].game = info.game
    end
    C.checked = {}
    for _, id in ipairs(msg.checked_locations or {}) do C.checked[id] = true end
    C.items = {}
    C.itemsSynced = false
    C.scouted = {}
    setStatus("connected", ("Connected as %s"):format(C.slotName))
    if C.slotData.death_link then C.setDeathLink(true) end
    emit("connected")
  elseif cmd == "ConnectionRefused" then
    attempts = {}
    if socket then socket:close() end
    socket = nil
    setStatus("disconnected", "Connection refused: " .. table.concat(msg.errors or {}, ", "))
  elseif cmd == "ReceivedItems" then
    local index = msg.index or 0
    if index == 0 then
      C.items = {}
    elseif index ~= #C.items then
      log.warn(("item index mismatch (got %d, have %d), resyncing"):format(index, #C.items))
      sendCommands({ { cmd = "Sync" } })
      return
    end
    for _, item in ipairs(msg.items or {}) do C.items[#C.items + 1] = item end
    C.itemsSynced = true
    emit("items", C.items, index)
  elseif cmd == "RoomUpdate" then
    if msg.checked_locations then
      for _, id in ipairs(msg.checked_locations) do C.checked[id] = true end
      emit("checked")
    end
    for _, player in ipairs(msg.players or {}) do
      C.players[player.slot] = C.players[player.slot] or {}
      C.players[player.slot].name = player.name
      C.players[player.slot].alias = player.alias
    end
  elseif cmd == "LocationInfo" then
    for _, item in ipairs(msg.locations or {}) do C.scouted[item.location] = item end
    emit("scouted")
  elseif cmd == "PrintJSON" then
    emit("print", renderPrintJSON(msg.data), msg)
  elseif cmd == "Bounced" then
    for _, tag in ipairs(msg.tags or {}) do
      if tag == "DeathLink" and msg.data and msg.data.source ~= C.slotName then
        emit("deathlink", msg.data.source, msg.data.cause)
      end
    end
  elseif cmd == "InvalidPacket" then
    log.warn("InvalidPacket: " .. tostring(msg.text))
  end
end

function C.update()
  if not socket then return end
  for _, event in ipairs(socket:poll()) do
    if event.type == "open" then
      log.info("websocket open")
    elseif event.type == "message" then
      local ok, msgs = pcall(json.decode, event.data)
      if not ok then
        log.error("bad json: " .. tostring(msgs))
      else
        for _, msg in ipairs(msgs) do
          local handled, err = pcall(onCommand, msg)
          if not handled then log.error("handling " .. tostring(msg.cmd) .. ": " .. tostring(err)) end
        end
      end
    elseif event.type == "close" or event.type == "error" then
      socket = nil
      log.warn("socket " .. event.type .. ": " .. tostring(event.msg))
      if not handshakeDone and startAttempt() then return end
      local wasConnected = C.status == "connected"
      setStatus("disconnected", (handshakeDone and "Connection lost: " or "Could not connect: ") .. tostring(event.msg))
      handshakeDone = false
      if wasConnected then emit("disconnected") end
      return
    end
  end
end

return C
