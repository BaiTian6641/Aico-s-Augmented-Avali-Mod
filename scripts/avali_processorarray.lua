-- Avali Integrated Processor Array (compact)
-- FU-style examiner: insert ANY item to research, computing units boost speed & rewards
require '/scripts/util.lua'
require '/scripts/fupower.lua'

local statusList = {
  waiting    = "^yellow;Waiting for subject...^reset;",
  fossilID   = "^green;Fossil identified^reset;",
  artifactID = "^green;Artifact identified^reset;",
  artifactBasicID = "^green;Artifact identified^reset;",
  geodeID    = "^green;Geode identified^reset;",
  genericID  = "^green;Item analysed^reset;",
  invalid    = "^red;Invalid sample detected^reset;"
}

-- Tag-based rewards + generic fallback for any item
local tagList = {
  fossil        = { range=65, currencies={ bonusResearch=60, bonusEssence=1 }, overrideCategory="fossilResearched" },
  geode         = { range=65, currencies={ bonusResearch=2,  bonusEssence=1 }, overrideCategory="geodeResearched" },
  artifact      = { range=35, currencies={ bonusResearch=50, bonusEssence=1, bonusProtheon=1 }, overrideCategory="artifactResearched" },
  artifactBasic = { range=50, currencies={ bonusResearch=15, bonusEssence=0 }, overrideCategory="artifactResearched" },
  generic       = { range=100, currencies={ bonusResearch=3 } }
}

local COMPUTE_UNIT_EFF  = 0.6
local COMBIN_UNIT_EFF   = 1.8
local COMPUTE_MULT_PER  = 0.25
local BASE_IDLE_POWER   = 2.0
local POWER_PER_SLOT    = 2.0

function init()
  power.init()
  playerUsing = nil; selfWorking = nil; shoveTimer = 0.0
  defaultMaxStack = root.assetJson("/items/defaultParameters.config").defaultMaxStack
  defaultDelta = config.getParameter("scriptDelta")
  microscopeRank = config.getParameter("microscopeRank", 1)
  playerWorkingEfficiency = config.getParameter("playerWorkingEfficiency")
  selfWorkingEfficiency   = config.getParameter("selfWorkingEfficiency")
  selfWorking             = config.getParameter("selfWorking")
  storage.status = storage.status or statusList.waiting

  -- Slot layout (4 slots): itemGrid shows input+compute, itemGrid2 shows outputs
  -- [0:Input] [1:Compute]  |  [2:Research] [3:Output]
  self.inputSlot    = 0
  self.computeMin   = 1
  self.computeMax   = 1
  self.researchSlot = 2
  self.outputSlot   = 3

  message.setHandler("paneOpened", paneOpened)
  message.setHandler("paneClosed", paneClosed)
  message.setHandler("getStatus", getStatus)
  math.randomseed(util.seedTime())
end

function scanComputingBoost()
  local totalEff = 0
  for i = self.computeMin, self.computeMax do
    local item = world.containerItemAt(entity.id(), i)
    if item then
      if item.name == "avali_computeunit" then
        totalEff = totalEff + COMPUTE_UNIT_EFF * item.count
      elseif item.name == "avali_combinunit" then
        totalEff = totalEff + COMBIN_UNIT_EFF * item.count
      end
    end
  end
  return totalEff
end

function countOccupiedSlots()
  local used = 0
  local sc = config.getParameter("slotCount", 4)
  for i = 0, sc - 1 do
    if world.containerItemAt(entity.id(), i) then used = used + 1 end
  end
  return used
end

function fetchTags(params)
  local tags = {}
  for k, v in pairs(params or {}) do
    if string.lower(k) == "itemtags" then
      tags = util.mergeTable(tags, copy(v))
    end
  end
  return tags
end

-- Returns matching tag, or "generic" as fallback for ANY item
function checkTags(item)
  if not item then return end
  local tags = fetchTags(item)
  for tag, _ in pairs(tagList) do
    if tag == "generic" then goto continue end
    for _, t in pairs(tags) do
      if t == tag then return tag end
    end
    ::continue::
  end
  return "generic"
