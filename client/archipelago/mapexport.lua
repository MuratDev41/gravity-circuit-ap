-- Developer tool for the PopTracker maps. Runs only when archipelago/export_maps.flag exists: renders every
-- official map with the game's tile renderer to archipelago/mapexport/<map>/<x>_<y>.png, then quits.
local log = require("archipelago.log")

local EX = {}
local FLAG = "archipelago/export_maps.flag"
local SCALE = 0.5
local MAPS = { "opening-level", "hub-area", "optic-area", "patch-area", "cooler-area", "power-area", "shift-area",
               "wave-area", "break-area", "cipher-area", "final-area-1", "final-area-2", "final-area-3" }

local active = nil
local index, phase, timer, canvas = 0, "next", 0, nil

local function enabled()
  if active == nil then
    active = love.filesystem.getInfo(FLAG) ~= nil
    if active then log.info("map export: starting") end
  end
  return active
end

local function usedTilesets()
  local used = {}
  for _, cell in pairs(Map.grid.cells or {}) do
    if type(cell) == "table" then
      for _, layer in pairs({ cell[0], cell[-1], cell[1], cell[-2] }) do
        if type(layer) == "table" then
          for _, t in pairs(layer) do
            if type(t) ~= "number" and t.tileset and t.tileset > 0 then used[t.tileset] = true end
          end
        end
      end
    end
  end
  return used
end

local requested = nil
-- Attaches the map's tilesets the same way MapManager:fixLoadingDebug does.
local function tilesetsReady()
  if not requested then
    requested = usedTilesets()
    for k in pairs(requested) do pcall(Tileset.load, Tileset, k) end
  end
  for k in pairs(requested) do
    if not (Tileset.activated and Tileset.activated[k]) then return false end
    local obj = Tileset:grabTilesetObj(k)
    if not (obj and obj.image and obj.image.image) then return false end
  end
  if Texture and Texture.isLoading and Texture:isLoading() then return false end
  Map.tilesets = Map.tilesets or {}
  for k in pairs(requested) do Map.tilesets[k] = Tileset:grabTilesetObj(k) end
  return true
end

function EX.update()
  if not enabled() or not INITIAL_ASSETS_LOADED or not Map or not Map.load then return end
  timer = timer + 1
  if phase == "next" then
    index = index + 1
    if index > #MAPS then
      log.info("map export: done")
      love.filesystem.remove(FLAG)
      active = false
      if QUIT_GAME then QUIT_GAME() end
      return
    end
    log.info("map export: loading " .. MAPS[index])
    Map:load(MAPS[index] .. ".gcl", true, nil, nil, nil, true)
    phase, timer, requested = "loading", 0, nil
  elseif phase == "loading" then
    -- the title screen does not update a map it did not load itself
    if Map:isLoading() then pcall(Map.update, Map, 1 / 60) end
    if Tileset and Tileset.update then pcall(Tileset.update, Tileset) end
    if Texture and Texture.lateUpdate then pcall(Texture.lateUpdate, Texture) end
    if timer % 120 == 0 then
      local want, active = 0, 0
      for k in pairs(requested or {}) do
        want = want + 1
        if Tileset.activated and Tileset.activated[k] then active = active + 1 end
      end
      log.info(("map export: waiting, loading=%s tilesets wanted=%d active=%d file=%s"):format(
        tostring(Map:isLoading()), want, active, tostring(Map.file)))
    end
    if timer > 60 and not Map:isLoading() and Map.grid and tilesetsReady() then
      phase = "draw"
    elseif timer > 1200 then
      log.error("map export: timed out loading " .. MAPS[index])
      phase = "next"
    end
  end
end

function EX.draw()
  if not active or phase ~= "draw" then return end
  phase = "next"
  local ok, err = pcall(function()
    local name = MAPS[index]
    local grid = Map.grid
    local tw, th = grid.tileWidth, grid.tileHeight
    local cw, ch = grid.limits.cWidth, grid.limits.cHeight
    for _, ts in pairs(Map.tilesets) do ts.direct_image = ts.image.image end
    love.filesystem.createDirectory("archipelago/mapexport/" .. name)
    canvas = canvas or love.graphics.newCanvas(cw * SCALE, ch * SCALE)
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setScissor()
    local count = 0
    for cy = 1, grid.cellsVertically do
      for cx = 1, grid.cellsHorizontally do
        local cell = grid.cells[cx + (cy - 1) * grid.cellsHorizontally]
        if cell and cell.active then
          love.graphics.setCanvas(canvas)
          love.graphics.clear(0, 0, 0, 0)
          love.graphics.origin()
          love.graphics.scale(SCALE, SCALE)
          love.graphics.setColor(1, 1, 1, 1)
          for layer = -grid.layers.background, grid.layers.foreground do
            if cell[layer] and (not cell.isLayerActive or cell:isLayerActive(layer)) then
              Map:drawCellLayer(cell, layer, 1, cell.width, 1, cell.height, tw, th, 0, 0)
            end
          end
          love.graphics.setCanvas()
          canvas:newImageData():encode("png", ("archipelago/mapexport/%s/%d_%d.png"):format(name, cx, cy))
          count = count + 1
        end
      end
    end
    love.graphics.pop()
    love.filesystem.write("archipelago/mapexport/" .. name .. "/meta.txt",
      ("%d %d %d %d %s"):format(grid.cellsHorizontally, grid.cellsVertically, cw, ch, tostring(SCALE)))
    log.info(("map export: %s, %d cells"):format(name, count))
  end)
  if not ok then log.error("map export draw: " .. tostring(err)) end
end

return EX
