require '/scripts/fupower.lua'

function init()
  heat = config.getParameter('heat')
  power.init()
end

function update(dt)
  if storage.fueltime and storage.fueltime > 0 then
    storage.fueltime = math.max(storage.fueltime - dt, 0)
  end

  if not storage.fueltime or storage.fueltime == 0 then
    storage.powermod = nil
    local item = world.containerItemAt(entity.id(), 0)
    if item and (not object.isInputNodeConnected(1) or object.getInputNodeLevel(1)) then
      local itemlist = config.getParameter('acceptablefuel')
      for key, value in pairs(itemlist) do
        if item.name == key then
          world.containerConsumeAt(entity.id(), 0, 1)
          storage.fueltime = value
          storage.powermod = value
        end
      end
    end
  end

  if storage.fueltime and storage.fueltime > 0 then
    storage.heat = math.min((storage.heat or 0) + dt * 4, 100)
  else
    storage.heat = math.max((storage.heat or 0) - dt * 4, 0)
  end

  local heatmark = 0
  for i = 1, #heat do
    if storage.heat >= heat[i].minheat then
      heatmark = heat[i].power
      power.setPower(heatmark + math.floor((storage.powermod or 0) * 0.1))
      local lightColor = config.getParameter("lightColor", heat[i].light)
      local brightness = math.min(0.75, 0.75 * (storage.heat / 90))
      lightColor[1] = math.floor(lightColor[1] * 0.25 + lightColor[1] * brightness)
      lightColor[2] = math.floor(lightColor[2] * 0.25 + lightColor[2] * brightness)
      lightColor[3] = math.floor(lightColor[3] * 0.25 + lightColor[3] * brightness)
      object.setLightColor(lightColor)
      object.setSoundEffectEnabled(heat[i].sound)
      break
    end
  end
  object.setAllOutputNodes(heatmark > 0)
  power.update(dt)
end
