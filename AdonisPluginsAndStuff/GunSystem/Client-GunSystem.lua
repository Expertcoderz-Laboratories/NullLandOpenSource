--!nocheck
--[[
	Description: The clientside component of the Adonis Gun System; handles most of the visuals & controls.
	Author: Expertcoderz
	Release Date: 2022-02-11 (project started in December 2021; originated from Aug/Sep 2021)
	Last Updated: 2022-03-10
--]]

client, service = nil, nil

local FIRST_PERSON_ARMS_VISIBLE = true

local AMMO_BAR_EASING_STYLE, AMMO_BAR_TWEEN_DURATION = Enum.EasingStyle.Sine, 0.5
local MAG_BAR_EASING_STYLE, MAG_BAR_TWEEN_DURATION = Enum.EasingStyle.Sine, 0.5
local RELOADING_TEXT = "Reloading..."

local DAMAGE_BILLBOARD_ENABLED = true
local DAMAGE_BILLBOARD_DURATION = 1
local DAMAGE_BILLBOARD_FONT = Enum.Font.ArialBold
local DAMAGE_BILLBOARD_TEXT_STROKE_TRANSPARENCY = 0.7
local DAMAGE_BILLBOARD_HARM_COLOR = Color3.fromRGB(255, 35, 35)
local DAMAGE_BILLBOARD_HEAL_COLOR = Color3.fromRGB(85, 255, 100)

