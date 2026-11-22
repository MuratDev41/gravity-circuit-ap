-- WebSocket client over LuaSocket, with TLS through Schannel (tls.lua) for wss:// and permessage-deflate.
-- Thread args: host, port, secure, path, inChannelName, outChannelName.
require("love.filesystem")
require("love.data")
local socket = require("socket")
local bit = require("bit")
local ffi = require("ffi")
local json = require("archipelago.json")

local host, port, secure, path, inName, outName = ...
local inbox = love.thread.getChannel(inName)
local outbox = love.thread.getChannel(outName)

local tls = nil
if secure then
  local ok, mod = pcall(require, "archipelago.tls")
  if not ok or not mod.available then
    inbox:push({ type = "error", msg = "no TLS available: " .. tostring(ok and "secur32 missing" or mod),
                 reason = "nosecure" })
    return
  end
  tls = mod
end

local function socketReason(err)
  err = tostring(err)
  if err:find("refused", 1, true) then return "refused" end
  if err:find("timeout", 1, true) or err:find("timed out", 1, true) then return "timeout" end
  if err:find("not found", 1, true) or err:find("host", 1, true) then return "notfound" end
  if err:find("closed", 1, true) or err:find("reset", 1, true) then return "reset" end
  return "other"
end

math.randomseed(os.time() + math.floor((socket.gettime() % 1) * 1e6))
local function randomBytes(n)
  local t = {}
  for i = 1, n do t[i] = string.char(math.random(0, 255)) end
  return table.concat(t)
end

local function fail(msg, reason, status)
  inbox:push({ type = "error", msg = msg, reason = reason, status = status })
end

local tcp = socket.tcp()
tcp:settimeout(10)
local connected, cerr = tcp:connect(host, port)
if not connected then return fail("connect: " .. tostring(cerr), socketReason(cerr)) end
tcp:setoption("tcp-nodelay", true)

-- conn:send(data), conn:receive() -> data | nil, err, conn:settimeout(t), conn:close()
local conn
if tls then
  local c, terr = tls.connect(tcp, host, 10)
  if not c then
    tcp:close()
    return fail("tls: " .. tostring(terr), "tls")
  end
  conn = c
else
  conn = {
    send = function(_, data)
      local i = 1
      while i <= #data do
        local last, err, partial = tcp:send(data, i)
        if last then i = last + 1
        elseif err == "timeout" then i = (partial or i - 1) + 1
        else return nil, err end
      end
      return true
    end,
    receive = function()
      local data, err, partial = tcp:receive(65536)
      local chunk = data or partial
      if chunk and #chunk > 0 then return chunk end
      return nil, err
    end,
    settimeout = function(_, t) tcp:settimeout(t) end,
    close = function() tcp:close() end,
  }
end

-- handshake ----------------------------------------------------------------------------------------------
local hostHeader = host:find(":", 1, true) and ("[" .. host .. "]") or host
local request = table.concat({
  "GET " .. (path or "/") .. " HTTP/1.1",
  "Host: " .. hostHeader .. ":" .. port,
  "Upgrade: websocket",
  "Connection: Upgrade",
  "Sec-WebSocket-Key: " .. love.data.encode("string", "base64", randomBytes(16)),
  "Sec-WebSocket-Version: 13",
  "Sec-WebSocket-Extensions: permessage-deflate; client_no_context_takeover; server_no_context_takeover",
  "User-Agent: GravityCircuitAP",
  "", "",
}, "\r\n")
local sent, serr = conn:send(request)
if not sent then
  conn:close()
  return fail("handshake send: " .. tostring(serr), socketReason(serr))
end

local response = ""
local deadline = socket.gettime() + 10
conn:settimeout(0.2)
while not response:find("\r\n\r\n", 1, true) do
  local data, rerr = conn:receive()
  if data then response = response .. data
  elseif rerr ~= "timeout" then
    conn:close()
    return fail("handshake: " .. tostring(rerr), socketReason(rerr))
  end
  if socket.gettime() > deadline then
    conn:close()
    return fail("handshake: no answer", "timeout")
  end
end
local headEnd = response:find("\r\n\r\n", 1, true)
local head, leftover = response:sub(1, headEnd - 1), response:sub(headEnd + 4)
local status = tonumber(head:match("^HTTP/%d%.%d (%d+)"))
if status ~= 101 then
  conn:close()
  return fail("handshake: " .. tostring(head:match("^[^\r\n]*")), "notap", status)
end

-- permessage-deflate: messages are inflated one by one, so it is only used when the server resets its
-- context per message; ours are compressed one by one, so they are only compressed when the server
-- agreed to client_no_context_takeover.
local inflate, deflateOut = false, false
for line in head:gmatch("[^\r\n]+") do
  local name, value = line:match("^([^:]+):%s*(.*)$")
  if name and name:lower() == "sec-websocket-extensions" and value:find("permessage-deflate", 1, true) then
    inflate = value:find("server_no_context_takeover", 1, true) ~= nil
    deflateOut = value:find("client_no_context_takeover", 1, true) ~= nil
    if not inflate then
      conn:close()
      return fail("server compression without server_no_context_takeover", "other")
    end
  end
end

inbox:push({ type = "open", compressed = inflate })

