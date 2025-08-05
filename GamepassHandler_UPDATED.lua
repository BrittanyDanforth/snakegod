-- Copy the entire GamepassHandler but with the critical fix at the end
-- [Previous 550+ lines of code remain exactly the same]

-- Around line 555, this is the ONLY change needed:

-- FIXED: Direct communication listener - the master OFF switch
local playerRevivedEffectRemote = remotes:WaitForChild("PlayerRevivedEffect")

playerRevivedEffectRemote.OnClientEvent:Connect(function()
	print("✅ GamepassHandler received revive signal.")
	
	-- This function is intentionally empty.
	-- By doing nothing, no revive effect will be created.
	-- This is your master OFF switch.
end)

print("GamepassHandler loaded successfully with boost system!")