-- Avali Research Processor Array
-- Advanced FU-style examiner: insert tagged items, computing units boost speed & rewards
-- Top tier: broader tag recognition and more compute slots
require '/scripts/util.lua'
require '/scripts/fupower.lua'

-- Status strings
local statusList = {
  waiting           = "^yellow;Waiting for subject...^reset;",
  queenID           = "^green;Queen identified^reset;",
  youngQueenID      = "^green;Larva identified^reset;",
  droneID           = "^green;Drone identified^reset;",
  fossilID          = "^green;Fossil identified^reset;",
  mediumFossilID    = "^green;Fossil identified^reset;",
  smallFossilID     = "^green;Fossil identified^reset;",
  artifactID        = "^green;Artifact identified^reset;",
  artifactElderID   = "^green;Artifact identified^reset;",
  artifactProtheonID= "^green;Artifact identified^reset;",
  artifactBasicID   = "^green;Artifact identified^reset;",
  geodeID           = "^green;Artifact identified^reset;",
  invalid           = "^red;Invalid sample detected^reset;"
}

-- Full tag-based reward definitions (top-tier research array)
local tagList = {
  queen             = { range=25, currencies={ bonusResearch=3,  bonusGene=1 }},
  youngQueen        = { range=25, currencies={ bonusResearch=3,  bonusGene=1 }},
  drone             = { range=100,currencies={ bonusGene=1 }},
  fossil            = { range=65, currencies={ bonusResearch=60, bonusEssence=1 }, overrideCategory="fossilResearched" },
  mediumFossil      = { range=65, currencies={ bonusResearch=40, bonusEssence=1 }, overrideCategory="fossilResearched" },
  smallFossil       = { range=65, currencies={ bonusResearch=20, bonusEssence=1 }, overrideCategory="fossilResearched" },
  geode             = { range=65, currencies={ bonusResearch=2,  bonusEssence=1 }, overrideCategory="geodeResearched" },
  artifact          = { range=35, currencies={ bonusResearch=50, bonusEssence=1, bonusProtheon=1 }, overrideCategory="artifactResearched" },
  artifactElder     = { range=25, currencies={ bonusResearch=35, bonusEssence=10 }, overrideCategory="artifactElderResearched" },
  artifactProtheon  = { range=25, currencies={ bonusResearch=20, bonusProtheon=3 }, overrideCategory="artifactResearched" },
  artifactBasic     = { range=50, currencies={ bonusResearch=15, bonusEssence=0 }, overrideCategory="artifactResearched" }
}

-- Computing unit boost values
local COMPUTE_UNIT_EFF  = 0.6   -- Added efficiency per Integrated Computing Unit
local COMBIN_UNIT_EFF   = 1.8   -- Added efficiency per Combined Computing Unit
local COMPUTE_MULT_PER  = 0.3   -- Extra multiplier per tick per unit of compute efficiency

-- Power constants
local BASE_IDLE_POWER   = 3.0
local POWER_PER_SLOT    = 2.5

function init()
  power.init()
  playerUsing = nil
  selfWorking = nil
  shoveTimer = 0.0

  defaultMaxStack = root.assetJson("/items/defaultParameters.config").defaultMaxStack
  defaultDelta = config.getParameter("scriptDelta")

  microscopeRank = config.getParameter("microscopeRank", 2)

  playerWorkingEfficiency = config.getParameter("playerWorkingEfficiency")
  selfWorkingEfficiency   = config.getParameter("selfWorkingEfficiency")
  selfWorking             = config.getParameter("selfWorking")

  storage.status = storage.status or statusList.waiting

  -- Slot layout (20 slots)
  self.inputSlot   = 0   -- item to examine
  self.computeMin  = 1   -- first computing unit slot
  self.computeMax  = 8   -- last computing unit slot (8 slots: 1-8)
  self.researchSlot= 9   -- research currency output
  self.essenceSlot = 10  -- essence currency output
  self.protheonSlot= 11  -- protheon currency output
  self.geneSlot    = 12  -- genetic material output
  self.outputSlot  = 13  -- examined item output (14-19 are overflow)

  message.setHandler("paneOpened", paneOpened)
  message.setHandler("paneClosed", paneClosed)
  message.setHandler("getStatus", getStatus)

  math.randomseed(util.seedTime())
end

-- Scan computing unit slots for total efficiency boost
function scanComputingBoost()
  local totalEff = 0
  local compSlotsUsed = 0
  for i = self.computeMin, self.computeMax do
    local item = world.containerItemAt(entity.id(), i)
    if item then
      compSlotsUsed = compSlotsUsed + 1
      if item.name == "avali_computeunit" then
        totalEff = totalEff + COMPUTE_UNIT_EFF * item.count
      elseif item.name == "avali_combinunit" then
        totalEff = totalEff + COMBIN_UNIT_EFF * item.count
      end
    end
  end
  return totalEff, compSlotsUsed
