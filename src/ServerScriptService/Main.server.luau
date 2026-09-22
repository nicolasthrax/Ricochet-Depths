-- Server entry point. All construction and wiring lives in GameBootstrap.
local GameBootstrap = require(script.Parent:WaitForChild("Modules").GameBootstrap)

local game_ = GameBootstrap.Start()

-- Developer handle for the Studio command bar; carries no authority of its own.
_G.RicochetDepths = game_