-- frames -------------------------------------------------------------------------------------------------
local function sendFrame(opcode, payload, rsv1)
  payload = payload or ""
  local len = #payload
  local b1 = 0x80 + opcode + (rsv1 and 0x40 or 0)
  local header
  if len < 126 then
    header = string.char(b1, 0x80 + len)
  elseif len < 65536 then
    header = string.char(b1, 0x80 + 126, bit.rshift(len, 8), bit.band(len, 0xff))
  else
    local bytes = {}
    for i = 7, 0, -1 do bytes[#bytes + 1] = math.floor(len / 2 ^ (8 * i)) % 256 end
    header = string.char(b1, 0x80 + 127, unpack(bytes))
  end
  local mask = randomBytes(4)
  local m = { mask:byte(1, 4) }
  local out = ffi.new("uint8_t[?]", len)
  ffi.copy(out, payload, len)
  for i = 0, len - 1 do out[i] = bit.bxor(out[i], m[i % 4 + 1]) end
  return conn:send(header .. mask .. ffi.string(out, len))
end

local function sendText(text)
  if deflateOut and #text >= 64 then
    return sendFrame(0x1, love.data.compress("string", "deflate", text), true)
  end
  return sendFrame(0x1, text)
end

-- a compressed message ends on a sync flush; adding an empty final block makes it a whole deflate stream
local FINISH = "\0\0\255\255\1\0\0\255\255"
local function inflateText(payload)
  return love.data.decompress("string", "deflate", payload .. FINISH)
end

local chunks, size = {}, 0
if #leftover > 0 then chunks[1], size = leftover, #leftover end
local function joined()
  if #chunks > 1 then chunks = { table.concat(chunks) } end
  return chunks[1] or ""
end
local function consume(n)
  local rest = joined():sub(n + 1)
  chunks = rest ~= "" and { rest } or {}
  size = #rest
end

-- Returns fin, opcode, payload, rsv1 for the next complete frame, or nil.
local function nextFrame()
  if size < 2 then return nil end
  local head1 = chunks[1]
  if #head1 < 14 and #chunks > 1 then head1 = joined() end
  local b1, b2 = head1:byte(1, 2)
  local fin, opcode, rsv1 = bit.band(b1, 0x80) ~= 0, bit.band(b1, 0x0f), bit.band(b1, 0x40) ~= 0
  local masked, len = bit.band(b2, 0x80) ~= 0, bit.band(b2, 0x7f)
  local pos = 3
  if len == 126 then
    if size < 4 then return nil end
    local x, y = head1:byte(3, 4)
    len, pos = x * 256 + y, 5
  elseif len == 127 then
    if size < 10 then return nil end
    len = 0
    for i = 3, 10 do len = len * 256 + head1:byte(i) end
    pos = 11
  end
  local maskKey
  if masked then
    if size < pos + 3 then return nil end
    maskKey = { head1:byte(pos, pos + 3) }
    pos = pos + 4
  end
  if size < pos - 1 + len then return nil end
  local payload = joined():sub(pos, pos + len - 1)
  consume(pos - 1 + len)
  if maskKey then
    local buf = ffi.new("uint8_t[?]", len)
    ffi.copy(buf, payload, len)
    for i = 0, len - 1 do buf[i] = bit.bxor(buf[i], maskKey[i % 4 + 1]) end
    payload = ffi.string(buf, len)
  end
  return fin, opcode, payload, rsv1
end

local message, messageCompressed = {}, false
local closing, closeDeadline = false, nil

local function finish(ev)
  if ev then inbox:push(ev) end
  conn:close()
end

while true do
  while not closing do
    local msg = outbox:pop()
    if not msg then break end
    if msg == "__close__" then
      sendFrame(0x8, string.char(0x03, 0xe8))
      closing, closeDeadline = true, socket.gettime() + 2
    else
      local ok, err = sendText(msg)
      if not ok then return finish({ type = "close", msg = "send: " .. tostring(err), reason = "lost" }) end
    end
  end

  conn:settimeout(0.02)
  local chunk, err = conn:receive()
  if chunk then
    chunks[#chunks + 1] = chunk
    size = size + #chunk
  end

  while true do
    local fin, opcode, payload, rsv1 = nextFrame()
    if not fin and not opcode then break end
    if opcode == 0x8 then
      if not closing then sendFrame(0x8, payload:sub(1, 2)) end
      return finish(not closing and { type = "close", msg = "server closed the connection", reason = "closed" })
    elseif opcode == 0x9 then
      sendFrame(0xA, payload)
    elseif opcode == 0x1 or opcode == 0x2 or opcode == 0x0 then
      if opcode ~= 0x0 then messageCompressed = rsv1 end
      message[#message + 1] = payload
      if fin then
        local text = table.concat(message)
        message = {}
        local decoded, msgs
        if messageCompressed then
          decoded, text = pcall(inflateText, text)
          if not decoded then
            inbox:push({ type = "message", err = "inflate: " .. tostring(text) })
            text = nil
          end
        end
        if text then
          decoded, msgs = pcall(json.decode, text)
          if decoded and type(msgs) == "table" then
            inbox:push({ type = "message", msgs = msgs })
          else
            inbox:push({ type = "message", err = tostring(msgs) })
          end
        end
      end
    end
  end

  if err and err ~= "timeout" then
    return finish(not closing and { type = "close", msg = "receive: " .. tostring(err), reason = "lost" })
  end
  if closing and socket.gettime() > closeDeadline then return finish() end
end
