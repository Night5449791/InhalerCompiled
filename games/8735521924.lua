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

local fireSignal = (getgenv and getgenv().firesignal) or _G.firesignal

run(function()
	if typeof(fireSignal) ~= 'function' then return end
	task.spawn(function()
		local fired = false
		repeat
			for _, obj in lplr.PlayerGui:GetDescendants() do
				if obj:IsA('GuiButton') and obj.Visible then
					local matched = false
					if obj:IsA('TextButton') and obj.Text:upper():find('PRESS TO PLAY', 1, true) then
						matched = true
					else
						for _, child in obj:GetDescendants() do
							if child:IsA('TextLabel') and child.Text:upper():find('PRESS TO PLAY', 1, true) then
								matched = true
								break
							end
						end
					end

					if matched then
						pcall(fireSignal, obj.MouseButton1Click)
						pcall(fireSignal, obj.Activated)
						fired = true
						break
					end
				end
			end
			task.wait(0.5)
		until fired or vape.Loaded == nil
	end)
end)

run(function()
	local trekModules = replicatedStorage:WaitForChild('TREKModules', 30)
	if not trekModules then return end
	GunSettings = trekModules:WaitForChild('GunSettings', 30)
end)

for _, v in {'Reach', 'Killaura', 'HitBoxes', 'AutoClicker', 'TargetStrafe', 'AntiFall', 'HighJump', 'LongJump', 'Invisible', 'Jesus', 'MouseTP', 'SpinBot', 'Spider', 'Swim', 'Timer', 'MurderMystery'} do
	vape:Remove(v)
end


run(function()
	local SilentAim
	local Target
	local Range
	local HitChance
	local oldnamecall
	local hooked
	local rand = Random.new()

	local function restoreHook()
		if not hooked then return end
		pcall(restorefunction, getrawmetatable(game).__namecall)
		hooked = nil
	end

	local function getTarget(origin)
		if rand.NextNumber(rand, 0, 100) > HitChance.Value then return end

		local entity = entitylib.EntityMouse({
			Part = 'Head',
			Range = Range.Value,
			Origin = origin,
			Players = Target.Players.Enabled,
			NPCs = Target.NPCs.Enabled
		})

		if entity then
			targetinfo.Targets[entity] = os.clock() + 1
		end

		return entity, entity and entity.Head
	end

	local function namecallHook(...)
		if not hooked or not SilentAim.Enabled or vape.Loaded == nil or not entitylib then
			return oldnamecall(...)
		end

		if getnamecallmethod() ~= 'FindPartOnRayWithIgnoreList' or checkcaller() then
			return oldnamecall(...)
		end

		local self, ray, ignoreList = ...
		if typeof(ray) ~= 'Ray' or type(ignoreList) ~= 'table' then
			return oldnamecall(...)
		end

		local entity, part = getTarget(ray.Origin)
		if entity and part then
			local origin = ray.Origin
			ray = Ray.new(origin, CFrame.lookAt(origin, part.Position).LookVector * ray.Direction.Magnitude)
		end

		return oldnamecall(self, ray, ignoreList, select(4, ...))
	end

	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if callback then
				local mt = getrawmetatable(game)
				if isreadonly(mt) then
					setreadonly(mt, false)
				end
				local hook = typeof(newcclosure) == 'function' and newcclosure(namecallHook) or namecallHook
				oldnamecall = hookmetamethod(game, '__namecall', hook)
				hooked = true
			else
				restoreHook()
			end
		end,
		Tooltip = 'Silently adjusts your aim towards the enemy'
	})
	vape:Clean(restoreHook)
	Target = SilentAim:CreateTargets({
		Players = true
	})
	Range = SilentAim:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 1000,
		Default = 150,
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
	local InfiniteAmmo
	
	local fields = {'MaxDamage', 'MinDamage', 'AmmoCount', 'HeadshotMultiplier', 'ReloadSpeed', 'firerate', 'spread', 'crouchSpread', 'Recoil', 'Penetration', 'Range', 'ShellsPerShot', 'teamkill', 'Weight', 'Suppression'}
	local originals = {}
	
	local function modify(settings)
		if not originals[settings] then
			originals[settings] = table.clone(settings)
		end
	
		local ammo = AmmoCount.Value
		if InfiniteAmmo.Enabled then
			ammo = math.huge
		end
	
		settings.MaxDamage = MaxDamage.Value
		settings.MinDamage = MinDamage.Value
		settings.AmmoCount = ammo
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
	InfiniteAmmo = GunModifications:CreateToggle({
		Name = 'Infinite Ammo',
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

run(function()
	local AntiVotekick
	local Mode
	local voteCounter
	local rejoining
	
	local function trigger()
		if rejoining then return end
		rejoining = true
	
		task.spawn(function()
			task.wait(1)
	
			pcall(function()
				lplr:Kick('Inhaler: Anti Votekick is working')
			end)
	
			local target = vape.Modules and vape.Modules[Mode.Value]
			if target and not target.Enabled then
				target:Toggle()
			end
		end)
	end
	
	AntiVotekick = vape.Categories.Utility:CreateModule({
		Name = 'AntiVotekick',
		Function = function(callback)
			rejoining = nil
			if callback then
				repeat
					local votekickValues = replicatedStorage:FindFirstChild('VotekickValues')
					voteCounter = votekickValues and votekickValues:FindFirstChild(lplr.Name)
				until voteCounter and voteCounter:IsA('IntValue') or not AntiVotekick.Enabled
				if voteCounter and voteCounter:IsA('IntValue') then
					if voteCounter.Value > 0 then
						trigger()
					end
	
					AntiVotekick:Clean(voteCounter:GetPropertyChangedSignal('Value'):Connect(function()
						if voteCounter.Value > 0 then
							trigger()
						end
					end))
				end
			else
				voteCounter = nil
			end
		end,
		Tooltip = 'Rejoins or serverhops when someone votekicks you'
	})
	Mode = AntiVotekick:CreateDropdown({
		Name = 'Mode',
		List = {'Rejoin', 'ServerHop'}
	})
	
end)