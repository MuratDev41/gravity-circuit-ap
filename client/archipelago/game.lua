local data = require("archipelago.data")
local client = require("archipelago.client")
local log = require("archipelago.log")

local G = {
  active = false,   -- the loaded save is bound to the connected slot
  saveLoaded = false,
  warning = nil,
  access = {},      -- [stage select slot 1..8] = true
  hooks = {},
  notify = function() end,
}

local STAGE_KEYS = { "OPTIC", "PATCH", "COOLER", "ELEC", "SHIFT", "WAVE", "BREAK", "CIPHER" }
local LEGACY_CREDITS_PER_ITEM = 500
local INSTANT_COOLDOWN_FRAMES = 45
local POSITION_THRESHOLD = 24
local MAX_RESCUE_TOKENS = 99

-- countBoosterPickups recomputes max HP/burst from these per-stage flags; received upgrades set them in order.
local HEALTH_FLAGS, BURST_FLAGS = {}, {}
for i, key in ipairs(STAGE_KEYS) do
  HEALTH_FLAGS[i] = "HEALTH_BOOSTER_PICKUP_" .. key
  BURST_FLAGS[i] = "BURST_BOOSTER_PICKUP_" .. key
end

-- Location kinds that only exist when the matching slot option is enabled.
local OPTIONAL_KINDS = {
  cache = "money_caches",
  smallcache = "small_money_caches",
  datachip = "data_chips",
  datachiprandom = "random_data_chips",
  shopburst = "shopsanity",
  shopchip = "shopsanity",
}

local locByKey = {}
local paletteLoc = {}
local cacheLoc = {}
local shopLoc = { bursts = {}, chips = {} }
for _, loc in ipairs(data.LOCATIONS) do
  locByKey[loc.kind .. ":" .. loc.stage .. ":" .. loc.index] = loc.id
  if loc.kind == "palette" then paletteLoc[loc.index] = loc.id end
  if loc.kind == "cache" or loc.kind == "smallcache" then cacheLoc[loc.stage .. "|" .. loc.obj] = loc end
  if loc.kind == "shopburst" then shopLoc.bursts[loc.index] = loc end
  if loc.kind == "shopchip" then shopLoc.chips[loc.index] = loc end
end

local function flagName(i)
  return BOSS_CLEAR_FLAGS and BOSS_CLEAR_FLAGS.kai and BOSS_CLEAR_FLAGS.kai[i]
end

local function hasFlag(name)
  local player = GAMEDATA and GAMEDATA.player
  return name and player and player.flags and player.flags[name] ~= nil and player.flags[name] > 0
end

local function apData()
  return GAMEDATA and GAMEDATA.player and GAMEDATA.player.ap
end

local function currentStage()
  if not MapTracker then return nil end
  local official, file = MapTracker:isOfficialMap()
  if official then return file end
  return nil
end

local function itemClass(flags)
  flags = flags or 0
  if flags % 2 == 1 then return "progression" end
  if math.floor(flags / 2) % 2 == 1 then return "useful" end
  if math.floor(flags / 4) % 2 == 1 then return "trap" end
  return "filler"
end

function G.isDone(id)
  local ap = apData()
  return (ap and ap.found and ap.found[id]) or client.checked[id] or false
end

local function markFound(id)
  local ap = apData()
  if not ap or not id then return end
  ap.found = ap.found or {}
  if not ap.found[id] then
    ap.found[id] = true
    log.info("found location " .. id .. " (" .. tostring(data.locationNames[id]) .. ")")
  end
end

function G.bossesDefeated()
  local count = 0
  for i = 1, 8 do
    if hasFlag(flagName(i)) then count = count + 1 end
  end
  return count
end

function G.bossesRequired()
  local ap = apData()
  return (client.slotData and client.slotData.bosses_required) or (ap and ap.bossesRequired) or 8
end

function G.fortressOpen()
  return G.bossesDefeated() >= G.bossesRequired()
