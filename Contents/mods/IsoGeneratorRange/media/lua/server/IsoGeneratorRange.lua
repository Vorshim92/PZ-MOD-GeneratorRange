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

local function ReplaceInfoItem(object, fuel, condition)

	local item = InventoryItemFactory.CreateItem("Base.Generator")
	if item == nil then
		noise('Failed to create Base.Generator item')
		return
	end
    noise('Created Base.Generator item from ReplaceInfoItem')
	item:setCondition(condition)
	item:getModData().fuel = fuel

	object:setInfoFromItem(item)
	-- javaObject:transmitCompleteItemToClients()
end

local function vorshimSerial (tbl, indent)
    indent = indent or ""
    local serialized = ""
    
    if type(tbl) ~= "table" then
        -- Se non è una tabella, serializza come stringa o altro tipo
        if type(tbl) == "string" then
            return string.format("%q", tbl)
        elseif type(tbl) == "number" or type(tbl) == "boolean" then
            return tostring(tbl)
        elseif type(tbl) == "userdata" then
            return tostring(tbl)
            else
            return '"UnsupportedType"'
        end
    end

    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        if not keyStr:match("^[_%a][_%w]*$") then
            keyStr = string.format("[%q]", keyStr)
        end
        if type(value) == "table" then
            serialized = serialized .. indent .. keyStr .. " = {\n"
            serialized = serialized .. vorshimSerial(value, indent .. "    ")
            serialized = serialized .. indent .. "},\n"
        else
            local valueStr
            if type(value) == "string" then
                valueStr = string.format("%q", value)
            elseif type(value) == "number" or type(value) == "boolean" then
                valueStr = tostring(value)
            elseif type(value) == "userdata" then
                valueStr = tostring(value)
            else
                valueStr = '"UnsupportedType"'
            end
            serialized = serialized .. indent .. keyStr .. " = " .. valueStr .. ",\n"
        end
    end
    return serialized
end

local function changeGenerator(object)
	-- local modData = object:getModData()
	-- if modData.isModded then
	-- 	print("il generatore e' stato modificato")
	-- end
	local square = object:getSquare()
	noise('square: '..tostring(square:getX())..' '..tostring(square:getY()) ..' '..tostring(square:getZ()))
	
	noise('preFuel: '..tostring(object:getFuel()))
	
    ReplaceInfoItem(object, 99999999, 99999999)

	noise('getFuel: '..tostring(object:getFuel()))
	-- ReplaceExistingObject(object, fuel, condition)
	
	-- modData.isModded = true
	-- print(vorshimSerial(modData))
end

local PRIORITY = 5

MapObjects.OnLoadWithSprite("appliances_misc_01_0", changeGenerator, PRIORITY)



-- getTileOverlays():fixTableTopOverlays(_square);

--     _square:RecalcProperties();
--     _square:RecalcAllWithNeighbours(true);