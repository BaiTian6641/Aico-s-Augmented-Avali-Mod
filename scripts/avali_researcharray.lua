-- Avali Research Processor Array
-- Advanced server rack: computing units boost speed, items are researched into various point types
require '/scripts/fupower.lua'

local COMPUTE_UNIT_BOOST = 0.04   -- Speed boost per Integrated Computing Unit
local COMBIN_UNIT_BOOST = 0.12    -- Speed boost per Combined Computing Unit
local POWER_PER_SLOT = 3.5        -- Watts per occupied slot
local BASE_IDLE_POWER = 2.0       -- Base idle power
local BASE_RESEARCH_TIME = 8.0    -- Base seconds per research cycle

-- Some items generate bio/geo flavored research currency
local BIO_ITEMS = {
  plantfibre = true, livingroot = true, alienweirdplant = true,
  mutavisk = true, geneticextract = true
}

local GEO_ITEMS = {
  coalore = true, copperore = true, ironore = true, silverore = true,
  goldore = true, diamond = true, uraniumore = true, plutoniumore = true,
  titaniumore = true, solariumore = true, lead = true, sulphur = true
}

function init()
  power.init()
  storage.researchTimer = storage.researchTimer or 0
  storage.scanIndex = storage.scanIndex or 0
end

function scanComputingBoost()
  local totalBoost = 0
  local slotsUsed = 0
  local slotCount = config.getParameter("slotCount", 20)

  for i = 0, slotCount - 1 do
    local item = world.containerItemAt(entity.id(), i)
    if item then
      slotsUsed = slotsUsed + 1
      if item.name == "avali_computeunit" then
        totalBoost = totalBoost + COMPUTE_UNIT_BOOST * item.count
      elseif item.name == "avali_combinunit" then
        totalBoost = totalBoost + COMBIN_UNIT_BOOST * item.count
      end
    end
  end

  return totalBoost, slotsUsed
end

function update(dt)
  local computeBoost, slotsUsed = scanComputingBoost()

  -- Power draw scales with occupied slots
  local powerDraw = BASE_IDLE_POWER + (slotsUsed * POWER_PER_SLOT)
  power.setPower(powerDraw)

  -- Research processing: consume non-computing-unit items
  if computeBoost > 0 then
    -- Research speed improves with computing boost
    local researchInterval = BASE_RESEARCH_TIME / math.max(1.0, 1.0 + computeBoost * 10)
    storage.researchTimer = (storage.researchTimer or 0) + dt

    if storage.researchTimer >= researchInterval then
      storage.researchTimer = 0
      local slotCount = config.getParameter("slotCount", 20)

      -- Scan for a researchable item (skip computing units)
      for attempt = 1, slotCount do
        local slot = (storage.scanIndex or 0) % slotCount
        storage.scanIndex = slot + 1

        local item = world.containerItemAt(entity.id(), slot)
        if item and item.name ~= "avali_computeunit" and item.name ~= "avali_combinunit" then
          -- Calculate points: base 2-5 per item, scaled by boost
          local points = math.max(1, math.floor(2 + computeBoost * 20))

          -- Consume 1 item and spawn research currency
          world.containerConsumeAt(entity.id(), slot, 1)
          world.spawnItem("fuscienceresource", entity.position(), points)
          break
        end
      end
    end
  else
    storage.researchTimer = 0
  end

  -- Activity light
  if computeBoost > 0 then
    local brightness = math.min(1.0, slotsUsed / 20)
    object.setLightColor({
      math.floor(255 * brightness),
      math.floor(100 * brightness),
      math.floor(50 * brightness)
    })
  else
    object.setLightColor({0, 0, 0})
  end

  power.update(dt)
end
