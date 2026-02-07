require "TimedActions/ISTakeGenerator"

local original_isValidStart = ISTakeGenerator.isValidStart
function ISTakeGenerator:isValidStart()
	if self.generator:getModData().pyno and not isAdmin() then
		self.character:Say("Only Admins may take infinite generators.")
		return false
	end
	if original_isValidStart then
		return original_isValidStart(self)
	end
	return true
end

local original_complete = ISTakeGenerator.complete
function ISTakeGenerator:complete()
	local mData = self.generator:getModData()
	if mData.pyno and not checkPermissions(self.character, Capability.AddItem) then
		print("Non-admin tried to take pyno generator: " .. self.character:getUsername())
		return false
	end
	return original_complete(self)
end