end

function startProcessing(itm, itmParams, lastTag)
  -- Safety: never consume computing units
  if itm.name == "avali_computeunit" or itm.name == "avali_combinunit" then return end
  itm.count = 1
  if world.containerConsume(entity.id(), itm) then
    storage.processTag = lastTag
    storage.currentItem = itm
    storage.mergedParams = itmParams
    storage.futureItem = copy(storage.currentItem)
    if tagList[storage.processTag].overrideCategory then
      storage.futureItem.parameters.category = tagList[storage.processTag].overrideCategory
    end
    storage.futureItem.parameters.genomeInspected = true
    storage.progress = 0
    storage.multiplier = 0
    storage.status = "^cyan;" .. storage.progress .. "%^reset;"
  end
end

function finishProcessing()
  storage.status = statusList[storage.processTag .. "ID"]
  local protheonRank = (storage.mergedParams.protheonRank or 0)
  local geneRank     = (storage.mergedParams.geneRank or 0)
  local essenceRank  = (storage.mergedParams.essenceRank or 0)
  local researchRank = (storage.mergedParams.researchRank or 0)
  local bonusEssence = 0; local bonusGene = 0
  local bonusProtheon = 0; local bonusResearch = 0
  local itemCount = storage.futureItem.count or 1
  local tagDef = tagList[storage.processTag]

  for _ = 1, math.floor(storage.multiplier) do
    local r = math.random(tagDef.range or 100)
    if r == 1 and tagDef.currencies.bonusResearch then
      bonusResearch = bonusResearch + ((tagDef.currencies.bonusResearch + microscopeRank) * itemCount)
    elseif r == 2 and tagDef.currencies.bonusEssence then
      bonusEssence = bonusEssence + ((tagDef.currencies.bonusEssence + microscopeRank) * itemCount)
    elseif r == 3 and tagDef.currencies.bonusProtheon then
      bonusProtheon = bonusProtheon + ((tagDef.currencies.bonusProtheon + microscopeRank) * itemCount)
    elseif r == 4 and tagDef.currencies.bonusGene then
      bonusGene = bonusGene + ((tagDef.currencies.bonusGene + microscopeRank) * itemCount)
    end
  end
  storage.bonusResearch = bonusResearch + (itemCount * researchRank)
  storage.bonusGene     = bonusGene     + (itemCount * geneRank)
  storage.bonusEssence  = bonusEssence  + (itemCount * essenceRank)
  storage.bonusProtheon = bonusProtheon + (itemCount * protheonRank)
  storage.progress = 0
  storage.mergedParams = nil
  storage.processTag = nil
  storage.finishedProcessing = true
end

function update(dt)
  local computeEff = scanComputingBoost()
  local powerDraw = BASE_IDLE_POWER + (countOccupiedSlots() * POWER_PER_SLOT)
  power.setPower(powerDraw)

  if playerUsing or selfWorking then
    if storage.currentItem then
      if not storage.finishedProcessing then
        local eff = (playerUsing and playerWorkingEfficiency or selfWorkingEfficiency) + computeEff
        storage.progress = math.min(100, storage.progress + (eff * dt))
        storage.multiplier = storage.multiplier + 1 + (computeEff * COMPUTE_MULT_PER)
        storage.progress = math.floor(storage.progress * 100) * 0.01
        storage.status = "^cyan;" .. storage.progress .. "%^reset;"
        if storage.progress >= 100 then finishProcessing() end
      else
        if storage.futureItem then
          if not shoveLoop(dt, storage.futureItem, self.outputSlot) then return end
          storage.futureItem = nil
        else
          spawnBonus("fuscienceresource", storage.bonusResearch, self.researchSlot)
          storage.bonusResearch = 0
          spawnBonus("essence", storage.bonusEssence)
          storage.bonusEssence = 0
          spawnBonus("fuprecursorresource", storage.bonusProtheon)
          storage.bonusProtheon = 0
          spawnBonus("fugeneticmaterial", storage.bonusGene)
          storage.bonusGene = 0
          storage.currentItem = nil
          storage.finishedProcessing = false
        end
      end
    else
      local itm = world.containerItemAt(entity.id(), self.inputSlot)
      if not itm then
        storage.status = statusList.waiting
      elseif itm.name == "avali_computeunit" or itm.name == "avali_combinunit" then
        storage.status = statusList.invalid
        if not shoveLoop(dt, itm, self.outputSlot) then return end
        world.containerTakeAt(entity.id(), self.inputSlot)
      else
        local params = itm and mergedParams(root.itemConfig(itm))
        local tag = checkTags(params)
        if itm.parameters.genomeInspected then
          storage.status = statusList[tag .. "ID"]
          if not shoveLoop(dt, itm, self.outputSlot) then return end
          world.containerTakeAt(entity.id(), self.inputSlot)
        else
          startProcessing(itm, params, tag)
        end
      end
    end
  else
    script.setUpdateDelta(-1)
  end
  power.update(dt)
