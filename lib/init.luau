--!strict

--[[
	Wrapper: Manages the life-cycle of object-oriented classes by tracking tagged instances
	Author: Jaeymo
	Version: 2.0.3
	License: MIT
	Created: 09/06/2025

	For issues or feedback message `jaeymo` on Discord!
]]

local GeneralUtil = require(script.Parent["general-util"])
local Promise = require(script.Parent["promise"])
local Viewer = require(script.Parent["viewer"])
local Signal = require(script.Parent["signal"])
local Trove = require(script.Parent["trove"])

local DEFAULT_OPTIONS =
{
	Methods = {
		Init = "Init",
		Destroy = "Destroy",
		Startup = "OnStart",
		Constructor = "new",
	},

	Debug = false,                                          -- Whether debug mode is enabled (extra logs, warnings, etc.)
	Context = nil,                                          -- The context provided to the class
	Logging = false,                                        -- Logging of all instances being processed
	AutoInit = true,                                        -- Automatically call the init method on creation
	Filter = function(instance: Instance) return true end,  -- Function to filter instances
	Resolver = function(instance: Instance) return nil end, -- If you want dynamic requires
}

--[=[
	@class Wrapper
	A Wrapper is useful for instantiating and managing instances of
	a class based off tags.
]=]
local Wrapper = {}
Wrapper.__index = Wrapper

type Trove = Trove.Trove
type Signal = Signal.Signal
type Promise = Promise.TypedPromise

export type Options =
{
	Methods: {
		Init: string,
		Startup: string,
		Destroy: string,
		Constructor: string,
	}?,
	Context: any?,
	GUID: string?,
	Logging: boolean?,
	Debug: boolean?,
	AutoInit: boolean?,
	Filter: ((object: Instance) -> boolean)?,
	Resolver: ((instance: Instance) -> Class<any>)?,
}

export type Class<T> = {
	__index: any,
	new: (inst: Instance, trove: Trove, guid: string?) -> T,
	[any]: any,
}

type WrapperProperties<T> = {
	Trove: Trove,
	Options: Options,
	Tag: string,
	Class: Class<T>?,

	SharedData: { [any]: any },
	ObjectTroves: { [Instance]: Trove },
	Objects: { [Instance]: T },
	IdMap: { [string]: Instance },

	OnAdded: Signal,
	OnRevoked: Signal,

	_isActive: boolean,
}

export type Wrapper<T> = typeof(setmetatable({} :: WrapperProperties<T>, Wrapper))

--[=[
	@return Wrapper<T>
	Constructs a Wrapper object.

	```lua
	local wrapper = Wrapper.new()
	```
]=]
function Wrapper.new<T>(Class: Class<T>?, Tag: string, Options: Options?): Wrapper<T>
	assert(type(Tag) == "string", `Expected string, got: {type(Tag)}`)

	local self = setmetatable({} , Wrapper) :: Wrapper<T>
	self.Options = Options or {} :: Options
	self.Trove = Trove.new()
	self.Class = Class
	self.Tag = Tag

	for k, v in DEFAULT_OPTIONS do
		if self.Options[k] == nil then
			self.Options[k] = v
		end
	end

	self.SharedData = {}
	self.ObjectTroves = {}
	self.Objects = {}
	self.IdMap = {}

	self.OnAdded = Signal.new()
	self.OnRevoked = Signal.new()

	-- if there is a startup method, we will pass this wrapper object and the context to that func
	local Methods = self.Options.Methods
	local Startup = Methods and Methods.Startup
	local Context = self.Options.Context
	local Debug = self.Options.Debug :: boolean

	if Startup then
		GeneralUtil.DebugSafecall(Class, Startup, Debug, self, Context)
	end

	self:_watch()

	return self
end

--[=[
	@method GetAll
	@within Wrapper
	@return { [ Instance ]: T }
	Returns all of the currently tracked objects.

	```lua
	local objects = wrapper:GetAll()
	```
]=]
function Wrapper.GetAll<T>(self: Wrapper<T>): { [Instance]: T }
	return self.Objects
