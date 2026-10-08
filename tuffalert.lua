--my discord is @misenthropic and my roblox username is misenthropic
--gun client script i made a while back for a combat system i was trying to make. 
--lots of client side effects plus their replication are handled here 
--and the gun object is set up
--also for the networking i would probably use packet or instead of a random ahh remote event/function for everything
--it had to do with the way the system worked. i'm not working on this anymore and haven't in a long time. the client script was just conveniently long
--also uses a couple open source modules
--roblox user id 177241457

--//PREACH

local gun = {}
gun.__index = gun

--//SERVICES

local PLAYERS = game:GetService("Players")
local REPLICATED_STORAGE = game:GetService("ReplicatedStorage")
local USER_INPUT_SERVICE = game:GetService("UserInputService")
local DEBRIS = game:GetService("Debris")
local RUN_SERVICE = game:GetService("RunService")
local TWEEN_SERVICE = game:GetService("TweenService")
local REPLICATED_FIRST = game:GetService("ReplicatedFirst")
local CONTENT_PROVIDER = game:GetService("ContentProvider")

--//OBJECTS

local player = PLAYERS.LocalPlayer
local mouse = player:GetMouse()
local storage = REPLICATED_STORAGE:WaitForChild("UEStorage")

local network_function = storage.NetworkFunction
local network_event = storage.NetworkEvent

local projectile = require(storage.Modules.ProjectileManager)
local effect_manager = require(player.UEClient.EffectManager)
local spring = require(storage.Modules.SpringModule)

--//GUN

gun.setup = function(tool, config)
	local self = setmetatable({}, gun)
	self.tool = tool
	self.equipped = false

	self.animations = {}
	self.config = {}

	for setting, value in config do
		self.config[setting] = value
	end

	self.ammo = self.tool.UEConfig.Ammo
	self.reserve = self.tool.UEConfig.Reserve

	for animation_name, animation_info in self.config.animations do
		if animation_info[1] == nil then return end
		local animation_object = Instance.new("Animation")
		animation_object.AnimationId = animation_info[1]

		self.animations[animation_name] = player.Character.Humanoid:LoadAnimation(animation_object)
		self.animations[animation_name].Priority = animation_info[2]
	end

	self.tool.Equipped:Connect(function() self:equip() end)
	self.tool.Unequipped:Connect(function() self:unequip() end)
	self.gun_model = network_function:InvokeServer("setup", self.config)
	self.projectile = projectile.new()
	self.projectile.hit = function(ray_result) self:hit(ray_result) end
	
	self.recoil_spring = spring.new(Vector3.new())
	self.recoil_spring.Speed = 15
	self.recoil_spring.Damper = 0.4

	self.sway_spring = spring.new(Vector3.new())
	self.sway_spring.Speed = 5
	self.sway_spring.Damper = 0.7

	self.shake_spring = spring.new(Vector3.new())
	self.shake_spring.Speed = 10
	self.shake_spring.Damper = 0.2

	if self.network_connection then
		self.network_connection:Disconnect()
	end

	task.delay(0.01, function()
		if self.animations["Unequipped"] == nil then
			network_event:FireServer("hidemodel", self.gun_model)
		else
			self.animations["Unequipped"]:Play()
			self.animations["ViewmodelUnequipped"]:Play()
		end
	end)
end