end

-- fortress_access: Fortress 1 and 2 are opened by Access items; only Fortress 3 waits for the bosses.
function G.fortressItems()
  local ap = apData()
  if client.slotData and client.slotData.fortress_access ~= nil then return client.slotData.fortress_access == true end
  return ap ~= nil and ap.fortressAccess == true
end

local FORTRESS_NAMES = { [9] = "Fortress 1", [10] = "Fortress 2", [11] = "Fortress 3" }

-- Returns a short label and a full message when the stage select slot is locked, nil otherwise.
local function slotLocked(slot)
  if not slot then return nil end
  if slot <= 8 then
    if G.access[slot] then return nil end
    local name = data.STAGES[slot].name
    return name .. " - LOCKED", ("%s is locked: you need %s Access."):format(name, name)
  end
  if slot > 11 then return nil end
  local name = FORTRESS_NAMES[slot]
  if G.fortressItems() and slot < 11 then
    if G.access[slot] then return nil end
    return name .. " - LOCKED", ("%s is locked: you need %s Access."):format(name, name)
  end
  if G.fortressOpen() then return nil end
  local progress = ("%d/%d bosses"):format(G.bossesDefeated(), G.bossesRequired())
  return ("%s - LOCKED (%s)"):format(name, progress),
    ("%s needs %d Circuit bosses defeated (%s)."):format(name, G.bossesRequired(), progress)
end

local function anyFortressOpen()
  if G.fortressOpen() then return true end
  return G.fortressItems() and (G.access[9] or G.access[10]) or false
end

function G.optionEnabled(kind)
  local key = OPTIONAL_KINDS[kind]
  if not key then return true end
  if client.isConnected() then return client.slotData[key] == true end
  local ap = apData()
  return ap and ap.caches and ap.caches[key] == true
end

local function locationEnabled(loc)
  return G.optionEnabled(loc.kind) == true
end

function G.shopsanity()
  return G.optionEnabled("shopburst") == true
end

-- Every shop slot is its own check: owned state and price come from the check rather than from whether that
-- burst/chip was received as an item, and buying the slot sends the check.
function G.shopsanityListing(kind, res)
  local slots = shopLoc[kind]
  if not slots then return end
  local bursts = GAMEDATA.equippables.burstAttacks
  local inShop = {}
  if kind == "bursts" then
    for _, id in ipairs(bursts.getUnlockedList()) do inShop[id] = true end
  end
  for i = 1, 20 do
    local item = res[i]
    local loc = item and item.id and slots[item.id]
    if loc then
      local done = G.isDone(loc.id) and true or false
      item.purchased = done
      item.new = false
      if kind == "bursts" then
        item.unlocked = done or inShop[item.id] or false
        local attack = bursts.getData()[item.id]
        item.price = (item.unlocked and not done and attack and attack.price) or 0
      else
        item.unlocked = done
      end
      local shopType, tokenCost = kind, item.tokens or 0
      item.unlock = function(id)
        if shopType == "chips" then
          local ap = apData()
          ap.tokensSpent = (ap.tokensSpent or 0) + tokenCost
        end
        G.shopBuy(shopType, id)
        return true
      end
    end
  end
end

function G.shopBuy(kind, id)
  local loc = shopLoc[kind] and shopLoc[kind][id]
  if not loc then return end
  markFound(loc.id)
  G.pendingShop = { burst = kind == "bursts", id = id }
  local item = client.scouted[loc.id]
  if item then
    local who = item.player == client.slot and "you" or client.playerName(item.player)
    G.notify(("Bought %s for %s"):format(client.itemName(item.item, item.player), who), "item")
  else
    G.notify("Bought " .. loc.name, "item")
  end
end

