--!nocheck
--[[
	Description: The serverside component of the Adonis Gun System.
	Author: Expertcoderz
	Release Date: 2022-02-11 (project started in December 2021; originated from Aug/Sep 2021)

	THIS REQUIRES THE CollectionServiceHandler PLUGIN TO FUNCTION.
--]]

server, service = nil, nil

return function()
	local function Debug(...)
		warn("[GunServer]", ...)
	end

	local ReplicatedGunConfigs = service.New("Folder", {
		Parent = service.ReplicatedStorage;
		Name = "__GUN_CONFIGURATION_STORE";
	})

	local configCaches: {[string]:{[string]:any}} = {}
	local specialEffects: {[string]:()->()} = {}

	xpcall(function()
		server.Functions.RegisterGunSpecialEffect = function(effectName: string, effectFunc: ()->())
			specialEffects[effectName] = effectFunc
		end
		for _, module: ModuleScript in ipairs(script.SpecialEffects:GetChildren()) do
			server.Functions.RegisterGunSpecialEffect(module.Name, require(module))
		end

		for _, tool in pairs(script.GunTools:GetChildren()) do
			if not service.CollectionService:HasTag(tool, "ADONIS_GUN") then
				service.CollectionService:AddTag(tool, "ADONIS_GUN")
			end
			tool.Parent = service.UnWrap(server.Settings.Storage)
		end

		--// Loads up a copy of the specified weapon's config module for use (including client access)
		local function LoadConfig(toolName: string, chain: {string}?): ModuleScript?
			chain = chain or {}
			if table.find(chain, toolName) then
				Debug("WARNING:", toolName, "is a config dependency of itself; chain:", table.concat(chain, " > "), ">", toolName)
				return nil
			end
			table.insert(chain, toolName)
			local targetModule = ReplicatedGunConfigs:FindFirstChild(toolName)
			if not targetModule then
				local new = script.GunSettings:FindFirstChild(toolName)
				if new then
					targetModule = new:Clone()
					targetModule.Parent = ReplicatedGunConfigs
				else
					Debug("Unable to add configuration module for", toolName, "(not found)")
					return nil
				end
			end
			local config = require(targetModule)
			if config._ConfigTemplate then
				LoadConfig(config._ConfigTemplate, chain)
			end
			return targetModule
		end

		--// Resolves config templates (dependencies) & generates a complete config dictionary for the specified weapon
		local function GetFullConfig(toolName: string, chain: {string}?): {[string]:any}
			chain = chain or {}
			if table.find(chain, toolName) then
				return {}
			end
			table.insert(chain, toolName)
			local module = script.GunSettings:FindFirstChild(toolName)
			if not module then
				Debug("Config not found for", toolName)
				return {}
			end
			local config = require(module)
			if not config._AmmoBillboard and module:FindFirstChild("AmmoBillboard") then
				config._AmmoBillboard = module.AmmoBillboard
			end
			if module.Name == "_Base" then
				return config
			end
			if not config._ConfigTemplate then
				config._ConfigTemplate = "_Base"
			end
			for setting, defaultValue in pairs(GetFullConfig(config._ConfigTemplate, chain)) do
				if config[setting] == nil then
					config[setting] = defaultValue
				end
			end
			return config
		end

		LoadConfig("_Base")

		local function tagTemp(obj: Instance): Instance
			service.CollectionService:AddTag(obj, "ADONIS_GUN_COMPONENT")
			return obj
		end

		local function recurseWeld(parent, parts, last)
			parts = parts or {}
			for _, v in pairs(parent:GetChildren()) do
				if v:IsA("BasePart") then
					if last then
						tagTemp(service.New("Weld", {
							Parent = last;
							Name = v.Name.."_Weld";
							Part0 = last;
							Part1 = v;
							C0 = last.CFrame:inverse();
							C1 = v.CFrame:inverse();
						}))
					end
					last = v
					table.insert(parts, v)
				end
				recurseWeld(v, parts, last)
			end
			for _, v in pairs(parts) do
				v.Anchored = false
			end
		end

		local Gun = {TagName = "ADONIS_GUN"}
		Gun.__index = Gun
		function Gun.Setup(tool: Tool)
			local self = {Root = tool;}
			setmetatable(self, Gun)

			if tool.Parent and not tool.Parent:IsA("Backpack") and not service.Players:GetPlayerFromCharacter(tool.Parent) then
				return nil
			end

			return select(2, xpcall(function()
				self:Cleanup()
				recurseWeld(tool)

				self.connections = {} :: {RBXScriptConnection}

				self.handles = {}
				for _, v in ipairs(tool:GetChildren()) do
					if v.Name:sub(1, 6) == "Handle" then
						table.insert(self.handles, v)
					end
				end

				self.ConfigModule = LoadConfig(tool.Name) :: ModuleScript
				self.config = configCaches[tool.Name] :: {[string]:any}
				if not self.config then
					configCaches[tool.Name] = GetFullConfig(tool.Name)
					self.config = configCaches[tool.Name]
				end

				self.CurrentHumanoid = nil :: Humanoid?
				local function updateCurrentHumanoid()
					local hum = tool.Parent and tool.Parent:FindFirstChildOfClass("Humanoid")
					self.CurrentHumanoid = if hum then hum else nil
				end
				table.insert(self.connections, tool:GetPropertyChangedSignal("Parent"):Connect(updateCurrentHumanoid))
				updateCurrentHumanoid()

				for i, handle in pairs(self.handles) do
					self["fireSounds"..i] = {}
					for _, sound in pairs(self.ConfigModule:WaitForChild("Sounds", 2):GetChildren()) do
						sound = tagTemp(sound:Clone())
						sound.Parent = handle
						if sound.Name == "Fire" then
							table.insert(self["fireSounds"..i], sound)
						end
					end
				end

				--// Table of toggleable neon parts & Lights for flashlight functionality
				self.flashlightObjs = {} :: {BasePart|Light}
				for _, v in pairs(tool:GetDescendants()) do
					if v.Name == "Flashlight" or v:GetAttribute("Flashlight") then
						table.insert(self.flashlightObjs, v)
					end
				end
				if #self.flashlightObjs > 0 then
					tool:SetAttribute("FlashlightEnabled", true) --// for informing the client that flashlight functionality exists
				end

				--// Dictionary of color-customizable component parts of the gun, with their respective original/default colors
				self.camoPartOriginals = {} :: {[BasePart]:BrickColor}
				for _, v in pairs(tool:GetDescendants()) do
					if v:GetAttribute("Camo") or (v.Name == "Camo" and v:IsA("BasePart")) then
						local originalBrickColor = v:GetAttribute("OriginalCamoBrickColor")
						if not originalBrickColor then
							originalBrickColor = v.BrickColor
							v:SetAttribute("OriginalCamoBrickColor", originalBrickColor)
						end
						self.camoPartOriginals[v] = originalBrickColor
					end
				end
				if tool:GetAttribute("CurrentCamoBrickColor") then
					self:setCamo(tool:GetAttribute("CurrentCamoBrickColor"))
				end

				--// Create gun animation objects
				for _, v in ipairs({"Idle", "Fire", "Reload", "ShotgunClipin", "HoldDown", "Equip", "Aiming"}) do
					if self.config[v.."AnimationId"] ~= 0 then
						tagTemp(service.New("Animation", {
							Parent = tool;
							Name = v.."Anim";
							AnimationId = "rbxassetid://"..self.config[v.."AnimationId"];
						}))
					end
				end

				if not tool:GetAttribute("CurrentMag") then
					tool:SetAttribute("CurrentMag", self.config.AmmoPerMag)
					tool:SetAttribute("CurrentAmmo", self.config.LimitedAmmo and self.config.Ammo or 0)
				end

				self.AmmoGui = self.handles[1]:FindFirstChild("AmmoBillboard") or self.config._AmmoBillboard:Clone()
				self.AmmoGui.Parent = self.handles[1]
				self.AmmoGui.Enabled = self.config.ShowAmmoBillboard
				self.AmmoGuiLabel = self.AmmoGui:FindFirstChild("AmmoLabel", true)
				local function updateAmmoGui()
					self.AmmoGuiLabel.Text = string.format("Ammo: %s/%s", server.Functions.FormatNumber(tool:GetAttribute("CurrentMag")), if self.config.LimitedAmmo then server.Functions.FormatNumber(tool:GetAttribute("CurrentAmmo")) else "Inf")
					if self.AmmoGuiLabel.Text == "Ammo: Inf/Inf" then
						self.AmmoGuiLabel.Text = "Ammo: Inf"
					end
				end
				updateAmmoGui()

				table.insert(self.connections, tool.Equipped:Connect(function()
					local speedReduction = self.config.WalkspeedReduction
					task.wait(0.1)
					if speedReduction ~= 0 and self.CurrentHumanoid then
						self.CurrentHumanoid:SetAttribute("_OriginalWalkspeed", self.CurrentHumanoid.WalkSpeed)
						self.CurrentHumanoid.WalkSpeed -= self.config.WalkspeedReduction
					end
				end))

				table.insert(self.connections, tool.Unequipped:Connect(function()
					if self.config.WalkspeedReduction ~= 0 and self.CurrentHumanoid then
						self.CurrentHumanoid.WalkSpeed = self.CurrentHumanoid:GetAttribute("_OriginalWalkspeed") or 16
					end
				end))

				self.RemotesFolder = tagTemp(service.New("Folder", {Name = "Remotes";})) :: Folder
				for name, callback in pairs({
					Flashlight = function(plr: Player)
						for _, v in pairs(self.flashlightObjs) do
							if v:IsA("Light") then
								v.Enabled = not v.Enabled
							elseif v:IsA("BasePart") then
								v.Material = if v.Material == Enum.Material.Neon then Enum.Material.SmoothPlastic else Enum.Material.Neon
							end
						end
						local sound = self.handles[1]:FindFirstChild("Flashlight")
						if sound and sound:IsA("Sound") then
							sound:Play()
						end
					end,
					VisualizeBulletSet = function(plr: Player, fireDirs: {Vector3}, handle: BasePart)
						if not type(fireDirs) == "table" and typeof(handle) == "Instance" then
							server.Anti.Detected(plr, "kill", "[Gun System] Invalid remote data for VisualizeBulletSet")
							return
						end
						if #fireDirs ~= self.config.BulletPerShot and #fireDirs ~= 1 then
							server.Anti.Detected(plr, "kick", "[Gun System] Attempt to fire bullet set of incorrect size")
							return
						end
						for i, handle in pairs(self.handles) do
							if handle == handle then
								self["fireSounds"..i][math.random(1, #self["fireSounds"..i])]:Play()
								break
							end
						end
						self.RemotesFolder.VisualizeBulletSet:FireAllClients(plr, fireDirs, handle)
						server.Functions.AddToGlobalStat("Shots Fired", #fireDirs)
					end,
					VisualizeMuzzle = function(plr: Player, ...)
						self.RemotesFolder.VisualizeMuzzle:FireAllClients(plr, ...)
					end,
					InflictTarget = function(plr: Player, targetHitPart: BasePart)
						local targetHum = (targetHitPart and targetHitPart.Parent) and targetHitPart.Parent:FindFirstChildOfClass("Humanoid")
						local targetPlr = targetHum and service.Players:GetPlayerFromCharacter(targetHitPart.Parent)
						if targetHum and targetHum.Health ~= 0 and (not targetPlr or not workspace:GetAttribute("_TeamkillDisabled") or not targetPlr.Team or plr.Team ~= targetPlr.Team) then
							server.Functions.ApplyDeathTag(targetHum, plr)
							local damageAmount = self.config.BaseDamage * if targetHitPart.Name == "Head" then self.config.HeadshotDamageMultiplier else 1
							targetHum:TakeDamage(damageAmount)
							if self.config.Knockback > 0 and plr ~= targetPlr then
								local shover = plr.Character.PrimaryPart or plr.Character.Head
								local duration = 0.1
								local shoveForce = service.New("BodyVelocity", {
									MaxForce = Vector3.new(1e9, 1e9, 1e9);
									Velocity = (targetHitPart.Position - shover.Position).unit * (self.config.Knockback / duration);
								})
								shoveForce.Parent = targetHitPart
								service.Debris:AddItem(shoveForce, duration)
							end
							for _, effect in ipairs(self.config.SpecialEffects) do
								local context = {server = server, service = service, Attacker = plr, AttackerChar = plr.Character, Damage = damageAmount, Weapon = tool}
								table.foreach(effect, function(key, val)
									context[key] = val
								end)
								xpcall(if type(effect) == "table" then specialEffects[effect.Effect] else effect, function(err)
									Debug("SpecialEffect application error:", err)
								end, context, targetHum.Parent)
							end
						end
					end,
					ChangeMagAndAmmo = function(plr: Player, mag: number, ammo: number, reloading: boolean?)
						if not tonumber(mag) or not tonumber(ammo) or ammo > tool:GetAttribute("CurrentAmmo") or mag > self.config.AmmoPerMag then
							server.Anti.Detected(plr, "kick", "[Gun System] Attempt to set mag/ammo to an illegal value")
							return
						end
						tool:SetAttribute("CurrentMag", mag)
						tool:SetAttribute("CurrentAmmo", ammo)
						updateAmmoGui()
						if self.config.RocketLauncher then
							for _, v in pairs(tool.Rocket:GetChildren()) do
								if v:IsA("BasePart") then
									v.Transparency = if reloading then 0 else 1
								end
							end
						end
					end,
					})
				do
					local event: RemoteEvent = service.New("RemoteEvent", {
						Parent = self.RemotesFolder;
						Name = name;
					}, nil, true)
					table.insert(self.connections, event.OnServerEvent:Connect(function(plr: Player, ...)
						if plr == service.Players:GetPlayerFromCharacter(tool.Parent) or plr == tool.Parent.Parent then
							callback(plr, ...)
						else
							server.Anti.Detected(plr, "kick", "[Gun System] Fired remote for someone else's gun")
						end
					end))
				end
				self.RemotesFolder.Parent = tool

				for _, v in pairs(service.Players:GetPlayers()) do
					server.Remote.Send(v, "RegisterGun", tool)
				end
				table.insert(self.connections, service.Players.PlayerAdded:Connect(function(plr)
					server.Remote.Send(plr, "RegisterGun", tool)
				end))

				return self
			end, function(err)
				Debug(string.format("Error registering gun %s;", tool:GetFullName()), err)
			end))
		end

		function Gun:Cleanup()
			for _, conn in pairs(self.connections or {}) do
				conn:Disconnect()
			end
			if self.Root then
				for _, v in pairs(self.Root:GetDescendants()) do
					if service.CollectionService:HasTag(v, "ADONIS_GUN_COMPONENT") then
						v:Destroy()
					end
				end
			end
			if self.config and self.config.WalkspeedReduction ~= 0 and self.CurrentHumanoid then
				self.CurrentHumanoid.WalkSpeed = self.CurrentHumanoid:GetAttribute("_OriginalWalkspeed") or 16
			end
		end

		--// Adonis Gun pkg object methods
		function Gun:setAmmo(amount: number)
			self.Root:SetAttribute("CurrentAmmo", amount)
			self.RemotesFolder.ChangeMagAndAmmo:FireClient(service.Players:GetPlayerFromCharacter(self.Root.Parent) or self.Root.Parent.Parent)
		end
		function Gun:refillAmmo()
			self:setAmmo(self.config.MaxAmmo)
		end
		function Gun:setCamo(brickColor: BrickColor)
			self.Root:SetAttribute("CurrentCamoBrickColor", brickColor)
			for part in pairs(self.camoPartOriginals) do
				part.BrickColor = brickColor
			end
		end
		function Gun:resetCamo()
			self.Root:SetAttribute("CurrentCamoBrickColor", nil)
			for part, originalBrickColor in pairs(self.camoPartOriginals) do
				part.BrickColor = originalBrickColor
			end
		end

		while not server.Functions.RegisterCollectionServiceInstance do task.wait() end
		server.Functions.RegisterCollectionServiceInstance(Gun)

		server.Commands.RefillAmmo = {
			Prefix = server.Settings.Prefix;
			Commands = {"refillammo", "getammo", "ammorefill", "refill"};
			Args = {"player"};
			Description = "Refills the ammo of the target player's equipped gun, if any";
			AdminLevel = "Moderators";
			Function = function(plr: Player, args: {string})
				for _, v: Player in pairs(service.GetPlayers(plr, args[1])) do
					local gun = v.Character and v.Character:FindFirstChildOfClass("Tool")
					local pkg = gun and server.Functions.GetCollectionServicePackageFromInstance(gun, "ADONIS_GUN")
					if pkg then
						pkg:refillAmmo()
					end
				end
			end
		}

		server.Commands.ColorWeapon = {
			Prefix = server.Settings.PlayerPrefix;
			Commands = {"gunskin", "camo", "guncamo", "colorgun"};
			Args = {"BrickColor"};
			Description = "Change the color of your weapon camo (leave BrickColor arg blank to reset)";
			AdminLevel = "Players";
			Function = function(plr: Player, args: {string})
				local gun = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
				assert(gun, "Gun not equipped/character missing")
				assert(not args[1] or args[1] == "Medium stone grey" or BrickColor.new(args[1]).Name ~= "Medium stone grey", "Invalid BrickColor supplied (refer to !colors for a list).")
				local pkg = gun and server.Functions.GetCollectionServicePackageFromInstance(gun, "ADONIS_GUN")
				if pkg then
					if args[1] then
						pkg:setCamo(BrickColor.new(args[1]))
					else
						pkg:resetCamo()
					end
				else
					error("A valid gun must be equipped")
				end
			end
		}

		server.Commands.TeamkillEnabled = {
			Prefix = server.Settings.Prefix;
			Commands = {"teamkill", "tk", "teamkillenabled", "setteamkill", "teamkilling"};
			Args = {"on/off/toggle"};
			Description = "Set whether players can harm others on their team with weapons";
			AdminLevel = "Moderators";
			Function = function(plr: Player, args: {string})
				workspace:SetAttribute("_TeamkillDisabled", if args[1] and args[1]:lower() == "on" then false
					elseif args[1] and args[1]:lower() == "off" then true
					else not workspace:GetAttribute("_TeamkillDisabled"))
				server.Functions.Hint(string.format("Teamkill is now %s.", workspace:GetAttribute("_TeamkillDisabled") and "disabled" or "enabled"), service.Players:GetPlayers())
			end
		}

		server.Commands.WeaponStats = {
			Prefix = server.Settings.PlayerPrefix;
			Commands = {"gunstats", "weaponstats", "guninfo", "weaponinfo"};
			Args = {};
			Description = "Shows you detailed information about your currently-equipped gun";
			AdminLevel = "Players";
			Function = function(plr: Player, args: {string})
				local gun = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
				assert(gun, "Gun not equipped/character missing")
				local pkg = gun and server.Functions.GetCollectionServicePackageFromInstance(gun, "ADONIS_GUN")
				if pkg then
					local tab = {}
					for setting: string, value: any in pairs(pkg.config) do
						if type(setting) ~= "string" or setting:sub(1, 1) == "_" then continue end
						table.insert(tab, setting..": "..if type(value) == "table" then service.HttpService:JSONEncode(value) else tostring(value))
					end
					table.sort(tab)
					server.Remote.MakeGui(plr, "List", {
						Title = gun.Name.." Stats";
						Icon = server.MatIcons.Leaderboard;
						Tab = tab;
						Size = {290, 350};
					})
				else
					error("A valid gun must be equipped")
				end
			end
		}

		Debug("Installation complete")
		if _G._ESIAS then _G._RaiseFlag("GunSystem") end
	end, function(err)
		Debug("Installation error:", err)
	end)
end

--// Expertcoderz Laboratories 2022
