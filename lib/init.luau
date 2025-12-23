--!strict

--[[
	Wrapper: A Wrapper is useful for instantiating and managing instances of a class based off tags.
	Author: Jaeymo
	Version: 2.2.0
	License: MIT
	Created: 09/06/2025

	For issues or feedback message `jaeymo` on Discord!
]]

local GeneralUtil = require(script.Parent["general-util"])
local Janitor = require(script.Parent["janitor"])
local Promise = require(script.Parent["promise"])
local Viewer = require(script.Parent["viewer"])
local Signal = require(script.Parent["signal"])

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
		UseServerGUID = false,                                  -- Automatically call the init method on creation
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

export type Janitor = Janitor.Janitor
export type Signal<T...> = Signal.Signal<T...>
export type Promise<T...> = Promise.TypedPromise<T...>

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
		UseServerGUID: boolean?,
		Filter: ((object: Instance) -> boolean)?,
		Resolver: ((instance: Instance) -> Class<any>)?,
	}

export type Class<T> = {
	__index: any,
	new: (inst: Instance, janitor: Janitor, guid: string?) -> T,
	[any]: any,
}

type WrapperProperties<T> = {
	Janitor: Janitor,
	Options: Options,
	Tag: string,
	Class: Class<T>?,

	SharedData: { [any]: any },
	ObjectJanitors: { [Instance]: Janitor },
	Objects: { [Instance]: T },
	IdMap: { [string]: Instance },

	OnAdded: Signal<Instance, T>,
	OnRevoked: Signal<Instance, T>,

	_isActive: boolean,
}

export type Wrapper<T> = typeof(setmetatable({} :: WrapperProperties<T>, Wrapper))

--[=[
	When an instance gets an object applied into Wrapper.
	@prop OnAdded Signal
	@within Wrapper
]=]
--[=[
	When an instance gets an object revoked from Wrapper.
	@prop OnRevoked Signal
	@within Wrapper
]=]

--[=[
	Instantiates a new Wrapper object.
	@return Wrapper<T>
]=]
function Wrapper.new<T>(Class: Class<T>?, Tag: string, Options: Options?): Wrapper<T>
	assert(type(Tag) == "string", `Expected string, got: {type(Tag)}`)

	local self = setmetatable({} , Wrapper) :: Wrapper<T>
	self.Options = Options or {} :: Options
	self.Janitor = Janitor.new()
	self.Class = Class
	self.Tag = Tag

	for k, v in DEFAULT_OPTIONS do
		if self.Options[k] == nil then
			self.Options[k] = v
		end
	end

	self.SharedData = {}
	self.ObjectJanitors = {}
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
	@return { [ Instance ]: T }
	Returns all of the currently tracked objects.
]=]
function Wrapper.GetAll<T>(self: Wrapper<T>): { [Instance]: T }
	return self.Objects
end

--[=[
	Gets the `object` associated with the given `instance`.

	```lua
	local object = wrapper:GetObject(someInstance)
	object:DoSomething()
	```

	@param Inst Instance
	@return T?
]=]
function Wrapper.GetObject<T>(self: Wrapper<T>, Inst: Instance): T?
	return self.Objects[Inst]
end

--[=[
	Gets the `object` associated with the given `GUID`.

	```lua
	local guid = "342dcb0a-11b0-4119-abd8-ef8a100816b4"
	local object = wrapper:GetObjectByGUID(guid)
	object:DoSomething()
	```

	@param GUID string
	@return T?
]=]
function Wrapper.GetObjectByGUID<T>(self: Wrapper<T>, GUID: string): T?
	return self.IdMap[GUID] and self:GetObject(self.IdMap[GUID])
end

--[=[
	Method that returns a `Promise` for when an `object` may not be loaded.

	```lua
	wrapper:AwaitObject(someInstance)
		:andThen(function(object)
			object:DoSomething()
		end)
		:catch(warn)
	```

	@param Inst Instance
	@param Timeout number?
	@return Promise
]=]
function Wrapper.AwaitObject<T>(self: Wrapper<T>, Inst: Instance, Timeout: number?): Promise<any>
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
	Calls a `method` on the `object` corresponding with the given `instance`. You can
	pass any parameters you'd like after the object and the method name.

	:::info Note
	Setting `Debug` to `true` in the options parameter in the constructor will
	have this method use debug warns.
	:::

	```lua
	local object = wrapper:GetObject(someInstance)
	wrapper:Call(object, "DoSomething")
	```

	@param Object T
	@param Method string
	@param ... any
	@return any
]=]
function Wrapper.Call<T>(self: Wrapper<T>, Object: T, Method: string, ...: any): any
	return GeneralUtil.DebugSafecall(Object, Method, self.Options.Debug or DEFAULT_OPTIONS.Debug, ...)
end

--[=[
	Calls a `method` on all `objects`.

	```lua
	local randomVariable = 10
	wrapper:CallAll("DoSomething", randomVariable)
	```

	@param Method string
	@param ... any
]=]
function Wrapper.CallAll<T>(self: Wrapper<T>, Method: string, ...: any): ()
	for _, Object in self.Objects do
		self:Call(Object, Method, ...)
	end
end

