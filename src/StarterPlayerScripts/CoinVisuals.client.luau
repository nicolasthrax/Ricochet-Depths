-- Spins every visible coin pickup on this client. The server only places coins; this
-- makes them read as treasure. Purely local, so it never fights the server's position updates.
local RunService = game:GetService("RunService")

local SPIN_SPEED = 3 -- radians per second

RunService.RenderStepped:Connect(function()
	local arenas = workspace:FindFirstChild("Arenas")
	if not arenas then
		return
	end
	local now = os.clock()
	for _, slot in arenas:GetChildren() do
		local arena = slot:FindFirstChild("Arena")
		local pool = arena and arena:FindFirstChild("CoinPool")
		if pool then
			for index, coin in pool:GetChildren() do
				if coin:IsA("BasePart") and coin.Transparency < 1 then
					local position = coin.Position
					local spin = now * SPIN_SPEED + index
					-- A cylinder's axis is its X: standing it on edge and turning it about Y.
					coin.CFrame = CFrame.new(position) * CFrame.Angles(0, spin, math.pi / 2)
				end
			end
		end
	end
end)
