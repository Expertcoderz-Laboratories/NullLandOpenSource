--// ModuleScript placed under Server-CollectionServiceHandler
--// or manually registered with server.Functions.RegisterCollectionServiceInstance(Package)

local Package = {}
Package.__index = Package

Package.TagName = "Thing"
Package.SingleSetup = false --// If true, will only setup existing instances with the CollectionService tag on start

function Package.Setup(instance, service, server)
	local self = {Root = instance; service = service; server = server;}
	setmetatable(self, Package)
	
	--// Instance setup code here
end

function Package:Cleanup()
	--// Instance cleanup code here
end

function Package.Extra(service, server)
	--// Code that runs once at the start when this package is loaded
end

return Package
