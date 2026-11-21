-- Thread args: host, port, secure, path, inChannelName, outChannelName.
-- The writer thread owns and frees the WinHTTP handles; this thread signals it with "__dead__".
require("love.filesystem")
local ffi = require("ffi")
local host, port, secure, path, inName, outName = ...
local inbox = love.thread.getChannel(inName)
local outbox = love.thread.getChannel(outName)

local ok, W = pcall(require, "archipelago.winhttp")
if not ok then
  inbox:push({ type = "error", msg = "could not load WinHTTP: " .. tostring(W), reason = "nowinhttp" })
  return
end
local json = require("archipelago.json")

local ws, session, connect, httpStatus = W.open(host, port, secure, path)
if not ws then
  local msg, code = session, connect
  local reason = code and W.reason(code) or (httpStatus and "notap") or "other"
  inbox:push({ type = "error", msg = msg, reason = reason, status = httpStatus })
  return
end

inbox:push({
  type = "open",
  ws = W.handleToNumber(ws),
  session = W.handleToNumber(session),
  connect = W.handleToNumber(connect),
})

local SIZE = 65536
local buf = ffi.new("uint8_t[?]", SIZE)
local read = ffi.new("unsigned long[1]")
local btype = ffi.new("int[1]")
local parts = {}

while true do
  local rc = W.lib.WinHttpWebSocketReceive(ws, buf, SIZE, read, btype)
  if rc ~= 0 then
    inbox:push({ type = "close", msg = "connection lost (" .. tonumber(rc) .. ")", reason = "lost" })
    break
  end
  local t = btype[0]
  if t == W.BUFFER_CLOSE then
    inbox:push({ type = "close", msg = "server closed the connection", reason = "closed" })
    break
  end
  parts[#parts + 1] = ffi.string(buf, read[0])
  if t == W.BUFFER_UTF8_MESSAGE or t == W.BUFFER_BINARY_MESSAGE then
    local text = table.concat(parts)
    parts = {}
    local decoded, msgs = pcall(json.decode, text)
    if decoded and type(msgs) == "table" then
      inbox:push({ type = "message", msgs = msgs })
    else
      inbox:push({ type = "message", err = tostring(msgs) })
    end
  end
end

outbox:push("__dead__")
