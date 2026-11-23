-- Data chip markers: with random_data_chips, enemies whose data chip check isn't done yet get the Archipelago icon
-- above them. An enemy's data chip id is its class name (DataChip.spawn(self.class.name, ...)), the same as the
-- location's obj in data.lua. Drawn on the ENEMIES/PARTICLES layer.
local client = require("archipelago.client")
local data = require("archipelago.data")
local log = require("archipelago.log")

local M = { game = nil }

local ICON = "archipelago/ap_item.png"
local REFRESH_SECONDS = 1

local image, imageTried = nil, false
local pending = {}
local nextRefresh = 0
local layer = nil

local function enabled()
  local G = M.game
  if not (G and G.active and client.isConnected()) then return false end
  if client.slotData.data_chip_markers == false then return false end
  return G.optionEnabled("datachiprandom") == true
end

local function refresh()
  pending = {}
  for _, loc in ipairs(data.LOCATIONS) do
    if loc.kind == "datachiprandom" and not M.game.isDone(loc.id) then pending[loc.obj] = true end
  end
end

local function drawIcon(img, x, y)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y)
end

function M.update()
  if not enabled() then return end
  local stage = M.game.currentStage()
  if not stage or stage == "HUB" then return end
  if not imageTried then
    imageTried = true
    local ok, img = pcall(love.graphics.newImage, ICON)
    if ok then
      image = img
      image:setFilter("nearest", "nearest")
    else
      log.error("marker icon: " .. tostring(img))
    end
  end
  if not image or not (GameObject and GameObject.active and GFX and Layer) then return end
  if not layer then
    local ok, l = pcall(function() return Layer:get("ENEMIES", "PARTICLES") end)
    if not ok or not l then return end
    layer = l
  end
  local now = love.timer.getTime()
  if now >= nextRefresh then
    nextRefresh = now + REFRESH_SECONDS
    refresh()
  end
  if next(pending) == nil then return end
  local l = layer()
  local bob = math.floor(math.sin(now * 4) * 1.5 + 0.5)
  local list = GameObject.active.draw
  for i = 1, list.len or 0 do
    local obj = list[i]
    local cls = obj and obj.class
    if cls and pending[cls.name] and obj.getMiddlePoint and obj.dimensions and obj.transform
      and not obj.deleted and not (obj.state and obj.state.isDestroyed) then
      local x, y, _, h = obj:getMiddlePoint()
      local top = y - math.floor(h / 2)
      if not (Camera and Camera.isWithinView) or Camera:isWithinView(x, top, 40) then
        GFX:push(l, drawIcon, image, x - 8, top - 20 + bob)
      end
    end
  end
end

return M
