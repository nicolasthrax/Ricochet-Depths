-- The results screen's three-second look at home: the camera swings over the player's plot in
-- the Outpost (the PlotIndex the server set), so a haul is seen as the buildings it pays for.
-- It borrows the camera the way the descent cinematic does (the Cinematic attribute makes
-- CameraController stand aside) and always hands it back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage:WaitForChild("BaseConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))

local BasePreview = {}

BasePreview.Seconds = 3
-- Where the camera sits relative to the plot's centre: high and to the south, looking down.
local EYE_OFFSET = Vector3.new(0, 42, 58)

-- The camera frame over plot `index`, or nil for no plot.
function BasePreview.Frame(index)
	if type(index) ~= "number" or index < 1 or index > BaseConfig.Plots.Count then
		return nil
	end
	local centre = BaseConfig.PlotCentre(index, RunConfig.LobbyPosition)
	return CFrame.lookAt(centre + EYE_OFFSET, centre)
end

-- Shows the plot for Seconds, then hands the camera back. Returns false when there is nothing to
-- show (no plot, no camera, or a preview already playing).
function BasePreview.Play(player, camera, seconds)
	local frame = BasePreview.Frame(player:GetAttribute("PlotIndex"))
	if not frame or not camera or player:GetAttribute("Cinematic") then
		return false
	end
	player:SetAttribute("Cinematic", true)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = frame
	task.delay(seconds or BasePreview.Seconds, function()
		player:SetAttribute("Cinematic", nil)
		-- The tactical camera re-takes it next frame during a run; anywhere else the default
		-- camera is what the player had.
		camera.CameraType = Enum.CameraType.Custom
	end)
	return true
end

return BasePreview
