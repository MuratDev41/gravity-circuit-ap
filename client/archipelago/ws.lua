local log = require("archipelago.log")

local WS = {}
WS.__index = WS

local counter = 0

-- Accepts "wss://host:port", "ws://host:port" or "host:port".
function WS.parseUrl(url)
  local scheme, rest = url:match("^(wss?)://(.+)$")
  rest = rest or url
  rest = rest:gsub("/+$", "")
  local host, port = rest:match("^%[?([^%]]+)%]?:(%d+)$")
  if not host then host, port = rest, "38281" end
  return scheme, host, tonumber(port)
end

function WS.new(host, port, secure)
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
  self.host, self.port, self.secure = host, port, secure
  self.reader = love.thread.newThread("archipelago/ws_reader.lua")
  self.reader:start(host, port, secure, "/", self.inName, self.outName)
  log.info(("ws#%d connecting to %s://%s:%d"):format(counter, secure and "wss" or "ws", host, port))
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

-- Events: { type = "open" | "message" | "close" | "error", data = ..., msg = ... }
function WS:poll()
  local events = {}
  local err = self.reader and self.reader:getError()
  if err then
    log.error("ws reader thread error: " .. err)
    events[#events + 1] = { type = "error", msg = err }
    self.reader = nil
    self.state = "closed"
  end
  while true do
    local ev = self.inbox:pop()
    if not ev then break end
    if ev.type == "open" then
      self.writer = love.thread.newThread("archipelago/ws_writer.lua")
      self.writer:start(ev.ws, ev.session, ev.connect, self.outName)
      if self.state == "closing" then
        self.outbox:push("__close__")
      else
        self.state = "open"
        events[#events + 1] = { type = "open" }
      end
    elseif ev.type == "message" then
      if self.state == "open" then events[#events + 1] = ev end
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
