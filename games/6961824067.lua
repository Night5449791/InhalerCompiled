local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local collectionService = game:GetService('CollectionService')

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local whitelist = vape.Libraries.whitelist

local friends = vape.Categories.Friends
local useFriends = friends.Options['Use friends']
local recolorFriends = friends.Options['Recolor visuals']
local friendsColor = friends.Options['Friends color']
local teamsByServer = vape.Settings.Modules.Options['Teams by server']
local useTeamColor = vape.Settings.Modules.Options['Use team color']

local ftap = {
	remotes = nil,
	toys = {},
	grabbed = {},
}

local function isFriend(plr, recolor)
	if not useFriends.Enabled then return nil end

	local friend = table.find(friends.ListEnabled, plr.Name) and true
	if recolor then
		friend = friend and recolorFriends.Enabled
	end

	return friend
end

local function notif(...)
	return vape:CreateNotification(...)
end

function ftap.isGrabbed(ent)
	if not ent or not ent.Character then return false end

	local ragdolled = ent.Character:FindFirstChild('Humanoid')
	ragdolled = ragdolled and ragdolled:FindFirstChild('Ragdolled')

	return ragdolled ~= nil and ragdolled.Value == true
end

function ftap.isToy(obj)
	if typeof(obj) ~= 'Instance' then return false end

	return obj:IsA('Model') and (obj:GetAttribute('ToyName') ~= nil or obj.Name:find('SpawnedInToys') ~= nil)
end

function ftap.resetRemotes()
	ftap.remotes = nil
	table.clear(ftap.toys)
	table.clear(ftap.grabbed)
end

run(function()
	local function grabRemotes()
		local menuToys = replicatedStorage:WaitForChild('MenuToys', 15)
		local grabEvents = replicatedStorage:WaitForChild('GrabEvents', 15)
		local characterEvents = replicatedStorage:WaitForChild('CharacterEvents', 15)

		if not menuToys or not grabEvents then return end

		ftap.remotes = {
			spawnToy = menuToys:FindFirstChild('SpawnToyRemoteFunction'),
			canSpawnToy = menuToys:FindFirstChild('CanSpawnToy'),
			destroyToy = menuToys:FindFirstChild('DestroyToy'),
			setNetworkOwner = grabEvents:FindFirstChild('SetNetworkOwner'),
			grabPart = grabEvents:FindFirstChild('GrabPart'),
			plusGrabPart = grabEvents:FindFirstChild('PlusGrabPart'),
			endGrabEarly = grabEvents:FindFirstChild('EndGrabEarly'),
			createGrabLine = grabEvents:FindFirstChild('CreateGrabLine'),
			extendGrabLine = grabEvents:FindFirstChild('ExtendGrabLine'),
			ragdoll = characterEvents and characterEvents:FindFirstChild('RagdollRemote'),
			struggle = characterEvents and characterEvents:FindFirstChild('Struggle'),
		}
	end

	task.spawn(function()
		repeat
			if not ftap.remotes then grabRemotes() end
			if not ftap.remotes then
				task.wait(1)
			end
		until ftap.remotes or not vape.Loaded
	end)

	local function trackToy(obj)
		if not obj:IsA('Model') then return end
		ftap.toys[obj] = true
	end

	local function untrackToy(obj)
		ftap.toys[obj] = nil
	end

	for _, tag in {'Toy', 'SpawnedToy'} do
		for _, obj in collectionService:GetTagged(tag) do
			trackToy(obj)
		end

		vape:Clean(collectionService:GetInstanceAddedSignal(tag):Connect(trackToy))
		vape:Clean(collectionService:GetInstanceRemovedSignal(tag):Connect(untrackToy))
	end
end)

function ftap.plot()
	return workspace:FindFirstChild(lplr.Name .. 'SpawnedInToys')
end

function ftap.spawnToy(toy, position)
	if not ftap.remotes or not ftap.remotes.spawnToy then return false end
	if not toy or toy == '' then return false end

	local suc = pcall(function()
		ftap.remotes.spawnToy:InvokeServer(toy, position or ftap.plot() or Vector3.zero, Vector3.zero)
	end)

	return suc
end

function ftap.destroyToy(obj)
	if not ftap.remotes or not ftap.remotes.destroyToy then return false end
	if not obj then return false end

	return pcall(function()
		ftap.remotes.destroyToy:FireServer(obj)
	end)
end

function ftap.setOwner(part, camera)
	if not ftap.remotes or not ftap.remotes.setNetworkOwner then return false end
	if not part then return false end

	return pcall(function()
		ftap.remotes.setNetworkOwner:FireServer(part, camera or gameCamera.CFrame)
	end)
end

local function updateVelocity(ent)
	if not ent.Character then return end

	local humanoid = ent.Humanoid
	if humanoid then
		humanoid.PlatformStand = false
	end
end

vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))

entitylib.targetCheck = function(ent)
	if ent == entitylib.character then return false end
	if ent.Player and isFriend(ent.Player) then return false end

	if ent.Player then
		local level, attackable = whitelist:get(ent.Player)
		if level > 0 and not attackable then return false end
	end

	return true
