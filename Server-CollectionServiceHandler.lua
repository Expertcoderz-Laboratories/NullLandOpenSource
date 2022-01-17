--// Author: @Expertcoderz
--// Last updated: 2022-01-17

server, service = nil, nil

return function()
	local Variables = server.Variables

	Variables.WorldInstances = {}

	server.Functions.RegisterCollectionServiceInstance = function(package: {
		TagName: string?, SingleSetup: boolean?, Setup: (Instance, {}, {})->()?, Cleanup: (Instance, {}, {})->()?, Extra: ({}, {})->()?
		})
		if not package.TagName then return end
		Variables.WorldInstances[package.TagName] = {}
		if package.Setup then
			if not package.SingleSetup then
				service.CollectionService:GetInstanceAddedSignal(package.TagName):Connect(function(inst)
					task.defer(function()
						local pkg = select(2, xpcall(package.Setup, function(err) warn("Error setting up pkg", package.TagName, ":", err) return nil end, inst, service, server))
						if pkg then
							Variables.WorldInstances[package.TagName][inst] = pkg
						end
					end)
				end)
			end
			for _, inst in ipairs(service.CollectionService:GetTagged(package.TagName)) do
				task.defer(function()
					local pkg = select(2, xpcall(package.Setup, function(err) warn("Error setting up pkg", package.TagName, ":", err) return nil end, inst, service, server))
					if pkg then
						Variables.WorldInstances[package.TagName][inst] = pkg
					end
				end)
			end
		end
		if package.Cleanup then
			service.CollectionService:GetInstanceRemovedSignal(package.TagName):Connect(function(inst)
				local pkg = Variables.WorldInstances[package.TagName][inst]
				if pkg then
					xpcall(pkg.Cleanup, function(err) warn("Error cleaning up pkg", package.TagName, ":", err) end, pkg, service, server)
				end
			end)
		end
		if package.Extra then
			task.defer(package.Extra, service, server)
		end
	end

	for _, module in ipairs(script:GetChildren()) do
		if not module:IsA("ModuleScript") then continue end
		xpcall(server.Functions.RegisterCollectionServiceInstance, function(err) warn("Error loading package module", module.Name, ":", err) end, require(module))
	end

	server.Functions.GetCollectionServicePackageFromInstance = function(inst: Instance, tag: string)
		return Variables.WorldInstances[tag][inst] or nil
	end
end
