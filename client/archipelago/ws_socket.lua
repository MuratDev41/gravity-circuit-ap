-- ws:// client over LuaSocket (LÖVE has no TLS, so no wss://).
-- Thread args: host, port, secure, path, inChannelName, outChannelName.
require("love.filesystem")
local socket = require("socket")
local bit = require("bit")
local ffi = require("ffi")
local json = require("archipelago.json")

local host, port, secure, path, inName, outName = ...
local inbox = love.thread.getChannel(inName)
local outbox = love.thread.getChannel(outName)

if secure then
  inbox:push({ type = "error", msg = "wss:// needs WinHTTP", reason = "nosecure" })
  return
end

local function socketReason(err)
  err = tostring(err)
  if err:find("refused", 1, true) then return "refused" end
  if err:find("timeout", 1, true) then return "timeout" end
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

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
  return ((s:gsub(".", function(c)
    local r, b = "", c:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return B64:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#s % 3 + 1])
end

local tcp = socket.tcp()
tcp:settimeout(10)
local connected, cerr = tcp:connect(host, port)
if not connected then
  inbox:push({ type = "error", msg = "connect: " .. tostring(cerr), reason = socketReason(cerr) })
  return
end
tcp:setoption("tcp-nodelay", true)

local hostHeader = host:find(":", 1, true) and ("[" .. host .. "]") or host
local request = table.concat({
  "GET " .. (path or "/") .. " HTTP/1.1",
  "Host: " .. hostHeader .. ":" .. port,
  "Upgrade: websocket",
  "Connection: Upgrade",
  "Sec-WebSocket-Key: " .. base64(randomBytes(16)),
  "Sec-WebSocket-Version: 13",
  "User-Agent: GravityCircuitAP",
  "", "",
}, "\r\n")
local sent, serr = tcp:send(request)
if not sent then
  tcp:close()
  inbox:push({ type = "error", msg = "handshake send: " .. tostring(serr), reason = socketReason(serr) })
  return
end
local statusLine, rerr = tcp:receive("*l")
local status = statusLine and tonumber(statusLine:match("^HTTP/%d%.%d (%d+)"))
if status ~= 101 then
  tcp:close()
  inbox:push({ type = "error", msg = "handshake: " .. tostring(statusLine or rerr),
               reason = status and "notap" or socketReason(rerr), status = status })
  return
end
repeat
  local line = tcp:receive("*l")
until not line or line == ""

inbox:push({ type = "open" })

local function sendFrame(opcode, payload)
  payload = payload or ""
  local len = #payload
  local header
  if len < 126 then
    header = string.char(0x80 + opcode, 0x80 + len)
  elseif len < 65536 then
    header = string.char(0x80 + opcode, 0x80 + 126, bit.rshift(len, 8), bit.band(len, 0xff))
  else
    local bytes = {}
    for i = 7, 0, -1 do bytes[#bytes + 1] = math.floor(len / 2 ^ (8 * i)) % 256 end
    header = string.char(0x80 + opcode, 0x80 + 127, unpack(bytes))
  end
  -- client frames must be masked
  local mask = randomBytes(4)
  local m = { mask:byte(1, 4) }
  local out = ffi.new("uint8_t[?]", len)
  ffi.copy(out, payload, len)
  for i = 0, len - 1 do out[i] = bit.bxor(out[i], m[i % 4 + 1]) end
  local data = header .. mask .. ffi.string(out, len)
  local i = 1
  while i <= #data do
    local last, err, partial = tcp:send(data, i)
    if last then
      i = last + 1
    elseif err == "timeout" then
      i = (partial or i - 1) + 1
    else
      return false, err
    end
  end
  return true
end

local chunks, size = {}, 0
local function joined()
  if #chunks > 1 then chunks = { table.concat(chunks) } end
  return chunks[1] or ""
end
local function consume(n)
  local rest = joined():sub(n + 1)
  chunks = rest ~= "" and { rest } or {}
  size = #rest
end

-- Returns fin, opcode, payload for the next complete frame, or nil.
local function nextFrame()
  if size < 2 then return nil end
  local head = chunks[1]
  if #head < 14 and #chunks > 1 then head = joined() end
  local b1, b2 = head:byte(1, 2)
  local fin, opcode = bit.band(b1, 0x80) ~= 0, bit.band(b1, 0x0f)
  local masked, len = bit.band(b2, 0x80) ~= 0, bit.band(b2, 0x7f)
  local pos = 3
  if len == 126 then
    if size < 4 then return nil end
    local x, y = head:byte(3, 4)
    len, pos = x * 256 + y, 5
  elseif len == 127 then
    if size < 10 then return nil end
    len = 0
    for i = 3, 10 do len = len * 256 + head:byte(i) end
    pos = 11
  end
  local maskKey
  if masked then
    if size < pos + 3 then return nil end
    maskKey = { head:byte(pos, pos + 3) }
    pos = pos + 4
  end
  if size < pos - 1 + len then return nil end
  local all = joined()
  local payload = all:sub(pos, pos + len - 1)
  consume(pos - 1 + len)
  if maskKey then
    local buf = ffi.new("uint8_t[?]", len)
    ffi.copy(buf, payload, len)
    for i = 0, len - 1 do buf[i] = bit.bxor(buf[i], maskKey[i % 4 + 1]) end
    payload = ffi.string(buf, len)
  end
  return fin, opcode, payload
end

local message = {}
local closing, closeDeadline = false, nil

local function finish(ev)
  if ev then inbox:push(ev) end
  tcp:close()
end

while true do
  while not closing do
    local msg = outbox:pop()
    if not msg then break end
    if msg == "__close__" then
      sendFrame(0x8, string.char(0x03, 0xe8))
      closing, closeDeadline = true, socket.gettime() + 2
    else
      local ok, err = sendFrame(0x1, msg)
      if not ok then return finish({ type = "close", msg = "send: " .. tostring(err), reason = "lost" }) end
    end
  end

  tcp:settimeout(0.02)
  local data, err, partial = tcp:receive(65536)
  local chunk = data or partial
  if chunk and #chunk > 0 then
    chunks[#chunks + 1] = chunk
    size = size + #chunk
  end

  while true do
    local fin, opcode, payload = nextFrame()
    if not fin and not opcode then break end
    if opcode == 0x8 then
      if not closing then sendFrame(0x8, payload:sub(1, 2)) end
      return finish(not closing and { type = "close", msg = "server closed the connection", reason = "closed" })
    elseif opcode == 0x9 then
      sendFrame(0xA, payload)
    elseif opcode == 0x1 or opcode == 0x2 or opcode == 0x0 then
      message[#message + 1] = payload
      if fin then
        local text = table.concat(message)
        message = {}
        local decoded, msgs = pcall(json.decode, text)
        if decoded and type(msgs) == "table" then
          inbox:push({ type = "message", msgs = msgs })
        else
          inbox:push({ type = "message", err = tostring(msgs) })
        end
      end
    end
  end

  if err and err ~= "timeout" then
    return finish(not closing and { type = "close", msg = "receive: " .. tostring(err), reason = "lost" })
  end
  if closing and socket.gettime() > closeDeadline then return finish() end
end
