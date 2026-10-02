-- Installed to %APPDATA%\Gravity Circuit\. The game's conf.lua sets appendidentity = false, so LÖVE loads this
-- file instead of the game's own main.lua; it loads the client and then runs the original main.lua.

local ok, AP = pcall(require, "archipelago.init")
if ok then
  local installed, err = pcall(AP.install)
  if not installed then love.filesystem.append("archipelago/ap_log.txt", "install failed: " .. tostring(err) .. "\n") end
else
  love.filesystem.createDirectory("archipelago")
  love.filesystem.append("archipelago/ap_log.txt", "load failed: " .. tostring(AP) .. "\n")
end

local identity = love.filesystem.getIdentity()
love.filesystem.setIdentity(identity, true)
local chunk, err = love.filesystem.load("main.lua")
love.filesystem.setIdentity(identity, false)
if not chunk then error("Archipelago loader could not load the game's main.lua: " .. tostring(err)) end

return chunk("main")
