# Wrapper
Wrapper library. A module that manages the lifecycle of class objects tied to tagged instances.

Taking a bit of inspiration from ECS systems, Wrapper automates the creation, initialization, and destruction
of tagged class instances. Wrapper provides the constructor with a [Trove](https://github.com/Sleitnick/RbxUtil/blob/main/modules/trove/init.luau) object that is cleaned up on destruction.

## Why Use Wrapper?
- Wrapper makes object-oriented code quicker and cleaner to write.
- There's plenty of customization when it comes to what naming convention Wrapper uses for your class' methods.
- Generic type-checking does great in this case. Accessing a wrapper object from elsewhere will still provide the class' type-checking.

## Example Usage
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
local Wrapper = require(path.to.Wrapper)

local KillPartWrapper = Wrapper.new(KillPartClass, "KillPart", {
    Logging = true,
    AutoInit = true, -- AutoInit is true automatically, this redundant but shows what it does nonetheless
    GUID = "KillPart"
})
```