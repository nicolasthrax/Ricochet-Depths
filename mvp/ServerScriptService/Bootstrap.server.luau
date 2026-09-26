--!strict
-- The only server Script. Creates the remotes, then starts the services in dependency order:
-- UpgradeService (no dependencies) -> CombatService (reads shot stats) -> RunDirector (drives both).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Network)
local UpgradeService = require(script.Parent.Services.UpgradeService)
local CombatService = require(script.Parent.Services.CombatService)
local RunDirector = require(script.Parent.Services.RunDirector)

Network.mountServer()
UpgradeService.init()
CombatService.init()
RunDirector.init()
