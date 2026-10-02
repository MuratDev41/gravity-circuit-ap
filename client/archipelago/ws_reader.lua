-- Thread args: host, port, secure, path, inChannelName, outChannelName.
-- The writer thread owns and frees the WinHTTP handles; this thread signals it with "__dead__".
require("love.filesystem")
local ffi = require("ffi")
local host, port, secure, path, inName, outName = ...
local inbox = love.thread.getChannel(inName)
local outbox = love.thread.getChannel(outName)

local ok, W = pcall(require, "archipelago.winhttp")
if not ok then
  inbox:push({ type = "error", msg = "could not load WinHTTP: " .. tostring(W) })
  return
end

local ws, session, connect = W.open(host, port, secure, path)
if not ws then
  inbox:push({ type = "error", msg = session })
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
    inbox:push({ type = "close", msg = "connection lost (" .. tonumber(rc) .. ")" })
    break
  end
  local t = btype[0]
  if t == W.BUFFER_CLOSE then
    inbox:push({ type = "close", msg = "server closed the connection" })
    break
  end
  parts[#parts + 1] = ffi.string(buf, read[0])
  if t == W.BUFFER_UTF8_MESSAGE or t == W.BUFFER_BINARY_MESSAGE then
    inbox:push({ type = "message", data = table.concat(parts) })
    parts = {}
  end
end

outbox:push("__dead__")