end

-- Output currency: use slot if provided, else spawn in-world
function spawnBonus(name, count, slot)
  if not count or count <= 0 then return end
  if slot then
    shoveItem({ name = name, count = count }, slot)
  else
    world.spawnItem({ name = name, count = count }, entity.position())
  end
end

function shoveLoop(dt, itm, slot)
  shoveTimer = (shoveTimer or 0.0) + dt
  if shoveTimer < 1.0 then return false end
  shoveTimer = 0.0
  if (nudgeCount or 0) > 3 then shoveItem(itm, slot)
  elseif not nudgeItem(itm, slot) then nudgeCount = (nudgeCount or 0) + 1; return false end
  nudgeCount = 0
  return true
end

function shoveItem(item, slot)
  if not item then return end
  local sitm = world.containerItemAt(entity.id(), slot)
  if sitm and sitm.name ~= item.name then
    if world.containerTakeAt(entity.id(), slot) then world.spawnItem(sitm, entity.position()) end
  end
  local left = world.containerPutItemsAt(entity.id(), item, slot)
  if left then world.spawnItem(left, entity.position()) end
end

function nudgeItem(item, slot)
  local sitm = world.containerItemAt(entity.id(), slot)
  if not item then return end
  if not sitm then world.containerPutItemsAt(entity.id(), item, slot); return true end
  if sitm.name ~= item.name then return false end
  local ci = copy(item); local cs = copy(sitm)
  ci.count = 1; cs.count = 1
  if not compare(ci, cs) then return false end
  local cfg = sitm and root.itemConfig(sitm)
  if cfg then cfg = mergedParams(cfg); cfg = cfg.maxStack or defaultMaxStack end
  if (item.count + sitm.count > cfg) then return false end
  world.containerPutItemsAt(entity.id(), item, slot)
  return true
end

function mergedParams(item)
  if not item or not item.config then return end
  if item.config and not item.parameters then return item.config end
  return util.mergeTable(item.config, item.parameters)
end

function paneOpened() script.setUpdateDelta(defaultDelta); playerUsing = true end
function paneClosed() playerUsing = nil end
function getStatus() if storage.status then return storage.status end end

function die()
  if storage.finishedProcessing then
    if storage.bonusResearch > 0 then world.spawnItem({ name = "fuscienceresource", count = storage.bonusResearch }, entity.position()) end
    if storage.bonusEssence > 0 then world.spawnItem({ name = "essence", count = storage.bonusEssence }, entity.position()) end
    if storage.bonusProtheon > 0 then world.spawnItem({ name = "fuprecursorresource", count = storage.bonusProtheon }, entity.position()) end
    if storage.bonusGene > 0 then world.spawnItem({ name = "fugeneticmaterial", count = storage.bonusGene }, entity.position()) end
    if storage.futureItem then world.spawnItem(storage.futureItem, entity.position()); storage.futureItem = nil end
    storage.currentItem = nil
  elseif storage.currentItem then
    world.spawnItem(storage.currentItem, entity.position())
    storage.currentItem = nil; storage.futureItem = nil
  end
end
