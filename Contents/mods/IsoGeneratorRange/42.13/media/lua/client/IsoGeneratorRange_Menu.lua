--***********************************************************
--**                    THE Vorshim STONE                    **
--***********************************************************

local function findGenerator(worldobjects)
	for _, obj in ipairs(worldobjects) do
		local square = obj:getSquare()
		if square then
			for i = 0, square:getObjects():size() - 1 do
				local o = square:getObjects():get(i)
				if instanceof(o, "IsoGenerator") then
					return o
				end
			end
		end
	end
	return nil
end

local function onTogglePyno(generator, playerObj, setPyno)
	local sq = generator:getSquare()
	sendClientCommand(playerObj, "IsoGeneratorRange", "togglePyno", {
		x = sq:getX(), y = sq:getY(), z = sq:getZ(), pyno = setPyno
	})
end

local function onContextMenu(player, context, worldobjects, test)
	if not isClient() or not isAdmin() then return end

	local generator = findGenerator(worldobjects)
	if not generator then return end

	if test then return ISWorldObjectContextMenu.setTest() end

	local playerObj = getSpecificPlayer(player)
	local modData = generator:getModData()

	if modData.pyno then
		context:addOption("Remove SPECIAL (Infinite)", generator, onTogglePyno, playerObj, false)
	else
		context:addOption("Set SPECIAL (Infinite)", generator, onTogglePyno, playerObj, true)
	end
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
