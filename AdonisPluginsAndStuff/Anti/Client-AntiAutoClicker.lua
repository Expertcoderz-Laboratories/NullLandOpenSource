client, service = nil, nil

return function()

	local function findMean(tab: {number}): number
		local total = 0
		for _, val in pairs(tab) do
			total += val
		end
		return total / #tab
	end

	local function checkConsistency(tab: {number}, uncertainty: number?): boolean
		local consistent = 0
		for _, val in pairs(tab) do
			if math.abs(math.abs(val) - math.abs(findMean(tab))) < (uncertainty or 1) then
				consistent += 1
				if consistent >= #tab / 2 then
					return true
				end
			end
		end
		return false
	end
	
	local Mouse: Mouse = service.Players.LocalPlayer:GetMouse()

	local clickHistory = {}
	local isActive = true
	local function activateClickCheck()
		if not isActive then return end
		
		table.insert(clickHistory, os.clock()) 
		task.delay(2, function()
			clickHistory = {}
		end)
		
		if #clickHistory > 4 then
			if checkConsistency(clickHistory, 0.1) then
				isActive = false
				client.Anti.Detected("kick", "Autoclicking detected")
			end
		end
	end
	
	Mouse.Button1Down:Connect(activateClickCheck)
	Mouse.Button2Down:Connect(activateClickCheck)

end