gun.equip = function(self)
	self.equipped_connections = {}
	self.viewmodel_cframes = {
		idle_offset = Instance.new("CFrameValue"),
		aim_offset = Instance.new("CFrameValue"),
		sway_offset = Instance.new("CFrameValue"),
		bob_offset = Instance.new("CFrameValue"),
		recoil_offset = Instance.new("CFrameValue"), 
		unequipped_offset = Instance.new("CFrameValue"),
	}
	self.camera_cframes = {
		aim_offset = Instance.new("CFrameValue"),
		recoil_offset = Instance.new("CFrameValue"), 
	}
	self.equipped = true
	self.reloading = false
	self.mouse_down = false
	self.aiming = false
	self.firing = false
	self.first_person = false
	self.camera_offsets = {}
	self.camera_offsets.fire = Vector3.new(0, 0, 0)
	
	self.viewmodel = storage.Assets.Viewmodel:Clone()
	self.gun_viewmodel = storage.Guns[self.config.gun_model]:Clone()

	local viewmodel_weld = Instance.new("Motor6D")
	viewmodel_weld.Parent = self.viewmodel.Torso
	viewmodel_weld.Part0 = self.viewmodel.Torso
	viewmodel_weld.Part1 = self.gun_viewmodel.Handle
	viewmodel_weld.Name = self.gun_viewmodel.Name

	self.gun_viewmodel.Parent = self.viewmodel
	self.viewmodel.Parent = workspace.CurrentCamera
	
	self.viewmodel["Right Arm"].Color = player.Character["Right Arm"].Color
	self.viewmodel["Left Arm"].Color = player.Character["Left Arm"].Color
	
	if player.Character:FindFirstChild("Shirt") then
		self.viewmodel.Shirt.ShirtTemplate = player.Character.Shirt.ShirtTemplate
	end

	task.delay(0.1, function()
		for _, base_part in self.viewmodel:GetDescendants() do
			if base_part:IsA("BasePart") then
				base_part.CanCollide = false
				base_part.CanQuery = false
				base_part.CanTouch = false
			end
		end
	end)
	
	for animation_name, animation_info in self.config.animations do
		if animation_info[1] == nil then return end
		local viewmodel_animation_object = Instance.new("Animation")
		viewmodel_animation_object.AnimationId = animation_info[1]

		self.animations["Viewmodel"..animation_name] = self.viewmodel.Humanoid:LoadAnimation(viewmodel_animation_object)
		self.animations["Viewmodel"..animation_name].Priority = animation_info[2]
	end
	
	self.animations["Equip"]:Play()
	self.animations["ViewmodelEquip"]:Play()
	if self.animations.Unequipped then
		self.animations["Unequipped"]:Stop()
		self.animations["ViewmodelUnequipped"]:Stop()
	end
	task.delay(self.animations["Equip"].Length - 0.2, function()
		self.animations["Equipped"]:Play()
		self.animations["ViewmodelEquipped"]:Play()
	end)

	self.gui = storage.Assets.UI.UEGunGui:Clone()
	self.gui.Info.Container.NameLabel.Text = self.tool.Name
	self.gui.Info.Container.AmmoLabel.Text = tostring(self.ammo.Value) .. "/" .. tostring(self.reserve.Value)

	--//INPUT

	for _, connection in self.equipped_connections do
		connection:Disconnect()
	end

	self.equipped_connections.input_began = USER_INPUT_SERVICE.InputBegan:Connect(function(input, gp)
		if not gp then
			if input.KeyCode == Enum.KeyCode.R then
				self:reload()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.mouse_down = true
				self:fire()
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.aiming = true
				
				if self.first_person then
					TWEEN_SERVICE:Create(
						workspace.CurrentCamera,
						TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{FieldOfView = self.config.aim_fov}
					):Play()

					USER_INPUT_SERVICE.MouseDeltaSensitivity = self.config.aim_sensitivity_multiplier
				end
			end
		end
	end)

	self.equipped_connections.input_ended = USER_INPUT_SERVICE.InputEnded:Connect(function(input, gp)
		if not gp then
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.mouse_down = false
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.aiming = false
				
				TWEEN_SERVICE:Create(
					workspace.CurrentCamera,
					TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{FieldOfView = 70}
				):Play()
				
				USER_INPUT_SERVICE.MouseDeltaSensitivity = 1
			end
		end
	end)

	self.equipped_connections.stepped_connection = RUN_SERVICE.PreRender:Connect(function(delta)
		local viewport_cframe = workspace.CurrentCamera.CFrame
		local camera_cframe = CFrame.new()

		for _, cframe_value in self.viewmodel_cframes do
			viewport_cframe *= cframe_value.Value
		end
		
		for _, cframe_value in self.camera_cframes do
			camera_cframe *= cframe_value.Value
		end

		self.viewmodel:PivotTo(viewport_cframe)
		workspace.CurrentCamera.CFrame *= camera_cframe
		
		if self.first_person then
			self.viewmodel_cframes.unequipped_offset.Value = CFrame.new()
		else
			self.viewmodel_cframes.unequipped_offset.Value = CFrame.new(0, 99999, 0)
		end
		
		if self.aiming then
			TWEEN_SERVICE:Create(
				self.viewmodel_cframes.aim_offset,
				TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{Value = self.gun_viewmodel.Handle.ADS.WorldCFrame:ToObjectSpace(self.viewmodel.Head.CFrame)}
			):Play()
			
			if self.first_person then
				self.gui.Crosshair.Visible = false
			end
		else
			TWEEN_SERVICE:Create(
				self.viewmodel_cframes.aim_offset,
				TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{Value = CFrame.new()}
			):Play()
			
			TWEEN_SERVICE:Create(
				self.camera_cframes.aim_offset,
				TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{Value = CFrame.new()}
			):Play()
			
			self.gui.Crosshair.Visible = true
		end
		
		self.viewmodel_cframes.recoil_offset.Value = CFrame.Angles(-self.recoil_spring.Value.X, -self.recoil_spring.Value.Y, -self.recoil_spring.Value.Z)	
		self.camera_cframes.recoil_offset.Value = CFrame.Angles(self.recoil_spring.Value.X, self.recoil_spring.Value.Y, self.recoil_spring.Value.Z)	
		self.viewmodel_cframes.sway_offset.Value = CFrame.new(self.sway_spring.Value.X, self.sway_spring.Value.Y, self.sway_spring.Value.Z)	
		self.viewmodel_cframes.sway_offset.Value *= CFrame.Angles(-self.sway_spring.Value.Y * 2, self.sway_spring.Value.X * 2, 0)	
		self.sway_spring:Impulse(Vector3.new(-USER_INPUT_SERVICE:GetMouseDelta().X/250, USER_INPUT_SERVICE:GetMouseDelta().Y/250, 0))

		local distance = ((player.Character.HumanoidRootPart.Position + Vector3.new(0, 1, 0)) - workspace.CurrentCamera.CFrame.Position).Magnitude
		if distance <= 2 then
			self.first_person = true
		else
			self.first_person = false
		end

		self.gui.Info.Container.NameLabel.Text = self.tool.Name
		self.gui.Info.Container.AmmoLabel.Text = tostring(self.ammo.Value) .. "/" .. tostring(self.reserve.Value)

		local ammo_factor = (self.ammo.Value / self.ammo:GetAttribute("Capacity")) - 0.5
		TWEEN_SERVICE:Create(
			self.gui.Info.AmmoGradient,
			TweenInfo.new(
				0.2,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			),
			{Offset = Vector2.new(ammo_factor, 0)}
		):Play()
		TWEEN_SERVICE:Create(
			self.gui.Crosshair.Container,
			TweenInfo.new(
				self.config.recoil_speed,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			),
			{Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0.5, 0, 0.5, 0), Rotation = 0}
		):Play()
		TWEEN_SERVICE:Create(
			self.gui.Crosshair,
			TweenInfo.new(
				0,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			),
			{Position = UDim2.new(0, mouse.X, 0, mouse.Y + 37)}
		):Play()
		TWEEN_SERVICE:Create(
			self.gui.CrosshairCircle,
			TweenInfo.new(
				0.05,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			),
			{Position = UDim2.new(0, mouse.X, 0, mouse.Y + 37)}
		):Play()
		TWEEN_SERVICE:Create(
			self.gui.Crosshair.Container.Crosshair,
			TweenInfo.new(
				self.config.recoil_speed,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			),
			{ImageTransparency = 0.2}
		):Play()
		TWEEN_SERVICE:Create(
			player.Character.Humanoid,
			TweenInfo.new(
				self.config.recoil_speed,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			),
			{CameraOffset = Vector3.new(0, 0, 0)}
		):Play()

		self.gui.CrosshairCircle.Container.Position = UDim2.new(0.5, USER_INPUT_SERVICE:GetMouseDelta().X, 0.5, USER_INPUT_SERVICE:GetMouseDelta().Y)

		if math.abs(math.abs(self.gui.Crosshair.Position.X.Offset) - math.abs(mouse.X)) <= 2 then
			self.gui.Crosshair.Position = UDim2.new(0, mouse.X, 0, mouse.Y + 37)
		end
		
		self.recoil_spring:TimeSkip(delta)
		self.sway_spring:TimeSkip(delta)
		self.shake_spring:TimeSkip(delta)
	end)
	
	for _, animation in self.config.animations do
		CONTENT_PROVIDER:PreloadAsync({animation[1]})
	end

	for event, sound_id in self.config.sfx do
		for name, animation in self.animations do
			self.equipped_connections[animation.Name..event] = animation:GetMarkerReachedSignal(event):Connect(function()
				if not string.find(name, "Viewmodel") then
					local sound = Instance.new("Sound")
					sound.SoundId = sound_id
					sound.Parent = self.gun_model.Handle
					sound.RollOffMode = Enum.RollOffMode.InverseTapered
					sound.RollOffMinDistance = 10
					sound.RollOffMaxDistance = 500
					sound.Name = event
					effect_manager:effect("sound", sound)

					if event == "MagOut" and self.gun_model:FindFirstChild("Mag") then
						local clone = self.gun_model.Mag:Clone()
						clone.Parent = workspace.UEWorkspace
						clone.CFrame = self.gun_model.Mag.CFrame
						clone.Anchored = false
						clone.CanCollide = false
						delay(0.1, function()
							clone.CanCollide = true
						end)
						self.gun_model.Mag.Transparency = 1
						DEBRIS:AddItem(clone, 60)
					elseif event == "MagIn" and self.gun_model:FindFirstChild("Mag") then
						self.gun_model.Mag.Transparency = 0
					end
				end
			end)
		end
	end

	if self.animations.Unequipped == nil then
		network_event:FireServer("showmodel", self.gun_model)
	end

	self.gui.Parent = player.PlayerGui
	USER_INPUT_SERVICE.MouseIconEnabled = false
