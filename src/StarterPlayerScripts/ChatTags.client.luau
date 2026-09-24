-- Chat tags: every message is prefixed with the sender's level, and VIP pass holders get a gold
-- VIP tag. Reads the Level leaderstat and the VIP attribute the server sets; display only.
-- Works with TextChatService, the default chat for new experiences.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local LEVEL_COLOR = "#FFD678"
local VIP_COLOR = "#FFB02E"

local function levelOf(player)
	local stats = player:FindFirstChild("leaderstats")
	local level = stats and stats:FindFirstChild("Level")
	return level and level.Value or nil
end

TextChatService.OnIncomingMessage = function(message)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if not sender then
		return properties
	end
	local tags = {}
	if sender:GetAttribute("VIP") then
		table.insert(tags, string.format("<font color='%s'>[VIP]</font>", VIP_COLOR))
	end
	local level = levelOf(sender)
	if level then
		table.insert(tags, string.format("<font color='%s'>[Lv %d]</font>", LEVEL_COLOR, level))
	end
	if #tags > 0 then
		properties.PrefixText = table.concat(tags, " ") .. " " .. message.PrefixText
	end
	return properties
end
