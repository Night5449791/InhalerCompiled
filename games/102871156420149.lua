local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

-- the executor helpers live in getgenv() on this executor, not in the chunk environment, so they
-- are pulled out once and the modules read them from here
local executor = getgenv and getgenv() or _G
local getrawmetatable = getrawmetatable or executor.getrawmetatable
local setreadonly = setreadonly or executor.setreadonly
local newcclosure = newcclosure or executor.newcclosure
local restorefunction = restorefunction or executor.restorefunction
local getnamecallmethod = getnamecallmethod or executor.getnamecallmethod
local mousemoveabs = executor.mousemoveabs
local mouse1press = executor.mouse1press
local mouse1release = executor.mouse1release

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

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

local thelostfront = {
	Network = nil,
	Shot = nil
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

-- the characters are presentation models parented under one of two folders, and those folders are
-- the only thing that separates the two sides: Teams is empty, the players carry no Team and no
-- character carries a team attribute. The side is the folder itself, not its name, because the
-- game names those two folders per server.
function thelostfront.team(obj)
	local character = typeof(obj) == 'Instance' and (obj:IsA('Player') and obj.Character or obj:IsA('Model') and obj) or nil
	local folder = character and character.Parent
	if not (folder and folder.ClassName == 'Model') then return end

	return folder
end

function thelostfront.health(obj)
	local character = typeof(obj) == 'Instance' and (obj:IsA('Player') and obj.Character or obj:IsA('Model') and obj) or nil
	local humanoid = character and character:FindFirstChildOfClass('Humanoid')

	return humanoid and humanoid.Health or 0
end

function thelostfront.maxHealth(obj)
	local character = typeof(obj) == 'Instance' and (obj:IsA('Player') and obj.Character or obj:IsA('Model') and obj) or nil
	local humanoid = character and character:FindFirstChildOfClass('Humanoid')

	return humanoid and humanoid.MaxHealth or 100
end

function thelostfront.dead(obj)
	local character = typeof(obj) == 'Instance' and (obj:IsA('Player') and obj.Character or obj:IsA('Model') and obj) or nil
	if not character or not character.Parent then return true end

	return thelostfront.health(character) <= 0
end

-- the shot packet is a single buffer on ReplicatedStorage's only RemoteEvent: the weapon name is
-- a length prefixed string, then the origin and the direction as three floats each, then the
-- spread block, then the bullet uuid. Moving the direction at offset 24 is what redirects a shot
local SHOT_DIRECTION = 24

function thelostfront.shot()
	return thelostfront.Shot
end

function thelostfront.directionOf(shot)
	if typeof(shot) ~= 'buffer' or buffer.len(shot) < SHOT_DIRECTION + 12 then return end

	return Vector3.new(
		buffer.readf32(shot, SHOT_DIRECTION),
		buffer.readf32(shot, SHOT_DIRECTION + 4),
		buffer.readf32(shot, SHOT_DIRECTION + 8)
	)
end

function thelostfront.originOf(shot)
	if typeof(shot) ~= 'buffer' or buffer.len(shot) < 12 then return end

	return Vector3.new(
		buffer.readf32(shot, 12),
		buffer.readf32(shot, 16),
		buffer.readf32(shot, 20)
	)
end

function thelostfront.aim(shot, position)
	local origin = thelostfront.originOf(shot)
	if not origin or typeof(position) ~= 'Vector3' then return false end

	local direction = position - origin
	if direction.Magnitude < 0.01 then return false end

	direction = direction.Unit
	buffer.writef32(shot, SHOT_DIRECTION, direction.X)
	buffer.writef32(shot, SHOT_DIRECTION + 4, direction.Y)
	buffer.writef32(shot, SHOT_DIRECTION + 8, direction.Z)

	return true
end

-- the only RemoteEvent in ReplicatedStorage carries every client packet as one buffer, so it is
-- resolved once and the modules hook its FireServer instead of hashing the name again
run(function()
	for _, child in replicatedStorage:GetChildren() do
		if child:IsA('RemoteEvent') then
			thelostfront.Shot = child
		end
	end

	thelostfront.Network = replicatedStorage:FindFirstChild('network')
end)

-- the characters are presentation models parented under one of two folders, and those folders are
-- the only thing that separates the two sides: Teams is empty and nothing carries a team attribute
local function registerCharacter(char)
	if not (typeof(char) == 'Instance' and char:IsA('Model')) then return end
	if not char:FindFirstChildOfClass('Humanoid') then return end
	if entitylib.getEntity(char) then return end

	entitylib.addEntity(char, playersService:GetPlayerFromCharacter(char))
end

local watchModel

local function scanFolder(folder)
	for _, child in folder:GetChildren() do
		if child:IsA('Model') and child:FindFirstChildOfClass('Humanoid') then
			registerCharacter(child)
		elseif child:IsA('Model') then
			watchModel(child)
		end
	end
end

watchModel = function(model)
	table.insert(entitylib.Connections, model.ChildAdded:Connect(function(child)
		if child:IsA('Model') then
			task.delay(0.1, registerCharacter, child)
		end
	end))

	for _, child in model:GetChildren() do
		if child:IsA('Model') and not child:FindFirstChildOfClass('Humanoid') then
			scanFolder(child)
			table.insert(entitylib.Connections, child.ChildAdded:Connect(function(grandchild)
				if grandchild:IsA('Model') then
					task.delay(0.1, registerCharacter, grandchild)
				end
			end))
		end
	end
end

entitylib.targetCheck = function(entity)
	if entity.Health <= 0 then return false end

	if entity.Player then
		if isFriend(entity.Player) then return false end
		if not select(2, whitelist:get(entity.Player)) then return false end
	end

	if teamsByServer.Enabled then
		local myTeam = thelostfront.team(lplr)
		local theirTeam = thelostfront.team(entity.Character)

		if myTeam and theirTeam then
			return myTeam ~= theirTeam
		end
	end

	return true
end

entitylib.addEntity = function(char, plr, teamfunc, spawntime)
	if not char then return end

	local thread = task.spawn(function()
		local root = char:FindFirstChild('HumanoidRootPart') or char:WaitForChild('HumanoidRootPart', 10)
		if not root then
			entitylib.EntityThreads[char] = nil
			return
		end

		local humanoid = char:FindFirstChildOfClass('Humanoid')
		local head = char:FindFirstChild('Head') or root
		local torso = char:FindFirstChild('Torso') or char:FindFirstChild('UpperTorso') or root
		local entity = {
			Character = char,
			Connections = {},
			Health = humanoid and humanoid.Health or 0,
			Head = head,
			HipHeight = 3,
			Humanoid = humanoid,
			HumanoidRootPart = root,
			MaxHealth = humanoid and humanoid.MaxHealth or 100,
			NPC = plr == nil,
			Player = plr,
			RootPart = root,
			SpawnTime = spawntime or os.clock(),
			Team = thelostfront.team(char),
			TeamCheck = teamfunc,
			Torso = torso,
			UpperTorso = torso
		}

		if plr == lplr then
			entitylib.character = entity
			entitylib.isAlive = entity.Health > 0
			entitylib.Events.LocalAdded:Fire(entity)

			if humanoid then
				table.insert(entity.Connections, humanoid.HealthChanged:Connect(function(health)
					entity.Health = health
					entitylib.isAlive = health > 0
				end))
			end
		else
			entity.Targetable = entitylib.targetCheck(entity)

			if humanoid then
				table.insert(entity.Connections, humanoid.HealthChanged:Connect(function(health)
					entity.Health = health
					entitylib.Events.EntityUpdated:Fire(entity)
				end))
			end

			table.insert(entitylib.List, entity)
			entitylib.Events.EntityAdded:Fire(entity)
		end

		entitylib.EntityThreads[char] = nil
	end)

	if thread and coroutine.status(thread) ~= 'dead' then
		entitylib.EntityThreads[char] = thread
	end
end

entitylib.addPlayer = function(plr)
	if entitylib.PlayerConnections[plr] then return end

	entitylib.PlayerConnections[plr] = {
		plr.CharacterAdded:Connect(function(char)
			task.wait(0.1)
			entitylib.refreshEntity(char, plr, os.clock())
		end),
		plr.CharacterRemoving:Connect(function(char)
			entitylib.removeEntity(char, plr == lplr)
		end)
	}

	if plr.Character then
		entitylib.refreshEntity(plr.Character, plr)
	end
end

entitylib.start = function()
	if entitylib.Running then
		entitylib.stop()
	end

	entitylib.Connections = {
		playersService.PlayerAdded:Connect(entitylib.addPlayer),
		playersService.PlayerRemoving:Connect(entitylib.removePlayer),
		workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
			gameCamera = cloneref(workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera') or Instance.new('Camera'))
		end)
	}

	for _, plr in playersService:GetPlayers() do
		entitylib.addPlayer(plr)
	end

	-- the two side folders live under a model that the game names at load, so the container is
	-- walked instead of matched by name
	for _, child in workspace:GetChildren() do
		if child:IsA('Model') and not child:FindFirstChildOfClass('Humanoid') and child.Name ~= 'bodies' then
			watchModel(child)
			scanFolder(child)
		end
	end

	table.insert(entitylib.Connections, workspace.ChildAdded:Connect(function(child)
		if child:IsA('Model') and not child:FindFirstChildOfClass('Humanoid') and child.Name ~= 'bodies' then
			watchModel(child)
			scanFolder(child)
		end
	end))

	entitylib.Running = true
end

run(function()
	entitylib.getEntityColor = function(ent)
		if not (ent.Player and useTeamColor.Enabled) then return end
		if isFriend(ent.Player, true) then
			return Color3.fromHSV(friendsColor.Hue, friendsColor.Sat, friendsColor.Value)
		end

		local team = ent.Team or thelostfront.team(ent.Character)
		if team == thelostfront.team(lplr) then
			return Color3.fromRGB(82, 148, 226)
		end

		if team then
			return Color3.fromRGB(214, 163, 74)
		end
	end
end)

vape.Libraries.thelostfront = thelostfront
vape:Clean(function()
	vape.Libraries.thelostfront = nil
	table.clear(thelostfront)
end)

-- the rig has a Humanoid but no physics owned by the client, so the physics based universal
-- modules cannot drive it and are dropped
for _, v in {'AntiFall', 'DiedTP', 'Fly', 'HighJump', 'HitBoxes', 'Invisible', 'Jesus', 'Killaura', 'LongJump', 'MouseTP', 'Phase', 'Speed', 'SpinBot', 'Spider', 'Swim', 'TargetStrafe', 'Timer', 'Reach', 'AntiRagdoll'} do
	vape:Remove(v)
end

entitylib.start()


local SilentAim
local Targets
local Mode
local HitChance
local HeadshotChance
local Range
local ShowTarget
local AutoFire

local rand = Random.new()

run(function()
	local shotRemote = thelostfront.Shot
	if not shotRemote then return end

	local entityMouse = entitylib.EntityMouse
	local entityPosition = entitylib.EntityPosition

	-- the game ships its own packet serialiser, so the aim is written into the buffer the weapon
	-- already built instead of a packet of our own: origin, spread and the bullet uuid stay
	-- untouched, only the direction at offset 24 is replaced
	local ignore = {}

	local function getTarget(origin)
		if rand:NextNumber(0, 100) > HitChance.Value then return end

		local targetPart = rand:NextNumber(0, 100) < HeadshotChance.Value and 'Head' or 'Torso'
		local fromMouse = Mode.Value == 'Mouse'
		local entity = (fromMouse and entityMouse or entityPosition)({
			Part = targetPart,
			Range = Range.Value,
			MouseOrigin = fromMouse and gameCamera.ViewportSize / 2 or nil,
			Origin = fromMouse and nil or origin,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled
		})

		return entity, entity and entity[targetPart]
	end

	-- the aim only moves the packet, so the crosshair never leaves the player and the shot lands
	-- even while the camera is pointing somewhere else entirely. RemoteEvent.FireServer is a locked
	-- member, so the hook goes on the shared namecall instead and only the shot remote is touched
	local hooked = false
	local originalNamecall

	local function redirect(self, packet, ...)
		if not SilentAim.Enabled or typeof(packet) ~= 'buffer' then
			return originalNamecall(self, packet, ...)
		end

		local origin = thelostfront.originOf(packet)
		if not origin then return originalNamecall(self, packet, ...) end

		local entity, part = getTarget(origin)
		if not part then return originalNamecall(self, packet, ...) end

		local position = part.Position
		ignore[1] = entity.Character

		-- a clear line only: anything the ray hits keeps the shot where the player pointed it
		if entitylib.Wallcheck(origin, position, ignore) then
			return originalNamecall(self, packet, ...)
		end

		thelostfront.aim(packet, position)

		if ShowTarget.Enabled then
			targetinfo.Targets[entity] = os.clock() + 1
		end

		return originalNamecall(self, packet, ...)
	end

	local function hookShot(self, ...)
		if self ~= shotRemote or getnamecallmethod() ~= 'FireServer' then
			return originalNamecall(self, ...)
		end

		return redirect(self, ...)
	end

	-- the wrapper is kept in shared so a re-inject unwraps its own version instead of stacking a
	-- second one on top of a chain that would then redirect every shot twice
	local function installHook()
		if hooked then return end

		local previous = shared.__tlfsilentaim
		if previous and typeof(previous.Hook) == 'function' and typeof(restorefunction) == 'function' then
			pcall(restorefunction, getrawmetatable(game).__namecall)
		end

		originalNamecall = getrawmetatable(game).__namecall
		setreadonly(getrawmetatable(game), false)
		getrawmetatable(game).__namecall = newcclosure(hookShot)
		setreadonly(getrawmetatable(game), true)

		shared.__tlfsilentaim = {
			Hook = hookShot,
			Original = originalNamecall
		}

		hooked = true
	end

	local function removeHook()
		if not hooked then return end

		local previous = shared.__tlfsilentaim
		if previous and typeof(restorefunction) == 'function' then
			pcall(restorefunction, getrawmetatable(game).__namecall)
		else
			setreadonly(getrawmetatable(game), false)
			getrawmetatable(game).__namecall = originalNamecall
			setreadonly(getrawmetatable(game), true)
		end

		shared.__tlfsilentaim = nil
		hooked = false
	end

	-- the packet cannot be replayed: the server keys each shot on the uuid it carries, so a copy of
	-- an earlier one is dropped. Autofire therefore presses the game's own trigger, and the weapon
	-- builds a fresh packet that the hook above then redirects like any other shot
	local function fireButton()
		local playerGui = lplr:FindFirstChild('PlayerGui')
		local mobile = playerGui and playerGui:FindFirstChild('mobile')
		local weapon = mobile and mobile:FindFirstChild('weapon')

		return weapon and weapon:FindFirstChild('fire')
	end

	-- the touch buttons only exist while the game is in its mobile layout; the desktop path presses
	-- the mouse and needs no button at all. Both helpers come from the base, which is where the
	-- executor hands them out on this client
	local function trigger()
		local button = fireButton()
		if button and button.Visible and mousemoveabs and mouse1press then
			local position = button.AbsolutePosition + button.AbsoluteSize / 2

			mousemoveabs(position.X, position.Y)
			mouse1press()
			task.wait(0.05)
			if mouse1release then
				mouse1release()
			end

			return true
		end

		if mouse1press and mouse1release then
			mouse1press()
			task.wait(0.05)
			mouse1release()

			return true
		end

		return false
	end

	-- the expensive half is the entity sweep, so it runs on its own clock while the trigger itself
	-- is pulled every tick and the weapon decides the fire rate
	local GATE_SECONDS = 0.15

	local function reachable()
		local localEntity = entitylib.character
		if not (entitylib.isAlive and localEntity) then return false end

		local root = localEntity.RootPart
		if not root then return false end

		local entity = entityPosition({
			Part = 'Torso',
			Range = Range.Value,
			Origin = root.Position,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled
		})

		if not entity or not entity.Torso then return false end

		ignore[1] = localEntity.Character
		ignore[2] = entity.Character

		return entitylib.Wallcheck(root.Position, entity.Torso.Position, ignore) == nil
	end

	local function autoFireLoop()
		local gateUntil, gateOk = 0, false

		repeat
			task.wait()

			if AutoFire.Enabled and SilentAim.Enabled and hooked then
				local now = os.clock()
				if now >= gateUntil then
					gateOk = reachable()
					gateUntil = now + GATE_SECONDS
				end

				if gateOk then
					trigger()
				end
			end
		until not AutoFire.Enabled
	end

	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if callback then
				installHook()
			else
				removeHook()
			end
		end,
		Tooltip = 'Moves the shot direction onto the target inside the packet, the crosshair itself never moves'
	})

	Targets = SilentAim:CreateTargets({
		Players = true,
		NPCs = true
	})
	Mode = SilentAim:CreateDropdown({
		Name = 'Mode',
		List = {'Mouse', 'Position'},
		Tooltip = 'Mouse - looks for targets near the crosshair\nPosition - looks for the closest target around you'
	})
	HitChance = SilentAim:CreateSlider({
		Name = 'Hit Chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%',
		Tooltip = 'Chance that the shot is redirected onto the target'
	})
	HeadshotChance = SilentAim:CreateSlider({
		Name = 'Headshot Chance',
		Min = 0,
		Max = 100,
		Default = 65,
		Suffix = '%',
		Tooltip = 'Chance that the shot is aimed at the head instead of the body'
	})
	Range = SilentAim:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 1000,
		Default = 300,
		Suffix = function(val)
			if Mode.Value == 'Mouse' then
				return val == 1 and 'pixel' or 'pixels'
			end

			return val == 1 and 'stud' or 'studs'
		end
	})
	ShowTarget = SilentAim:CreateToggle({
		Name = 'Show target info'
	})
	AutoFire = SilentAim:CreateToggle({
		Name = 'Auto Fire',
		Tooltip = 'Fires while a target is in range',
		Function = function(callback)
			if not callback then return end

			task.spawn(autoFireLoop)
		end
	})
end)