end

gun.unequip = function(self)
	self.equipped = false

	for _, animation in self.animations do
		animation:Stop()
		delay(0.5, function()
			if self.equipped == false then
				animation:Stop()
			end
		end)
	end
	if self.animations.Unequipped then
		self.animations["Unequipped"]:Play()
		self.animations["ViewmodelUnequipped"]:Play()
	end
	for _, connection in self.equipped_connections do
		connection:Disconnect()
	end

	if self.animations.Unequipped == nil then
		network_event:FireServer("hidemodel", self.gun_model)
	end
	
	self.gui:Destroy()
	self.viewmodel:Destroy()
	
	workspace.CurrentCamera.FieldOfView = 70
	
	USER_INPUT_SERVICE.MouseDeltaSensitivity = 1
	USER_INPUT_SERVICE.MouseIconEnabled = true
end

gun.reload = function(self)
	if self.equipped == false then return end

	local ammo_needed = self.ammo:GetAttribute("Capacity") - self.ammo.Value

	if self.reserve.Value > 0 and ammo_needed > 0 then
		if self.reserve.Value - ammo_needed >= 0 then
			self.reserve.Value -= ammo_needed
			self.ammo.Value += ammo_needed
		else
			self.ammo.Value = self.reserve.Value
			self.reserve.Value = 0
		end

		self.animations["Reload"]:Play()
		self.animations["ViewmodelReload"]:Play()
		self.reloading = true
		task.delay(self.config.reload_time, function()
			self.reloading = false
		end)
	end
