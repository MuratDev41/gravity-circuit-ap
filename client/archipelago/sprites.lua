-- Item sprites for other games, from KaitoKid's ArchipelagoUtilities asset database
-- (github.com/agilbert1412/ArchipelagoUtilities, AssetDownloader). Each game is a zip of
-- "<Game>/<Game>_<Item>.png" files (48x48), "<Game>/<Game>.png" as the game's own icon, and an optional
-- aliases.json. Zips are cached in archipelago/sprites/ and fetched again after a week.
local json = require("archipelago.json")
local log = require("archipelago.log")

local S = {}

local HOST = "raw.githubusercontent.com"
local BASE = "/agilbert1412/ArchipelagoUtilities/main/KaitoKid.ArchipelagoUtilities.Net/"
  .. "KaitoKid.ArchipelagoUtilities.AssetDownloader/ZippedAssets/"
local DIR = "archipelago/sprites"
local MAX_AGE = 7 * 24 * 3600
local SIZE = 16
-- shown for games that aren't in the database, or have neither the item nor a game icon there
local FALLBACK = "archipelago/ap_item.png"

local games = {}    -- [clean game] = { state = "loading" | "ready" | "missing", items = {}, icon = path }
local images = {}   -- [path] = Image | false
local mounts = 0
local thread, requests, results

-- Same cleaning as the library: lowercase, without spaces, "_", "'", ":", "<" and ">".
local function clean(name)
  return (tostring(name or ""):lower():gsub("[%s_':<>]", ""))
end

local function fileName(game)
  return (tostring(game):gsub("[:<>]", ""))
end

local function urlEncode(s)
  return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function pngs(dir, out)
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
    local path = dir .. "/" .. name
    local info = love.filesystem.getInfo(path)
    if info and info.type == "directory" then
      pngs(path, out)
    elseif name:lower():match("%.png$") then
      out[#out + 1] = { path = path, base = name:sub(1, -5) }
    end
  end
  return out
end

local function register(key, zipPath)
  local entry = games[key]
  mounts = mounts + 1
  local mountPoint = "apsprites/" .. mounts
  if not love.filesystem.mount(zipPath, mountPoint) then
    log.warn("sprites: could not open " .. zipPath)
    entry.state = "missing"
    return
  end
  local items, icon, count = {}, nil, 0
  for _, file in ipairs(pngs(mountPoint, {})) do
    local sep = file.base:find("_", 1, true)
    if sep then
      items[clean(file.base:sub(sep + 1))] = file.path
      count = count + 1
    else
      icon = icon or file.path
    end
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems(mountPoint)) do
    local text = love.filesystem.read(mountPoint .. "/" .. name .. "/aliases.json")
    if text then
      local ok, decoded = pcall(json.decode, text)
      if ok and type(decoded) == "table" and type(decoded.Aliases) == "table" then
        for _, alias in ipairs(decoded.Aliases) do
          local path = items[clean(alias.AliasName)]
          if path and type(alias.ItemNames) == "table" then
            for _, itemName in ipairs(alias.ItemNames) do
              local k = clean(itemName)
              items[k] = items[k] or path
            end
          end
        end
      end
    end
  end
  entry.items, entry.icon, entry.state = items, icon, "ready"
  log.info(("sprites: %s, %d items"):format(entry.game, count))
end

local function start()
  if thread then return true end
  local ok, err = pcall(function()
    requests = love.thread.getChannel("gcap_sprites_req")
    results = love.thread.getChannel("gcap_sprites_res")
    requests:clear()
    results:clear()
    thread = love.thread.newThread("archipelago/sprites_fetch.lua")
    thread:start("gcap_sprites_req", "gcap_sprites_res")
  end)
  if not ok then
    log.warn("sprites: no fetch thread: " .. tostring(err))
    thread = false
  end
  return thread and true or false
end

local function request(game)
  local key = clean(game)
  if games[key] then return games[key] end
  local entry = { game = game, state = "loading" }
  games[key] = entry
  local zipPath = DIR .. "/" .. fileName(game) .. ".zip"
  entry.zip = zipPath
  local info = love.filesystem.getInfo(zipPath)
  if info and info.modtime and os.time() - info.modtime < MAX_AGE then
    register(key, zipPath)
  elseif start() then
    requests:push({ key = key, host = HOST, path = BASE .. urlEncode(fileName(game)) .. ".zip" })
  elseif info then
    register(key, zipPath)
  else
    entry.state = "missing"
  end
  return entry
end

function S.update()
  if not thread then return end
  local err = thread:getError()
  if err then
    log.error("sprites thread: " .. err)
    thread = false
    return
  end
  while true do
    local res = results:pop()
    if not res then break end
    local entry = games[res.key]
    if entry then
      if res.body then
        love.filesystem.createDirectory(DIR)
        love.filesystem.write(entry.zip, res.body)
        register(res.key, entry.zip)
      elseif love.filesystem.getInfo(entry.zip) then
        register(res.key, entry.zip)
      else
        if res.status ~= 404 then log.warn(("sprites: %s: %s"):format(entry.game, res.err)) end
        entry.state = "missing"
      end
    end
  end
end

-- Starts loading a game's sprites so they are ready when a shop opens.
function S.prefetch(game)
  if game then request(game) end
end

local hasFallback = nil
local function fallback()
  if hasFallback == nil then hasFallback = love.filesystem.getInfo(FALLBACK) ~= nil end
  return hasFallback and FALLBACK or nil
end

-- Path of the sprite for an item, else the game's own icon, else the AP icon; nil while the game is loading.
function S.find(game, item)
  if not game then return nil end
  local entry = request(game)
  if entry.state == "loading" then return nil end
  if entry.state == "ready" then
    local path = entry.items[clean(item)] or entry.icon
    if path then return path end
  end
  return fallback()
end

local function image(path)
  local img = images[path]
  if img == nil then
    local ok, res = pcall(love.graphics.newImage, path)
    img = ok and res or false
    if img then img:setFilter("nearest", "nearest") end
    images[path] = img
  end
  return img or nil
end

-- Runs when the game renders its layers; the shop's colour swap shader is turned off for the sprite.
local function render(img, x, y, scale, shade)
  local shader = love.graphics.getShader()
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setShader()
  love.graphics.setColor(shade, shade, shade, 1)
  love.graphics.draw(img, x, y, 0, scale, scale)
  love.graphics.setColor(r, g, b, a)
  love.graphics.setShader(shader)
end

-- Queues the sprite into the game's UI layer l, fitted into a SIZE x SIZE box at x, y. False if there is none.
function S.draw(game, item, x, y, l, dim)
  local path = S.find(game, item)
  local img = path and image(path)
  if not (img and GFX and GFX.pushUI) then return false end
  local w, h = img:getDimensions()
  local scale = SIZE / math.max(w, h)
  x = x + math.floor((SIZE - w * scale) / 2)
  y = y + math.floor((SIZE - h * scale) / 2)
  GFX:pushUI(l, render, img, x, y, scale, dim and 0.55 or 1)
  return true
end

return S
