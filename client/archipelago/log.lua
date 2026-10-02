-- The game disables print() in release builds, so the client logs to archipelago/ap_log.txt.
local log = {}
local PATH = "archipelago/ap_log.txt"
local started = false

local function write(level, msg)
  if not started then
    started = true
    love.filesystem.createDirectory("archipelago")
    love.filesystem.write(PATH, "")
  end
  local line = string.format("[%s] %-5s %s\n", os.date("%H:%M:%S"), level, tostring(msg))
  love.filesystem.append(PATH, line)
end

function log.info(msg) write("INFO", msg) end
function log.warn(msg) write("WARN", msg) end
function log.error(msg) write("ERROR", msg) end

return log
