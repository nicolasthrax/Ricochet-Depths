-- Constructs and wires every server system. Main.server.luau does nothing but call this.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local EffectBroadcaster = require(script.Parent.EffectBroadcaster)
local EnemyService = require(script.Parent.EnemyService)
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local MatchService = require(script.Parent.MatchService)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local ProjectileService = require(script.Parent.ProjectileService)
local RemoteRouter = require(script.Parent.RemoteRouter)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RewardService = require(script.Parent.RewardService)
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RoomService = require(script.Parent.RoomService)
local TelemetryService = require(script.Parent.TelemetryService)
local UpgradeService = require(script.Parent.UpgradeService)
local WorldAdapter = require(script.Parent.WorldAdapter)

local GameBootstrap = {}

local NET_EVENTS = {
	"RunStateChanged",
	"PlayerStateChanged",
	"UpgradeOffer",
	"UpgradeResolved",
	"RunResults",
	"EnemyDefeated",
}

function GameBootstrap.Start()
	local seed = os.time() % 2147483647

	-- Everything a projectile may collide with lives under Arena, so one filter covers it all.
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = workspace

	local _, startPrompt = LobbyBuilder.Build(workspace)

	local planeY = RoomConfig.FloorY + ProjectileConfig.PlaneHeight
	local enemies = EnemyService.new(arena, planeY, seed)
	local projectiles = ProjectileService.new(workspace, arena, planeY)
	local rooms = RoomService.new(arena, enemies, planeY, Random.new(seed))

	local telemetry = TelemetryService.new(function(eventName, payload, now)
		if DebugConfig.LogTelemetry and DebugConfig.IsEnabled() then
			print(string.format("[telemetry %7.1f] %s %s", now, eventName, GameBootstrap._format(payload)))
		end
	end)

	local net = {}
	for _, name in NET_EVENTS do
		net[name] = Remotes.Get(name)
	end

	local match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = UpgradeService.new(seed),
		projectiles = projectiles,
		rewards = RewardService.new(),
		effects = EffectBroadcaster.new(Remotes.Get("ProjectileImpact")),
		telemetry = telemetry,
		net = net,
		world = WorldAdapter,
	})

	projectiles.OnImpact = function(result, entry)
		return match:HandleImpact(result, entry, os.clock())
	end

	local router = RemoteRouter.new(match)
	router:Bind()

	startPrompt.Triggered:Connect(function(player)
		match:RequestStart(player, os.clock())
	end)

	for _, player in Players:GetPlayers() do
		match:RegisterPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		match:RegisterPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		match:UnregisterPlayer(player, os.clock())
		router:ClearPlayer(player)
	end)

	local effects = match._effects
	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		enemies:Step(deltaTime, now)
		projectiles:Step(deltaTime)
		match:Step(deltaTime, now)
		effects:Step(now)
	end)

	return {
		match = match,
		rooms = rooms,
		enemies = enemies,
		projectiles = projectiles,
		router = router,
		telemetry = telemetry,
	}
end

function GameBootstrap._format(payload)
	local parts = {}
	for key, value in payload do
		table.insert(parts, tostring(key) .. "=" .. tostring(value))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, " ") .. "}"
end

return GameBootstrap
