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
  transport = "auto", -- "auto", "winhttp" or "socket" (connection.json)
  retry = true,       -- false after a failure reconnecting can't fix (bad address, refused by the server)
}

-- Archipelago text client colours
local COLOR = {
  self = { 0.93, 0, 0.93 },          -- your own name (magenta)
  player = { 0.98, 0.98, 0.82 },     -- other players (light yellow)
  progression = { 0.69, 0.6, 0.94 }, -- plum
  useful = { 0.43, 0.55, 0.91 },     -- slate blue
  trap = { 0.98, 0.5, 0.45 },        -- salmon
  filler = { 0, 0.93, 0.93 },        -- cyan
  location = { 0, 1, 0.5 },          -- spring green
  entrance = { 0.39, 0.58, 0.93 },   -- cornflower blue
  text = { 1, 1, 1 },
}
C.COLOR = COLOR
local NAMED_COLORS = {
  red = { 0.93, 0.2, 0.2 }, green = { 0, 1, 0.5 }, yellow = { 0.98, 0.98, 0.82 }, blue = { 0.39, 0.58, 0.93 },
  magenta = { 0.93, 0, 0.93 }, cyan = { 0, 0.93, 0.93 }, white = { 1, 1, 1 }, black = { 0.3, 0.3, 0.3 },
  plum = COLOR.progression, slateblue = COLOR.useful, salmon = COLOR.trap,
}

function C.itemClass(flags)
  flags = flags or 0
  if flags % 2 == 1 then return "progression" end
  if math.floor(flags / 2) % 2 == 1 then return "useful" end
  if math.floor(flags / 4) % 2 == 1 then return "trap" end
  return "filler"
end

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

local failures = {}

local function startAttempt()
  local attempt = table.remove(attempts, 1)
  if not attempt then return false end
  socket = WS.new(attempt.host, attempt.port, attempt.secure, attempt.transport)
  setStatus("connecting", ("Connecting to %s://%s:%d ..."):format(
    attempt.secure and "wss" or "ws", attempt.host, attempt.port))
  return true
end

-- Message for the player once every attempt failed; the most specific reason wins.
local REASON_ORDER = { "notap", "notfound", "refused", "timeout", "badaddress", "reset", "tls", "nosecure",
                       "nowinhttp", "other" }