end

entitylib.isVulnerable = function(ent)
	return ent.Health > 0
end

entitylib.getEntityColor = function(ent)
	if ent.Player then
		local friend = isFriend(ent.Player, true)
		if friend then
			return friendsColor.Value
		end
	end

	return nil
end

entitylib.start()

vape:Clean(ftap.resetRemotes)

for _, module in {'AutoClicker', 'TriggerBot', 'HitBoxes', 'Killaura', 'Jesus', 'AutoRejoin', 'Disabler', 'MurderMystery', 'Parkour', 'Wallhop', 'Reach'} do
	vape:Remove(module)
end


run(function()
	local FlingAura
	
	FlingAura = vape.Categories.Blatant:CreateModule({
		Name = 'Fling Aura',
		Function = function(callback)
			if callback then
				local range = FlingAura.Options['Range']
				local speed = FlingAura.Options['Speed']
				local setOwner = ftap.remotes and ftap.remotes.setNetworkOwner
	
				repeat
					setOwner = ftap.remotes and ftap.remotes.setNetworkOwner
					local origin = entitylib.character.RootPart.Position
					local reach = range.Value
	
					for _, ent in entitylib.List do
						if not FlingAura.Enabled then break end
						if not ent.Targetable or not ent.RootPart then continue end
						if (ent.RootPart.Position - origin).Magnitude > reach then continue end
	
						local root = ent.RootPart
						pcall(function()
							if setOwner then setOwner:FireServer(root, gameCamera.CFrame) end
							local power = speed.Value * 1e5
							root.AssemblyLinearVelocity = Vector3.new(power, power, power)
							root.AssemblyAngularVelocity = Vector3.new(power, power, power)
						end)
					end
	
					task.wait(0.1)
				until not FlingAura.Enabled
			end
		end
	})
	FlingAura:CreateSlider({
		Name = 'Range',
		Min = 5,
		Max = 120,
		Default = 30,
		Suffix = 'studs'
	})
	FlingAura:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 100,
		Default = 50
	})
	
end)

run(function()
	local GamepassReach
	
	GamepassReach = vape.Categories.Blatant:CreateModule({
		Name = 'Gamepass Reach',
		Function = function(callback)
			if callback then
				local flag
	
				local function apply()
					if not entitylib.isAlive then return end
					if not flag then
						flag = Instance.new('BoolValue')
						flag.Name = 'FartherReach'
						flag.Parent = lplr
					end
	
					flag.Value = true
				end
	
				apply()
	
				GamepassReach:Clean(function()
					if flag then
						flag:Destroy()
						flag = nil
					end
				end)
	
				repeat
					apply()
					task.wait(0.5)
				until not GamepassReach.Enabled
			end
		end
	})
	
end)

run(function()
	local LongGrab
	
	local function grabPart(part)
		local remotes = ftap.remotes
		if not remotes or not remotes.createGrabLine then return false end
		if not part then return false end
	
		return pcall(function()
			remotes.createGrabLine:FireServer(part, part.CFrame)
		end)
	end
	
	LongGrab = vape.Categories.Blatant:CreateModule({
		Name = 'Long Grab',
		Function = function(callback)
			if callback then
				local held = false
				local range = LongGrab.Options['Range']
	
				LongGrab:Clean(LongGrab.Options['Bind'].Triggered:Connect(function(isDown)
					held = isDown
				end))
	
				repeat
					if held then
						local target = entitylib.EntityPosition({
							Players = true,
							Part = 'RootPart',
							Range = range.Value
						})
	
						if target and target.RootPart then
							grabPart(target.RootPart)
						end
					end
	
					task.wait(0.15)
				until not LongGrab.Enabled
			end
		end
	})
	LongGrab:CreateSlider({
		Name = 'Range',
		Min = 5,
		Max = 300,
		Default = 80,
		Suffix = 'studs'
	})
	LongGrab:CreateBind({
		Name = 'Bind',
		Default = {'E'},
		Hold = true
	})
	
end)

