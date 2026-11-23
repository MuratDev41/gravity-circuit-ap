-- Boss health: every boss gets its health from GAMEDATA.boss.getMaxHealth (32, or 48 for the final boss and Rude
-- Enemies). With boss_health, slot_data.boss_hp maps a stage's map id to the health its bosses get instead. The
-- final boss and other values (debug, boss rush halves) are left alone. The boss HUD reads the same function.
local client = require("archipelago.client")
local log = require("archipelago.log")

local B = { game = nil }

local VANILLA = 32
local installed = false

local function healthFor(stage)
  local map = client.isConnected() and client.slotData.boss_hp
  local hp = type(map) == "table" and stage and tonumber(map[stage])
  if not hp then return nil end
  return math.max(1, math.min(48, math.floor(hp)))
end

function B.update()
  if installed then return end
  local boss = GAMEDATA and GAMEDATA.boss
  if not (boss and boss.getMaxHealth) then return end
  local original = boss.getMaxHealth
  boss.getMaxHealth = function(hud, initialization, final, ...)
    local value = original(hud, initialization, final, ...)
    if final or value ~= VANILLA then return value end
    local G = B.game
    return healthFor(G and G.currentStage and G.currentStage()) or value
  end
  installed = true
  log.info("hook installed: boss health")
end

return B
