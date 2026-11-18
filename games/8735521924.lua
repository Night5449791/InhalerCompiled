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
		local suc, res = pcall(function() return game:HttpGet('https://raw.githubusercontent.com/Night5449791/InhalerCompiled/'..readfile('InhalerV4/profiles/commit.txt')..'/'..select(1, path:gsub('InhalerV4/', '')), true) end)
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
	adonis.Start()
elseif shared.vape then
	shared.vape:CreateNotification('Vape', 'Failed to load adonis bypass', 30, 'alert')
end

local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

local gameCamera = workspace.CurrentCamera
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo

local GunSettings

run(function()
	local trekModules = replicatedStorage:WaitForChild('TREKModules', 30)
	if not trekModules then return end
	GunSettings = trekModules:WaitForChild('GunSettings', 30)
end)

for _, v in {'SilentAim', 'Reach', 'Killaura', 'HitBoxes', 'AutoClicker', 'TargetStrafe', 'AntiFall', 'HighJump', 'LongJump', 'Invisible', 'Jesus', 'MouseTP', 'Phase', 'Fly', 'Speed', 'SpinBot', 'Spider', 'Swim', 'Timer', 'AntiFeature', 'MurderMystery'} do
	vape:Remove(v)
end


run(function()
	local SilentAim
	local Targets
	local Mode
	local Range
	local HitChance
	local HeadshotChance
	local Wallbang
	local ShowTarget
	local AutoFire
	local ShootDelay
	local rand = Random.new()
	local clickDelay = os.clock()
	local mouseClicked
	local oldnamecall
	local othOriginal
	local useOth
	
	local function getTarget(origin, ignoreList)
		if rand:NextNumber(0, 100) > HitChance.Value then return end
	
		local partName = rand:NextNumber(0, 100) < HeadshotChance.Value and 'Head' or 'RootPart'
		local fromMouse = Mode.Value == 'Mouse'
		local wallcheck
		if not Wallbang.Enabled then
			wallcheck = ignoreList
		end
	
		local entity = entitylib['Entity'..Mode.Value]({
			Part = partName,
			Range = Range.Value,
			MouseOrigin = fromMouse and gameCamera.ViewportSize / 2 or nil,
			Origin = origin,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled,
			Wallcheck = wallcheck
		})
	
		if not entity then return end
		return entity, entity[partName]
	end
	
	local function isGunRay(ignoreList)
		if type(ignoreList) ~= 'table' or not entitylib.isAlive then return false end
	
		local hasIgnoreList, hasCharacter = false, false
		for _, v in ignoreList do
			if v == workspace.IgnoreList then
				hasIgnoreList = true
			end
			if v == entitylib.character.Character then
				hasCharacter = true
			end
		end
	
		return hasIgnoreList and hasCharacter
	end
	
	local function restoreNamecall()
		local mt = getrawmetatable(game)
		if isreadonly(mt) then
			setreadonly(mt, false)
		end
		if useOth then
			if othOriginal then
				pcall(function() oth.unhook(othOriginal) end)
				othOriginal = nil
			end
			oldnamecall = nil
			useOth = nil
		elseif oldnamecall then
			pcall(restorefunction, rawget(mt, '__namecall'))
			oldnamecall = nil
		end
	end
	
	local function namecallHook(self, ...)
		if not SilentAim.Enabled or getnamecallmethod() ~= 'FindPartOnRayWithIgnoreList' then
			return oldnamecall(self, ...)
		end
	
		local ray, ignoreList = ...
		if typeof(ray) ~= 'Ray' or not isGunRay(ignoreList) then
			return oldnamecall(self, ...)
		end
	
		local entity, part = getTarget(ray.Origin, ignoreList)
		if entity and part then
			if ShowTarget.Enabled then
				targetinfo.Targets[entity] = os.clock() + 1
			end
	
			if Wallbang.Enabled then
				return part, part.Position, part.GetClosestPointOnSurface(part, ray.Origin), part.Material
			end
	
			ray = Ray.new(ray.Origin, CFrame.lookAt(ray.Origin, part.Position).LookVector * ray.Direction.Magnitude)
		end
	
		return oldnamecall(self, ray, ignoreList, select(3, ...))
	end
	
	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			restoreNamecall()
			if callback then
				local mt = getrawmetatable(game)
				if isreadonly(mt) then
					setreadonly(mt, false)
				end
				local original = rawget(mt, '__namecall')
				useOth = typeof(oth) == 'table' and typeof(oth.hook) == 'function' and typeof(oth.unhook) == 'function'
				if useOth then
					othOriginal = original
					oldnamecall = original
					oth.hook(original, namecallHook)
				else
					local hook = typeof(newcclosure) == 'function' and newcclosure(namecallHook) or namecallHook
					oldnamecall = hookmetamethod(game, '__namecall', hook)
				end
			else
				if mouse1click and (isrbxactive or iswindowactive)() then
					if mouseClicked then
						mouse1release()
					end
				end
				mouseClicked = false
			end
	
			repeat
				if AutoFire.Enabled and mouse1click and (isrbxactive or iswindowactive)() then
					local origin = entitylib.isAlive and entitylib.character.RootPart.Position or gameCamera.CFrame.Position
					local entity = getTarget(origin, nil)
					if entity and clickDelay < os.clock() then
						if mouseClicked then
							mouse1release()
							clickDelay = os.clock() + ShootDelay.Value
						else
							mouse1press()
						end
	
						mouseClicked = not mouseClicked
					elseif not entity and mouseClicked then
						mouse1release()
						mouseClicked = false
					end
				end
	
				task.wait()
			until not SilentAim.Enabled
		end,
		Tooltip = 'Redirects your bullets onto the target without moving your camera'
	})
	vape:Clean(restoreNamecall)
	Targets = SilentAim:CreateTargets({
		Players = true,
		NPCs = true
	})
	Mode = SilentAim:CreateDropdown({
		Name = 'Mode',
		List = {'Mouse', 'Position'},
		Tooltip = 'Mouse - targets near your crosshair\nPosition - targets closest to your gun'
	})
	Range = SilentAim:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 1000,
		Default = 150,
		Suffix = function(val)
			if Mode.Value == 'Mouse' then
				return val == 1 and 'pixel' or 'pixels'
			end
	
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
	Wallbang = SilentAim:CreateToggle({
		Name = 'Wallbang'
	})
	ShowTarget = SilentAim:CreateToggle({
		Name = 'Show target info'
	})
	AutoFire = SilentAim:CreateToggle({
		Name = 'AutoFire',
		Function = function(callback)
			ShootDelay.Object.Visible = callback
		end
	})
	ShootDelay = SilentAim:CreateSlider({
		Name = 'Next Shot Delay',
		Min = 0,
		Max = 1,
		Decimal = 100,
		Default = 0.1,
		Visible = false,
		Darker = true,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end
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