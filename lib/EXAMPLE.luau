--[[
	```lua
	--!strict

	-- Example class
	local KillPartClass = {}
	KillPartClass.__index = KillPartClass

	type KillPart = typeof(setmetatable({} :: {
		Part: BasePart,	
		Trove: any,
		GUID: string
	}, KillPartClass))

	function KillPartClass.new(Part: Instance, Trove: any, GUID: string?): KillPart
		local self = setmetatable({}, KillPartClass)
		self.Part = Part :: BasePart
		self.Trove = Trove
		self.GUID = GUID :: string

		return self
	end

	function KillPartClass.Init(self: KillPart) -- automatically runs!
		self:WatchTouchedEvent()
	end

	function KillPartClass.WatchTouchedEvent(self: KillPart)
		self.Trove:Add(self.Part.Touched:Connect(function(Hit: BasePart)
			local Humanoid = Hit.Parent and Hit.Parent:FindFirstChildWhichIsA("Humanoid")
			if not Humanoid then return end

			Humanoid.Health = 0
		end))
	end

	function KillPartClass.Destroy(self: KillPart)
		print("This object has been destroyed!") -- the trove and metatable are cleaned externally, no need to do it here.
	end

	-- Usage of class
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Wrapper = require(path.to.Wrapper)

	local KillPartWrapper = Wrapper.new(KillPartClass, "KillPart", {
		Logging = true,
		AutoInit = true,
		GUID = "KillPart"
	})
	```
]]