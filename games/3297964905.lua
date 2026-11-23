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
local WeaponData

run(function()
	if not replicatedStorage then return end

	local remoteFolder = replicatedStorage:FindFirstChild('Remotes')
	if remoteFolder then
		for _, name in {'WeaponHandler', 'HitHandler', 'BulletReplicator', 'BulletImpact', 'Hitmarker', 'ServerHitmarker', 'TakeDMGer', 'TeamChoose', 'TeamSwitchState', 'AntiExploit', 'ValidateTool', 'GetData', 'GetEssentials', 'UpdateData', 'KillFeed', 'StartGame', 'GameStateUpdater', 'LoadChar', 'CharacterReplicator', 'ServerMessage', 'VotekickPlayerInit', 'VotekickPlayerVote'} do
			local event = remoteFolder:FindFirstChild(name)
			if event then Remotes[name] = event end
		end
	end

	local weapons = replicatedStorage:FindFirstChild('Weapons')
	if weapons then
		local data = weapons:FindFirstChild('WeaponData')
		if data then WeaponData = data end
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

vape:Clean(function()
	table.clear(Remotes)
	WeaponData = nil
end)

entitylib.start()

for _, v in {'Reach', 'Jesus', 'MurderMystery', 'StaffDetector', 'FullBright', 'Health', 'FastProxPrompt', 'AnimationPlayer'} do
	vape:Remove(v)
end


run(function()
	local GunModifications
	local FireRate
	local Bloom
	local MaxBloom
	local Accuracy
	local Range
	local Recoil
	local modified = {}
	
	local function applyModule(scriptObj)
		if modified[scriptObj] then return end
	
		local suc, stats = pcall(require, scriptObj)
		if not suc or type(stats) ~= 'table' then return end
	
		local original = {
			FireRate = stats.FireRate,
			BloomPerShot = stats.BloomPerShot,
			MaxBloom = stats.MaxBloom,
			BaseAccuracy = stats.BaseAccuracy,
			Range = stats.Range
		}
		modified[scriptObj] = original
	
		stats.FireRate = FireRate.Value
		stats.BloomPerShot = Bloom.Value
		stats.MaxBloom = MaxBloom.Value
		stats.BaseAccuracy = Accuracy.Value
		stats.Range = Range.Value
	
		if type(stats.RecoilData) == 'table' then
			original.RecoilData = table.clone(stats.RecoilData)
			if Recoil.Enabled then
				for key, value in stats.RecoilData do
					if type(value) == 'number' then
						stats.RecoilData[key] = value * Recoil.Value
					end
				end
			end
		end
	end
	
	local function restore()
		for scriptObj, original in modified do
			local suc, stats = pcall(require, scriptObj)
			if suc and type(stats) == 'table' then
				for key, value in original do
					if key ~= 'RecoilData' then
						stats[key] = value
					end
				end
	
				if original.RecoilData and type(stats.RecoilData) == 'table' then
					table.clear(stats.RecoilData)
					for key, value in original.RecoilData do
						stats.RecoilData[key] = value
					end
				end
			end
		end
		table.clear(modified)
	end
	
	GunModifications = vape.Categories.Blatant:CreateModule({
		Name = 'GunModifications',
		Function = function(callback)
			if callback then
				local weapons = replicatedStorage and replicatedStorage:FindFirstChild('Weapons')
				if weapons then
					for _, folder in weapons:GetChildren() do
						if folder:IsA('Folder') then
							for _, scriptObj in folder:GetChildren() do
								if scriptObj:IsA('ModuleScript') then
									applyModule(scriptObj)
								end
							end
						end
					end
				end
			else
				restore()
			end
		end,
		Tooltip = 'Modifies local weapon handling; damage is server-side'
	})
	FireRate = GunModifications:CreateSlider({
		Name = 'Fire Rate',
		Min = 0.01,
		Max = 1,
		Default = 0.18,
		Decimal = 100
	})
	Bloom = GunModifications:CreateSlider({
		Name = 'Bloom Per Shot',
		Min = 0,
		Max = 5,
		Default = 0.52,
		Decimal = 100
	})
	MaxBloom = GunModifications:CreateSlider({
		Name = 'Max Bloom',
		Min = 0,
		Max = 10,
		Default = 1.6,
		Decimal = 10
	})
	Accuracy = GunModifications:CreateSlider({
		Name = 'Base Accuracy',
		Min = 0,
		Max = 10,
		Default = 0,
		Decimal = 10
	})
	Range = GunModifications:CreateSlider({
		Name = 'Range',
		Min = 100,
		Max = 3000,
		Default = 1000
	})
	Recoil = GunModifications:CreateSlider({
		Name = 'Recoil',
		Min = 0,
		Max = 3,
		Default = 1,
		Decimal = 10
	})
	
end)