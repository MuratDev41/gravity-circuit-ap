-- The game disables print() in release builds, so the client logs to archipelago/ap_log.txt.
-- Lines are buffered and appended every couple of seconds; repeated lines are collapsed.
local log = {}
local PATH = "archipelago/ap_log.txt"
local FLUSH_INTERVAL = 2
local MAX_BUFFERED = 200

local started = false
local buffer = {}
local lastFlush = 0
local lastLine, repeats = nil, 0

local function now()
  return love.timer and love.timer.getTime() or os.clock()
end

function log.flush()
  if repeats > 0 then
    buffer[#buffer + 1] = ("[%s] (last line repeated %d more times)\n"):format(os.date("%H:%M:%S"), repeats)
    repeats = 0
  end
  lastFlush = now()
  if #buffer == 0 then return end
  if not started then
    started = true
    love.filesystem.createDirectory("archipelago")
    love.filesystem.write(PATH, "")
  end
  love.filesystem.append(PATH, table.concat(buffer))
  buffer = {}
end

local function write(level, msg)
  local text = ("%-5s %s"):format(level, tostring(msg))
  if text == lastLine then
    repeats = repeats + 1
  else
    if repeats > 0 then
      buffer[#buffer + 1] = ("[%s] (last line repeated %d more times)\n"):format(os.date("%H:%M:%S"), repeats)
      repeats = 0
    end
    lastLine = text
    buffer[#buffer + 1] = ("[%s] %s\n"):format(os.date("%H:%M:%S"), text)
  end
  if #buffer >= MAX_BUFFERED then log.flush() end
end

function log.update()
  if now() - lastFlush >= FLUSH_INTERVAL then log.flush() end
end

function log.info(msg) write("INFO", msg) end
function log.warn(msg) write("WARN", msg) end
function log.error(msg) write("ERROR", msg) end

return log