--[=[
	Creates a new `object` for an `instance`. It will call the constructor method
	of the object and give pass in the instance, janitor, and optionally a GUID.

	```lua
	local object = wrapper:Apply(someInstance)
	if object then
		object: DoSomething()
	end
	```

	@param Inst Instance
	@return T?
]=]
function Wrapper.Apply<T>(self: Wrapper<T>, Inst: Instance): T?
	if self.Objects[Inst] then return nil end

	if self.Options.Filter and not self.Options.Filter(Inst) then
		return nil
	end

	local ObjectJanitor = Janitor.new()
	local GUID
	
	if self.Options.UseServerGUID then
		local Start = os.clock()
		
		while not GUID do
			if os.clock() - Start > 10 then
				warn(`[{script.Name}] Timed out waiting for GUID for {Inst:GetFullName()}`)
				return nil
			end
			
			GUID = Inst:GetAttribute(self.Tag .. "GUID")
			task.wait()
		end
	else
		GUID = self.Options.GUID and GeneralUtil.NewGUID(self.Options.GUID)
	end

	local Class = self.Options.Resolver and self.Options.Resolver(Inst) or self.Class
	if not Class then
		ObjectJanitor:Destroy()

		if self.Options.Debug then
			warn(`[{script.Name}] No class could be resolved for: {Inst:GetFullName()}`)
		end

		return nil
	end

	local Methods = self.Options.Methods
	local Constructor = Methods and Methods.Constructor or DEFAULT_OPTIONS.Methods.Constructor
	local Success, Object = pcall(Class[Constructor], Inst, ObjectJanitor, GUID)

	if not Success then
		ObjectJanitor:Destroy()

		return error(`[{script.Name}] Failed to construct object for {Inst.Name}. Error: {Object}`)
	end

	if not GUID then
		local ExistingGUID = Inst:GetAttribute(self.Tag .. "GUID")
		if ExistingGUID then
			GUID = ExistingGUID
		end
	end

	if GUID then
		Inst:SetAttribute(self.Tag .. "GUID", GUID)
		self.IdMap[GUID] = Inst
	end

	self.Objects[Inst] = Object
	self.ObjectJanitors[Inst] = ObjectJanitor :: any

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

	self.OnAdded:Fire(Inst, Object)

	return Object
end

--[=[
	Cleans up an `object`.

	:::info Note
	This will nullify the object's metatable, so you will not be able to use
	the object after revoking it from Wrapper.
	:::

	```lua
	local object = wrapper:Apply(someInstance)

	-- cleans up the instance in the wrapper
	wrapper:Revoke(someInstance)

	-- you could also destroy the instance, thereby invoking the tag removed event
	someInstance:Destroy -- also cleans up
	```

	@param Inst Instance
]=]
function Wrapper.Revoke<T>(self: Wrapper<T>, Inst: Instance): ()
	if not self.Objects[Inst] then return end

	local GUID

	if Inst:GetAttribute(self.Tag .. "GUID") then
		GUID = Inst:GetAttribute(self.Tag .. "GUID")

		self.IdMap[Inst:GetAttribute(self.Tag .. "GUID")] = nil
		Inst:SetAttribute(self.Tag .. "GUID", nil)
	end

	local ObjectJanitor = self.ObjectJanitors[Inst]
	if ObjectJanitor then
		ObjectJanitor:Destroy()
		self.ObjectJanitors[Inst] = nil
	end

	local Object = self.Objects[Inst]
	if Object then
		self.OnRevoked:Fire(Inst, Object)

		local Methods = self.Options.Methods
		local Destroy = Methods and Methods.Destroy or DEFAULT_OPTIONS.Methods.Destroy
		local Debug = self.Options.Debug or DEFAULT_OPTIONS.Debug
		GeneralUtil.DebugSafecall(Object, Destroy, Debug)

		table.clear(Object :: any)
		setmetatable(Object :: any, nil)

		self.Objects[Inst] = nil
	end

	if self.Options.Logging then
		warn(`[{script.Name}] Revoked instance: {Inst:GetFullName()}`)
	end
end

--[=[
	Revokes all wrapped objects.
]=]
function Wrapper.RevokeAll<T>(self: Wrapper<T>): ()
	for Inst in self.Objects do
		self:Revoke(Inst)
	end
end

--[=[
	Destroys all tracked `objects`, cleans the `janitor` object and all `signals`, rendering
	this object useless.

	:::warning Metatable Removal
	Running this will make any further attempts to call a method of Wrapper
	error.
	:::

	```lua
	wrapper:Destroy()
	```
]=]
function Wrapper.Destroy<T>(self: Wrapper<T>): ()
	self:RevokeAll()
	self.OnRevoked:Destroy()
	self.OnAdded:Destroy()
	self.Janitor:Destroy()

	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

function Wrapper._watch<T>(self: Wrapper<T>)
	if self._isActive then return end
	self._isActive = true

	self.Janitor:Add(Viewer.WatchTag(self.Tag, false, function(Inst: Instance)
		self:Apply(Inst)
	end))

	self.Janitor:Add(Viewer.WatchTag(self.Tag, true, function(Inst: Instance)
		self:Revoke(Inst)
	end))
end

-- syntax sugar :)
Wrapper.__call = function(_, ...)
	return Wrapper.new(...)
end

return Wrapper