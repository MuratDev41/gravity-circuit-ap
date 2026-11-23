-- Burst Link: the base burst bar (the first BASE bursts) is shared with the team through a data storage key.
-- Bursts above it (from Burst Boosters) and the progress toward the next burst stay local.
--   gravity_circuit: the key holds bursts, 0..BASE, shared with other Gravity Circuit players.
--   silk_link: Silksong's Silk Link key, 0..9 Silk; one burst is SILK_PER_BURST Silk.
-- Changes are sent as clamped adds, so players changing it at the same time don't overwrite each other.
local client = require("archipelago.client")
local log = require("archipelago.log")

-- settings is replaced by the F9 panel's table; burstlink is "auto" (the YAML), "off", "gravity_circuit" or
-- "silk_link"
local BL = { game = nil, settings = { burstlink = "auto" } }

local BASE = 2
local SILK_PER_BURST = 4
local SILK_CAP = 9
local MODES = {
  [1] = { name = "Gravity Circuit", key = "GravityCircuitAP:BurstLink:v1:Bursts", unit = 1, cap = BASE },
  [2] = { name = "Silk Link", key = "SilksongRandomizer:SilkLink:v1:BaseSilk", unit = SILK_PER_BURST,
          cap = SILK_CAP },
}
-- after the HUD resets (stage start, respawn) bursts it grants itself are refilled over a few frames
local RESYNC_SECONDS = 2

local SETTING_MODE = { off = 0, gravity_circuit = 1, silk_link = 2 }

local mode, key = nil, nil
local server = nil      -- last value from the server, in the key's units
local pending = {}      -- [nonce] = units sent but not yet confirmed
local nonce = 0
local personal = 0      -- local bursts above the shared part
local tracked = nil     -- the HUD's burst count after the last sync
local resyncUntil = nil
local hud = nil
local installed = false

local function predicted()
  local v = server or 0
  for _, units in pairs(pending) do v = v + units end
  return math.max(0, math.min(mode.cap, v))
end

local function sharedBursts()
  return math.min(BASE, math.floor(predicted() / mode.unit))
end

local function personalCap()
  local max = GAMEDATA and GAMEDATA.player and GAMEDATA.player.maxBurst or BASE
  return math.max(0, max - BASE)
end

local function send(bursts)
  local units = bursts * mode.unit
  nonce = nonce + 1
  pending[nonce] = units
  client.storageSet(key, 0, {
    { operation = "add", value = units },
    { operation = "max", value = 0 },
    { operation = "min", value = mode.cap },
  }, { gc_burst_nonce = nonce })
end

local function setHudBursts(n)
  local before = hud.availableBursts
  n = math.max(0, math.min(n, hud.maxBurstStacks or n))
  if n < before then
    hud.availableBursts = n
    hud.burstMaxed = false
    hud:setUsedBurstBits(before)
  elseif n > before then
    for i = before + 1, n do
      hud.availableBursts = i
      hud:addBits(hud.burstbits.fg, 5, 0, hud.maxBurstStacks)
    end
    if n >= hud.maxBurstStacks then
      hud.burstMaxed = true
      hud.power.target = 0
    end
  end
  return hud.availableBursts
end

local function install()
  local HUD = UI and UI.objects and UI.objects.PlayerHUD
  if installed or not (HUD and HUD.update and HUD.reset) then return end
  local update, reset = HUD.update, HUD.reset
  HUD.update = function(self, ...)
    hud = self
    return update(self, ...)
  end
  HUD.reset = function(self, ...)
    hud = self
    resyncUntil = love.timer.getTime() + RESYNC_SECONDS
    return reset(self, ...)
  end
  installed = true
  log.info("hook installed: burstLink")
end

function BL.enabled()
  return mode ~= nil and client.isConnected()
end

local function chosenMode()
  local setting = BL.settings.burstlink
  if SETTING_MODE[setting] then return SETTING_MODE[setting] end
  return tonumber(client.slotData and client.slotData.burst_link) or 0
end

-- Picks the mode from the setting (or the YAML) and joins its key. Called on connect and when the setting changes.
function BL.configure()
  local wanted = client.isConnected() and MODES[chosenMode()] or nil
  if wanted == mode and (not mode or server ~= nil) then return end
  mode = wanted
  server, pending, tracked = nil, {}, nil
  resyncUntil = love.timer.getTime()
  if not mode then
    key = nil
    log.info("burst link: off")
    return
  end
  key = ("Team:%d:%s"):format(client.team or 0, mode.key)
  client.watch({ key })
  client.storageSet(key, 0, { { operation = "add", value = 0 } })
  log.info("burst link: " .. mode.name .. " (" .. key .. ")")
end

function BL.onConnected()
  mode = nil
  BL.configure()
end

function BL.onStorage(msg)
  if not (mode and msg.key == key) then return end
  server = tonumber(msg.value) or 0
  if msg.gc_burst_nonce then pending[msg.gc_burst_nonce] = nil end
end

function BL.update()
  install()
  if not BL.enabled() or server == nil then return end
  if not (BL.game and BL.game.active and hud and hud.spawned and hud.active) then return end
  local now = love.timer.getTime()
  local bursts = hud.availableBursts
  local shared = sharedBursts()

  if resyncUntil then
    -- wait for the HUD's own refill, then keep what it gave as personal bursts and take the shared part
    if now < resyncUntil and (hud.power.target or 0) >= 1000 then return end
    resyncUntil = nil
    personal = math.min(bursts, personalCap())
    tracked = setHudBursts(shared + personal)
    return
  end

  if tracked and bursts ~= tracked then
    local d = bursts - tracked
    if d > 0 then
      local toShared = math.min(d, BASE - shared)
      if toShared > 0 then send(toShared) end
      personal = math.min(personal + d - math.max(toShared, 0), personalCap())
    else
      local fromPersonal = math.min(-d, personal)
      personal = personal - fromPersonal
      local rest = -d - fromPersonal
      if rest > 0 then send(-math.min(rest, shared)) end
    end
    tracked = bursts
    return
  end

  -- a teammate changed the shared part
  local want = math.min(sharedBursts() + personal, hud.maxBurstStacks or BASE)
  if want ~= bursts then tracked = setHudBursts(want) else tracked = bursts end
end

-- Burst Drain Trap: empties the bar. With Burst Link on, only the bursts above the shared part go, so the drain
-- isn't passed on to the team.
function BL.drain()
  if not (hud and hud.availableBursts) then return end
  local keep = 0
  if BL.enabled() and server ~= nil then
    keep = math.min(sharedBursts(), hud.availableBursts)
    personal = 0
  end
  local left = setHudBursts(keep)
  if tracked then tracked = left end
  if hud.power then
    hud.power.current, hud.power.target = 0, 0
  end
end

-- Line for the F9 panel, or nil when off.
function BL.info()
  if not mode then
    if not client.isConnected() then return nil end
    return "Burst Link is off" .. (BL.settings.burstlink == "auto" and " (from your YAML)" or "")
  end
  if server == nil then return mode.name .. ": waiting for the server" end
  if mode.unit == 1 then
    return ("Burst Link: %d of %d bursts shared"):format(sharedBursts(), BASE)
  end
  return ("Silk Link: %d of %d Silk, %d bursts shared"):format(predicted(), mode.cap, sharedBursts())
end

return BL