end

gun.fire = function(self)
	if self.equipped == false then return end

	repeat 
		task.spawn(function()
			if self.ammo.Value > 0 and self.reloading == false and self.firing == false and self.equipped == true then
				self.animations["Fire"]:Play()
				self.animations["ViewmodelFire"]:Play()
				self.ammo.Value -= 1
				if self.first_person then
					self.gun_viewmodel.Handle.Ejection.ParticleEffect:Emit(1)
				else
					self.gun_model.Handle.Ejection.ParticleEffect:Emit(1)
				end
				effect_manager:effect("sound", self.gun_model.Handle.Muzzle.Fire)
				network_event:FireServer("fire", self.gun_model.Handle.Muzzle.Fire)
				self.firing = true
				local projectile_info = {
					origin = self.gun_model.Handle.Muzzle.WorldPosition, 
					destination = mouse.Hit.Position, 
					force = self.config.muzzle_velocity, 
					origin_velocity = player.Character.HumanoidRootPart.AssemblyLinearVelocity,
					gravity = self.config.gravity, 
					visual_instance = self.config.visual, 
					blacklist = {player.Character, workspace.UEWorkspace}, 
					lifetime = 5,
					debug_mode = false
				}
				
				if self.first_person then
					projectile_info.origin = self.gun_viewmodel.Handle.Muzzle.WorldCFrame.Position
					
					for _, particle in self.gun_viewmodel.Handle.Muzzle:GetChildren() do
						if particle:IsA("ParticleEmitter") then
							particle:Emit(1)
						end
					end
					
					self.gun_viewmodel.Handle.Muzzle.SpotLight.Enabled = true
					task.delay(0.01, function()
						self.gun_viewmodel.Handle.Muzzle.SpotLight.Enabled = false
					end)
				else
					for _, particle in self.gun_model.Handle.Muzzle:GetChildren() do
						if particle:IsA("ParticleEmitter") then
							particle:Emit(1)
						end
					end

					self.gun_model.Handle.Muzzle.SpotLight.Enabled = true
					task.delay(0.01, function()
						self.gun_model.Handle.Muzzle.SpotLight.Enabled = false
					end)
				end

				if self.ammo.Value % self.config.visual_interval ~= 0 then
					projectile_info.visual_instance = storage.Assets.Projectiles.TracerSilenced
				end 

				self.projectile:cast(projectile_info)
				network_event:FireServer("projectile", projectile_info)

				self.gui.Crosshair.Container.Size += UDim2.new(0, 300, 0, 300)
				self.gui.Crosshair.Container.Rotation += Random.new():NextNumber(-20, 20)
				self.gui.Crosshair.Container.Position += UDim2.new(0, 0, 0, -10)
				self.gui.Crosshair.Container.Crosshair.ImageTransparency += 4

				player.Character.Humanoid.CameraOffset += self.config.recoil_offset
				
				self.recoil_spring:Impulse(Vector3.new(self.config.recoil_x, math.random(-self.config.recoil_y, self.config.recoil_y), self.config.recoil_z))

				task.delay(60/self.config.rpm, function()
					self.firing = false
				end)
			end
		end)
		task.wait(60/self.config.rpm)
	until 
	self.config.fire_mode ~= "auto"
		or self.ammo.Value <= 0 
		or self.reloading == true
		or self.mouse_down == false
		or self.equipped == false
end

gun.hit = function(self, ray_result)
	if ray_result == nil then return end
	local humanoid = ray_result.Instance.Parent:FindFirstChildOfClass("Humanoid") or ray_result.Instance.Parent.Parent:FindFirstChildOfClass("Humanoid")

	local damage = self.config.damage
	for limb, multiplier in self.config.limb_multipliers do
		if ray_result.Instance.Name == limb then
			damage *= multiplier
		end
	end

	local hit_info = {
		instance = ray_result.Instance,
		position = ray_result.Position,
		material = ray_result.Material,
		normal = ray_result.Normal,
		damage = damage,
		lethality = self.config.lethality
	}

	effect_manager:effect("hit", hit_info)
	network_event:FireServer("hit", hit_info)
end

return gun