end

-- Count all occupied slots for power scaling
function countOccupiedSlots()
  local used = 0
  local slotCount = config.getParameter("slotCount", 20)
  for i = 0, slotCount - 1 do
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

function checkTags(item)
  if not item then return end
  local tags = fetchTags(item)
  local buffer = nil
  for tag, _ in pairs(tagList) do
    for _, t in pairs(tags) do
      if t == tag then
        buffer = tag
        break
      end
    end
    if buffer then break end
  end
  return buffer
end

function startProcessing(itm, itmParams, lastTag)
  if lastTag ~= "drone" then itm.count = 1 end
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

  local protheonRank  = (storage.mergedParams.protheonRank or 0)
  local geneRank      = (storage.mergedParams.geneRank or 0)
  local essenceRank   = (storage.mergedParams.essenceRank or 0)
  local researchRank  = (storage.mergedParams.researchRank or 0)

  local bonusEssence   = 0
  local bonusGene      = 0
  local bonusProtheon  = 0
  local bonusResearch  = 0

  local itemCount = storage.futureItem.count or 1
  local tagDef = tagList[storage.processTag]

  for _ = 1, math.floor(storage.multiplier) do
    local randCheck = math.random(tagDef.range or 100)

    if (randCheck == 1) and (tagDef.currencies.bonusResearch) then
      bonusResearch = bonusResearch + ((tagDef.currencies.bonusResearch + microscopeRank) * itemCount)
    elseif (randCheck == 2) and (tagDef.currencies.bonusEssence) then
      bonusEssence = bonusEssence + ((tagDef.currencies.bonusEssence + microscopeRank) * itemCount)
    elseif (randCheck == 3) and (tagDef.currencies.bonusProtheon) then
      bonusProtheon = bonusProtheon + ((tagDef.currencies.bonusProtheon + microscopeRank) * itemCount)
    elseif (randCheck == 4) and (tagDef.currencies.bonusGene) then
      bonusGene = bonusGene + ((tagDef.currencies.bonusGene + microscopeRank) * itemCount)
    end
  end

  storage.bonusResearch  = bonusResearch  + (itemCount * researchRank)
  storage.bonusGene      = bonusGene      + (itemCount * geneRank)
  storage.bonusEssence   = bonusEssence   + (itemCount * essenceRank)
  storage.bonusProtheon  = bonusProtheon  + (itemCount * protheonRank)
  storage.progress       = 0
  storage.mergedParams   = nil
  storage.processTag     = nil
  storage.finishedProcessing = true
end

function update(dt)
  local computeEff, compSlots = scanComputingBoost()
  local occupiedSlots = countOccupiedSlots()

  -- Power draw scales with occupied slots
  local powerDraw = BASE_IDLE_POWER + (occupiedSlots * POWER_PER_SLOT)
  power.setPower(powerDraw)

  if playerUsing or selfWorking then
    if storage.currentItem then
      if not storage.finishedProcessing then
        local effectiveEff
        if playerUsing then
          effectiveEff = playerWorkingEfficiency + computeEff
        else
          effectiveEff = selfWorkingEfficiency + computeEff
        end
        storage.progress = math.min(100, storage.progress + (effectiveEff * dt))
        storage.multiplier = storage.multiplier + 1 + (computeEff * COMPUTE_MULT_PER)
        storage.progress = math.floor(storage.progress * 100) * 0.01
        storage.status = "^cyan;" .. storage.progress .. "%^reset;"
        if storage.progress >= 100 then
          finishProcessing()
        end
      else
        if storage.futureItem then
          if not shoveLoop(dt, storage.futureItem, self.outputSlot) then return end
          storage.futureItem = nil
        else
          if storage.bonusResearch > 0 then
            shoveItem({ name = "fuscienceresource", count = storage.bonusResearch }, self.researchSlot)
            storage.bonusResearch = 0
          end
          if storage.bonusEssence > 0 then
            shoveItem({ name = "essence", count = storage.bonusEssence }, self.essenceSlot)
            storage.bonusEssence = 0
          end
          if storage.bonusProtheon > 0 then
            shoveItem({ name = "fuprecursorresource", count = storage.bonusProtheon }, self.protheonSlot)
            storage.bonusProtheon = 0
          end
          if storage.bonusGene > 0 then
            shoveItem({ name = "fugeneticmaterial", count = storage.bonusGene }, self.geneSlot)
            storage.bonusGene = 0
          end
          storage.currentItem = nil
          storage.finishedProcessing = false
        end
      end
    else
      local currentItem = world.containerItemAt(entity.id(), self.inputSlot)
      if currentItem == nil then
        storage.status = statusList.waiting
      else
        if currentItem.name == "avali_computeunit" or currentItem.name == "avali_combinunit" then
          storage.status = statusList.invalid
          if not shoveLoop(dt, currentItem, self.outputSlot) then return end
          world.containerTakeAt(entity.id(), self.inputSlot)
        else
          local currentItemParameters = currentItem and mergedParams(root.itemConfig(currentItem))
          local lastTag = checkTags(currentItemParameters)
          if not lastTag then
            storage.status = statusList.invalid
            if not shoveLoop(dt, currentItem, self.outputSlot) then return end
            world.containerTakeAt(entity.id(), self.inputSlot)
          else
            if currentItem.parameters.genomeInspected then
              storage.status = statusList[lastTag .. "ID"]
              if not shoveLoop(dt, currentItem, self.outputSlot) then return end
              world.containerTakeAt(entity.id(), self.inputSlot)
            else
              startProcessing(currentItem, currentItemParameters, lastTag)
            end
          end
        end
      end
    end
  else
    script.setUpdateDelta(-1)
  end

  power.update(dt)
