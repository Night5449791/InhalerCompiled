local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then vape:CreateNotification('Vape', 'Failed to load : '..err, 30, 'alert') end
	return res
end
local isfile = isfile or function(file)
	local suc, res = pcall(function() return readfile(file) end)
	return suc and res ~= nil and res ~= ''
end
local function downloadFile(path, func)
	if not isfile(path) then
		local suc, res = pcall(function() return game:HttpGet('https://raw.githubusercontent.com/Night5449791/InhalerCompiled/'..(isfile('InhalerV4/profiles/commit.txt') and readfile('InhalerV4/profiles/commit.txt') or 'main')..'/'..select(1, path:gsub('InhalerV4/', '')), true) end)
		if not suc or res == '404: Not Found' then error(res) end
		if path:find('.lua') then res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after inhaler updates.\n'..res end
		writefile(path, res)
	end
	return (func or readfile)(path)
end
local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local adonisLoaded, adonis = pcall(function()
	return loadstring(downloadFile('InhalerV4/libraries/adonis.lua'), 'adonis')()
end)
if adonisLoaded and adonis then
	pcall(adonis.Start)
elseif shared.vape then
	shared.vape:CreateNotification('Vape', 'Failed to load adonis bypass', 30, 'alert')
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local httpService = cloneref(game:GetService('HttpService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local prediction = vape.Libraries.prediction

local function canClick()
	local pos = (inputService:GetMouseLocation() - guiService:GetGuiInset())

	if gethui and gethui():IsA('BasePlayerGui') then
		for _, obj in gethui():GetGuiObjectsAtPosition(pos.X, pos.Y) do
			local holder = obj:FindFirstAncestorOfClass('ScreenGui')
			if obj.Active and obj.Visible and holder and holder.Enabled then
				return false
			end
		end
	end

	for _, obj in coreGui:GetGuiObjectsAtPosition(pos.X, pos.Y) do
		local holder = obj:FindFirstAncestorOfClass('ScreenGui')
		if obj.Active and obj.Visible and holder and holder.Enabled then
			return false
		end
	end

	for _, obj in lplr.PlayerGui:GetGuiObjectsAtPosition(pos.X, pos.Y) do
		local holder = obj:FindFirstAncestorOfClass('ScreenGui')
		if obj.Active and obj.Visible and holder and holder.Enabled then
			return false
		end
	end

	return (not vape.gui.ScaledGui.ClickGui.Visible) and (not inputService:GetFocusedTextBox())
end

local GunSettings

run(function()
	local trekModules = replicatedStorage:WaitForChild('TREKModules', 30)
	if not trekModules then return end
	GunSettings = trekModules:WaitForChild('GunSettings', 30)
end)

for _, v in {'SilentAim', 'Reach', 'Killaura', 'HitBoxes', 'AutoClicker', 'TargetStrafe', 'AntiFall', 'HighJump', 'LongJump', 'Invisible', 'Jesus', 'MouseTP', 'Phase', 'Fly', 'Speed', 'SpinBot', 'Spider', 'Swim', 'Timer', 'AntiFeature', 'MurderMystery'} do
	vape:Remove(v)
end


local mouseClicked
run(function()
	local SilentAim
	local Target
	local Mode
	local Method
	local RayMethod
	local SchedulerPriority
	local IgnoredScripts
	local Range
	local HitChance
	local HeadshotChance
	local AutoFire
	local AutoFireShootDelay
	local AutoFireMode
	local AutoFirePosition
	local Wallbang
	local FunctionHook
	local OthHook
	local CircleColor
	local CircleTransparency
	local CircleFilled
	local CircleObject
	local Projectile
	local ProjectileSpeed
	local ProjectileGravity
	local RaycastWhitelist = RaycastParams.new()
	RaycastWhitelist.FilterType = Enum.RaycastFilterType.Include
	local ProjectileRaycast = RaycastParams.new()
	ProjectileRaycast.RespectCanCollide = true
	local oldnamecall, oldhook, hookmethod
	local rand = Random.new()
	local clickDelay = os.clock()
	local fireOffset = CFrame.new()
	local didOth

	local function getMousePosition()
		if inputService.TouchEnabled then
			return gameCamera.ViewportSize / 2
		end

		return inputService:GetMouseLocation()
	end

	local function getTarget(origin, obj)
		if rand.NextNumber(rand, 0, 100) > (AutoFire.Enabled and 100 or HitChance.Value) then
			return
		end

		local targetPart = (rand.NextNumber(rand, 0, 100) < (AutoFire.Enabled and 100 or HeadshotChance.Value)) and 'Head' or 'RootPart'
		local entity = entitylib['Entity'..Mode.Value]({
			Range = Range.Value,
			Wallcheck = Target.Walls.Enabled and (obj or true) or nil,
			Part = targetPart,
			Origin = origin,
			Players = Target.Players.Enabled,
			NPCs = Target.NPCs.Enabled
		})

		if entity then
			targetinfo.Targets[entity] = os.clock() + 1

			if Projectile.Enabled then
				ProjectileRaycast.FilterDescendantsInstances = {gameCamera, entity.Character}
				ProjectileRaycast.CollisionGroup = entity[targetPart].CollisionGroup
			end
		end

		return entity, entity and entity[targetPart], origin
	end

	local Hooks = {
		FindPartOnRayWithIgnoreList = {
			Hook = workspace.FindPartOnRayWithIgnoreList,
			Function = function(args)
				if typeof(args[1]) ~= 'Ray' then
					return
				end

				local entity, targetPart, origin = getTarget(args[1].Origin, {args[2]})
				if not entity then
					return
				end

				if Wallbang.Enabled then
					return {
						targetPart,
						targetPart.Position,
						targetPart.GetClosestPointOnSurface(targetPart, origin),
						targetPart.Material
					}
				end

				args[1] = Ray.new(origin, CFrame.lookAt(origin, targetPart.Position).LookVector * args[1].Direction.Magnitude)
			end
		},
		Raycast = {
			Hook = workspace.Raycast,
			Function = function(args)
				if typeof(args[1]) ~= 'Vector3' or typeof(args[2]) ~= 'Vector3' or args[3] and typeof(args[3]) ~= 'RaycastParams' then
					return
				end

				if RayMethod.Value ~= 'All' and args[3] and args[3].FilterType ~= Enum.RaycastFilterType[RayMethod.Value] then
					return
				end

				local entity, targetPart, origin = getTarget(args[1])
				if not entity then
					return
				end

				args[2] = CFrame.lookAt(origin, targetPart.Position).LookVector * args[2].Magnitude
				if Wallbang.Enabled then
					RaycastWhitelist.FilterDescendantsInstances = {targetPart}
					args[3] = RaycastWhitelist
				end
			end
		},
		ScreenPointToRay = {
			Hook = Instance.new('Camera').ScreenPointToRay,
			Function = function(args)
				if args[3] and type(args[3]) ~= 'number' then
					return
				end

				local entity, targetPart, origin = getTarget(gameCamera.CFrame.Position)
				if not entity then
					return
				end

				local direction = CFrame.lookAt(origin, targetPart.Position)
				if Projectile.Enabled then
					local calc = prediction.SolveTrajectory(origin, ProjectileSpeed.Value, ProjectileGravity.Value, targetPart.Position, targetPart.Velocity, workspace.Gravity, entity.HipHeight, nil, ProjectileRaycast)
					if not calc then
						return
					end

					direction = CFrame.lookAt(origin, calc)
				end

				return {
					Ray.new(origin + (args[3] and direction.LookVector * args[3] or Vector3.zero), direction.LookVector)
				}
			end
		},
		Ray = {
			Hook = Ray.new,
			Function = function(args)
				if typeof(args[1]) ~= 'Vector3' or typeof(args[2]) ~= 'Vector3' then
					return
				end

				local entity, targetPart, origin = getTarget(args[1])
				if not entity then
					return
				end

				if Projectile.Enabled then
					local calc = prediction.SolveTrajectory(origin, ProjectileSpeed.Value, ProjectileGravity.Value, targetPart.Position, targetPart.Velocity, workspace.Gravity, entity.HipHeight, nil, ProjectileRaycast)
					if not calc then
						return
					end

					args[2] = CFrame.lookAt(origin, calc).LookVector * args[2].Magnitude
				else
					args[2] = CFrame.lookAt(origin, targetPart.Position).LookVector * args[2].Magnitude
				end
			end,
			NoNamecall = true
		}
	}

	local function namecallHook(...)
		if getnamecallmethod() ~= Method.Value then
			return oldnamecall(...)
		end

		if checkcaller() then
			return oldnamecall(...)
		end

		local caller = getcallingscript()
		if typeof(caller) == 'Instance' and caller then
			if table.find(IgnoredScripts.ListEnabled, tostring(caller)) then
				return oldnamecall(...)
			end
		end

		local self, args = ..., {select(2, ...)}
		local data = hookmethod.Function(args)
		if data then
			return unpack(data)
		end

		return oldnamecall(self, unpack(args))
	end

	for _, method in {'FindPartOnRayWithWhitelist', 'FindPartOnRay'} do
		Hooks[method] = table.clone(Hooks.FindPartOnRayWithIgnoreList)
		Hooks[method].Hook = workspace[method]
	end

	Hooks.ViewportPointToRay = table.clone(Hooks.ScreenPointToRay)
	Hooks.ViewportPointToRay.Hook = Instance.new('Camera').ViewportPointToRay

	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if CircleObject then
				CircleObject.Visible = callback and Mode.Value == 'Mouse'
			end

			if callback then
				if Method.Value == 'TaskScheduler' then
					local old
					SilentAim:Clean(runService.PostSimulation:Connect(function()
						local entity, targetPart = getTarget(gameCamera.CFrame.Position)
						if entity then
							old = gameCamera.CFrame
							gameCamera.CFrame = CFrame.lookAt(gameCamera.CFrame.Position, targetPart.Position)
						end
					end))

					local key = httpService:GenerateGUID(false)
					runService:BindToRenderStep(key, SchedulerPriority.Value, function()
						if old then
							gameCamera.CFrame = old
							old = nil
						end
					end)

					SilentAim:Clean(function()
						runService:UnbindFromRenderStep(key)
					end)
				else
					hookmethod = Hooks[Method.Value]
					didOth = OthHook.Enabled

					if FunctionHook.Enabled or hookmethod.NoNamecall then
						oldhook = (OthHook.Enabled and oth.hook or hookfunction)(hookmethod.Hook, function(...)
							if checkcaller() then
								return oldhook(...)
							end

							local caller = getcallingscript()
							if typeof(caller) == 'Instance' and caller then
								if table.find(IgnoredScripts.ListEnabled, tostring(caller)) then
									return oldnamecall(...)
								end
							end

							if hookmethod.NoNamecall then
								local args = {...}
								local data = hookmethod.Function(args)
								if data then
									return unpack(data)
								end

								return oldhook(unpack(args))
							else
								local self, args = ..., {select(2, ...)}
								local data = hookmethod.Function(args)
								if data then
									return unpack(data)
								end

								return oldhook(self, unpack(args))
							end
						end)
					end

					if not hookmethod.NoNamecall then
						oldnamecall = OthHook.Enabled and oth.hook(getrawmetatable(game).__namecall, namecallHook) or hookmetamethod(game, '__namecall', namecallHook)
					end
				end
			else
				if oldhook then
					(didOth and oth.unhook or restorefunction)(hookmethod.Hook)
					oldhook = nil
				end

				if oldnamecall then
					(didOth and oth.unhook or restorefunction)(getrawmetatable(game).__namecall)
					oldnamecall = nil
				end
			end

			repeat
				if CircleObject then
					CircleObject.Position = getMousePosition()
				end

				if AutoFire.Enabled then
					local origin = AutoFireMode.Value == 'Camera' and gameCamera.CFrame or entitylib.isAlive and entitylib.character.RootPart.CFrame or CFrame.identity
					local entity = entitylib['Entity'..Mode.Value]({
						Range = Range.Value,
						Wallcheck = Target.Walls.Enabled or nil,
						Part = 'Head',
						Origin = (origin * fireOffset).Position,
						Players = Target.Players.Enabled,
						NPCs = Target.NPCs.Enabled
					})

					if mouse1click and (isrbxactive or iswindowactive)() then
						if entity and canClick() then
							if clickDelay < os.clock() then
								if mouseClicked then
									mouse1release()
									clickDelay = os.clock() + AutoFireShootDelay.Value
								else
									mouse1press()
								end

								mouseClicked = not mouseClicked
							end
						else
							if mouseClicked then
								mouse1release()
							end

							mouseClicked = false
						end
					end
				end

				task.wait()
			until not SilentAim.Enabled
		end,
		ExtraText = function()
			return Method.Value:gsub('FindPartOnRay', '')
		end,
		Tooltip = 'Silently adjusts your aim towards the enemy'
	})
	Target = SilentAim:CreateTargets({
		Players = true
	})
	Mode = SilentAim:CreateDropdown({
		Name = 'Mode',
		List = {'Mouse', 'Position'},
		Function = function(val)
			if CircleObject then
				CircleObject.Visible = SilentAim.Enabled and val == 'Mouse'
			end
		end,
		Tooltip = 'Mouse - Checks for entities near the mouses position\nPosition - Checks for entities near the local character'
	})
	Method = SilentAim:CreateDropdown({
		Name = 'Method',
		List = {'FindPartOnRayWithIgnoreList'},
		Function = function(val)
			if SilentAim.Enabled then
				SilentAim:Toggle()
				SilentAim:Toggle()
			end

			RayMethod.Object.Visible = val == 'Raycast'
			IgnoredScripts.Object.Visible = val ~= 'TaskScheduler'
			SchedulerPriority.Object.Visible = val == 'TaskScheduler'
		end,
		Tooltip = 'FindPartOnRay* - Deprecated methods of raycasting used in old games\nRaycast - The modern raycast method\n*PointToRay - Method to generate a ray from a screen position\nRay - Used in old games'
	})
	RayMethod = SilentAim:CreateDropdown({
		Name = 'Raycast Type',
		List = {'All', 'Exclude', 'Include'},
		Darker = true,
		Visible = false
	})
	IgnoredScripts = SilentAim:CreateTextList({
		Name = 'Ignored Scripts',
		Default = {'CameraModule'}
	})
	Range = SilentAim:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 1000,
		Default = 150,
		Function = function(val)
			if CircleObject then
				CircleObject.Radius = val
			end
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	HitChance = SilentAim:CreateSlider({
		Name = 'Hit Chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	HeadshotChance = SilentAim:CreateSlider({
		Name = 'Headshot Chance',
		Min = 0,
		Max = 100,
		Default = 65,
		Suffix = '%'
	})
	SchedulerPriority = SilentAim:CreateSlider({
		Name = 'Scheduler Priority',
		Min = -5,
		Max = 5,
		Default = 0,
		Function = function()
			if SilentAim.Enabled then
				SilentAim:Toggle()
				SilentAim:Toggle()
			end
		end,
		Darker = true,
		Visible = false,
		Tooltip = 'Adjust the RenderStepped priority for TaskScheduler, only adjust this if you know what you are doing!'
	})
	AutoFire = SilentAim:CreateToggle({
		Name = 'AutoFire',
		Function = function(callback)
			AutoFireShootDelay.Object.Visible = callback
			AutoFireMode.Object.Visible = callback
			AutoFirePosition.Object.Visible = callback
		end
	})
	AutoFireShootDelay = SilentAim:CreateSlider({
		Name = 'Next Shot Delay',
		Min = 0,
		Max = 1,
		Decimal = 100,
		Visible = false,
		Darker = true,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end
	})
	AutoFireMode = SilentAim:CreateDropdown({
		Name = 'Origin',
		List = {'RootPart', 'Camera'},
		Visible = false,
		Darker = true,
		Tooltip = 'Determines the position to check for before shooting'
	})
	AutoFirePosition = SilentAim:CreateTextBox({
		Name = 'Offset',
		Function = function()
			local success, cf = pcall(function()
				return CFrame.new(unpack(AutoFirePosition.Value:split(',')))
			end)

			if success then
				fireOffset = cf
			end
		end,
		Default = '0, 0, 0',
		Visible = false,
		Darker = true
	})
	Wallbang = SilentAim:CreateToggle({Name = 'Wallbang'})
	FunctionHook = SilentAim:CreateToggle({
		Name = 'Function hook',
		Function = function()
			if SilentAim.Enabled then
				SilentAim:Toggle()
				SilentAim:Toggle()
			end
		end,
		Tooltip = 'Hook the function used for index calling (used on some games)'
	})
	OthHook = SilentAim:CreateToggle({
		Name = 'Oth hook',
		Function = function()
			if SilentAim.Enabled then
				SilentAim:Toggle()
				SilentAim:Toggle()
			end
		end,
		Tooltip = 'Hook the function using a less detected method (useful on some games)'
	})
	SilentAim:CreateToggle({
		Name = 'Range Circle',
		Function = function(callback)
			if callback then
				CircleObject = Drawing.new('Circle')
				CircleObject.Filled = CircleFilled.Enabled
				CircleObject.Color = Color3.fromHSV(CircleColor.Hue, CircleColor.Sat, CircleColor.Value)
				CircleObject.Position = vape.gui.AbsoluteSize / 2
				CircleObject.Radius = Range.Value
				CircleObject.NumSides = 100
				CircleObject.Transparency = 1 - CircleTransparency.Value
				CircleObject.Visible = SilentAim.Enabled and Mode.Value == 'Mouse'
			else
				pcall(function()
					CircleObject.Visible = false
					CircleObject:Remove()
				end)
			end
			CircleColor.Object.Visible = callback
			CircleTransparency.Object.Visible = callback
			CircleFilled.Object.Visible = callback
		end
	})
	CircleColor = SilentAim:CreateColorSlider({
		Name = 'Circle Color',
		Function = function(hue, sat, val)
			if CircleObject then
				CircleObject.Color = Color3.fromHSV(hue, sat, val)
			end
		end,
		Darker = true,
		Visible = false
	})
	CircleTransparency = SilentAim:CreateSlider({
		Name = 'Transparency',
		Min = 0,
		Max = 1,
		Decimal = 10,
		Default = 0.5,
		Function = function(val)
			if CircleObject then
				CircleObject.Transparency = 1 - val
			end
		end,
		Darker = true,
		Visible = false
	})
	CircleFilled = SilentAim:CreateToggle({
		Name = 'Circle Filled',
		Function = function(callback)
			if CircleObject then
				CircleObject.Filled = callback
			end
		end,
		Darker = true,
		Visible = false
	})
	Projectile = SilentAim:CreateToggle({
		Name = 'Projectile',
		Function = function(callback)
			ProjectileSpeed.Object.Visible = callback
			ProjectileGravity.Object.Visible = callback
		end
	})
	ProjectileSpeed = SilentAim:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 1000,
		Default = 1000,
		Darker = true,
		Visible = false,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	ProjectileGravity = SilentAim:CreateSlider({
		Name = 'Gravity',
		Min = 0,
		Max = 192.6,
		Default = 192.6,
		Darker = true,
		Visible = false
	})
end)

