--***********************************************************
--**                    THE Vorshim STONED                 **
--***********************************************************

if isClient() then return end

local function noise(message) print('IsoGeneratorRange.lua: '..message) end

---@param object IsoGenerator
local function changeGenerator(object)
	local modData = object:getModData()
	if not modData.pyno then
		return
	end
	noise('Refueling SPECIAL generator at '..tostring(object:getSquare():getX())..' '..tostring(object:getSquare():getY())..' '..tostring(object:getSquare():getZ()))
	object:setFuel(999999.0)
	object:setCondition(999999)
    object:transmitModData()
    local square = object:getSquare()
    square:transmitModdata()
end

local PRIORITY = 5

local generatorSprites = {
	"appliances_misc_01_0", "appliances_misc_01_1",
	"appliances_misc_01_2", "appliances_misc_01_3",
	"appliances_misc_01_4", "appliances_misc_01_5",
	"appliances_misc_01_6", "appliances_misc_01_7",
	"appliances_misc_01_8", "appliances_misc_01_9",
	"appliances_misc_01_10", "appliances_misc_01_11",
	"appliances_misc_01_12", "appliances_misc_01_13",
	"appliances_misc_01_14", "appliances_misc_01_15",
}

for _, sprite in ipairs(generatorSprites) do
	MapObjects.OnLoadWithSprite(sprite, changeGenerator, PRIORITY)
end

local function onClientCommand(module, command, player, args)
	if module ~= "IsoGeneratorRange" then return end
	if command == "togglePyno" then
		if not checkPermissions(player, Capability.AddItem) then
			noise("Non-admin tried to toggle pyno from player: " .. player:getUsername())
			return
		end
		local sq = getCell():getGridSquare(args.x, args.y, args.z)
		if not sq then return end
		for i = 0, sq:getObjects():size() - 1 do
			local obj = sq:getObjects():get(i)
			if instanceof(obj, "IsoGenerator") then
                ---@cast obj IsoGenerator
				if args.pyno then
					obj:getModData().pyno = true
					changeGenerator(obj)
				else
					obj:getModData().pyno = nil
					obj:transmitModData()
				end
				noise("Generator pyno set to " .. tostring(args.pyno) .. " at " .. tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z))
				break
			end
		end
	end
end

Events.OnClientCommand.Add(onClientCommand)

-- TODO: agganciare Events.EveryDays per reimpostare fuel/condition dei generatori pyno
-- anche quando un player resta fisso nella cella (OnLoadWithSprite non viene ritriggerato in quel caso)