end

--[=[
	@method GetObject
	@within Wrapper
	@param Inst Instance
	@return T?
	Gets the object associated with the given instance.

	```lua
	local object = wrapper:GetObject(someInstance)
	object:DoSomething()
	```
]=]
function Wrapper.GetObject<T>(self: Wrapper<T>, Inst: Instance): T?
	return self.Objects[Inst]
end

--[=[
	@method GetObjectByGUID
	@within Wrapper
	@param GUID string
	@return T?
	Gets the object associated with the given GUID.

	```lua
	local guid = "342dcb0a-11b0-4119-abd8-ef8a100816b4"
	local object = wrapper:GetObjectByGUID(guid)
	object:DoSomething()
	```
]=]
function Wrapper.GetObjectByGUID<T>(self: Wrapper<T>, GUID: string): T?	
	return self.IdMap[GUID] and self:GetObject(self.IdMap[GUID])
end

--[=[
	@method AwaitObject
	@within Wrapper
	@param Inst Instance
	@param Timeout number?
	@return Promise

	```lua
	wrapper:AwaitObject(someInstance)
		:andThen(function(object)
			object:DoSomething()
		end)
		:catch(warn)
	```
]=]
function Wrapper.AwaitObject<T>(self: Wrapper<T>, Inst: Instance, Timeout: number?): Promise
	return Promise.new(function(resolve, reject)
		if typeof(Inst) ~= "Instance" then
			reject("Invalid instance")
			return
		end

		local Start = os.clock()
		local ActualTimeout = Timeout or 10

		repeat
			task.wait()

			local Object = self:GetObject(Inst)
			if Object then
				resolve(Object)
				return
			end

		until os.clock() - Start >= ActualTimeout

		reject(`Timed out waiting for: {Inst:GetFullName()}`)
	end)
end

--[=[
	@method Call
	@within Wrapper
	@param Object T
	@param Method string
	@param ... any
	@return any
	Calls a method on the object associated with the given instance.

	```lua
	local object = wrapper:GetObject(someInstance)
	wrapper:Call(object, "DoSomething")
	```
]=]
function Wrapper.Call<T>(self: Wrapper<T>, Object: T, Method: string, ...: any)
	return GeneralUtil.DebugSafecall(Object, Method, self.Options.Debug or DEFAULT_OPTIONS.Debug, ...)
end

--[=[
	@method CallAll
	@within Wrapper
	@param Method string
	@param ... any
	Calls a method on all objects.

	```lua
	local randomVariable = 10
	wrapper:CallAll("DoSomething", randomVariable)
	```
]=]
function Wrapper.CallAll<T>(self: Wrapper<T>, Method: string, ...: any)
	for _, Object in self.Objects do
		self:Call(Object, Method, ...)
	end
end

--[=[
	@method Apply
	@within Wrapper
	@param Inst Instance
	Creates a new object for an instance and starts tracking it.
	Also provides the object with a trove that will be cleaned up
	upon destruction.

	```lua
	local object = wrapper:Apply(someInstance)
	if object then
		object: DoSomething()
	end
	```
]=]
function Wrapper.Apply<T>(self: Wrapper<T>, Inst: Instance): T?
	if self.Objects[Inst] then return nil end

	if self.Options.Filter and not self.Options.Filter(Inst) then
		return nil
	end

	local ObjectTrove = Trove.new()
	local GUID = self.Options.GUID and GeneralUtil.NewGUID(self.Options.GUID)

	local Class = self.Options.Resolver and self.Options.Resolver(Inst) or self.Class
	if not Class then
		ObjectTrove:Destroy()

		if self.Options.Debug then
			warn(`[{script.Name}] No class could be resolved for: {Inst:GetFullName()}`)
		end

		return nil
	end

	local Methods = self.Options.Methods
	local Constructor = Methods and Methods.Constructor or DEFAULT_OPTIONS.Methods.Constructor
	local Success, Object = pcall(Class[Constructor], Inst, ObjectTrove, GUID)

	if not Success then
		ObjectTrove:Destroy()

		if self.Options.Debug then
			warn(`[{script.Name}] Failed to construct object for {Inst.Name}. Error: {Object}`)
		end

		return nil
	end

	if not GUID then
		local ExistingGUID = Inst:GetAttribute("GUID")
		if ExistingGUID then
			GUID = ExistingGUID
		end
	end

	if GUID then
		Inst:SetAttribute("GUID", GUID)
		self.IdMap[GUID] = Inst
	end

	self.Objects[Inst] = Object
	self.ObjectTroves[Inst] = ObjectTrove

	if self.Options.AutoInit then
		local Init = Methods and Methods.Init or DEFAULT_OPTIONS.Methods.Init
		local Debug = self.Options.Debug or DEFAULT_OPTIONS.Debug
		GeneralUtil.DebugSafecall(Object, Init, Debug)
	end

	if self.Options.Logging then
		warn(`[{script.Name}] Added instance: {Inst:GetFullName()}`)
	end

	if not Inst:HasTag(self.Tag) then
		Inst:AddTag(self.Tag)
	end

	return Object