run(function()
	local PlayerFling
	
	local spinCFrame = CFrame.new(150, 307, 332)
	
	local function primaryOf(obj)
		if not obj then return nil end
	
		if obj:IsA('BasePart') then return obj end
		if obj.PrimaryPart then return obj.PrimaryPart end
	
		return obj:FindFirstChild('HumanoidRootPart')
			or obj:FindFirstChild('Head')
			or obj:FindFirstChild('Torso')
			or obj:FindFirstChildWhichIsA('BasePart')
	end
	
	local function flingTarget(ent)
		local remotes = ftap.remotes
		if not remotes or not remotes.setNetworkOwner then return false end
	
		local character = ent and ent.Character
		local root = character and (ent.RootPart or character:FindFirstChild('HumanoidRootPart'))
		if not root then return false end
	
		pcall(function()
			remotes.setNetworkOwner:FireServer(root, gameCamera.CFrame)
			root.AssemblyLinearVelocity = Vector3.new(0, 1e7, 0)
			root.AssemblyAngularVelocity = Vector3.new(1e7, 1e7, 1e7)
		end)
	
		return true
	end
	
	PlayerFling = vape.Categories.Blatant:CreateModule({
		Name = 'Player Fling',
		Function = function(callback)
			if callback then
				local range = PlayerFling.Options['Range']
				local auto = PlayerFling.Options['Auto']
				local immediate = PlayerFling.Options['Instant']
	
				repeat
					local target = entitylib.EntityPosition({
						Players = true,
						Part = 'RootPart',
						Range = range.Value
					})
	
					if target then
						if immediate.Enabled then
							flingTarget(target)
						else
							repeat
								flingTarget(target)
								task.wait(0.1)
							until not PlayerFling.Enabled or not auto.Enabled or not target.Character
						end
					end
	
					task.wait(0.1)
				until not PlayerFling.Enabled
			end
		end
	})
	PlayerFling:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 200,
		Default = 60,
		Suffix = 'studs'
	})
	PlayerFling:CreateToggle({
		Name = 'Auto',
		Default = true,
		Tooltip = 'Keep flinging whoever comes into range without holding a key'
	})
	PlayerFling:CreateToggle({
		Name = 'Instant',
		Default = false,
		Tooltip = 'One throw instead of a continuous loop'
	})
	
end)

run(function()
	local ToyESP
	
	local hue, sat, val = 0.5, 1, 1
	local boxes = {}
	
	local function paint()
		local colour = Color3.fromHSV(hue, sat, val)
		for _, box in boxes do
			box.Color3 = colour
		end
	end
	
	ToyESP = vape.Categories.Render:CreateModule({
		Name = 'Toy ESP',
		Function = function(callback)
			if callback then
				local function partOf(obj)
					if obj:IsA('BasePart') then return obj end
	
					return obj.PrimaryPart
						or obj:FindFirstChild('Hitbox')
						or obj:FindFirstChildWhichIsA('BasePart')
				end
	
				local function add(obj)
					if not ToyESP.Enabled or boxes[obj] then return end
	
					local part = partOf(obj)
					if not part then return end
	
					local box = Instance.new('BoxHandleAdornment')
					box.Size = part.Size
					box.Adornee = part
					box.AlwaysOnTop = true
					box.ZIndex = 5
					box.Transparency = 0.5
					box.Color3 = Color3.fromHSV(hue, sat, val)
					box.Parent = vape.gui
					boxes[obj] = box
				end
	
				for obj in ftap.toys do
					add(obj)
				end
	
				ToyESP:Clean(collectionService:GetInstanceAddedSignal('Toy'):Connect(add))
				ToyESP:Clean(collectionService:GetInstanceAddedSignal('SpawnedToy'):Connect(add))
	
				repeat
					task.wait(1)
	
					for obj, box in boxes do
						if not obj.Parent then
							box:Destroy()
							boxes[obj] = nil
						end
					end
				until not ToyESP.Enabled
	
				for _, box in boxes do
					box:Destroy()
				end
	
				table.clear(boxes)
			end
		end
	})
	ToyESP:CreateColorSlider({
		Name = 'Color',
		Default = 500,
		DefaultOpacity = 100,
		Function = function(h, s, v)
			hue, sat, val = h, s, v
			if ToyESP.Enabled then paint() end
		end
	})
	
end)

run(function()
	local ToySpawner
	
	local TOYS = {
		'Campfire',
		'CreatureBlobman',
		'CreatureRobot',
		'CupMugBrown',
		'FoodCoconut',
		'InstrumentWoodwindOcarina',
		'NinjaShuriken',
		'PalletLightBrown',
		'TractorGreen',
		'FlyingToyHelicopter',
		'FlyingToyPlane',
		'FlyingToyUfo'
	}
	
	ToySpawner = vape.Categories.Utility:CreateModule({
		Name = 'Toy Spawner',
		Function = function(callback)
			if callback then
				local toy = ToySpawner.Options['Toy']
				local bind = ToySpawner.Options['Bind']
				local distance = ToySpawner.Options['Distance']
	
				local function spawn()
					if not entitylib.isAlive then return end
	
					local root = entitylib.character.RootPart
					if not root then return end
	
					local position = root.Position + (gameCamera.CFrame.LookVector * distance.Value)
	
					if not ftap.spawnToy(toy.Value, position) then
						notif('Toy Spawner', 'The game has not loaded its spawn remote yet', 3, 'warning')
					end
				end
	
				ToySpawner:Clean(bind.Triggered:Connect(function(isDown)
					if isDown then spawn() end
				end))
	
				repeat
					task.wait()
				until not ToySpawner.Enabled
			end
		end
	})
	ToySpawner:CreateDropdown({
		Name = 'Toy',
		List = TOYS,
		Default = 'TractorGreen'
	})
	ToySpawner:CreateSlider({
		Name = 'Distance',
		Min = 2,
		Max = 50,
		Default = 8,
		Suffix = 'studs'
	})
	ToySpawner:CreateBind({
		Name = 'Bind',
		Default = {'F'},
		Tooltip = 'Spawn the selected toy where you are looking'
	})
	
end)