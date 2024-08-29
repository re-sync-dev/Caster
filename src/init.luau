--[==[

	Copyright (C) Re-Sync - All Rights Reserved

	[Caster.lua]:
		Simple & straight forward raycast based projectile module.

	[References]:
		- Signal (https://data-oriented-house.github.io/LemonSignal/)

	[Author(s)]:
		- Vyon (https://github.com/Vyon)

--]==]

-- Services:
local RunService = game:GetService("RunService")

-- Folders:
local Packages = script:FindFirstChild("Packages") or script.Parent

-- Modules:
local Signal = require(Packages.Signal)

-- Types:
-- Generic:
type Connection<U...> = {
	Connected: boolean,

	Disconnect: (self: Connection<U...>) -> (),
	Reconnect: (self: Connection<U...>) -> (),
}

type Signal<T...> = {
	RBXScriptConnection: RBXScriptConnection?,

	Connect: <U...>(self: Signal<T...>, fn: (...any) -> (), U...) -> Connection<U...>,
	Once: <U...>(self: Signal<T...>, fn: (...any) -> (), U...) -> Connection<U...>,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

-- Public:
--[=[

	@within Caster
	@interface CasterOptions
	.Origin Vector3,
	.Direction Vector3,
	.Speed number,
	.RaycastParams RaycastParams?,
	.UseVisuals boolean?,
	.HumanoidsOnly boolean?,
	.Wallbangs number?,

--]=]
export type CasterOptions = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	RaycastParams: RaycastParams?,

	UseVisuals: boolean?,
	HumanoidsOnly: boolean?,
	Wallbangs: number?,
}

-- Private:
type Caster = {
	Active: boolean,
	Location: CFrame,

	OnHit: Signal<(Humanoid?, RaycastResult)>,
	OnUpdate: Signal<(CFrame, CFrame)>,
	OnStop: Signal<boolean?>,

	_Direction: Vector3,
	_Speed: number,
	_Visualize: boolean?,
	_RaycastParams: RaycastParams,
	_ConnectionPool: { [string | number]: RBXScriptConnection },
	_Config: {
		HumanoidsOnly: boolean,
		Wallbangs: number,
	},

	new: (Options: CasterOptions) -> Caster,

	Start: (self: Caster, Lifetime: number?) -> (),
	Stop: (self: Caster) -> (),
	Destroy: (self: Caster) -> (),

	_Update: (self: Caster, DeltaTime: number) -> (),
}

-- Constants:
local FPS = 1 / 60

local DEFAULT_LIFETIME = 5
local VISUAL_LIFETIME = 3

-- Functions:
local function GetVisualContainer(): Folder
	local Container = workspace.Terrain:FindFirstChild("CasterVisuals")

	if not Container then
		Container = Instance.new("Folder")
		Container.Name = "CasterVisuals"
		Container.Parent = workspace.Terrain
	end

	return Container
end

local function VisualizeCast(Origin: Vector3, TargetPosition: Vector3, Color: Color3?)
	local Distance = (Origin - TargetPosition).Magnitude

	-- Create the part used to visualize the cast:
	local Part = Instance.new("Part")
	Part.Name = "Part"
	Part.Anchored = true
	Part.BottomSurface = Enum.SurfaceType.Smooth
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.Color = Color or Color3.fromRGB(255, 0, 0)
	Part.Material = Enum.Material.Neon
	Part.TopSurface = Enum.SurfaceType.Smooth
	Part.Transparency = 0.25

	-- NOTE: Ty for visualization logic https://devforum.roblox.com/t/how-would-i-visualize-a-raycast/1004773/2?u=vyonexe
	Part.Size = Vector3.new(0.5, 0.5, Distance)
	Part.CFrame = CFrame.lookAt(Origin, TargetPosition) * CFrame.new(0, 0, -Distance / 2)

	Part.Parent = GetVisualContainer()

	-- Simulate Debris:AddItem(Part, VISUAL_LIFETIME)
	task.delay(VISUAL_LIFETIME, function()
		Part:Destroy()
	end)
end

-- Main Module:
--[=[

	@class Caster
	Simple & straight forward raycast based projectile module.

	[References]:
		- Signal (https://data-oriented-house.github.io/LemonSignal/)

--]=]
local Caster = {} :: Caster
Caster.__index = Caster

--[=[

	@within Caster
	@function new
	@param Options CasterOptions

	Constructs a new Caster object

--]=]
function Caster.new(Options: CasterOptions)
	local self = setmetatable({}, Caster)

	self.Active = false
	self.Location = CFrame.lookAt(Options.Origin, Options.Origin + Options.Direction)

	self.OnHit = Signal.new()
	self.OnUpdate = Signal.new()
	self.OnStop = Signal.new()

	self._Direction = Options.Direction
	self._Speed = Options.Speed
	self._Visualize = Options.UseVisuals
	self._RaycastParams = Options.RaycastParams or RaycastParams.new()
	self._ConnectionPool = {}
	self._Config = {
		HumanoidsOnly = Options.HumanoidsOnly or false,
		Wallbangs = Options.Wallbangs or 1, --> Caster can only intersect 1 object.
	}

	-- Init:
	self._RaycastParams:AddToFilter(GetVisualContainer())

	-- Internal Connections:
	table.insert(
		self._ConnectionPool,
		self.OnStop:Connect(function(ShouldDestroy: boolean?)
			if not ShouldDestroy then
				self:Stop()
				return
			end

			self:Destroy()
		end)
	)

	return self
end

--[=[

	@within Caster
	@method _Update
	@param DeltaTime number
	@private

--]=]
function Caster:_Update(_DeltaTime: number)
	local Velocity = self._Direction * (self._Speed * FPS)
	local CurrentPosition = self.Location

	local Params = self._RaycastParams
	local Result = workspace:Raycast(CurrentPosition.Position, Velocity, Params)

	-- Check if the raycast hit anything:
	if Result then
		local Hit = Result.Instance
		local Character = Hit:FindFirstAncestorOfClass("Model")
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

		if self._Config.HumanoidsOnly then
			if Humanoid then
				self.OnHit:Fire(Humanoid, Result)
			end
		else
			self._Config.Wallbangs -= 1
			self.OnHit:Fire(Humanoid, Result)
		end
	end

	-- Update the caster's current position:
	self.Location += Velocity

	-- Visualize the update if applicable:
	if self._Visualize then
		VisualizeCast(CurrentPosition.Position, self.Location.Position)
	end

	-- Fire the OnUpdate signal with (LastPosition, NextPosition)
	self.OnUpdate:Fire(CurrentPosition, self.Location)

	-- Stop updating the caster if we cannot wallbang anymore:
	if self._Config.Wallbangs <= 0 and self.Active then
		self.OnStop:Fire(true)
	end
end

--[=[

	@within Caster
	@method Start
	@param Lifetime number?

	Start updating the projectile

--]=]
function Caster:Start(Lifetime: number?)
	Lifetime = Lifetime or DEFAULT_LIFETIME
	self.Active = true

	local NextUpdateAt = 0

	-- Add the heartbeat connection to the pool:
	-- NOTE: This connection will update the caster <60 fps
	self._ConnectionPool["Heartbeat"] = RunService.Heartbeat:Connect(function()
		local Now = os.clock()

		if Now < NextUpdateAt then
			return
		end

		self:_Update(Now - NextUpdateAt)
		NextUpdateAt = Now + FPS
	end)

	-- Create a new thread to wait for the caster to expire:
	task.delay(Lifetime, function()
		if not self.Active then
			return
		end

		self.OnStop:Fire()
		self:Destroy()
	end)
end

--[=[

	@within Caster
	@method Stop

	Stop updating the projectile

--]=]
function Caster:Stop()
	-- Cleanup the heartbeat connection:
	self._ConnectionPool["Heartbeat"]:Disconnect()
	self._ConnectionPool["Heartbeat"] = nil

	self.Active = false
end

--[=[

	@within Caster
	@method Destroy

	Destroy the caster object & cleanup any remaining connections.

--]=]
function Caster:Destroy()
	self.Active = false

	-- Cleanup any existing connections:
	for Key, Connection in self._ConnectionPool do
		Connection:Disconnect()

		self._ConnectionPool[Key] = nil
	end

	-- Destroy the caster's signals & signal connections:
	self.OnUpdate:Destroy()
	self.OnHit:Destroy()
	self.OnStop:Destroy()

	-- Dereference signals:
	self.OnUpdate = nil
	self.OnHit = nil
	self.OnStop = nil

	setmetatable(self, nil)
end

return Caster
