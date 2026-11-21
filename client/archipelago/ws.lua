-- WebSocket connections run in love.threads, which also decode the JSON.
--   winhttp: ws:// and wss://, reader and writer threads (ws_reader.lua, ws_writer.lua)
--   socket:  LuaSocket, ws:// only, one thread (ws_socket.lua); for Proton/Wine and as a fallback
local log = require("archipelago.log")

local WS = {}
WS.__index = WS

local counter = 0

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Accepts "wss://host:port", "ws://host:port", "host:port" or "host" (port 38281). Spaces, "/connect " and a
-- trailing slash are ignored. Returns scheme, host, port, or nil and an error message.
function WS.parseUrl(url)
  url = trim(tostring(url or ""))
  url = url:gsub("^/connect%s+", "")
  if url == "" then return nil, "Enter the server address, for example archipelago.gg:38281." end
  if url:match("^https?://") then
    if url:find("/room/", 1, true) or url:find("/seed/", 1, true) then
      return nil, "That is the room page link. Open it and use the server address shown there, "
        .. "for example archipelago.gg:38281."
    end
    url = url:gsub("^https?://", "")
  end
  local scheme, rest = url:match("^(wss?)://(.+)$")
  rest = (rest or url):gsub("/+$", "")
  local host, port = rest:match("^%[([^%]]+)%]:(%d+)$")
  if not host then host, port = rest:match("^([^:/%s]+):(%d+)$") end
  if not host and rest:match("^[^:/%s]+$") then host, port = rest, "38281" end
  if not host then
    return nil, ('"%s" is not a server address. Use host:port, for example archipelago.gg:38281.'):format(url)
  end
  if host:find("[^%w%.%-_:]") then
    return nil, ('The server name "%s" has characters that are not allowed. Check for typos.'):format(host)
  end
  port = tonumber(port)
  if not port or port < 1 or port > 65535 then
    return nil, ("The port must be a number from 1 to 65535 (got %s)."):format(tostring(port))
  end
  return scheme, host, port
end

local winhttpOk = nil
function WS.hasWinHTTP()
  if winhttpOk == nil then
    local ok, ffi = pcall(require, "ffi")
    winhttpOk = false
    if ok and ffi.os == "Windows" then
      local loaded, W = pcall(require, "archipelago.winhttp")
      winhttpOk = loaded and W.hasWebSocket() or false
      if not loaded then log.warn("WinHTTP unavailable: " .. tostring(W)) end
    end
    log.info("WinHTTP websockets " .. (winhttpOk and "available" or "not available"))
  end
  return winhttpOk
end

function WS.new(host, port, secure, transport)
  counter = counter + 1
  local self = setmetatable({}, WS)
  self.id = counter
  self.inName = "gcap_in_" .. counter
  self.outName = "gcap_out_" .. counter
  self.inbox = love.thread.getChannel(self.inName)
  self.outbox = love.thread.getChannel(self.outName)
  self.inbox:clear()
  self.outbox:clear()
  self.state = "connecting"
  self.host, self.port, self.secure, self.transport = host, port, secure, transport
  local script = transport == "socket" and "archipelago/ws_socket.lua" or "archipelago/ws_reader.lua"
  self.reader = love.thread.newThread(script)
  self.reader:start(host, port, secure, "/", self.inName, self.outName)
  log.info(("ws#%d connecting to %s://%s:%d (%s)"):format(counter, secure and "wss" or "ws", host, port, transport))
  return self
end

function WS:send(text)
  if self.state == "open" then self.outbox:push(text) end
end

function WS:close()
  if self.state == "open" then
    self.outbox:push("__close__")
  end
  self.state = "closing"
end

-- Events: { type = "open" | "message" | "close" | "error", msgs = ..., msg = ..., reason = ... }
function WS:poll()
  local events = {}
  local err = self.reader and self.reader:getError()
  if err then
    log.error("ws reader thread error: " .. err)
    events[#events + 1] = { type = "error", msg = err, reason = "The connection thread crashed (see ap_log.txt)." }
    self.reader = nil
    self.state = "closed"
  end
  while true do
    local ev = self.inbox:pop()
    if not ev then break end
    if ev.type == "open" then
      if self.transport ~= "socket" then
        self.writer = love.thread.newThread("archipelago/ws_writer.lua")
        self.writer:start(ev.ws, ev.session, ev.connect, self.outName)
      end
      if self.state == "closing" then
        self.outbox:push("__close__")
      else
        self.state = "open"
        events[#events + 1] = { type = "open" }
      end
    elseif ev.type == "message" then
      if ev.err then log.error("bad json from server: " .. tostring(ev.err)) end
      if self.state == "open" and ev.msgs then events[#events + 1] = ev end
    elseif ev.type == "close" or ev.type == "error" then
      self.state = "closed"
      events[#events + 1] = ev
    end
  end
  if self.writer then
    local werr = self.writer:getError()
    if werr then
      log.error("ws writer thread error: " .. werr)
      self.writer = nil
    end
  end
  return events
end

return WS
