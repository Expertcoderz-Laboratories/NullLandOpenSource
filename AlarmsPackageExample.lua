local TWEEN_INFO = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local DEFAULT_COLOR = BrickColor.new("Really red")

local Package = {}
Package.__index = Package

Package.TagName = "Alarm"

function Package.Setup(alarm, service, server)
	local self = {Root = alarm; service = service; server = server;}
	setmetatable(self, Package)

	self.Spinner = alarm:WaitForChild("Spinner", 2)
	self.Sound = service.New("Sound", {
		Parent = self.Spinner:WaitForChild("Middle");
		SoundId = "rbxassetid://1974216350";
		Volume = 1;
		Looped = true;
	})

	self.enabled = false

	return self
end

function Package:setEnabled(enabled: boolean, color: BrickColor?)
	self.enabled = if enabled == nil then not self.enabled elseif enabled then true else false

	for _, v in pairs(self.Spinner:GetChildren()) do
		if v.Name == "Bulb" and v:IsA("Part") then
			v.BrickColor = if self.enabled then color or DEFAULT_COLOR else BrickColor.new("Dark stone grey")
			v.Material = if self.enabled then Enum.Material.Neon else Enum.Material.SmoothPlastic
			for _, c in pairs(v:GetChildren()) do
				if c:IsA("SpotLight") then c:Destroy() end
			end
			if self.enabled then
				self.service.New("SpotLight", {
					Parent = v;
					Angle = 90;
					Brightness = 5;
					Color = if color then color.Color else DEFAULT_COLOR.Color;
					Face = Enum.NormalId.Top;
					Range = 50;
					Shadows = true;
				})
			end
		end
	end

	if self.enabled then
		self.Sound.Looped = true
		self.Sound:Play()
		while self.service.RunService.Stepped:Wait() do
			if not self.enabled or not self.Root then break end
			local C = self.Spinner:GetModelCFrame()
			local parts = {}
			local function scan(parent)
				for _, OBJ in pairs(parent:GetChildren()) do
					if OBJ:IsA("BasePart") then
						table.insert(parts, OBJ)
					end	
					scan(OBJ)
				end
			end
			scan(self.Spinner)
			for _, part in pairs(parts) do
				part.CFrame = (C * CFrame.Angles(math.rad(5), math.rad(0), 0) * (C:inverse() * part.CFrame))
			end
		end
	else
		self.Sound.Looped = false
	end
end

function Package.Extra(service, server)
	server.Commands.SetAlarms = {
		Prefix = server.Settings.Prefix;
		Commands = {"alarms", "setalarms", "alarmsenabled", "setalarmsenabled"};
		Args = {"on/off/toggle", "BrickColor (default: Really red)"};
		Description = "Set or toggle the alarm beacons";
		AdminLevel = 100;
		Function = function(plr: Player, args: {string})
			local enabled = if args[1] and args[1]:lower() == "on" then true elseif args[1] and args[1]:lower() == "off" then false else nil
			assert(not args[2] or BrickColor.new(args[2]).Name ~= "Medium stone grey" or args[2] == "Medium stone grey", "Invalid BrickColor supplied")
			for alrm, pkg in pairs(server.Variables.WorldInstances[Package.TagName]) do
				pkg:setEnabled(enabled, args[2] and BrickColor.new(args[2]))
			end
		end
	}
end

return Package
