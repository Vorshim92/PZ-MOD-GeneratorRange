--***********************************************************
--**                    THE Vorshim STONE                    **
--***********************************************************
-- public class IsoGenerator extends IsoObject
-- public IsoGenerator(IsoCell var1) {
-- 	super(var1);
--  }

if isClient() then return end

-- function ISNewGeneratorRange.newGenerator(item, cell, square)
-- 	local javaObject = IsoGenerator.new(item, cell, square)
-- 	return javaObject
-- end



local function noise(message) print('MOGenerator.lua: '..message) end

local function ReplaceExistingObject(object, fuel, condition)
	local cell = getWorld():getCell()
	local square = object:getSquare()

	local item = InventoryItemFactory.CreateItem("Base.Generator")
	if item == nil then
		noise('Failed to create Base.Generator item')
		return
	end
	item:setCondition(condition)
	item:getModData().fuel = fuel

--	local index = object:getObjectIndex()
	square:transmitRemoveItemFromSquare(object)

	local javaObject = ISNewGeneratorRange.newGenerator(item, cell, square)
	-- IsoGenerator constructor calls AddSpecialObject, probably it shouldn't.
--	square:AddSpecialObject(javaObject, index)
	javaObject:transmitCompleteItemToClients()
end

local function changeGenerator(object)
	local square = object:getSquare()
	print ('square: '..tostring(square:getX())..' '..tostring(square:getY()) ..' '..tostring(square:getZ()))
	local preFuel = object:getFuel()
	print('preFuel: '..tostring(preFuel))
	object:setFuel(100)
	print('postFuel: '..tostring(object:getFuel()))
	-- ReplaceExistingObject(object, fuel, condition)
	local modData = object:getModData()
	modData.isModded = true
end

local PRIORITY = 5

MapObjects.OnLoadWithSprite("appliances_misc_01_0", changeGenerator, PRIORITY)
