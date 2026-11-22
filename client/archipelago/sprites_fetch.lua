-- HTTPS GET for sprite zips, one request at a time. Thread args: request channel name, result channel name.
-- Requests: { key = ..., host = ..., path = ... }. Results: { key = ..., body = ... } or { key = ..., err = ... }.
require("love.filesystem")
local socket = require("socket")

local reqName, resName = ...
local requests = love.thread.getChannel(reqName)
local results = love.thread.getChannel(resName)

local okTls, tls = pcall(require, "archipelago.tls")
if not okTls then tls = nil end

local function get(host, path)
  if not (tls and tls.available) then return nil, "no TLS" end
  local tcp = socket.tcp()
  tcp:settimeout(10)
  local ok, err = tcp:connect(host, 443)
  if not ok then return nil, "connect: " .. tostring(err) end
  local conn, terr = tls.connect(tcp, host, 10)
  if not conn then
    tcp:close()
    return nil, "tls: " .. tostring(terr)
  end
  -- HTTP/1.0 so the body is never chunked and the server closes when done
  local sent, serr = conn:send(("GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: GravityCircuitAP\r\n\r\n"):format(path, host))
  if not sent then
    conn:close()
    return nil, "send: " .. tostring(serr)
  end
  conn:settimeout(0.5)
  local parts, size, length, headEnd = {}, 0, nil, nil
  local deadline = socket.gettime() + 30
  while true do
    local data, rerr = conn:receive()
    if data then
      parts[#parts + 1] = data
      size = size + #data
      if not headEnd then
        local all = table.concat(parts)
        parts = { all }
        headEnd = all:find("\r\n\r\n", 1, true)
        if headEnd then length = tonumber(all:sub(1, headEnd):lower():match("\ncontent%-length:%s*(%d+)")) end
      end
      if headEnd and length and size >= headEnd + 3 + length then break end
    elseif rerr == "closed" then
      break
    elseif rerr ~= "timeout" then
      conn:close()
      return nil, "receive: " .. tostring(rerr)
    end
    if socket.gettime() > deadline then
      conn:close()
      return nil, "timeout"
    end
  end
  conn:close()
  local all = table.concat(parts)
  headEnd = all:find("\r\n\r\n", 1, true)
  if not headEnd then return nil, "no response" end
  local status = tonumber(all:match("^HTTP/%d%.%d (%d+)"))
  if status ~= 200 then return nil, "HTTP " .. tostring(status), status end
  local body = all:sub(headEnd + 4)
  if length then body = body:sub(1, length) end
  return body
end

while true do
  local req = requests:demand()
  if req == "__quit__" then return end
  local ok, body, err, status = pcall(get, req.host, req.path)
  if not ok then body, err = nil, body end
  if body then
    results:push({ key = req.key, body = body })
  else
    results:push({ key = req.key, err = tostring(err), status = status })
  end
end
