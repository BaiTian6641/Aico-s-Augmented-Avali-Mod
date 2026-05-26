-- Avali Integrated Processor Array
-- Server rack: holds computing units to passively generate research points
require '/scripts/fupower.lua'

local COMPUTE_UNIT_RATE = 0.5    -- Research per second per Integrated Computing Unit
local COMBIN_UNIT_RATE = 1.5     -- Research per second per Combined Computing Unit
local POWER_PER_SLOT = 3.0       -- Watts consumed per occupied slot
local BASE_IDLE_POWER = 1.0      -- Base idle power draw

function init()
  power.init()
  storage.researchAccum = storage.researchAccum or 0
end

function scanSlots()
  local totalRate = 0
  local slotsUsed = 0
  local slotCount = config.getParameter("slotCount", 10)

  for i = 0, slotCount - 1 do
    local item = world.containerItemAt(entity.id(), i)
    if item then
      slotsUsed = slotsUsed + 1
      if item.name == "avali_computeunit" then
        totalRate = totalRate + COMPUTE_UNIT_RATE * item.count
      elseif item.name == "avali_combinunit" then
        totalRate = totalRate + COMBIN_UNIT_RATE * item.count
      end
    end
  end

  return totalRate, slotsUsed
end

function update(dt)
  local researchRate, slotsUsed = scanSlots()

  -- Power draw scales with occupied slots
  local powerDraw = BASE_IDLE_POWER + (slotsUsed * POWER_PER_SLOT)
  power.setPower(powerDraw)

  -- Accumulate and spawn research
  if researchRate > 0 then
    storage.researchAccum = (storage.researchAccum or 0) + researchRate * dt

    -- Every time we accumulate enough, spawn a research resource
    while storage.researchAccum >= 1.0 do
      storage.researchAccum = storage.researchAccum - 1.0
      world.spawnItem("fuscienceresource", entity.position(), 1)
    end

    -- Activity light
    local brightness = math.min(1.0, slotsUsed / 10)
    object.setLightColor({
      math.floor(100 * brightness),
      math.floor(180 * brightness),
      math.floor(255 * brightness)
    })
  else
    object.setLightColor({0, 0, 0})
  end

  power.update(dt)
end