return function()
	local startTime = os.clock()
	local function Debug(...)
		warn("[GunClient]", ...)
	end

	xpcall(function()
		local UserInputService: UserInputService = service.UserInputService
		local TweenService: TweenService = service.TweenService
		local RunService: RunService = service.RunService
		local Debris: Debris = service.Debris
		local Players: Players = service.Players

		local LocalPlayer: Player = Players.LocalPlayer
		local LocalCharacter: Model?, LocalHumanoid: Humanoid? = nil, nil
		do
			local function update()
				LocalCharacter = LocalPlayer.Character
				if LocalCharacter then
					LocalCharacter.ChildAdded:Connect(function(child)
						if child:IsA("Humanoid") and not LocalHumanoid then
							LocalHumanoid = child
						end
					end)
					LocalPlayer.ChildRemoved:Connect(function()
						LocalHumanoid = LocalCharacter:FindFirstChildOfClass("Humanoid")
					end)
					LocalHumanoid = LocalCharacter:FindFirstChildOfClass("Humanoid")
				end
			end
			LocalPlayer.CharacterAdded:Connect(update)
			LocalPlayer.CharacterRemoving:Connect(update)
			update()
		end

		local Mouse = LocalPlayer:GetMouse()
		local Camera = workspace.CurrentCamera
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			Camera = workspace.CurrentCamera
		end)

		local _ammoGuiHidden, _ammoGuiPos = nil, nil

		local ReplicatedGunConfigs = service.ReplicatedStorage:WaitForChild("__GUN_CONFIGURATION_STORE")
		local configCaches: {[string]:{[string]:any}} = {}

		local create: (className: string, propertiesOrParent: {[string]:any}|Instance)->(Instance)
			= service.New
		local function edit(object: Instance, properties: {[string]:any}): Instance
			for prop, val in pairs(properties) do
				object[prop] = val
			end
			return object
		end

		local function numLerp(a, b, alpha)
			return a + (b - a) * alpha
		end
		local function rand(min: number, max: number, accuracy: number?): number
			local inverse = 1 / (accuracy or 1)
			return math.random(min * inverse, max * inverse) / inverse
		end
		local function getAssetUri(assetId: string|number): string
			return if type(assetId) == "number" then "rbxassetid://"..assetId else assetId
		end
		local function chooseRandAssetId(list: {string|number}): string?
			return getAssetUri(list[math.random(1, #list)])
		end
		local function getDistanceFromCharacter(point: Vector3): number
			if not LocalCharacter or not LocalCharacter.PrimaryPart then
				return 0
			end
			return (point - LocalCharacter.PrimaryPart.Position).Magnitude
		end

		if FIRST_PERSON_ARMS_VISIBLE then
			service.RunService.RenderStepped:Connect(function()
				if not LocalCharacter then return end
				for _, v in pairs(LocalCharacter:GetChildren()) do
					if string.match(v.Name, "Arm") and not string.match(v.Name, "Ragdoll") then
						v.LocalTransparencyModifier = 0
					end
				end
			end)
		end

		local damageBillboardTemplate: BillboardGui? = nil
		if DAMAGE_BILLBOARD_ENABLED then
			damageBillboardTemplate = create("BillboardGui", {
				Name = "DAMAGE_BILLBOARD";
				AlwaysOnTop = true;
				Size = UDim2.new(0, 200, 0, 50);
			})
			create("TextLabel", {
				Parent = damageBillboardTemplate;
				Name = "Amount";
				BackgroundTransparency = 1;
				Size = UDim2.fromScale(1, 1);
				Font = DAMAGE_BILLBOARD_FONT;
				Text = "";
				TextStrokeColor3 = Color3.new(0, 0, 0);
				TextStrokeTransparency = DAMAGE_BILLBOARD_TEXT_STROKE_TRANSPARENCY;
			})
		end

		local function getFullConfig(toolName: string): {[string]:any}
			local module: ModuleScript = ReplicatedGunConfigs:FindFirstChild(toolName)
			if not module then
				Debug("Config not found for", toolName)
				return {}
			end
			local config = require(module)
			for _, e in pairs({"Blood", "Explosion", "Hit", "Muzzle", "Particle", "Tracer"}) do
				e ..= "Effect"
				if not config["Folder_"..e] and module:FindFirstChild(e) then
					config["Folder_"..e] = module[e]
				end
			end
			if config._Modifier then
				task.defer(config._Modifier, config, service, client)
			end
			if module.Name == "_Base" then
				return config
			end
			if not config._ConfigTemplate then
				config._ConfigTemplate = "_Base"
			end
			for setting, defaultValue in pairs(getFullConfig(config._ConfigTemplate)) do
				if config[setting] == nil then
					config[setting] = defaultValue
				end
			end
			return config
		end

		client.Remote.Commands.RegisterGun = function(args)
			local Tool: Tool = args[1]
			local config = configCaches[Tool.Name]

			if not config then
				configCaches[Tool.Name] = getFullConfig(Tool.Name)
				config = configCaches[Tool.Name]
			end

			local Remotes = Tool:WaitForChild("Remotes")
			local MarkerEvent = create("BindableEvent", {Parent = Tool; Name = "MarkerEvent";})

			local caster = require(script.FastCast).new()

			local connections = {}
			local ownerConnections = {}

			local Owner, isOwnedByLocalPlayer = nil, nil

			local function connectEvent(event: RBXScriptSignal, callback: (any)->()): RBXScriptConnection?
				if not event or not callback then return end
				local conn = event:Connect(callback)
				local e:ClientGun = nil
				if conn then
					connections[conn] = true
				end
				return conn
			end
			local function connectOwnerEvent(...)
				local connection = connectEvent(...)
				ownerConnections[connection] = true
				return connection
			end

			local function inflictTarget(hitPart: BasePart)
				local damage = config.BaseDamage * if hitPart.Name == "Head" then config.HeadshotDamageMultiplier else 1
				local hitPlr = Players:GetPlayerFromCharacter(hitPart.Parent)

				if damageBillboardTemplate and damage ~= 0 and not config.NoDamageBillboards and (not hitPlr or Owner == hitPlr or not workspace:GetAttribute("TeamkillDisabled") or not hitPlr.Team or Owner.Team ~= hitPlr.Team) then
					task.spawn(function()
						local gui = damageBillboardTemplate:Clone()
						gui.Amount.Text = if damage > 0 then "-"..damage else "+"..damage
						gui.Amount.TextColor3 = if damage > 0 then DAMAGE_BILLBOARD_HARM_COLOR else DAMAGE_BILLBOARD_HEAL_COLOR
						gui.Amount.TextSize = math.random(16, 20)

						gui.Parent = Camera
						gui.Adornee = hitPart

						Debris:AddItem(gui, DAMAGE_BILLBOARD_DURATION)

						TweenService:Create(gui, TweenInfo.new(DAMAGE_BILLBOARD_DURATION, Enum.EasingStyle.Sine), {StudsOffset = Vector3.new(math.random(1, 6), math.random(5, 8), math.random(1, 6))}):Play()
						TweenService:Create(gui.Amount, TweenInfo.new(DAMAGE_BILLBOARD_DURATION, Enum.EasingStyle.Sine), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
					end)
				end

				if isOwnedByLocalPlayer then
					Remotes.InflictTarget:FireServer(hitPart)
					MarkerEvent:Fire(hitPart.Name == "Head" and config.HeadshotDamageMultiplier > 1)
				end
			end

			local function visualizeMuzzle(firingHandle: BasePart)
				if config.MuzzleFlashEnabled then
					task.spawn(function()
						for _, v in pairs(firingHandle.GunMuzzle:GetChildren()) do
							if v:GetAttribute("_IsMuzzleEffect") then
								v:Emit(v:GetAttribute("EmitCount") or 1)
							end
						end
					end)
				end

				if config.MuzzleLightEnabled then
					Debris:AddItem(create("PointLight", {
						Parent = firingHandle.GunMuzzle;
						Brightness = config.MuzzleLightBrightness;
						Color = config.MuzzleLightColor;
						Enabled = true;
						Range = config.MuzzleLightRange;
						Shadows = config.MuzzleLightShadows;
					}), config.MuzzleLightLifetime)
				end
			end

			local function visualizeBulletSet(plr: Player, setData: {Vector3}, firingHandle: BasePart)
				for _, fireDirection in pairs(setData) do
					local firePointObject: Attachment = firingHandle.GunMuzzle

					local bullet: Part = create("Part", {
						Name = "Bullet";
						Material = config.BulletMaterial;
						Color = config.BulletColor;
						CanCollide = false;
						Anchored = true;
						Size = config.BulletSize;
						Transparency = config.BulletTransparency;
						Shape = config.BulletShape;
					})
					if config.BulletMeshEnabled then
						create("SpecialMesh", {
							Parent = bullet;
							Scale = config.BulletMeshScale;
							MeshId = getAssetUri(config.BulletMeshId);
							TextureId = getAssetUri(config.BulletTextureId);
							MeshType = Enum.MeshType.FileMesh
						})
					end

					edit(bullet, {
						Parent = Camera;
						CFrame = CFrame.new(firePointObject.WorldPosition, firePointObject.WorldPosition + fireDirection);
					})

					if config.WhizSoundEnabled and (#setData == 1 or math.random(0, 1) == 1) then
						create("Sound", {
							Parent = bullet;
							Name = "WhizSound";
							Looped = true;
							RollOffMaxDistance = 50;
							RollOffMinDistance = 10;
							SoundId = chooseRandAssetId(config.WhizSoundIds);
							Volume = config.WhizSoundVolume;
							PlaybackSpeed = config.WhizSoundPitch;
						}):Play()
					end

					if config.BulletLightEnabled then
						create("PointLight", {
							Parent = bullet;
							Name = "BulletLight";
							Brightness = config.BulletLightBrightness;
							Color = config.BulletLightColor;
							Enabled = true;
							Range = config.BulletLightRange;
							Shadows = config.BulletLightShadows;
						})
					end

					if config.BulletTracerEnabled then
						for _, v in pairs(config.Folder_TracerEffect:GetChildren()) do
							if v:IsA("Trail") then
								edit(v:Clone(), {
									Parent = bullet;
									Attachment0 = create("Attachment", {
										Parent = bullet;
										Name = "Attachment0";
										Position = config.BulletTracerOffset0;
									});
									Attachment1 = create("Attachment", {
										Parent = bullet;
										Name = "Attachment1";
										Position = config.BulletTracerOffset1;
									});
								})
							end
						end
					end

					if config.BulletParticleEnabled then
						for _, v in pairs(config.Folder_ParticleEffect:GetChildren()) do
							if v:IsA("ParticleEmitter") then
								edit(v:Clone(), {
									Parent = bullet;
									Enabled = true;
								})
							end
						end
					end	

					caster:FireWithBlacklist(firePointObject.WorldPosition, fireDirection * config.Range, config.BulletSpeed, {service.UnWrap(firingHandle), service.UnWrap(Tool.Parent), service.UnWrap(Camera)}, service.UnWrap(bullet))
				end
			end
			
			caster.Gravity = config.DropGravity
			caster.ExtraForce = config.WindOffset

			caster.LengthChanged:Connect(function(_, segmentOrigin, segmentDirection, length, bullet)
				bullet.CFrame = CFrame.new(segmentOrigin, segmentOrigin + segmentDirection) * CFrame.new(0, 0, -(length - bullet.Size.Z / 2))
			end)

			caster.RayHit:Connect(function(hitPart: BasePart, HitPoint: Vector3, Normal: Vector3, Material: Enum.Material, bullet: BasePart)
				Debris:AddItem(bullet, 4)
				edit(bullet, {
					Transparency = 1;
					BrickColor = BrickColor.new("Really red");
					CFrame = bullet.CFrame; --// Makes the bullet stop traveling
				})

				for _, v in pairs(bullet:GetChildren()) do
					if v:IsA("ParticleEmitter") then
						v.Enabled = false
					elseif v:IsA("Sound") or v:IsA("PointLight") then
						v:Destroy()
					end
				end

				local targetHum = hitPart and (hitPart.Parent:FindFirstChildOfClass("Humanoid") or hitPart.Parent.Parent:FindFirstChildOfClass("Humanoid"))
				local targetChar = targetHum and targetHum.Parent
				local hitCore = targetChar and (if hitPart.Name == "Head" and hitPart.Parent == targetChar then hitPart else targetChar:FindFirstChild("HumanoidRootPart"))

				local surfaceCF = CFrame.new(HitPoint, HitPoint + (Normal or Vector3.new(0, 0, 0)))

				if not config.ExplosiveEnabled and hitPart and (hitPart.Transparency < 0.9 or hitPart.Name == "HumanoidRootPart") then
					if hitCore and targetHum.Health > 0 then
						--// Hit something alive
						task.spawn(function()
							if config.BloodEnabled and getDistanceFromCharacter(HitPoint) <= config.BloodEffectMaxVisibleDistance then
								local attachment = create("Attachment", {
									CFrame = surfaceCF;
									Parent = workspace.Terrain;
								})
								local sound = #config.HitCharSoundIds > 0 and create("Sound", {
									Parent = attachment;
									SoundId = chooseRandAssetId(config.HitCharSoundIds);
									PlaybackSpeed = config.HitCharSoundPitch;
									Volume = config.HitCharSoundVolume;
								})
								if client.Variables.ParticlesEnabled then
									task.spawn(function()
										for _, v in pairs(config.Folder_BloodEffect:GetChildren()) do
											if v:IsA("ParticleEmitter") then
												local particle = v:Clone()
												particle.Parent = attachment
												task.delay(0.01, function()
													particle:Emit(particle:GetAttribute("EmitCount") or 1)
													Debris:AddItem(particle, particle.Lifetime.Max)
												end)
											end
										end
										if sound then
											sound:Play()
										end
									end)
								end
								Debris:AddItem(attachment, 10)
							end

							if config.FleshHoleEnabled and getDistanceFromCharacter(HitPoint) <= config.FleshHoleMaxVisibleDistance then
								local hole = create("Part", {
									Name = "FleshHoleEnabled";
									Transparency = 1;
									Anchored = true;
									CanCollide = false;
									FormFactor = Enum.FormFactor.Custom;
									Size = Vector3.new(1, 1, 0.2);
									TopSurface = 0;
									BottomSurface = 0;
								})
								create("BlockMesh", {
									Parent = hole;
									Offset = Vector3.new(0, 0, 0);
									Scale = Vector3.new(config.FleshHoleSize, config.FleshHoleSize, 0);
								})
								local decal = create("Decal", {
									Parent = hole;
									Face = Enum.NormalId.Back;
									Texture = chooseRandAssetId(config.FleshHoleTextureIds);
									Color3 = config.FleshHoleColor;
								})
								edit(hole, {
									Parent = Camera;
									CFrame = surfaceCF * CFrame.Angles(0, 0, math.random(0, 360));
								})
								if not hitPart.Anchored then
									create("Weld", {
										Parent = hole;
										Part0 = hitPart;
										Part1 = hole;
										C0 = hitPart.CFrame:toObjectSpace(surfaceCF * CFrame.Angles(0, 0, math.random(0, 360)));
									})
									hole.Anchored = false
								end
								task.delay(config.FleshHoleVisibleTime, function()
									if config.FleshHoleVisibleTime > 0 then
										local t0 = tick()
										while true do
											local Alpha = math.min((tick() - t0) / config.FleshHoleFadeTime, 1)
											decal.Transparency = numLerp(0, 1, Alpha)
											if Alpha == 1 then break end
											RunService.Heartbeat:Wait()
										end
									end
									hole:Destroy()
								end)
							end
						end)
						inflictTarget(hitCore)
					else
						--// Hit something non-alive
						task.spawn(function()
							if config.HitEffectEnabled and getDistanceFromCharacter(HitPoint) <= config.HitEffectMaxVisibleDistance then
								local attachment = create("Attachment", {
									CFrame = surfaceCF;
									Parent = workspace.Terrain;
								})
								local sound = create("Sound", {
									Parent = attachment;
									SoundId = chooseRandAssetId(config.HitSoundIds);
									PlaybackSpeed = config.HitSoundPitch;
									Volume = config.HitSoundVolume;
								})

								if client.Variables.ParticlesEnabled then
									local folder = config.Folder_HitEffect:FindFirstChild(if config.CustomHitEffect then "Custom" else hitPart.Material.Name)
									if folder then
										for _, v in pairs(folder:GetChildren()) do
											local particle = v:Clone()
											particle.Parent = attachment
											if particle:GetAttribute("PartColor") then
												particle.Color = ColorSequence.new(hitPart.Color)
											end
											task.delay(0.01, function()
												particle:Emit(particle:GetAttribute("EmitCount") or 1)
												Debris:AddItem(particle, particle.Lifetime.Max)
											end)
										end
									end
									sound:Play()
								end

								Debris:AddItem(attachment, 8)				
							end

							if config.BulletHoleEnabled and getDistanceFromCharacter(HitPoint) <= config.BulletHoleMaxVisibleDistance then
								local hole = create("Part", {
									Name = "BulletHole";
									Transparency = 1;
									Anchored = true;
									CanCollide = false;
									FormFactor = Enum.FormFactor.Custom;
									Size = Vector3.new(1, 1, 0.2);
									TopSurface = 0;
									BottomSurface = 0;
								})
								create("BlockMesh", {
									Parent = hole;
									Offset = Vector3.new(0, 0, 0);
									Scale = Vector3.new(config.BulletHoleSize, config.BulletHoleSize, 0);
								})
								local decal = create("Decal", {
									Parent = hole;
									Face = Enum.NormalId.Front;
									Texture = chooseRandAssetId(config.BulletHoleTextureIds);
								})
								if config.BulletHoleSetToPartColor then
									decal.Color3 = hitPart.Color
								end
								edit(hole, {
									Parent = Camera;
									CFrame = surfaceCF * CFrame.Angles(0, 0, math.random(0, 360));
								})
								if not hitPart.Anchored then
									create("Weld", {
										Parent = hole;
										Part0 = hitPart;
										Part1 = hole;
										C0 = hitPart.CFrame:toObjectSpace(surfaceCF * CFrame.Angles(0, 0, math.random(0, 360)));
									})
									hole.Anchored = false
								end
								task.delay(config.BulletHoleVisibleTime, function()
									if config.BulletHoleVisibleTime > 0 then
										local t0 = tick()
										while true do
											local alpha = math.min((tick() - t0) / config.BulletHoleFadeTime, 1)
											decal.Transparency = numLerp(0, 1, alpha)
											if alpha == 1 then break end
											RunService.Heartbeat:Wait()
										end
									end
									hole:Destroy()
								end)
							end
						end)
					end
				elseif config.ExplosiveEnabled then
					--// Exploding on hit
					if #config.ExplosionSoundIds > 0 then
						create("Sound", {
							Parent = bullet;
							SoundId = chooseRandAssetId(config.ExplosionSoundIds);
							PlaybackSpeed = config.ExplosionSoundPitch;
							Volume = config.ExplosionSoundVolume;
						}):Play()	
					end

					local explosion: Explosion = create("Explosion", {
						Parent = Camera;
						BlastRadius = config.ExplosionRadius;
						BlastPressure = 0;
						Position = HitPoint;
					})

					if config.CustomExplosion then
						explosion.Visible = false

						local attachment = create("Attachment", {
							Parent = workspace.Terrain;
							CFrame = surfaceCF;
						})

						task.spawn(function()
							for _, v in pairs(config.Folder_ExplosionEffect:GetChildren()) do
								local particle = v:Clone()
								particle.Parent = attachment
								task.delay(0.01, function()
									if particle:IsA("ParticleEmitter") then
										particle:Emit(particle:GetAttribute("EmitCount") or 1)
										Debris:AddItem(particle, particle.Lifetime.Max)
									else
										particle.Enabled = true
										Debris:AddItem(particle, 0.5)
									end
								end)
							end
						end)
						
						Debris:AddItem(attachment, 10)
					end	

					local alreadyHit = {}
					explosion.Hit:Connect(function(hit)
						if hit and hit.Parent and (hit.Name == "HumanoidRootPart" or hit.Name == "Head") then
							local hitHum = hit.Parent:FindFirstChildOfClass("Humanoid")
							if hitHum and hitHum.Health > 0 and not alreadyHit[hitHum] then
								alreadyHit[hitHum] = true
								inflictTarget(hit)
							end
						end
					end)
				end
			end)

			connectEvent(Remotes.VisualizeBulletSet.OnClientEvent, function(plr, ...)
				if plr ~= LocalPlayer then
					visualizeBulletSet(plr, ...)
				end
			end)
			connectEvent(Remotes.VisualizeMuzzle.OnClientEvent, function(plr, ...)
				if plr ~= LocalPlayer and getDistanceFromCharacter(plr.Character.PrimaryPart.Position) <= config.MuzzleEffectMaxVisibleDistance then
					visualizeMuzzle(...)
				end
			end)

			local Overlay = nil
			local function updateOwnership()
				Owner = Tool.Parent and (Players:GetPlayerFromCharacter(Tool.Parent) or Tool.Parent.Parent)
				if not Tool.Parent or not Owner then
					for conn in pairs(connections) do
						conn:Disconnect()
					end
					connections = {}
				elseif Owner ~= LocalPlayer and isOwnedByLocalPlayer then
					isOwnedByLocalPlayer = false
					for conn in pairs(ownerConnections) do
						conn:Disconnect()
					end
					if Overlay then
						Overlay:Destroy()
						Overlay = nil
					end
					ownerConnections = {}
				elseif Owner == LocalPlayer and not isOwnedByLocalPlayer then
					isOwnedByLocalPlayer = true

					local _initialSensitivity = UserInputService.MouseDeltaSensitivity
					local _mag: number, _ammo: number = Tool:GetAttribute("CurrentMag"), Tool:GetAttribute("CurrentAmmo")
					local equipped, enabled, down, holdDown, singleHold, aimDown, scoping, reloading = false, true, false, false, false, false, false, false

					local AmmoGui, updateGui = nil, nil
					local Reload, ToggleFlashlight = nil, nil

					Overlay = edit(script.GunOverlay:Clone(), {
						Name = client.Functions.GetRandom();
						Enabled = true;
					})
					local CrosshairModule = require(Overlay.CrosshairModule)
					local CameraModule = require(Overlay.CameraModule)(config, RunService)

					local handles: {BasePart} = {}
					for _, v in ipairs(Tool:GetChildren()) do
						if v.Name == "Handle" or (v.Name:sub(1, 6) == "Handle" and tonumber(v.Name:sub(7, #v.Name))) then
							table.insert(handles, v)
						end
					end
					local CurrentHandle = handles[1]
					connectOwnerEvent(Tool.ChildAdded, function(c)
						task.wait()
						if c.Name == "Handle" or (c.Name:sub(1, 6) == "Handle" and tonumber(c.Name:sub(7, #c.Name))) then
							table.insert(handles, c)
							local sorted = {}
							for _, v in pairs(handles) do
								table.insert(sorted, v.Name)
							end
							table.sort(sorted)
							for i, v in ipairs(sorted) do
								handles[i] = Tool[v]
							end
						end
					end)

					connectOwnerEvent(Remotes.ChangeMagAndAmmo.OnClientEvent, function()
						_mag, _ammo = Tool:GetAttribute("CurrentMag"), Tool:GetAttribute("CurrentAmmo")
						updateGui()
					end)

					for _, v in pairs(config.Folder_MuzzleEffect:GetChildren()) do
						for _, h in pairs(handles) do
							local effect = v:Clone()
							effect.Parent = h:WaitForChild("GunMuzzle")
							effect:SetAttribute("_IsMuzzleEffect", true)
						end
					end

					local function mountAmmoGui()
						AmmoGui = client.UI.Make("Window", {
							Name = "GunGui_"..Tool.Name;
							Title = Tool.Name;
							NoClose = true;
							Size = {200, 110};
							SizeLocked = true;
							Position = _ammoGuiPos or if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then UDim2.new(1, -210, 1, -170) else  UDim2.new(1, -210, 1, -250);
							CanKeepAlive = false;
							Walls = true;
						})
						AmmoGui:Add("Frame", {
							Name = "Mag";
							AnchorPoint = Vector2.new(0.5, 0);
							BackgroundColor3 = Color3.fromRGB(225, 225, 225);
							BackgroundTransparency = 0.5;
							BorderColor3 = Color3.fromRGB(150, 150, 150);
							BorderSizePixel = 1;
							Position = UDim2.new(0.5, 0, 0, 10);
							Size = UDim2.new(1, -20, 0, 26);
							ClipsDescendants = false;
							Children = {
								{
									Class = "Frame";
									Name = "Fill";
									--BackgroundColor3 = Color3.fromRGB(50, 50, 50);
									BackgroundTransparency = 0.3;
									Position = UDim2.fromOffset(0, 0);
									Size = UDim2.fromScale(0, 1);
									ClipsDescendants = false;
									Children = {
										{
											Class = "UIGradient";
											Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0, 0, 0));
											--Transparency = NumberSequence.new(0.2);
										}
									};
								},
								{
									Class = "TextLabel";
									Name = "Status";
									BackgroundTransparency = 1;
									Position = UDim2.new(0.5, 4, 0.5, 0);
									Size = UDim2.fromOffset(0, 0);
									Font = "Arial";
									Text = "";
									TextSize = 16;
									TextStrokeColor3 = Color3.fromRGB(225, 225, 225);
									TextStrokeTransparency = 0.95;
									ClipsDescendants = false
								}
							};
						})
						pcall(function()
							AmmoGui.Mag:WaitForChild("Fill"):AddShadow()
						end)
						if _ammoGuiHidden then
							AmmoGui:Hide(true)
						end
						edit(AmmoGui.Mag:Clone(), {
							Parent = AmmoGui;
							Name = "Ammo";
							Position = UDim2.new(0.5, 0, 0, 46);
						})
						AmmoGui:Ready()
						updateGui()
						return AmmoGui
					end

					local animations: {[string]:AnimationTrack} = {}
					for _, v in ipairs({"Idle", "Fire", "Reload", "ShotgunClipin", "HoldDown", "Equip", "Aiming"}) do
						if config[v.."AnimationId"] ~= 0 then
							animations[v] = (LocalHumanoid:FindFirstChildOfClass("Animator") or LocalHumanoid):LoadAnimation(Tool:WaitForChild(v.."Anim"))
						end
					end
					local function playAnim(name: string)
						local anim = animations[name]
						if anim then
							anim:Play(nil, nil, config[name.."AnimationSpeed"])
						end
					end
					local function stopAnim(name: string)
						local anim = animations[name]
						if anim then
							anim:Stop()
						end
					end

					local function playSound(name: string)
						local sound = CurrentHandle:FindFirstChild(name)
						if sound then
							sound:Play()
						end
					end

					connectOwnerEvent(MarkerEvent.Event, function(isHeadshot)
						if config.HitmarkerEnabled then
							pcall(function()
								TweenService:Create(
									edit(Overlay.Crosshair.Hitmarker, {
										ImageColor3 = isHeadshot and config.HitmarkerColorHS or config.HitmarkerColor;
										ImageTransparency = 0;
									}),
									TweenInfo.new(isHeadshot and config.HitmarkerFadeTimeHS or config.HitmarkerFadeTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
									{ImageTransparency = 1}
								):Play()

								local markersound = Overlay.Crosshair.MarkerSound:Clone()
								edit(markersound, {
									Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui");
									PlaybackSpeed = isHeadshot and config.HitmarkerSoundPitchHS or config.HitmarkerSoundPitch;
								}):Play()

								Debris:AddItem(markersound, markersound.TimeLength)
							end)
						end
					end)

					function updateGui()
						if AmmoGui then
							local magSize, ammoSize = UDim2.fromScale(_mag/config.AmmoPerMag, 1), UDim2.fromScale(_ammo/config.MaxAmmo, 1) 
							local magDisplay, ammoDisplay = AmmoGui:WaitForChild("Mag", 2), AmmoGui:WaitForChild("Ammo", 2)
							if not magDisplay then return end
							magDisplay.Fill:TweenSize(magSize, Enum.EasingDirection.Out, MAG_BAR_EASING_STYLE, MAG_BAR_TWEEN_DURATION, true)
							ammoDisplay.Fill:TweenSize(ammoSize, Enum.EasingDirection.Out, AMMO_BAR_EASING_STYLE, AMMO_BAR_TWEEN_DURATION, true)

							magDisplay.Status.Text = if reloading then RELOADING_TEXT else _mag.."/"..config.AmmoPerMag
							ammoDisplay.Status.Text = _ammo.."/"..config.MaxAmmo

							ammoDisplay.Visible = config.LimitedAmmo
						end

						if UserInputService.TouchEnabled --[[and not UserInputService.MouseEnabled]] then --// Roblox bug seemingly causes MouseEnabled to reflect true sometimes even on mobile clients(?)
							Overlay.MobileButtons.Visible = true
							Overlay.MobileButtons.AimButton.Visible = config.IronsightEnabled or config.SniperEnabled
							Overlay.MobileButtons.HoldDownButton.Visible = config.HoldDownEnabled
						else
							Overlay.MobileButtons.Visible = false
						end

						UserInputService.MouseIconEnabled = false
					end

					local function Fire(inputPos: Vector2)
						down = true
						local IsChargedShot = false
						if equipped and enabled and down and not reloading and not holdDown  and _mag > 0 and LocalHumanoid.Health > 0 then
							enabled = false
							if config.ChargedShotEnabled then
								playSound("Charge")
								task.wait(config.ChargingTime)
								IsChargedShot = true
							end
							if config.MinigunEnabled then
								playSound("WindUp")
								task.wait(config.DelayBeforeFiring)
							end
							while equipped and not reloading and not holdDown  and (down or IsChargedShot) and _mag > 0 and LocalHumanoid.Health > 0 do
								IsChargedShot = false
								visualizeMuzzle(CurrentHandle)
								Remotes.VisualizeMuzzle:FireServer(CurrentHandle)
								for _ = 1, if config.BurstFireEnabled then config.BulletPerBurst else 1 do
									task.defer(function()
										if config.CameraRecoilEnabled then
											local currentRecoil = config.Recoil*(aimDown and 1 - config.RecoilReduction or 1)
											local recoilY = math.rad(currentRecoil * rand(0, 1, config.RecoilAccuracy))
											if (LocalCharacter.Head.Position - Camera.CoordinateFrame.p).Magnitude <= 2 then
												CameraModule:accelerate(recoilY, 0, 0)
											else
												recoilY /= 2
												local recoilX = math.rad(currentRecoil * rand(-1, 1, config.RecoilAccuracy))
												CameraModule:accelerate(recoilY, 0, recoilX)	    
												task.delay(0.03, function()
													CameraModule:accelerateXY(-recoilY, recoilX)
												end)
											end
										end
									end)
									if config.BulletShellEnabled then
										local chamber = create("Part", {
											Name = "Chamber";
											Size = Vector3.new(0.01, 0.01, 0.01);
											Transparency = 1;
											Anchored = false;
											CanCollide = false;
											TopSurface = Enum.SurfaceType.SmoothNoOutlines;
											BottomSurface = Enum.SurfaceType.SmoothNoOutlines;
										})
										create("Weld", {
											Parent = chamber;
											Part0 = CurrentHandle;
											Part1 = chamber;
											C0 = CFrame.new(config.BulletShellOffset.X, config.BulletShellOffset.Y, config.BulletShellOffset.Z);
										})
										edit(chamber, {
											Parent = Camera;
											Position = (CurrentHandle.CFrame * CFrame.new(config.BulletShellOffset.X, config.BulletShellOffset.Y, config.BulletShellOffset.Z)).p;
										})
										task.defer(function()
											local shell = create("Part", {
												Name = "Shell";
												CFrame = chamber.CFrame * CFrame.fromEulerAnglesXYZ(-2.5, 1, 1);
												Size = config.BulletShellSize;
												CanCollide = config.BulletShellCollisions;
												Velocity = chamber.CFrame.lookVector * 20 + Vector3.new(math.random(-10, 10), 20, math.random(-10, 10));
												RotVelocity = Vector3.new(0, 200, 0);
											})
											create("SpecialMesh", {
												Parent = shell;
												Scale = config.BulletShellScale;
												MeshId = getAssetUri(config.BulletShellMeshId);
												TextureId = getAssetUri(config.BulletShellTextureId);
												MeshType = Enum.MeshType.FileMesh;
											})
											shell.Parent = Camera
											Debris:AddItem(shell, config.BulletShellLifetime)
										end)
										Debris:AddItem(chamber, config.BulletShellLifetime + 1)			
									end
									CrosshairModule.crossspring:accelerate(config.CrossExpansion)
									task.spawn(function()
										local setData: {Vector3} = {}
										for i = 1, config.ShotgunEnabled and config.BulletsPerShot or 1 do
											if not singleHold then
												playAnim("Fire")
											end
											if not CurrentHandle.Fire.Playing or not CurrentHandle.Fire.Looped then
												if config.BoltBackAnimation then
													CurrentHandle.Parent.Bolt.Transparency = 1
													CurrentHandle.Parent.BoltBack.Transparency = 0 
												end
											end
											local rayMag1 = Camera:ScreenPointToRay(
												inputPos.X + math.random(-config.SpreadX * 2, config.SpreadX * 2) * (aimDown and 1-config.IronsightSpreadReduction and 1-config.SniperSpreadReduction or 1),
												inputPos.Y + math.random(-config.SpreadY * 2, config.SpreadY * 2) * (aimDown and 1-config.IronsightSpreadReduction and 1-config.SniperSpreadReduction or 1)
											)
											setData[i] = (select(2, workspace:FindPartOnRay(Ray.new(rayMag1.Origin, rayMag1.Direction * 5000), LocalCharacter)) - CurrentHandle.GunMuzzle.WorldPosition).Unit
										end
										visualizeBulletSet(LocalPlayer, setData, CurrentHandle)
										Remotes.VisualizeBulletSet:FireServer(setData)
									end)
									_mag -= 1
									Remotes.ChangeMagAndAmmo:FireServer(_mag, _ammo)
									updateGui()
									if config.BurstFireEnabled then
										task.wait(config.BurstRate)
									end
									if _mag <= 0 then break end
								end
								local ind = table.find(handles, CurrentHandle)
								CurrentHandle = if ind == #handles then handles[1] else handles[ind + 1]
								if config.BoltBackAnimation then
									task.wait(config.BoltBackDelay)
									Tool.BoltBack.Transparency = 1
									Tool.Bolt.Transparency = 0
								end
								task.wait(config.FireRate)
								if not config.Auto then break end
							end
							local fireSound = CurrentHandle:FindFirstChild("Fire")
							if fireSound and fireSound.Playing and fireSound.Looped then
								fireSound:Stop()
							end
							if config.MinigunEnabled then
								playSound("WindDown")
								task.wait(config.DelayAfterFiring)
							end
							enabled = true
							if _mag <= 0 then
								Reload()
							end
						end
					end

					function Reload()
						if not equipped then return end
						if enabled and not reloading and (_ammo > 0 or not config.LimitedAmmo) and _mag < config.AmmoPerMag then
							reloading = true
							if aimDown then
								TweenService:Create(Camera, TweenInfo.new(config.TweenLengthNAD, config.EasingStyleNAD, config.EasingDirectionNAD), {FieldOfView = 70}):Play()
								CrosshairModule:setcrossscale(1)
								scoping = false
								LocalPlayer.CameraMode = Enum.CameraMode.Classic
								UserInputService.MouseDeltaSensitivity = _initialSensitivity
								aimDown = false
							end
							updateGui()
							if config.ShotgunReload then
								for _ = 1, config.AmmoPerMag - _mag do
									playAnim("ShotgunClipin")
									playSound("ShotgunClipin")
									task.wait(config.ShellClipinTime)
								end
							end
							playAnim("Reload")
							playSound("Reload")
							task.wait(config.ReloadTime)
							if config.LimitedAmmo then
								local ammoToUse = math.min(config.AmmoPerMag - _mag, _ammo)
								_mag += ammoToUse
								_ammo -= ammoToUse
							else
								_mag = config.AmmoPerMag
							end
							Remotes.ChangeMagAndAmmo:FireServer(_mag, _ammo, true)
							reloading = false
							updateGui()
						end
					end

					local function stopAim()
						TweenService:Create(Camera, TweenInfo.new(config.TweenLengthNAD, config.EasingStyleNAD, config.EasingDirectionNAD), {FieldOfView = 70}):Play()
						CrosshairModule:setcrossscale(1)

						scoping = false
						LocalPlayer.CameraMode = Enum.CameraMode.Classic
						UserInputService.MouseDeltaSensitivity = _initialSensitivity
						aimDown = false
					end

					connectOwnerEvent(Overlay.MobileButtons.AimButton.MouseButton1Click, function()
						if not reloading and not holdDown  and not aimDown and equipped and config.IronsightEnabled and (LocalCharacter.Head.Position - Camera.CoordinateFrame.p).Magnitude <= 2 then
							TweenService:Create(Camera, TweenInfo.new(config.TweenLength, config.EasingStyle, config.EasingDirection), {FieldOfView = config.IronsightFieldOfView}):Play()
							CrosshairModule:setcrossscale(config.IronsightCrossScale)

							--Scoping = false
							LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
							UserInputService.MouseDeltaSensitivity = _initialSensitivity * config.IronsightMouseSensitivity
							aimDown = true
							playAnim("Aiming")
						elseif not reloading and not holdDown and not aimDown and equipped and config.SniperEnabled and (LocalCharacter.Head.Position - Camera.CoordinateFrame.p).Magnitude <= 2 then
							TweenService:Create(Camera, TweenInfo.new(config.TweenLength, config.EasingStyle, config.EasingDirection), {FieldOfView = config.SniperFieldOfView}):Play()
							CrosshairModule:setcrossscale(config.SniperCrossScale)

							local zoomsound = Overlay.Scope.ZoomSound:Clone()
							zoomsound.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
							zoomsound:Play()

							scoping = true
							LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
							UserInputService.MouseDeltaSensitivity = _initialSensitivity * config.SniperMouseSensitivity
							aimDown = true
							playAnim("Aiming")

							Debris:AddItem(zoomsound, 5)
						else
							stopAim()
							stopAnim("Aiming")
						end
					end)

					connectOwnerEvent(Overlay.MobileButtons.HoldDownButton.MouseButton1Click, function()
						if not reloading and not holdDown  and config.HoldDownEnabled then
							holdDown = true
							stopAnim("Idle")
							playAnim("HoldDown")
							if aimDown then
								stopAim()
							end
						else
							holdDown = false
							playAnim("Idle")
							stopAnim("HoldDown")
						end
					end)

					connectOwnerEvent(Overlay.MobileButtons.ReloadButton.MouseButton1Click, Reload)

					connectOwnerEvent(Overlay.MobileButtons.FireButton.MouseButton1Down, function()
						Fire(Overlay.Crosshair.AbsolutePosition)
					end)
					connectOwnerEvent(Overlay.MobileButtons.FireButton.MouseButton1Up, function()
						down = false
					end)

					connectOwnerEvent(Mouse.Button1Down, function()
						if not UserInputService.TouchEnabled then
							Fire(Mouse)
						end
					end)
					connectOwnerEvent(Mouse.Button1Up, function()
						if not UserInputService.TouchEnabled then
							down = false
						end
					end)

					local flashlightDebounce = false
					function ToggleFlashlight()
						flashlightDebounce = true
						Remotes.Flashlight:FireServer()
						task.delay(0.5, function()
							flashlightDebounce = false
						end)
					end

					local toolEquippedConnections = {}

					connectOwnerEvent(Tool.Equipped, function()
						for _, v in pairs(toolEquippedConnections) do
							if v then v:Disconnect() end
						end

						UserInputService.MouseIconEnabled = false
						Overlay.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
						CrosshairModule:setcrosssettings(config.CrossSize, config.CrossSpeed, config.CrossDamper)

						if config.AmmoPerMag == math.huge then AmmoGui = nil else mountAmmoGui() end
						updateGui()

						playSound("Equip")
						equipped = true

						if config.WalkSpeedReductionEnabled then
							LocalHumanoid.WalkSpeed -= config.WalkSpeedReduction
						end
						playAnim("Equip")
						playAnim("Idle")

						toolEquippedConnections = {
							connectOwnerEvent(UserInputService.InputBegan, function(inputObj, processed)
								if processed or not equipped or inputObj.UserInputType ~= Enum.UserInputType.Keyboard then return end

								if inputObj.KeyCode == config.Key_Reload then
									Reload()
								elseif inputObj.KeyCode == config.Key_HoldDown then
									if not reloading and not holdDown and config.HoldDownEnabled then
										holdDown = true
										stopAnim("Idle")
										playAnim("HoldDown")
										if aimDown then 
											stopAim()
										end
									else
										holdDown = false
										playAnim("Idle")
										stopAnim("HoldDown")
									end
								elseif inputObj.KeyCode == config.Key_Flashlight and Tool:GetAttribute("FlashlightEnabled") and not flashlightDebounce then
									ToggleFlashlight()
								elseif inputObj.KeyCode == config.Key_SingleHold and (config.SingleHoldEnabled or LocalPlayer:GetAttribute("CanSingleHoldGuns")) then
									if singleHold then
										singleHold = false
										playAnim("Idle")
									else
										singleHold = true
										stopAnim("Idle")
									end
								end
							end),
							connectOwnerEvent(Mouse.Button2Down, function()
								if reloading or holdDown  or aimDown or not equipped or (LocalCharacter.Head.Position - Camera.CoordinateFrame.p).Magnitude > 2 then return end
								if config.IronsightEnabled then
									TweenService:Create(Camera, TweenInfo.new(config.TweenLength, config.EasingStyle, config.EasingDirection), {FieldOfView = config.IronsightFieldOfView}):Play()
									CrosshairModule:setcrossscale(config.IronsightCrossScale)

									LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
									UserInputService.MouseDeltaSensitivity = _initialSensitivity * config.IronsightMouseSensitivity
									aimDown = true
									playAnim("Aiming")
								elseif config.SniperEnabled then
									TweenService:Create(Camera, TweenInfo.new(config.TweenLength, config.EasingStyle, config.EasingDirection), {FieldOfView = config.SniperFieldOfView}):Play()
									CrosshairModule:setcrossscale(config.SniperCrossScale)

									local zoomsound = Overlay.Scope.ZoomSound:Clone()
									zoomsound.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
									zoomsound:Play()

									scoping = true
									LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
									UserInputService.MouseDeltaSensitivity = _initialSensitivity * config.SniperMouseSensitivity
									aimDown = true
									playAnim("Aiming")

									Debris:AddItem(zoomsound, zoomsound.TimeLength)
								end
							end),
							connectOwnerEvent(Mouse.Button2Up, function()
								if aimDown then
									stopAim()
									stopAnim("Aiming")
								end
							end)
						}
					end)

					connectOwnerEvent(Tool.Unequipped, function()
						holdDown , equipped = false, false
						Overlay.Parent = script
						if AmmoGui then
							_ammoGuiHidden = not AmmoGui.IsVisible
							_ammoGuiPos = AmmoGui.Dragger.Position
							AmmoGui:Close()
						end
						if config.WalkSpeedReductionEnabled then
							LocalHumanoid.WalkSpeed += config.WalkSpeedReduction
						end
						local otherGun = LocalCharacter:FindFirstChildOfClass("Tool")
						if not otherGun or not service.CollectionService:HasTag(otherGun, "ADONIS_GUN") then
							UserInputService.MouseIconEnabled = true
						end
						stopAnim("Idle")
						stopAnim("Aiming")
						stopAnim("Equip")
						stopAnim("Reload")
						stopAnim("HoldDown")
						if aimDown then
							stopAim()
						end
						for _, v in pairs(toolEquippedConnections) do
							if v then v:Disconnect() end
						end
					end)

					connectOwnerEvent(LocalHumanoid.Died, function()
						LocalHumanoid:UnequipTools()
						holdDown, equipped = false, false
						Overlay.Parent = script
						if AmmoGui then
							_ammoGuiHidden, _ammoGuiPos = nil, nil
							AmmoGui:Close()
						end
						if config.WalkSpeedReductionEnabled then
							LocalHumanoid.WalkSpeed += config.WalkSpeedReduction
						end
						UserInputService.MouseIconEnabled = true
						stopAnim("Idle")
						stopAnim("HoldDown")
						if aimDown then
							stopAim()
						end
					end)

					local lastTick = tick()
					RunService:BindToRenderStep("Mouse", Enum.RenderPriority.Input.Value, function()
						local deltaTime = tick() - lastTick
						lastTick = tick()

						edit(Overlay.Scope,
							if scoping --[[and UserInputService.MouseEnabled]] and UserInputService.KeyboardEnabled then {
								Size = UDim2.new(numLerp(Overlay.Scope.Size.X.Scale, 1.2, math.min(deltaTime * 5, 1)), 36, numLerp(Overlay.Scope.Size.Y.Scale, 1.2, math.min(deltaTime * 5, 1)), 36);
								Position = UDim2.new(0, Mouse.X - Overlay.Scope.AbsoluteSize.X / 2, 0, Mouse.Y - Overlay.Scope.AbsoluteSize.Y / 2);
							} elseif scoping and UserInputService.TouchEnabled --[[and not UserInputService.MouseEnabled]] and not UserInputService.KeyboardEnabled then {
									Size = UDim2.new(numLerp(Overlay.Scope.Size.X.Scale, 1.2, math.min(deltaTime * 5, 1)), 36, numLerp(Overlay.Scope.Size.Y.Scale, 1.2, math.min(deltaTime * 5, 1)), 36);
									Position = UDim2.new(0, Overlay.Crosshair.AbsolutePosition.X - Overlay.Scope.AbsoluteSize.X / 2, 0, Overlay.Crosshair.AbsolutePosition.Y - Overlay.Scope.AbsoluteSize.Y / 2);
								} else {
									Size = UDim2.new(0.6, 36, 0.6, 36);
									Position = UDim2.fromScale(0, 0);
								})

						Overlay.Scope.Visible = scoping

						Overlay.Crosshair.Position =
							if UserInputService.TouchEnabled --[[and not UserInputService.MouseEnabled]] and not UserInputService.KeyboardEnabled and (LocalCharacter.Head.Position - Camera.CoordinateFrame.p).Magnitude <= 2 then UDim2.new(0.5, -1, 0.5, -19)
							else UDim2.fromOffset(Mouse.X, Mouse.Y)
					end)
				end
			end

			Tool.AncestryChanged:Connect(updateOwnership)
			updateOwnership()

			if config._Execute then
				config._Execute(Tool, service, client)
			end
		end

		Debug("Loaded;", string.format("%.4fs", os.clock() - startTime))
	end, function(err)
		Debug("Failed to load:", err)
	end)
end

--// Expertcoderz Laboratories 2022
