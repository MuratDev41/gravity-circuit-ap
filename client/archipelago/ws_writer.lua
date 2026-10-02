-- Thread args: wsNumber, sessionNumber, connectNumber, outChannelName.
-- WinHTTP allows one send and one receive in flight at once, so sending runs on its own thread next to
-- the blocking reader. This thread is the only one that frees the WinHTTP handles.
require("love.filesystem")
local wsNum, sessionNum, connectNum, outName = ...
local outbox = love.thread.getChannel(outName)
local W = require("archipelago.winhttp")
local ws = W.numberToHandle(wsNum)

local readerAlive = true
while true do
  local msg = outbox:demand()
  if msg == "__dead__" then
    readerAlive = false
    break
  elseif msg == "__close__" then
    -- sends a close frame; the server's reply wakes the reader, which then pushes "__dead__"
    W.lib.WinHttpWebSocketClose(ws, 1000, nil, 0)
    break
  else
    local rc = W.lib.WinHttpWebSocketSend(ws, W.BUFFER_UTF8_MESSAGE, msg, #msg)
    if rc ~= 0 then
      W.lib.WinHttpWebSocketClose(ws, 1011, nil, 0)
      break
    end
  end
end

if readerAlive then
  -- wait (bounded) for the reader to leave WinHttpWebSocketReceive before freeing the handle
  local deadline = 50
  while deadline > 0 do
    local msg = outbox:demand(0.1)
    if msg == "__dead__" then readerAlive = false break end
    deadline = deadline - 1
  end
end

W.lib.WinHttpCloseHandle(ws)
W.lib.WinHttpCloseHandle(W.numberToHandle(connectNum))
W.lib.WinHttpCloseHandle(W.numberToHandle(sessionNum))