run(function()
	local GunModifications
	local MaxDamage
	local MinDamage
	local AmmoCount
	local HeadshotMultiplier
	local ReloadSpeed
	local FireRate
	local Spread
	local CrouchSpread
	local Recoil
	local Penetration
	local Range
	local ShellsPerShot
	local Teamkill
	local Weight
	local Suppression
	
	local fields = {'MaxDamage', 'MinDamage', 'AmmoCount', 'HeadshotMultiplier', 'ReloadSpeed', 'firerate', 'spread', 'crouchSpread', 'Recoil', 'Penetration', 'Range', 'ShellsPerShot', 'teamkill', 'Weight', 'Suppression'}
	local originals = {}
	
	local function modify(settings)
		if not originals[settings] then
			originals[settings] = table.clone(settings)
		end
	
		settings.MaxDamage = MaxDamage.Value
		settings.MinDamage = MinDamage.Value
		settings.AmmoCount = AmmoCount.Value
		settings.HeadshotMultiplier = HeadshotMultiplier.Value
		settings.ReloadSpeed = ReloadSpeed.Value
		settings.firerate = FireRate.Value
		settings.spread = Spread.Value
		settings.crouchSpread = CrouchSpread.Value
		settings.Recoil = Recoil.Value
		settings.Penetration = Penetration.Value
		settings.Range = Range.Value
		settings.ShellsPerShot = ShellsPerShot.Value
		settings.teamkill = Teamkill.Enabled
		settings.Weight = Weight.Value
		settings.Suppression = Suppression.Value
	end
	
	local function apply()
		if not GunModifications.Enabled or not GunSettings then return end
		for _, gunModule in GunSettings:GetChildren() do
			if gunModule:IsA('ModuleScript') then
				local suc, settings = pcall(require, gunModule)
				if suc and type(settings) == 'table' then
					modify(settings)
				end
			end
		end
	end
	
	local function restore()
		for settings, data in originals do
			for _, field in fields do
				settings[field] = data[field]
			end
		end
		table.clear(originals)
	end
	
	GunModifications = vape.Categories.Blatant:CreateModule({
		Name = 'GunModifications',
		Function = function(callback)
			if callback then
				apply()
				if GunSettings then
					GunModifications:Clean(GunSettings.ChildAdded:Connect(function(gunModule)
						if gunModule:IsA('ModuleScript') then
							local suc, settings = pcall(require, gunModule)
							if suc and type(settings) == 'table' then
								modify(settings)
							end
						end
					end))
				end
			else
				restore()
			end
		end,
		Tooltip = 'Modify the stats of every weapon'
	})
	MaxDamage = GunModifications:CreateSlider({
		Name = 'Max Damage',
		Min = 0,
		Max = 1000,
		Default = 200,
		Function = apply
	})
	MinDamage = GunModifications:CreateSlider({
		Name = 'Min Damage',
		Min = 0,
		Max = 1000,
		Default = 200,
		Function = apply
	})
	AmmoCount = GunModifications:CreateSlider({
		Name = 'Ammo Count',
		Min = 0,
		Max = 500,
		Default = 100,
		Function = apply
	})
	HeadshotMultiplier = GunModifications:CreateSlider({
		Name = 'Headshot Multiplier',
		Min = 0,
		Max = 10,
		Default = 2,
		Function = apply
	})
	ReloadSpeed = GunModifications:CreateSlider({
		Name = 'Reload Speed',
		Min = 0,
		Max = 10,
		Default = 0,
		Function = apply
	})
	FireRate = GunModifications:CreateSlider({
		Name = 'Fire Rate',
		Min = 0,
		Max = 5000,
		Default = 100,
		Function = apply
	})
	Spread = GunModifications:CreateSlider({
		Name = 'Spread',
		Min = 0,
		Max = 20,
		Default = 0,
		Function = apply
	})
	CrouchSpread = GunModifications:CreateSlider({
		Name = 'Crouch Spread',
		Min = 0,
		Max = 20,
		Default = 0,
		Function = apply
	})
	Recoil = GunModifications:CreateSlider({
		Name = 'Recoil',
		Min = 0,
		Max = 50,
		Default = 0,
		Function = apply
	})
	Penetration = GunModifications:CreateSlider({
		Name = 'Penetration',
		Min = 0,
		Max = 20,
		Default = 5,
		Function = apply
	})
	Range = GunModifications:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 20000,
		Default = 6000,
		Function = apply
	})
	ShellsPerShot = GunModifications:CreateSlider({
		Name = 'Shells Per Shot',
		Min = 0,
		Max = 50,
		Default = 1,
		Function = apply
	})
	Teamkill = GunModifications:CreateToggle({
		Name = 'Teamkill',
		Function = apply
	})
	Weight = GunModifications:CreateSlider({
		Name = 'Weight',
		Min = 0,
		Max = 10,
		Default = 0,
		Function = apply
	})
	Suppression = GunModifications:CreateSlider({
		Name = 'Suppression',
		Min = 0,
		Max = 50,
		Default = 0,
		Function = apply
	})
	
end)