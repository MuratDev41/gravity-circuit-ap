-- Knockback Link (archipelago.miraheze.org/wiki/Knockback_Link): Bounce packets tagged "KnockbackLink" carry the
-- change in velocity of a player who got knocked back. Like Silksong's version only the direction is used: a
-- received knockback puts Kai in his damaged state without losing health, and a hit sends the direction scaled to
-- STRENGTH (PixelDraw's standard enemy launch). One per second each way; received ones expire after LIFETIME.
local client = require("archipelago.client")
local log = require("archipelago.log")

-- settings is replaced by the F9 panel's table; knockbacklink is "auto" (the YAML), "on" or "off"
local KB = { game = nil, settings = { knockbacklink = "auto" } }

local TAG = "KnockbackLink"
local STRENGTH = 40
local COOLDOWN = 1
local LIFETIME = 3

local pending, expires = nil, 0
local lastSent, lastApplied = -100, -100
local seen = {}
local applyingRemote = false
local hooked = false

function KB.fromYaml()
  return client.slotData and client.slotData.knockback_link == true or false
end

function KB.enabled()
  local mode = KB.settings.knockbacklink
  if mode == "on" then return true end
  if mode == "off" then return false end
  return KB.fromYaml()
end

-- Sends the KnockbackLink tag to the server to match the setting.
function KB.apply()
  client.setTag(TAG, KB.enabled())
  if not KB.enabled() then pending = nil end
end

local function player()
  local G = KB.game
  if not (G and G.active and G.currentStage and G.currentStage()) then return nil end
  if not (GameObject and GameObject.getPlayer) then return nil end
  return GameObject:getPlayer()
end

local function send(kai)
  local now = love.timer.getTime()
  if now - lastSent < COOLDOWN or not (client.isConnected() and KB.enabled()) then return end
  local h, v = kai.velocity and kai.velocity.horizontal, kai.velocity and kai.velocity.vertical
  if not (h and v) then return end
  local x = h.momentum ~= 0 and h.momentum or (h.current or 0) * (h.direction or 0)
  local y = -(v.current or 0) -- the game's y grows downward
  local length = math.sqrt(x * x + y * y)
  if length == 0 then return end
  lastSent = now
  client.bounce({ TAG }, {
    source = client.slotName, uuid = client.uuid(), time = os.time(),
    cause = client.slotName .. " was knocked back",
    value = { x = x / length * STRENGTH, y = y / length * STRENGTH, z = 0 },
  })
end

local function hook()
  if hooked then return end
  local kai = player()
  local states = kai and kai.class and kai.class.static and kai.class.static.states
  local damaged = states and states.DAMAGED
  if not (damaged and damaged.enteredState) then return end
  local entered = damaged.enteredState
  damaged.enteredState = function(self, ...)
    local results = { entered(self, ...) }
    if not applyingRemote then
      local ok, err = pcall(send, self)
      if not ok then log.error("knockback send: " .. tostring(err)) end
    end
    return unpack(results)
  end
  hooked = true
  log.info("hook installed: knockbackLink")
end

function KB.onBounce(data)
  if not KB.enabled() or type(data) ~= "table" then return end
  local value = data.value
  if type(data.source) ~= "string" or type(data.time) ~= "number" or type(value) ~= "table"
    or type(value.x) ~= "number" or type(value.y) ~= "number" then
    return
  end
  if data.uuid == client.uuid() or (data.uuid == nil and data.source == client.slotName) then return end
  local now = love.timer.getTime()
  for k, t in pairs(seen) do if now - t > 30 then seen[k] = nil end end
  local key = data.source .. "\n" .. tostring(data.uuid) .. "\n" .. tostring(data.time)
  if seen[key] then return end
  seen[key] = now
  pending = { x = value.x, y = value.y, source = data.source }
  expires = now + LIFETIME
end

local function canApply(kai)
  local G = KB.game
  return kai and not kai.dead and (kai.health or 0) > 0 and kai.checkVulnerable and kai:checkVulnerable()
    and not kai:isInDamagedState() and not (GAMESTATE and GAMESTATE.isGameOver) and not G.isPaused()
end

function KB.update()
  hook()
  if not pending then return end
  local now = love.timer.getTime()
  if now > expires then
    pending = nil
    return
  end
  if now - lastApplied < COOLDOWN then return end
  local kai = player()
  if not canApply(kai) then return end
  local dir = pending.x > 0 and 1 or (pending.x < 0 and -1 or nil)
  local source = pending.source
  pending, lastApplied = nil, now
  applyingRemote = true
  local ok, err = pcall(kai.gotoState, kai, "DAMAGED", dir, "weak", false)
  applyingRemote = false
  if not ok then
    log.error("knockback apply: " .. tostring(err))
    return
  end
  KB.game.notify(("Knockback from %s"):format(source), "warn")
end

return KB
