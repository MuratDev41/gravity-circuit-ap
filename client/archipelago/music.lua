-- Music shuffle: slot_data.music_map maps music ids (content/audio/music/music.lua) to the ones that play instead.
-- The game loads and plays tracks by index (BGM[id]) through Audio; the track calls are wrapped to swap the index,
-- so the replacement is loaded, protected and played in its place. Calls made from inside a wrapped call keep the
-- index they were given, since it is already swapped. getCurrentTrack answers with the original id.
local client = require("archipelago.client")
local log = require("archipelago.log")

local MU = {}

local WRAPPED = { "loadBgmAsync", "playTrack", "stopTrack", "unloadTrack", "setProtected", "destroyTrack" }

local map, reverse = {}, {}
local depth = 0
local installed = false

local function wrap(name)
  local original = Audio[name]
  if type(original) ~= "function" then return end
  rawset(Audio, name, function(self, track, ...)
    if depth == 0 and track ~= nil then track = map[track] or track end
    depth = depth + 1
    local results = { pcall(original, self, track, ...) }
    depth = depth - 1
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
  end)
end

local function install()
  if installed or not (Audio and BGM and Audio.playTrack and Audio.loadBgmAsync) then return end
  for _, name in ipairs(WRAPPED) do wrap(name) end
  local current = Audio.getCurrentTrack
  if current then
    rawset(Audio, "getCurrentTrack", function(self, ...)
      local track = current(self, ...)
      return track and reverse[track] or track
    end)
  end
  installed = true
  log.info("hook installed: music shuffle")
end

-- Builds the swap table for the connected seed.
function MU.configure()
  map, reverse = {}, {}
  local music = client.isConnected() and client.slotData.music_map
  if type(music) ~= "table" or not BGM then return end
  local count = 0
  for from, to in pairs(music) do
    local a, b = BGM[from], BGM[to]
    if a and b and a ~= b then
      map[a], reverse[b] = b, a
      count = count + 1
    end
  end
  if count > 0 then log.info(("music shuffle: %d tracks swapped"):format(count)) end
end

function MU.update()
  install()
end

return MU