local function failureText(host, port)
  local best, bestRank = nil, math.huge
  for _, f in ipairs(failures) do
    for rank, reason in ipairs(REASON_ORDER) do
      if f.reason == reason and rank < bestRank then best, bestRank = f, rank end
    end
  end
  best = best or failures[#failures] or { reason = "other" }
  local r = best.reason
  if r == "notfound" then
    return ('Could not find the server "%s". Check the address for typos.'):format(host)
  elseif r == "refused" then
    local hint = host:find("archipelago.gg", 1, true)
      and " archipelago.gg rooms get a new port when they wake up: reload the room page and copy the address again."
      or " If the server runs on someone's PC, they need to forward that port, and you need their public IP."
    return ("Nothing is accepting connections at %s:%d. Check the port.%s"):format(host, port, hint)
  elseif r == "timeout" then
    return ("%s:%d did not answer in time. Check the address, and that the host's firewall and port forwarding "
      .. "let you in."):format(host, port)
  elseif r == "badaddress" then
    return ('"%s:%d" is not a valid server address. Use host:port, for example archipelago.gg:38281.'):format(host, port)
  elseif r == "notap" then
    return ("%s:%d answered, but it is not an Archipelago server%s. Check the port."):format(
      host, port, best.status and (" (HTTP " .. tostring(best.status) .. ")") or "")
  elseif r == "reset" then
    return ("%s:%d closed the connection right away. Check the port, or try again in a moment."):format(host, port)
  elseif r == "tls" then
    return ("The secure (wss://) connection to %s:%d failed. Try the address with ws:// instead."):format(host, port)
  elseif r == "nosecure" then
    return "wss:// is not available here (no TLS support). Enter the address without wss://."
  end
  return ("Could not connect to %s:%d (%s)."):format(host, port, tostring(best.msg))
end

local REFUSED_TEXT = {
  InvalidSlot = 'There is no slot named "%s" in this room. Slot names are case-sensitive.',
  InvalidGame = [[Slot "%s" is not a Gravity Circuit (MuratDev's Implementation) slot, or the seed was made ]]
    .. "with an older apworld. Check the slot name, or regenerate with this version.",
  InvalidPassword = "Wrong password, or this room needs one (F9 to enter it).",
  IncompatibleVersion = "The server is too old or too new for this client. Update the mod or the server.",
  InvalidItemsHandling = "The server rejected this client's settings. Update the mod.",
  SlotAlreadyTaken = 'Slot "%s" is already connected from somewhere else.',
}

-- Without a scheme, wss is tried first and ws second, like the official clients. The LuaSocket transport
-- (TLS through Schannel, compression) goes first; WinHTTP is the fallback.
function C.connect(server, slotName, password)
  C.disconnect(true)
  slotName = tostring(slotName or ""):gsub("^%s+", ""):gsub("%s+$", "")
  C.server, C.slotName, C.password = server, slotName, password or ""
  C.retry = true
  local scheme, host, port = WS.parseUrl(server)
  if not port then
    C.retry = false
    setStatus("disconnected", host or "Invalid server address")
    return
  end
  attempts, failures = {}, {}
  local transports = {}
  if C.transport ~= "winhttp" then transports[#transports + 1] = "socket" end
  if C.transport ~= "socket" and WS.hasWinHTTP() then transports[#transports + 1] = "winhttp" end
  if #transports == 0 then transports[1] = "socket" end
  for _, transport in ipairs(transports) do
    if scheme ~= "ws" and (transport == "winhttp" or WS.hasTLS()) then
      attempts[#attempts + 1] = { host = host, port = port, secure = true, transport = transport }
    end
    if scheme ~= "wss" then
      attempts[#attempts + 1] = { host = host, port = port, secure = false, transport = transport }
    end
  end
  if #attempts == 0 then
    attempts[1] = { host = host, port = port, secure = true, transport = "socket" } -- reports "nosecure"
  end
  C.target = { host = host, port = port }
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

-- Connection tags (DeathLink, KnockbackLink); changes are sent right away.
local tagSet = {}
function C.setTag(tag, enabled)
  if (tagSet[tag] or false) == (enabled and true or false) and C.tagsSent then return end
  tagSet[tag] = enabled and true or nil
  local tags = json.array({})
  for name in pairs(tagSet) do tags[#tags + 1] = name end
  table.sort(tags)
  C.tags = tags
  if C.isConnected() then
    sendCommands({ { cmd = "ConnectUpdate", tags = tags } })
    C.tagsSent = true
  end
end

function C.setDeathLink(enabled)
  C.setTag("DeathLink", enabled)
end

function C.bounce(tags, data)
  if not C.isConnected() then return end
  sendCommands({ { cmd = "Bounce", tags = json.array(tags), data = data } })
end

function C.uuid()
  return getUuid()
end

function C.sendDeathLink(cause)
  if not C.isConnected() then return end
  sendCommands({ { cmd = "Bounce", tags = json.array({ "DeathLink" }),
                   data = { time = os.time(), source = C.slotName, cause = cause } } })
end

-- Data storage. Replies and changes to watched keys arrive as the "storage" event with the SetReply message.
function C.watch(keys)
  if not C.isConnected() or #keys == 0 then return end
  sendCommands({ { cmd = "SetNotify", keys = json.array(keys) } })
end

-- operations: list of { operation = "add" | "max" | "min" | ..., value = ... }; extra fields are echoed back.
function C.storageSet(key, default, operations, extra)
  if not C.isConnected() then return false end
  local command = { cmd = "Set", key = key, default = default, want_reply = true,
                    operations = json.array(operations) }
  for k, v in pairs(extra or {}) do command[k] = v end
  sendCommands({ command })
  return true
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

function C.playerColor(slot)
  return slot == C.slot and COLOR.self or COLOR.player
end

function C.itemPiece(id, slot, flags)
  return COLOR[C.itemClass(flags)] or COLOR.filler, C.itemName(id, slot)
end

-- Returns plain text and LÖVE coloredtext.
local function renderPrintJSON(parts)
  local plain, colored = {}, {}
  for _, part in ipairs(parts or {}) do
    local text, color = part.text or "", COLOR.text
    if part.type == "player_id" then
      local slot = tonumber(text)
      text, color = C.playerName(slot), C.playerColor(slot)
    elseif part.type == "player_name" then
      color = COLOR.player
    elseif part.type == "item_id" then
      color, text = C.itemPiece(tonumber(text), part.player, part.flags)
    elseif part.type == "item_name" then
      color = COLOR[C.itemClass(part.flags)] or COLOR.filler
    elseif part.type == "location_id" then
      text, color = C.locationName(tonumber(text), part.player), COLOR.location
    elseif part.type == "location_name" then
      color = COLOR.location
    elseif part.type == "entrance_name" then
      color = COLOR.entrance
    elseif part.type == "color" and part.color then
      color = NAMED_COLORS[part.color:gsub("_bg$", "")] or COLOR.text
    end
    plain[#plain + 1] = text
    colored[#colored + 1] = color
    colored[#colored + 1] = text
  end
  return table.concat(plain), colored
end

-- Data packages are cached by checksum, so only changed games are requested.
local DP_DIR = "archipelago/datapackage"

local function dpPath(game, checksum)
  return ("%s/%s_%s.lua"):format(DP_DIR, game:gsub("[^%w]", "_"):sub(1, 60), tostring(checksum):gsub("[^%w]", ""))
end

local function loadCachedPackage(game, checksum)
  if not checksum then return false end
  local path = dpPath(game, checksum)
  if not love.filesystem.getInfo(path) then return false end
  local ok, names = pcall(function() return love.filesystem.load(path)() end)
  if ok and type(names) == "table" and names.items and names.locations then
    C.dp[game] = names
    return true
  end
  log.warn("ignoring broken data package cache " .. path)
  return false
end

local function serializeNames(names)
  local out = { "return {items={" }
  for id, name in pairs(names.items) do out[#out + 1] = ("[%d]=%q,"):format(id, name) end
  out[#out + 1] = "},locations={"
  for id, name in pairs(names.locations) do out[#out + 1] = ("[%d]=%q,"):format(id, name) end
  out[#out + 1] = "}}" .. string.char(10)
  return table.concat(out)
end

local function saveCachedPackage(game, checksum, names)
  if not checksum then return end
  local ok, err = pcall(function()
    love.filesystem.createDirectory(DP_DIR)
    love.filesystem.write(dpPath(game, checksum), serializeNames(names))
  end)
  if not ok then log.warn("could not cache data package for " .. game .. ": " .. tostring(err)) end
end

local function onCommand(msg)
  local cmd = msg.cmd
  if cmd == "RoomInfo" then
    C.seed = msg.seed_name
    local checksums = msg.datapackage_checksums or {}
    local missing, cached = json.array({}), 0
    for _, game in ipairs(msg.games or {}) do
      if loadCachedPackage(game, checksums[game]) then cached = cached + 1 else missing[#missing + 1] = game end
    end
    log.info(("data packages: %d cached, %d requested"):format(cached, #missing))
    local commands = {}
    if #missing > 0 then commands[#commands + 1] = { cmd = "GetDataPackage", games = missing } end
    commands[#commands + 1] = {
      cmd = "Connect", password = C.password, game = data.GAME, name = C.slotName, uuid = getUuid(),
      version = CLIENT_VERSION, items_handling = ITEMS_HANDLING_ALL, tags = json.array({}), slot_data = true,
    }
    sendCommands(commands)
  elseif cmd == "DataPackage" then
    for game, package in pairs((msg.data and msg.data.games) or {}) do
      local names = { items = {}, locations = {} }
      for name, id in pairs(package.item_name_to_id or {}) do names.items[id] = name end
      for name, id in pairs(package.location_name_to_id or {}) do names.locations[id] = name end
      C.dp[game] = names
      saveCachedPackage(game, package.checksum, names)
    end
  elseif cmd == "Connected" then
    handshakeDone = true
    C.tagsSent = false
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
    emit("connected")
  elseif cmd == "ConnectionRefused" then
    attempts = {}
    if socket then socket:close() end
    socket = nil
    C.retry = false
    local reasons = {}
    for _, code in ipairs(msg.errors or {}) do
      local text = REFUSED_TEXT[code]
      reasons[#reasons + 1] = text and text:format(C.slotName) or code
    end
    log.warn("connection refused: " .. table.concat(msg.errors or {}, ", "))
    setStatus("disconnected", "The server refused the connection: " .. table.concat(reasons, " "))
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
    local plain, colored = renderPrintJSON(msg.data)
    emit("print", plain, msg, colored)
  elseif cmd == "Bounced" then
    for _, tag in ipairs(msg.tags or {}) do
      if tag == "DeathLink" and msg.data and msg.data.source ~= C.slotName then
        emit("deathlink", msg.data.source, msg.data.cause)
      elseif tag == "KnockbackLink" then
        emit("knockback", msg.data)
      end
    end
  elseif cmd == "SetReply" then
    emit("storage", msg)
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
      for _, msg in ipairs(event.msgs) do
        local handled, err = pcall(onCommand, msg)
        if not handled then log.error("handling " .. tostring(msg.cmd) .. ": " .. tostring(err)) end
      end
      if not socket then return end
    elseif event.type == "close" or event.type == "error" then
      socket = nil
      log.warn("socket " .. event.type .. ": " .. tostring(event.msg) .. " [" .. tostring(event.reason) .. "]")
      if not handshakeDone then
        failures[#failures + 1] = event
        if startAttempt() then return end
        local target = C.target or { host = "?", port = 0 }
        if event.reason == "badaddress" then C.retry = false end
        setStatus("disconnected", failureText(target.host, target.port))
        return
      end
      local wasConnected = C.status == "connected"
      setStatus("disconnected", "Connection lost: " .. (event.reason == "closed" and "the server closed it."
        or "the network dropped. Reconnecting..."))
      handshakeDone = false
      if wasConnected then emit("disconnected") end
      return
    end
  end
end

return C
