-- RevivePurchaseHandler - ServerScriptService
-- Handles Robux revive purchases

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

-- Product IDs
local REVIVE_PRODUCT_ID = 3356734577

-- Process receipt callback
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == REVIVE_PRODUCT_ID then
		print("💰 Processing revive purchase for", player.Name)
		
		-- Grant the player a revive
		local currentRevives = player:GetAttribute("RevivesAvailable") or 0
		player:SetAttribute("RevivesAvailable", currentRevives + 1)
		player:SetAttribute("HasRevive", true)
		
		print("✅ Granted revive to", player.Name, "- Total revives:", currentRevives + 1)
		
		-- Purchase was successful
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Unknown product
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

print("💰 RevivePurchaseHandler loaded - Product ID:", REVIVE_PRODUCT_ID)