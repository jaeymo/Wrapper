**Use _Classy_, an updated version of this package here: [link](https://github.com/jaeymo/Classy)**

# Wrapper
Wrapper library. A module that manages the lifecycle of class objects tied to tagged instances.

Wrapper automates the creation, initialization, and destruction of class objects based on tag instances.
Wrapper provides the constructor with a [Trove](https://github.com/Sleitnick/RbxUtil/blob/main/modules/trove/init.luau) object and an optional GUID.

## Why Use Wrapper?
- Wrapper makes object-oriented code quicker and cleaner to write.
- Wrapper handles the cleanup of the object's metatable and the provided [Trove](https://github.com/Sleitnick/RbxUtil/blob/main/modules/trove/init.luau) object.
- There's plenty of customization when it comes to what naming convention Wrapper uses for your class' methods.
- Generic type-checking does great in this case. Accessing a wrapper object from elsewhere will still provide the class' type-checking.
- Promise support for the `AwaitObject` method.
- If you are a fanatic about object-oriented programming, this is the module for you! Simply store classes for game objects and apply them via tags.

## Installation
Wrapper is installable via [wally](https://wally.run/) and you can visit the page [here](https://wally.run/package/jaeymo/wrapper?version=2.0.8).

## Dependencies
- [Trove](https://github.com/Sleitnick/RbxUtil/blob/main/modules/trove/init.luau)
- [Promise](https://github.com/evaera/roblox-lua-promise/blob/master/lib/init.lua)
- [Signal](https://github.com/Sleitnick/RbxUtil/blob/main/modules/signal/init.luau)
- [Viewer](https://github.com/jaeymo/roblox-packages/blob/main/Viewer/init.luau)
- [GeneralUtil](https://github.com/jaeymo/roblox-packages/blob/main/GeneralUtil/init.luau)
  
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

-- everytime a part with the "KillPart" tag is added, this runs.
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
