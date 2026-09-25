-- Chat tags: every message is prefixed with the sender's level, and pass holders get their pass's
-- tag (the Supporter Pack's [Supporter]). Reads the Level leaderstat and the ChatTag attribute
-- the server sets; display only.
-- Works with TextChatService, the default chat for new experiences.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local LEVEL_COLOR = "#FFD678"
local TAG_COLOR = "#FFB02E"

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
	local tag = sender:GetAttribute("ChatTag")
	if type(tag) == "string" and tag ~= "" then
		table.insert(tags, string.format("<font color='%s'>[%s]</font>", TAG_COLOR, tag))
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