end

--[=[
	@method Revoke
	@within Wrapper
	@param Inst Instance
	Manually cleans up an object. Note, this does not
	destroy the object (though that is another way to force
	cleanup).

	```lua
	local object = wrapper:Apply(someInstance)

	-- cleans up the instance in the wrapper
	wrapper:Revoke(someInstance)

	-- you could also destroy the instance, thereby invoking the tag removed event
	someInstance:Destroy -- also cleans up
	```
]=]
function Wrapper.Revoke<T>(self: Wrapper<T>, Inst: Instance)
	if not self.Objects[Inst] then return end

	if Inst:GetAttribute("GUID") then
		self.IdMap[Inst:GetAttribute("GUID")] = nil
		Inst:SetAttribute("GUID", nil)
	end

	local ObjectTrove = self.ObjectTroves[Inst]
	if ObjectTrove then
		ObjectTrove:Destroy()
		self.ObjectTroves[Inst] = nil
	end

	local Object = self.Objects[Inst]
	if Object then
		local Methods = self.Options.Methods
		local Destroy = Methods and Methods.Destroy or DEFAULT_OPTIONS.Methods.Destroy
		local Debug = self.Options.Debug or DEFAULT_OPTIONS.Debug
		GeneralUtil.DebugSafecall(Object, Destroy, Debug)

		setmetatable(Object :: any, nil)
		table.clear(Object :: any)

		self.Objects[Inst] = nil
	end

	if self.Options.Logging then
		warn(`[{script.Name}] Revoked instance: {Inst:GetFullName()}`)
	end
end

--[=[
	@method RevokeAll
	@within Wrapper
	Revokes all wrapped objects.

	```lua
	wrapper:RevokeAll()
	```
]=]
function Wrapper.RevokeAll<T>(self: Wrapper<T>)
	for Inst in self.Objects do
		self:Revoke(Inst)
	end
end

--[=[
	@method Destroy
	@within Wrapper
	Cleans up the entire Wrapper, destroying all tracked objects and resources.

	:::warning Metatable Removal
	Running this will make any further attempts to call a method of Janitor
	error.
	```lua
	wrapper:Destroy()
	```
]=]
function Wrapper.Destroy<T>(self: Wrapper<T>)
	self:RevokeAll()
	self.OnRevoked:Destroy()
	self.OnAdded:Destroy()
	self.Trove:Destroy()

	table.clear(self)
	setmetatable(self, nil)
end

function Wrapper._watch<T>(self: Wrapper<T>)
	if self._isActive then return end
	self._isActive = true

	self.Trove:Add(Viewer.WatchTag(self.Tag, false, function(Inst: Instance)
		self:Apply(Inst)
	end))

	self.Trove:Add(Viewer.WatchTag(self.Tag, true, function(Inst: Instance)
		self:Revoke(Inst)
	end))
end

-- syntax sugar :)
Wrapper.__call = function(_, ...)
	return Wrapper.new(...)
end

return Wrapper