function G.scoutShops()
  if not (client.isConnected() and G.shopsanity()) then return end
  local ids = {}
  for _, slots in pairs(shopLoc) do
    for _, loc in pairs(slots) do ids[#ids + 1] = loc.id end
  end
  client.scout(ids, 0)
end

local hinted = {}
function G.hintShop(kind)
  local slots = shopLoc[kind]
  if not (slots and client.isConnected()) then return end
  local ids = {}
  for _, loc in pairs(slots) do
    local item = client.scouted[loc.id]
    if item and not G.isDone(loc.id) and not hinted[loc.id] and itemClass(item.flags) == "progression" then
      hinted[loc.id] = true
      ids[#ids + 1] = loc.id
    end
  end
  if #ids > 0 then
    client.scout(ids, 2)
    log.info("hinted " .. #ids .. " progression items in the " .. kind .. " shop")
  end
end

function G.shopInfo()
  local shop = G.shop
  if not (G.active and G.shopsanity() and shop and shop.activated and G.shopSeen) then return nil end
  if love.timer.getTime() - G.shopSeen > 0.2 then return nil end
  local item = shop.inventory and shop.slot and shop.inventory[shop.slot]
  local loc = item and item.id and shopLoc[shop.type] and shopLoc[shop.type][item.id]
  if not loc then return nil end
  if G.isDone(loc.id) then return { text = "Already bought", kind = "done" } end
  if shop.type == "bursts" and not item.unlocked then
    local stageKey = data.BURST_BOSS_STAGE[item.id]
    for _, stage in ipairs(data.STAGES) do
      if stage.key == stageKey then return { text = "Not for sale yet: defeat " .. stage.boss, kind = "done" } end
    end
  end
  local scouted = client.scouted[loc.id]
  if not scouted then
    return { text = client.isConnected() and "Scouting..." or "Connect to see what this slot holds", kind = "done" }
  end
  local who = scouted.player == client.slot and "you" or client.playerName(scouted.player)
  return {
    text = ("Sends %s to %s"):format(client.itemName(scouted.item, scouted.player), who),
    kind = itemClass(scouted.flags),
  }
end

local function isFreshSave(player)
  for i = 1, 11 do
    if hasFlag(flagName(i)) then return false end
  end
  return not (player.rescues and player.rescues.count and player.rescues.count > 0)
end

-- A save takes part only if it is bound to this seed and slot; a fresh save is bound on first connect.
function G.evaluateSave()
  G.active = false
  G.warning = nil
  if not G.saveLoaded or not GAMEDATA or not GAMEDATA.player then return end
  local player = GAMEDATA.player
  if player.ap then
    if client.isConnected() and (player.ap.seed ~= client.seed or player.ap.slot ~= client.slotName) then
      G.warning = ("This save belongs to slot '%s' of another seed. Archipelago is off for it."):format(
        tostring(player.ap.slot))
      return
    end
  elseif client.isConnected() then
    if not isFreshSave(player) then
      G.warning = "This is a normal save. Start a NEW GAME while connected to play Archipelago."
      return
    end
    player.ap = { seed = client.seed, slot = client.slotName, found = {}, items = {}, credits = 0 }
    G.notify("This save is now linked to Archipelago slot " .. client.slotName)
    log.info("bound save slot " .. tostring(GAMESTATE and GAMESTATE.saveSlotInUse) .. " to " .. client.slotName)
  else
    G.warning = "Not an Archipelago save. Connect (F9), then start a new game."
    return
  end
  G.active = true
  if client.isConnected() then
    local ap = player.ap
    ap.bossesRequired = client.slotData.bosses_required
    ap.fortressAccess = client.slotData.fortress_access == true
    ap.deathLink = client.slotData.death_link
    ap.caches = {}
    for _, key in pairs(OPTIONAL_KINDS) do ap.caches[key] = client.slotData[key] == true end
  end
  G.applyItems(false)
end

-- Rebuilds item state from the full received list, so it is safe to call repeatedly. One-shot effects
-- (credits, traps, refills) are tracked by totals stored in the save.
function G.applyItems(announce)
  if not G.active then return end
  local player = GAMEDATA.player
  local ap = player.ap
  ap.items = ap.items or {}

  if client.isConnected() and client.itemsSynced then
    local known = #ap.items
    local list = {}
    for i, item in ipairs(client.items) do list[i] = item.item end
    if announce ~= false then
      for i = known + 1, #client.items do
        local item = client.items[i]
        local from = item.player == client.slot and "you" or client.playerName(item.player)
        G.notify(("Received %s from %s"):format(data.itemNames[item.item] or ("item " .. item.item), from), "item")
      end
    end
    ap.items = list
  end

  local equippables = GAMEDATA.equippables
  local health, burstUps, credits, leaked, tokens = 0, 0, 0, 0, 0
  local instant = { heal = 0, burstfill = 0, trapdamage = 0 }
  G.access = {}
  for _, id in ipairs(ap.items) do
    local item = data.ITEMS[id]
    if item then
      local kind = item.kind
      if kind == "access" then
        G.access[item.gid] = true
      elseif kind == "burst" then
        if not equippables.burstAttacks.isPurchased(item.gid) then equippables.burstAttacks.unlock(item.gid) end
      elseif kind == "chip" then
        if not equippables.chips.isPurchased(item.gid, true) then equippables.chips.unlock(item.gid) end
      elseif kind == "health" then
        health = health + 1
      elseif kind == "burstup" then
        burstUps = burstUps + 1
      elseif kind == "paint" then
        local armor = player.armorData
        if not (armor and armor.purchasable and armor.purchasable[item.gid]) then
          (G.hooks.unlockByPickup or equippables.armor.unlockByPickup)(item.gid)
        end
      elseif kind == "credits" then
        credits = credits + item.gid
      elseif kind == "trapcredits" then
        leaked = leaked + item.gid
      elseif kind == "token" then
        tokens = tokens + item.gid
      elseif instant[kind] then
        instant[kind] = instant[kind] + 1
      end
    end
  end

  for i = 1, math.min(health, #HEALTH_FLAGS) do SetFlag(HEALTH_FLAGS[i]) end
  for i = 1, math.min(burstUps, #BURST_FLAGS) do SetFlag(BURST_FLAGS[i]) end
  GAMEDATA.countBoosterPickups()
  if GlobalObserver then GlobalObserver:none("PLAYER_HUD_MAX_BURST_COUNT_UPDATED") end

  if not ap.creditsTotal then ap.creditsTotal = (ap.credits or 0) * LEGACY_CREDITS_PER_ITEM end
  if credits > ap.creditsTotal then
    Money.add(credits - ap.creditsTotal)
    ap.creditsTotal = credits
  end
  ap.leakTotal = ap.leakTotal or 0
  if leaked > ap.leakTotal then
    Money.remove(leaked - ap.leakTotal)
    G.notify(("Credit Leak Trap: lost %d credits"):format(leaked - ap.leakTotal), "death")
    ap.leakTotal = leaked
  end

  ap.tokenItems = tokens
  G.recountTokens()

  G.instantReceived = instant

  if G.shopsanity() and G.hooks.unlockToShop then
    for _, stage in ipairs(data.STAGES) do
      if hasFlag(flagName(stage.flag)) then G.hooks.unlockToShop(stage.key) end
    end
  end
end

-- The game's own recount on load treats chips received as items as bought, so tokens are derived here:
-- rescues + token items - tokens spent at the Nurse.
function G.recountTokens()
  local player = GAMEDATA and GAMEDATA.player
  local ap = player and player.ap
  if not (ap and player.rescues) then return end
  local count = (player.rescues.count or 0) + (ap.tokenItems or 0) - (ap.tokensSpent or 0)
  player.rescueTokens = math.max(0, math.min(count, MAX_RESCUE_TOKENS))
end

-- Refills and the damage trap act on Kai, so they wait until he is playable inside a stage.
local INSTANT_ORDER = { "heal", "burstfill", "trapdamage" }
local instantCooldown = 0

local function kaiReady()
  local stage = currentStage()
  if not stage or stage == "HUB" then return nil end
  if not (GameObject and GameObject.getPlayer) then return nil end
  if GAMESTATE.isGameOver or GAMESTATE.dialogue or GAMESTATE.levelTransitionInProgress then return nil end
  if Cinematics and Cinematics.isPlaying and Cinematics:isPlaying() then return nil end
  local pause = GAMESTATE._pauseScreenObject
  if pause and pause.active then return nil end
  local kai = GameObject:getPlayer()
  if not kai or kai.dead or not kai.health or kai.health <= 0 then return nil end
  return kai
end

local function applyOneInstant(kind, kai)
  local ap = GAMEDATA.player.ap
  local received = {}
  for _, id in ipairs(ap.items or {}) do
    local item = data.ITEMS[id]
    if item and item.kind == kind then received[#received + 1] = item end
  end
  local applied = ap.instant[kind] or 0
  local item = received[applied + 1]
  if not item then return end
  if kind == "heal" then
    GlobalObserver:none("PLAYER_COLLECTED_HEALTH_PICKUP", item.gid)
  elseif kind == "burstfill" then
    GlobalObserver:none("PLAYER_COLLECTED_BURST_ENERGY", 99999)
  elseif kind == "trapdamage" then
    local damage = math.min(item.gid, kai.health - 1)
    if damage > 0 then
      kai.health = kai.health - damage
      GlobalObserver:none("PLAYER_HEALTH_UPDATED", kai.health, kai.maxhealth)
    end
  end
  ap.instant[kind] = applied + 1
  G.notify(item.name, kind == "trapdamage" and "death" or "item")
end

local function processInstant()
  local ap = apData()
  local received = G.instantReceived
  if not (ap and received) then return end
  ap.instant = ap.instant or {}
  if instantCooldown > 0 then
    instantCooldown = instantCooldown - 1
    return
  end
  for _, kind in ipairs(INSTANT_ORDER) do
    if (received[kind] or 0) > (ap.instant[kind] or 0) then
      local kai = kaiReady()
      if not kai then return end
      applyOneInstant(kind, kai)
      instantCooldown = INSTANT_COOLDOWN_FRAMES
      return
    end
  end
end

local function detect(loc, player)
  if loc.kind == "opening" then
    return hasFlag(flagName(0))
  elseif loc.kind == "boss" or loc.kind == "fortress" then
    return hasFlag(flagName(loc.index))
  elseif loc.kind == "rescue" then
    local rescues = player.rescues and player.rescues[loc.stage]
    return rescues and rescues[loc.index] and rescues[loc.index] > 0
  elseif loc.kind == "datachip" or loc.kind == "datachiprandom" then
    return player.dataChips ~= nil and player.dataChips[loc.obj] ~= nil
  end
  return false
end

local sentThisSession = {}

local function scanLocations()
  local player = GAMEDATA.player
  local ap = player.ap
  ap.found = ap.found or {}
  for _, loc in ipairs(data.LOCATIONS) do
    if not ap.found[loc.id] and locationEnabled(loc) and detect(loc, player) then
      markFound(loc.id)
      if loc.kind == "datachip" or loc.kind == "datachiprandom" then G.notify(loc.name, "item") end
    end
  end

  if client.isConnected() then
    local batch = {}
    for id in pairs(ap.found) do
      if not client.checked[id] and not sentThisSession[id] then
        sentThisSession[id] = true
        batch[#batch + 1] = id
      end
    end
    if #batch > 0 then
      log.info("sending " .. #batch .. " checks")
      client.checkLocations(batch)
    end
  end

  if hasFlag(flagName(11)) or player.gameCleared then
    if not ap.goal then
      ap.goal = true
      G.notify("Goal complete!", "item")
    end
    client.sendGoal()
  end
end

local wasGameOver = false
local deathFromLink = false

function G.receiveDeath(source, cause)
  if not G.active or not GAMESTATE or GAMESTATE.isGameOver then return end
  if not currentStage() or not GameObject or not GameObject.getPlayer then return end
  local kai = GameObject:getPlayer()
  if kai and kai.die then
    deathFromLink = true
    G.notify(("DeathLink from %s%s"):format(tostring(source), cause and (": " .. cause) or ""), "death")
    kai:die()
  end
end

local function checkDeath()
  local over = GAMESTATE and GAMESTATE.isGameOver or false
  if over and not wasGameOver then
    local ap = apData()
    if not deathFromLink and ap and (client.slotData.death_link or ap.deathLink) then
      client.sendDeathLink(client.slotName .. " was scrapped in " .. tostring(currentStage() or "a stage"))
    end
  end
  if not over then deathFromLink = false end
  wasGameOver = over
end

-- Hooks are retried every frame until the game global they patch exists.
local installed = {}

local function try(name, install)
  if installed[name] then return end
  local ok, result = pcall(install)
  if ok and result then
    installed[name] = true
    log.info("hook installed: " .. name)
  elseif not ok then
    installed[name] = true
    log.error("hook " .. name .. " failed: " .. tostring(result))
  end
end

local function installHooks()
  try("setActiveSlot", function()
    if not (UserProfile and UserProfile.setActiveSlot) then return false end
    local original = UserProfile.setActiveSlot
    UserProfile.setActiveSlot = function(...)
      local results = { original(...) }
      G.saveLoaded = true
      G.evaluateSave()
      return unpack(results)
    end
    return true
  end)

  try("boosters", function()
    if not (GAMEDATA and GAMEDATA.increaseMaxHealth and MapTracker) then return false end
    for _, kind in ipairs({ "Health", "Burst" }) do
      local isPicked = GAMEDATA["is" .. kind .. "BoosterPicked"]
      GAMEDATA["is" .. kind .. "BoosterPicked"] = function(file, ...)
        if not G.active then return isPicked(file, ...) end
        local stage = file or currentStage()
        local id = stage and locByKey["booster:" .. stage .. ":0"]
        if not id then return true end
        return G.isDone(id)
      end
      local increase = GAMEDATA["increaseMax" .. kind]
      GAMEDATA["increaseMax" .. kind] = function(...)
        if not G.active then return increase(...) end
        local stage = currentStage()
        local id = stage and locByKey["booster:" .. stage .. ":0"]
        if id then markFound(id) end
      end
    end
    return true
  end)

  try("palettes", function()
    local armor = GAMEDATA and GAMEDATA.equippables and GAMEDATA.equippables.armor
    if not (armor and armor.unlockByPickup and armor.hasCollectedPickup) then return false end
    local unlock, hasCollected = armor.unlockByPickup, armor.hasCollectedPickup
    G.hooks.unlockByPickup = unlock
    armor.unlockByPickup = function(id, ...)
      if G.active and paletteLoc[id] then
        markFound(paletteLoc[id])
        return
      end
      return unlock(id, ...)
    end
    armor.hasCollectedPickup = function(id, ...)
      if G.active and paletteLoc[id] then return G.isDone(paletteLoc[id]) end
      return hasCollected(id, ...)
    end
    return true
  end)

  try("moneyCaches", function()
    -- the game keeps its class registry local, so the box classes are found through the class tree
    if not BaseObject or not BaseObject.subclasses then return false end
    local found, seen = {}, {}
    local function walk(class)
      if seen[class] then return end
      seen[class] = true
      if class.name == "LARGE_PICKUP_BOX" or class.name == "SMALL_PICKUP_BOX" then found[class.name] = class end
      for sub in pairs(class.subclasses or {}) do walk(sub) end
    end
    walk(BaseObject)
    if not (found.LARGE_PICKUP_BOX and found.SMALL_PICKUP_BOX) then return false end
    for _, class in pairs(found) do
      local original = class.spawnReward
      class.spawnReward = function(self, ...)
        if G.active and not self.spawnedReward then
          local stage = currentStage()
          local loc = stage and self.ID and cacheLoc[stage .. "|" .. tostring(self.ID)]
          if loc and G.optionEnabled(loc.kind) and not G.isDone(loc.id) then
            markFound(loc.id)
            G.notify("Cache: " .. loc.name, "item")
          end
        end
        return original(self, ...)
      end
    end
    return true
  end)

  try("bursts", function()
    local bursts = GAMEDATA and GAMEDATA.equippables and GAMEDATA.equippables.burstAttacks
    if not (bursts and bursts.unlockToShopBasedOnStage) then return false end
    local original = bursts.unlockToShopBasedOnStage
    G.hooks.unlockToShop = original
    bursts.unlockToShopBasedOnStage = function(...)
      -- without shopsanity boss bursts are items and never go on sale
      if G.active and not G.shopsanity() then return end
      return original(...)
    end
    return true
  end)

  try("shop", function()
    if not (GAMEDATA and GAMEDATA.purchasables and GAMEDATA.purchasables.get) then return false end
    local original = GAMEDATA.purchasables.get
    GAMEDATA.purchasables.get = function(kind, ...)
      local res = original(kind, ...)
      if not G.active then return res end
      if G.shopsanity() then
        G.shopsanityListing(kind, res)
      elseif kind == "chips" then
        for i = 1, 20 do
          local item = res[i]
          if item and item.id and item.id >= 2 and not item.purchased then
            item.unlocked = false
            item.forceFree = false
            item.tokens = 999
            item.price = 99999
          end
        end
      end
      return res
    end
    return true
  end)

  try("unlockNotification", function()
    -- After a purchase the shop dialogue grants the bought item through this popup; with shopsanity the
    -- purchase was a check, so that single grant is skipped. Story gifts still go through.
    if not (UI and UI.equippableUnlockNotification) then return false end
    local original = UI.equippableUnlockNotification
    UI.equippableUnlockNotification = function(burst, id, ...)
      local pending = G.pendingShop
      if pending and pending.id == id and pending.burst == (burst and true or false) then
        G.pendingShop = nil
        return
      end
      return original(burst, id, ...)
    end
    return true
  end)

  try("shopScreen", function()
    local ShopScreen = UI and UI.objects and UI.objects.ShopScreen
    if not (ShopScreen and ShopScreen.draw and ShopScreen.activate) then return false end
    local originalDraw, originalActivate = ShopScreen.draw, ShopScreen.activate
    ShopScreen.draw = function(self, ...)
      G.shop, G.shopSeen = self, love.timer.getTime()
      return originalDraw(self, ...)
    end
    ShopScreen.activate = function(self, activate, kind, ...)
      local results = { originalActivate(self, activate, kind, ...) }
      if activate and G.active and G.shopsanity() then G.hintShop(kind) end
      return unpack(results)
    end
    return true
  end)

  try("levelSelect", function()
    local LevelSelect = UI and UI.objects and UI.objects.LevelSelectScreen
    local states = LevelSelect and LevelSelect.static and LevelSelect.static.states
    if not (states and states.ACTIVE and states.ACTIVATING) then return false end
    local keys = LevelSelect.static.keys or { ACCEPT = 5 }

    local originalInput = states.ACTIVE.handleInput
    states.ACTIVE.handleInput = function(self, input, key)
      G.levelSelect = self
      if G.active and (input == keys.ACCEPT or input == keys.PAUSE)
        and not (self.checkpoint and self.checkpoint.active) and not self.tickingToDialogue
        and not GAMESTATE.dialogue and IsActiveMenu(self) then
        local _, blocked = slotLocked(self.state and self.state.selectedLevel)
        if blocked then
          if Audio and SFX and SFX.menu_error then Audio:playSound(SFX.menu_error) end
          G.notify(blocked, "warn")
          return
        end
      end
      return originalInput(self, input, key)
    end

    -- The stage select shows one Fortress stage per cleared boss past 8. While the Fortress is open, report
    -- enough clears for it; with fortress_access all three are shown and locked one by one.
    local originalEnter = states.ACTIVATING.enteredState
    states.ACTIVATING.enteredState = function(self, ...)
      G.levelSelect = self
      local progress = GAMEDATA.progressFlags
      local originalCount = progress.bossesCleared
      if G.active and anyFortressOpen() then
        progress.bossesCleared = function()
          local count = originalCount()
          if G.fortressItems() then return math.max(count, 10) end
          if count >= 8 then return count end
          local finals = 0
          for i = 9, 11 do
            if hasFlag(flagName(i)) then finals = finals + 1 end
          end
          return 8 + finals
        end
      end
      local ok, err = pcall(originalEnter, self, ...)
      progress.bossesCleared = originalCount
      if not ok then error(err, 0) end
    end
    return true
  end)
end

-- Trackers read the current map and Kai's position from data storage.
local reportedStage = nil
local lastPosition = { map = nil, x = 0, y = 0 }

local function storageKey(name)
  return ("gravity_circuit_%s_%d_%d"):format(name, client.team or 0, client.slot)
end

local function reportStage()
  if not client.isConnected() or not client.slot then
    reportedStage = nil
    return
  end
  local stage = currentStage() or "MENU"
  if stage ~= reportedStage then
    reportedStage = stage
    client.setData(storageKey("stage"), stage)
  end
end

local function reportPosition()
  if not client.isConnected() or not client.slot then return end
  local stage = currentStage()
  if not stage or not (GameObject and GameObject.getPlayer) then return end
  local kai = GameObject:getPlayer()
  if not (kai and kai.getPos) then return end
  local x, y = kai:getPos()
  if not (x and y) then return end
  if stage == lastPosition.map and math.abs(x - lastPosition.x) < POSITION_THRESHOLD
    and math.abs(y - lastPosition.y) < POSITION_THRESHOLD then
    return
  end
  lastPosition.map, lastPosition.x, lastPosition.y = stage, x, y
  client.setData(storageKey("pos"), ("%s,%d,%d"):format(stage, math.floor(x), math.floor(y)))
end

local tick = 0
function G.update()
  installHooks()
  tick = tick + 1
  if tick % 30 == 0 then pcall(reportStage) end
  if tick % 15 == 0 then pcall(reportPosition) end
  if not G.active then return end
  checkDeath()
  local ok, err = pcall(processInstant)
  if not ok then log.error("instant items: " .. tostring(err)) end
  if tick % 20 == 0 then
    ok, err = pcall(scanLocations)
    if not ok then log.error("scan: " .. tostring(err)) end
    G.recountTokens()
  end
end

function G.onConnected()
  sentThisSession = {}
  reportedStage = nil
  lastPosition.map = nil
  G.scoutShops()
  if G.saveLoaded then G.evaluateSave() end
end

function G.onItems()
  if not G.active then return end
  local ok, err = pcall(G.applyItems, true)
  if not ok then log.error("applyItems: " .. tostring(err)) end
end

function G.selectedStageLocked()
  local levelSelect = G.levelSelect
  if not (G.active and levelSelect and levelSelect.activated and levelSelect.state) then return nil end
  return (slotLocked(levelSelect.state.selectedLevel))
end

function G.counts()
  if not apData() then return 0, #data.LOCATIONS end
  local done, total = 0, 0
  for _, loc in ipairs(data.LOCATIONS) do
    if locationEnabled(loc) then
      total = total + 1
      if G.isDone(loc.id) then done = done + 1 end
    end
  end
  return done, total
end

return G