end

-- Shove loop: tries to nudge item into slot, falls back to force-insert
function shoveLoop(dt, currentItem, slot)
  shoveTimer = (shoveTimer or 0.0) + dt
  if not (shoveTimer >= 1.0) then
    return false
  else
    shoveTimer = 0.0
  end
  if (nudgeCount or 0) > 3 then
    shoveItem(currentItem, slot)
  else
    if not nudgeItem(currentItem, slot) then
      nudgeCount = (nudgeCount or 0) + 1
      return false
    end
  end
  nudgeCount = 0
  return true
end

function shoveItem(item, slot)
  if not item then return end

  local slotItem = world.containerItemAt(entity.id(), slot)
  if slotItem and slotItem.name ~= item.name then
    if world.containerTakeAt(entity.id(), slot) then
      world.spawnItem(slotItem, entity.position())
    end
  end

  local leftovers = world.containerPutItemsAt(entity.id(), item, slot)
  if leftovers then
    world.spawnItem(leftovers, entity.position())
  end
end

function nudgeItem(item, slot)
  local slotItem = world.containerItemAt(entity.id(), slot)
  if not item then return end
  if not slotItem then
    world.containerPutItemsAt(entity.id(), item, slot)
    return true
  end
  if slotItem.name ~= item.name then return false end

  local cItem = copy(item)
  local cSlotItem = copy(slotItem)
  cItem.count = 1
  cSlotItem.count = 1
  if not compare(cItem, cSlotItem) then return false end

  local slotItemConfig = slotItem and root.itemConfig(slotItem)
  if slotItemConfig then
    slotItemConfig = mergedParams(slotItemConfig)
    slotItemConfig = slotItemConfig.maxStack or defaultMaxStack
  end

  if (item.count + slotItem.count > slotItemConfig) then return false end

  world.containerPutItemsAt(entity.id(), item, slot)
  return true
end

function mergedParams(item)
  if not item or not item.config then return end
  if item.config and not item.parameters then return item.config end
  return util.mergeTable(item.config, item.parameters)
end

function paneOpened()
  script.setUpdateDelta(defaultDelta)
  playerUsing = true
end

function paneClosed()
  playerUsing = nil
end

function getStatus()
  if storage.status then return storage.status end
end

function die()
  if storage.finishedProcessing then
    if storage.bonusResearch > 0 then
      world.spawnItem({ name = "fuscienceresource", count = storage.bonusResearch }, entity.position())
      storage.bonusResearch = 0
    end
    if storage.bonusEssence > 0 then
      world.spawnItem({ name = "essence", count = storage.bonusEssence }, entity.position())
      storage.bonusEssence = 0
    end
    if storage.bonusProtheon > 0 then
      world.spawnItem({ name = "fuprecursorresource", count = storage.bonusProtheon }, entity.position())
      storage.bonusProtheon = 0
    end
    if storage.bonusGene > 0 then
      world.spawnItem({ name = "fugeneticmaterial", count = storage.bonusGene }, entity.position())
      storage.bonusGene = 0
    end
    if storage.futureItem then
      world.spawnItem(storage.futureItem, entity.position())
      storage.futureItem = nil
    end
    storage.currentItem = nil
  elseif storage.currentItem then
    world.spawnItem(storage.currentItem, entity.position())
    storage.currentItem = nil
    storage.futureItem = nil
  end
end
