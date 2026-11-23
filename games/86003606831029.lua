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
local queue_on_teleport = queue_on_teleport or function() end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:FindFirstChildOfClass('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local httpService = cloneref(game:GetService('HttpService'))
local teamsService = cloneref(game:GetService('Teams'))

local gameCamera = cloneref(workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera'))
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local whitelist = vape.Libraries.whitelist

local Remotes = {}
local GunStates

run(function()
	if replicatedStorage then
		for _, name in {'ShootEvent', 'ReloadEvent', 'meleeEvent', 'DamageEvent', 'ReplicateEvent', 'EquipEvent', 'UnequipEvent', 'weldEvent', 'SoundEvent', 'RefillEvent', 'UpdateEvent'} do
			local event = replicatedStorage:FindFirstChild(name)
			if event then Remotes[name] = event end
		end

		local states = replicatedStorage:FindFirstChild('GunStates')
		if states then GunStates = states end
	end

	local remoteFolder = workspace:FindFirstChild('Remote')
	if remoteFolder then
		for _, name in {'arrest', 'arrestPlayer', 'tazePlayer', 'votekick', 'R', 'H', 'requestJob', 'ItemHandler', 'BuyGamePass', 'loadchar', 'equipShield', 'toggleSiren'} do
			local event = remoteFolder:FindFirstChild(name)
			if event then Remotes[name] = event end
		end
	end
end)

entitylib.targetCheck = function(entity)
	if entity.TeamCheck then
		return entity:TeamCheck()
	end
	if entity.NPC then return true end
	if table.find(vape.Categories.Friends.ListEnabled, entity.Player.Name) then return false end
	if not select(2, whitelist:get(entity.Player)) then return false end

	local team, targetTeam = lplr.Team, entity.Player.Team
	if not team or not targetTeam then return true end
	return team ~= targetTeam
end

entitylib.getEntityColor = function(entity)
	entity = entity.Player
	if not (entity and vape.Settings.Modules.Options['Use team color'].Enabled) then return end
	if table.find(vape.Categories.Friends.ListEnabled, entity.Name) then
		return Color3.fromHSV(vape.Categories.Friends.Options['Friends color'].Hue, vape.Categories.Friends.Options['Friends color'].Sat, vape.Categories.Friends.Options['Friends color'].Value)
	end
	return tostring(entity.TeamColor) ~= 'White' and entity.TeamColor.Color or nil
end

sessioninfo:AddItem('Kills', 0)
sessioninfo:AddItem('Deaths', 0)
sessioninfo:AddItem('Arrests', 0)

vape:Clean(function()
	table.clear(Remotes)
	GunStates = nil
end)

entitylib.start()

for _, v in {'Reach', 'Jesus', 'MurderMystery', 'StaffDetector', 'FullBright', 'Health', 'FastProxPrompt', 'AnimationPlayer'} do
	vape:Remove(v)
end


run(function()
	local SilentAim
	local Targets
	local Mode
	local Range
	local HitChance
	local HeadshotChance
	local old
	local hooked
	local hookedFn
	local rand = Random.new()
	
	local function getGunData(tool)
		if not tool then return end
		local module = tool:FindFirstChild('GunStates')
		if not module then return end
	
		local suc, data = pcall(require, module)
		if suc and type(data) == 'table' then return data end
	end
	
	local function getTarget(origin, limit)
		if rand:NextNumber(0, 100) > HitChance.Value then return end
	
		local part = rand:NextNumber(0, 100) < HeadshotChance.Value and 'Head' or 'RootPart'
		local entity = entitylib['Entity'..Mode.Value]({
			Range = Range.Value,
			RangePosition = limit,
			Part = part,
			Origin = origin,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled,
			Wallcheck = Targets.Walls.Enabled and true or nil
		})
	
		if entity then
			targetinfo.Targets[entity] = os.clock() + 1
		end
		return entity, entity and entity[part]
	end
	
	local function hookFire(self, hitTable, gun, ...)
		if self ~= Remotes.ShootEvent or typeof(gun) ~= 'Instance' or not gun:IsA('Tool') then
			return old(self, hitTable, gun, ...)
		end
	
		local character = lplr.Character
		local head = character and character:FindFirstChild('Head')
		local muzzle = gun:FindFirstChild('Muzzle')
		if not head or not muzzle then
			return old(self, hitTable, gun, ...)
		end
	
		local data = getGunData(gun)
		local limit = data and data.Range or 800
		local target, targetPart = getTarget(head.Position, limit)
		if not target or not targetPart then
			return old(self, hitTable, gun, ...)
		end
	
		local hit = {{
			Hit = target.Character,
			Distance = (targetPart.Position - muzzle.Position).Magnitude,
			Cframe = CFrame.new(targetPart.Position, head.Position),
			RayObject = Ray.new(head.Position, (targetPart.Position - head.Position).Unit * limit)
		}}
	
		return old(self, hit, gun, ...)
	end
	
	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if callback then
				if hooked then return end
				hookedFn = Remotes.ShootEvent and Remotes.ShootEvent.FireServer
				local suc, result = pcall(function()
					return hookfunction(hookedFn, hookFire)
				end)
				if suc and result then
					old = result
					hooked = hookedFn
				else
					vape:CreateNotification('SilentAim', 'Failed to hook ShootEvent', 5, 'alert')
				end
			else
				if hooked then
					if restorefunction then
						pcall(restorefunction, hooked)
					elseif old then
						pcall(hookfunction, hooked, old)
					end
					hooked = nil
					old = nil
				end
			end
		end,
		Tooltip = 'Silences aim by replacing the shot hit table'
	})
	Targets = SilentAim:CreateTargets({Players = true})
	Mode = SilentAim:CreateDropdown({
		Name = 'Mode',
		List = {'Mouse', 'Position'},
		Function = function() end
	})
	Range = SilentAim:CreateSlider({
		Name = 'Range',
		Min = 50,
		Max = 1000,
		Default = 500,
		Suffix = 'studs'
	})
	HitChance = SilentAim:CreateSlider({
		Name = 'Hit Chance',
		Min = 1,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	HeadshotChance = SilentAim:CreateSlider({
		Name = 'Headshot Chance',
		Min = 0,
		Max = 100,
		Default = 50,
		Suffix = '%'
	})
	
end)

run(function()
	local AutoArrest
	local Range
	local HandCheck
	local arrestCooldown = 0
	
	AutoArrest = vape.Categories.Blatant:CreateModule({
		Name = 'AutoArrest',
		Function = function(callback)
			if callback then
				repeat
					local clock = os.clock()
					if arrestCooldown < clock and Remotes.arrest then
						local handcuffs = entitylib.isAlive and lplr.Character:FindFirstChild('Handcuffs')
						if not HandCheck.Enabled or handcuffs then
							local entities = entitylib.AllPosition({
								Range = Range.Value,
								Players = true,
								Part = 'RootPart',
								TargetCheck = true
							})
	
							for _, ent in entities do
								if ent.Character and not ent.Character:GetAttribute('Arrested') then
									local torso = ent.Character:FindFirstChild('Torso') or ent.RootPart
									local suc, result = pcall(function()
										return Remotes.arrest:InvokeServer(torso)
									end)
	
									if suc and result == true then
										arrestCooldown = clock + 15
										vape:CreateNotification('AutoArrest', 'Arrested '..ent.Player.Name, 5)
									end
									break
								end
							end
						end
					end
					task.wait(0.1)
				until not AutoArrest.Enabled
			end
		end,
		Tooltip = 'Automatically arrests nearby enemies'
	})
	Range = AutoArrest:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 8,
		Default = 6,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	HandCheck = AutoArrest:CreateToggle({
		Name = 'Hand Check',
		Tooltip = 'Only arrest while handcuffs are equipped'
	})
	
end)

run(function()
	local AutoTeam
	local Team
	local switching = false
	
	local function jobKey()
		local hex = tonumber('0x'..game.JobId:sub(1, 2))
		if not hex then return end
	
		local first = tostring(hex):sub(1, 2)
		local value = tonumber(first)
		if not value then return end
	
		if value == 24 then return first..'lop' end
		if value < 40 then
			if value < 10 then return '77dnuk' end
			return first..'wxug'
		end
		return first..'dnuk'
	end
	
	AutoTeam = vape.Categories.Blatant:CreateModule({
		Name = 'AutoTeam',
		Function = function(callback)
			if not callback or switching then return end
			switching = true
	
			task.spawn(function()
				local colors = {
					Guards = 'Bright blue',
					Inmates = 'Bright orange',
					Neutral = 'Medium stone grey',
					Criminals = 'Really red'
				}
				local color = colors[Team.Value]
				local key = jobKey()
	
				if color and key and Remotes.R then
					local suc = pcall(function()
						Remotes.R:InvokeServer(nil, color, key)
					end)
					vape:CreateNotification('AutoTeam', suc and ('Switched to '..Team.Value) or 'Failed to switch team', 5)
				end
	
				task.wait(0.2)
				switching = false
				AutoTeam:Toggle()
			end)
		end,
		Tooltip = 'Instantly switches team'
	})
	Team = AutoTeam:CreateDropdown({
		Name = 'Team',
		List = {'Guards', 'Inmates', 'Neutral', 'Criminals'}
	})
	
end)

run(function()
	local GunModifications
	local FireRate
	local Spread
	local Range
	local MaxAmmo
	local ReloadTime
	local Bullets
	local AutoFire
	local modified = {}
	
	local function apply(tool)
		if modified[tool] then return end
	
		local module = tool:FindFirstChild('GunStates')
		if not module then return end
	
		local suc, states = pcall(require, module)
		if not suc or type(states) ~= 'table' then return end
	
		modified[tool] = {
			FireRate = states.FireRate,
			Spread = states.Spread,
			Range = states.Range,
			MaxAmmo = states.MaxAmmo,
			ReloadTime = states.ReloadTime,
			Bullets = states.Bullets,
			AutoFire = states.AutoFire
		}
	
		states.FireRate = FireRate.Value
		states.Spread = Spread.Value
		states.Range = Range.Value
		states.MaxAmmo = MaxAmmo.Value
		states.ReloadTime = ReloadTime.Value
		states.Bullets = Bullets.Value
		states.AutoFire = AutoFire.Enabled
	end
	
	local function restore()
		for tool, values in modified do
			local module = tool and tool.Parent and tool:FindFirstChild('GunStates')
			if module then
				local suc, states = pcall(require, module)
				if suc and type(states) == 'table' then
					for key, value in values do
						states[key] = value
					end
				end
			end
		end
		table.clear(modified)
	end
	
	local function scan()
		local backpack = lplr:FindFirstChildWhichIsA('Backpack')
		if backpack then
			for _, tool in backpack:GetChildren() do
				if tool:IsA('Tool') then apply(tool) end
			end
		end
	
		local char = lplr.Character
		if char then
			for _, tool in char:GetChildren() do
				if tool:IsA('Tool') then apply(tool) end
			end
		end
	end
	
	GunModifications = vape.Categories.Blatant:CreateModule({
		Name = 'GunModifications',
		Function = function(callback)
			if callback then
				scan()
	
				local backpack = lplr:FindFirstChildWhichIsA('Backpack')
				GunModifications:Clean(backpack and backpack.ChildAdded:Connect(function(tool)
					if tool:IsA('Tool') then apply(tool) end
				end) or function() end)
	
				local char = lplr.Character
				GunModifications:Clean(char and char.ChildAdded:Connect(function(tool)
					if tool:IsA('Tool') then apply(tool) end
				end) or function() end)
			else
				restore()
			end
		end,
		Tooltip = 'Modifies local gun handling; damage is server-side'
	})
	FireRate = GunModifications:CreateSlider({
		Name = 'Fire Rate',
		Min = 0.01,
		Max = 0.5,
		Default = 0.08,
		Decimal = 100
	})
	Spread = GunModifications:CreateSlider({
		Name = 'Spread',
		Min = 0,
		Max = 50,
		Default = 11
	})
	Range = GunModifications:CreateSlider({
		Name = 'Range',
		Min = 100,
		Max = 2000,
		Default = 800
	})
	MaxAmmo = GunModifications:CreateSlider({
		Name = 'Max Ammo',
		Min = 1,
		Max = 200,
		Default = 30
	})
	ReloadTime = GunModifications:CreateSlider({
		Name = 'Reload Time',
		Min = 0.1,
		Max = 5,
		Default = 2,
		Decimal = 10
	})
	Bullets = GunModifications:CreateSlider({
		Name = 'Bullets',
		Min = 1,
		Max = 10,
		Default = 1
	})
	AutoFire = GunModifications:CreateToggle({
		Name = 'Auto Fire',
		Default = true
	})
	
end)