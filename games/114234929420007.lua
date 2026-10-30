local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local httpService = game:GetService('HttpService')

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local whitelist = vape.Libraries.whitelist

-- the option objects are created once when the gui loads and profiles only flip Enabled, so
-- they are resolved here instead of hashing the same three names on every target check
local friends = vape.Categories.Friends
local useFriends = friends.Options['Use friends']
local recolorFriends = friends.Options['Recolor visuals']
local friendsColor = friends.Options['Friends color']
local teamsByServer = vape.Settings.Modules.Options['Teams by server']
local useTeamColor = vape.Settings.Modules.Options['Use team color']

-- BloxStrike (universe 7633926880, this base is the root place 114234929420007) is a
-- client authoritative 5v5 shooter that also rotates into a zombies survival mode:
--   Workspace.Characters   every living model, players and bots alike (Folder Terrorists,
--                          Folder Counter-Terrorists, Folder Hostages, plus loose models)
--   Workspace.Debris       recycled ragdolls that still carry the Bot attribute
--   NetworkRemotes         Inventory.ShootWeapon / Inventory.BuyMenuPurchase / Melee.MeleeAttack
--   Remotes.BAC            the anti cheat endpoint
-- Players and bot models store their side in a 'Team' attribute ('Counter-Terrorists' or
-- 'Terrorists') and their health in 'Health' / 'MaxHealth' / 'Dead' attributes. There is no
-- Team service at all, and remote characters are presentation rigs without a Humanoid, so
-- both the team gate and the entity library have to read the attributes instead.
local bloxstrike = {
	CharacterRemote = nil,
	Inventory = nil,
	Melee = nil,
	Proxy = nil,
	Remotes = nil,
	Resolver = nil
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

function bloxstrike.character(obj)
	if typeof(obj) ~= 'Instance' then return end
	if obj:IsA('Player') then return obj.Character end
	if obj:IsA('Model') then return obj end
end

function bloxstrike.team(obj)
	return obj and obj:GetAttribute('Team') or nil
end

-- the health of a player lives on both the player and his character, a bot only has the
-- character copy, and a pooled ragdoll keeps the values of the bot it belonged to; the
-- character is resolved once for both numbers because every health update asks for both
local function vitals(obj)
	local character = bloxstrike.character(obj)
	local isPlayer = typeof(obj) == 'Instance' and obj:IsA('Player')
	local health = character and character:GetAttribute('Health')
	local maxHealth = character and character:GetAttribute('MaxHealth')

	if typeof(health) ~= 'number' then
		health = isPlayer and obj:GetAttribute('Health') or nil
	end

	if typeof(maxHealth) ~= 'number' then
		maxHealth = isPlayer and obj:GetAttribute('MaxHealth') or nil
	end

	return typeof(health) == 'number' and health or 0, typeof(maxHealth) == 'number' and maxHealth or 100
end

function bloxstrike.health(obj)
	local health = vitals(obj)
	return health
end

function bloxstrike.maxHealth(obj)
	local _, maxHealth = vitals(obj)
	return maxHealth
end

function bloxstrike.dead(obj)
	local character = bloxstrike.character(obj)
	return character ~= nil and character:GetAttribute('Dead') == true
end

-- the equipped item is serialized into a JSON attribute, and it is the only place that holds
-- the Identifier the shoot and melee packets are keyed on
function bloxstrike.equipped(plr)
	local raw = typeof(plr) == 'Instance' and plr:IsA('Player') and plr:GetAttribute('CurrentEquipped') or nil
	if type(raw) ~= 'string' then return end

	local suc, data = pcall(httpService.JSONDecode, httpService, raw)
	if not suc or type(data) ~= 'table' then return end
	return data
end

run(function()
	local remotes = replicatedStorage:WaitForChild('NetworkRemotes', 30)
	bloxstrike.Remotes = remotes
	if not remotes then return end

	bloxstrike.Inventory = remotes:FindFirstChild('Inventory')
	bloxstrike.Melee = remotes:FindFirstChild('Melee')
	bloxstrike.CharacterRemote = remotes:FindFirstChild('Character')
end)

run(function()
	local components = replicatedStorage:WaitForChild('Components', 30)
	local common = components and components:WaitForChild('Common', 30)
	local module = common and common:FindFirstChild('CharacterResolver')
	if not module then return end

	local suc, resolver = pcall(require, module)
	bloxstrike.Resolver = suc and resolver or nil
end)

-- every remote is used through Database.Security.Remotes, which returns proxy tables with a
-- Send method on top of NetworkRemotes (it encodes the payload before the FireServer), so
-- anything sent from here has to go through the same proxy instead of the RemoteEvent
run(function()
	local database = replicatedStorage:WaitForChild('Database', 30)
	local security = database and database:WaitForChild('Security', 30)
	local module = security and security:FindFirstChild('Remotes')
	if not module then return end

	local suc, proxy = pcall(require, module)
	bloxstrike.Proxy = suc and proxy or nil
end)

function bloxstrike.send(section, name, packet)
	local proxy = bloxstrike.Proxy
	local remote = proxy and proxy[section] and proxy[section][name]
	if not (remote and typeof(remote.Send) == 'function') then return false end

	local suc = pcall(remote.Send, packet)
	return suc
end

-- the client only keeps the characters it currently renders in Workspace.Characters. Every
-- character it culls (behind you, across the map, or dead) is reparented into
-- ReplicatedStorage._PVS_CulledCharacters with its position and attributes left intact, so both
-- containers are tracked and a character moving between them must keep its entity: dropping it
-- on the move is what makes the esp and the aura appear and disappear on their own.
-- Both containers are looked up on every PVS border crossing (measured at ~7 crossings a
-- second on a full server), and FindFirstChild is a children scan, so the instance is kept
-- and only re-resolved when the cached one has been removed from the tree (map change).
local charactersFolder
local culledFolder

local function getCharacters()
	local folder = charactersFolder
	if folder and folder.Parent then return folder end

	charactersFolder = workspace:FindFirstChild('Characters')
	return charactersFolder
end

local function getCulled()
	local folder = culledFolder
	if folder and folder.Parent then return folder end

	culledFolder = replicatedStorage:FindFirstChild('_PVS_CulledCharacters')
	return culledFolder
end

local function hosted(char)
	local characters = getCharacters()
	if characters and char:IsDescendantOf(characters) then return true end

	local culled = getCulled()
	return culled ~= nil and char:IsDescendantOf(culled)
end

local function rendered(char)
	local characters = getCharacters()
	return characters ~= nil and char:IsDescendantOf(characters)
end

-- a parked character is one the game stopped simulating: its rig is anchored in the PVS pool and
-- no new transform ever arrives, so drawing it would only paint a frozen corpse of a box. The
-- entity is kept out of entitylib.List (esp, aura and aim stop seeing it) but stays alive with
-- its connections, so the same object is put back when the game loads that part of the map again.
-- This is always on: culled characters are never drawn at their last known position.
entitylib.Culled = {}

local function park(char)
	local entity, index = entitylib.getEntity(char)
	if not entity or not index then return end

	table.remove(entitylib.List, index)
	entitylib.Culled[char] = entity
	entitylib.Events.EntityRemoved:Fire(entity)
end

local function unpark(char)
	local entity = entitylib.Culled[char]
	if not entity then return end

	entitylib.Culled[char] = nil
	if table.find(entitylib.List, entity) then return end

	table.insert(entitylib.List, entity)
	entitylib.Events.EntityAdded:Fire(entity)
end

-- the same disconnect pass runs when a parked entity is thrown away and when the library
-- stops, so it is one function instead of two copies
local function dropConnections(entity)
	for _, connection in entity.Connections do
		connection:Disconnect()
	end

	table.clear(entity.Connections)
end

local function discard(char)
	local entity = entitylib.Culled[char]
	if not entity then
		entitylib.removeEntity(char)
		return
	end

	entitylib.Culled[char] = nil
	dropConnections(entity)
end

run(function()
	local originalStop = entitylib.stop

	entitylib.stop = function()
		for _, entity in entitylib.Culled do
			dropConnections(entity)
		end

		table.clear(entitylib.Culled)
		originalStop()
	end
end)

-- parked entities are not in the list, so the library's own removal would leave them connected
-- and a refresh would end up with two entities on the same character
run(function()
	local originalRemove = entitylib.removeEntity

	entitylib.removeEntity = function(char, isLocal)
		if char and entitylib.Culled[char] then
			discard(char)
			return
		end

		return originalRemove(char, isLocal)
	end
end)

-- everything that can be shot at is a model under Workspace.Characters, bots included: they
-- are not in Players, they carry Bot = true, and the recycled ragdolls in Workspace.Debris
-- carry the same attributes, so those are skipped before anything is registered
local function registerCharacter(char)
	if not (typeof(char) == 'Instance' and char:IsA('Model')) then return end
	if char:GetAttribute('RagdollReady') or char:GetAttribute('RagdollStaged') then return end
	if char.Parent and char.Parent.Name == 'Debris' then return end
	if entitylib.getEntity(char) or entitylib.Culled[char] or entitylib.EntityThreads[char] then return end

	-- the game keeps its own player <-> character map, so a character is resolved the way it
	-- does: Player.Character first, then PresentationOwnerUserId, then CharacterResolver. A
	-- model that resolves to nothing is a bot and is registered as an NPC.
	local plr = playersService:GetPlayerFromCharacter(char)
	if not plr then
		local userId = char:GetAttribute('PresentationOwnerUserId')
		if typeof(userId) == 'number' then
			plr = playersService:GetPlayerByUserId(userId)
		end
	end

	if not plr and bloxstrike.Resolver then
		local suc, found = pcall(bloxstrike.Resolver.getPlayerFromCharacter, char)
		plr = suc and found or nil
	end

	entitylib.addEntity(char, plr)
end

local watchContainer
local ParkTokens = {}

local function scanContainer(container)
	for _, child in container:GetChildren() do
		if child:IsA('Folder') then
			scanContainer(child)
		else
			registerCharacter(child)
		end
	end
end

watchContainer = function(container)
	table.insert(entitylib.Connections, container.ChildAdded:Connect(function(child)
		if child:IsA('Folder') then
			watchContainer(child)
			scanContainer(child)
			return
		end

		-- the rig parts are a moment behind the reparent, but the signal thread does not have
		-- to sit through it: the unpark below is independent of the rig being complete
		task.delay(0.1, registerCharacter, child)

		if rendered(child) then
			-- coming back cancels a park that was still waiting out the debounce
			ParkTokens[child] = nil
			unpark(child)
		end
	end))

	table.insert(entitylib.Connections, container.ChildRemoved:Connect(function(child)
		if not child:IsA('Model') then return end

		-- the model may only have moved into or out of the PVS pool, so give the reparent a
		-- frame and check where it landed before the entity is thrown away
		task.defer(function()
			if rendered(child) then
				ParkTokens[child] = nil
				unpark(child)
				return
			end

			if not hosted(child) then
				ParkTokens[child] = nil
				discard(child)
				return
			end

			-- a character that keeps crossing the PVS border would otherwise add and drop its
			-- esp drawings every frame, so the park only lands after it stayed out for a moment
			local token = {}
			ParkTokens[child] = token
			task.delay(0.5, function()
				if ParkTokens[child] ~= token then return end
				ParkTokens[child] = nil

				if rendered(child) then
					unpark(child)
				elseif hosted(child) then
					park(child)
				else
					discard(child)
				end
			end)
		end)
	end))
end

-- remote characters are presentation rigs (AnimationController only), so the framework gets a
-- stand in that answers the two fields the entity library and the render modules read
local function standInHumanoid(char, plr)
	local target = plr or char
	local health, maxHealth = vitals(target)

	return {
		Health = health,
		MaxHealth = maxHealth,
		GetState = function()
			return Enum.HumanoidStateType.Running
		end,
		MoveDirection = Vector3.zero,
		WalkSpeed = 0,
		JumpPower = 0,
		HipHeight = 0
	}
end

-- entitylib.getUpdateConnections is not overridden: the only caller is the library's own
-- addEntity, which this file replaces below, so the signals this product needs are the ones
-- addEntity connects itself

entitylib.addEntity = function(char, plr, teamfunc, spawntime)
	if not char then return end

	-- task.spawn runs the body right away and it only yields while the rig parts are missing, so
	-- a body that finished on this tick has to be dropped instead of stored back as a dead thread
	local thread = task.spawn(function()
		local root = char:FindFirstChild('HumanoidRootPart') or char:WaitForChild('HumanoidRootPart', 10)
		if not root then
			entitylib.EntityThreads[char] = nil
			return
		end

		local head = char:FindFirstChild('Head') or root
		local humanoid = char:FindFirstChildOfClass('Humanoid')
		local standIn = humanoid == nil and standInHumanoid(char, plr) or nil
		local target = plr or char
		local health, maxHealth = vitals(target)
		local entity = {
			Character = char,
			Connections = {},
			Health = health,
			Head = head,
			HipHeight = 3,
			Humanoid = humanoid or standIn,
			HumanoidRootPart = root,
			MaxHealth = maxHealth,
			NPC = plr == nil,
			Player = plr,
			RootPart = root,
			SpawnTime = spawntime or 0,
			StandIn = standIn,
			Team = bloxstrike.team(char) or bloxstrike.team(plr),
			TeamCheck = teamfunc
		}

		if plr == lplr then
			entitylib.character = entity
			entitylib.isAlive = not bloxstrike.dead(char) and entity.Health > 0
			entitylib.Events.LocalAdded:Fire(entity)

			-- the local rig really does have a Humanoid, so only the entity copy is touched
			for _, name in {'Health', 'Dead'} do
				table.insert(entity.Connections, char:GetAttributeChangedSignal(name):Connect(function()
					entity.Health = bloxstrike.health(char)
					entitylib.isAlive = not bloxstrike.dead(char)
				end))
			end
		else
			entity.Targetable = entitylib.targetCheck(entity)

			local function updateHealth()
				local health, maxHealth = vitals(target)
				entity.Health = health
				entity.MaxHealth = maxHealth

				if standIn then
					standIn.Health = entity.Health
					standIn.MaxHealth = entity.MaxHealth
				end

				entitylib.Events.EntityUpdated:Fire(entity)
			end

			-- health changes on every hit, so it only refreshes the values; the team gate is the
			-- part that runs the friend and whitelist lookups and those only change on death or
			-- a side swap
			local function updateGate()
				updateHealth()
				entity.Team = bloxstrike.team(char) or bloxstrike.team(plr)
				entity.Targetable = entitylib.targetCheck(entity)
			end

			for _, name in {'Health', 'MaxHealth'} do
				table.insert(entity.Connections, char:GetAttributeChangedSignal(name):Connect(updateHealth))
			end

			for _, name in {'Dead', 'Team'} do
				table.insert(entity.Connections, char:GetAttributeChangedSignal(name):Connect(updateGate))
			end

			if plr then
				for _, name in {'Dead', 'Team'} do
					table.insert(entity.Connections, plr:GetAttributeChangedSignal(name):Connect(updateGate))
				end
			end

			-- a character that enters the game outside of Workspace.Characters is already culled
			-- by the game, so it goes straight into the parked pool instead of the drawable list
			if rendered(char) then
				table.insert(entitylib.List, entity)
				entitylib.Events.EntityAdded:Fire(entity)
			else
				entitylib.Culled[char] = entity
			end
		end

		entitylib.EntityThreads[char] = nil
	end)

	if thread and coroutine.status(thread) ~= 'dead' then
		entitylib.EntityThreads[char] = thread
	end
end

-- the library default reads Player.Team and counts Team:GetPlayers(), neither of which exists
-- in this game, so the side is compared through the attribute that players and bots share
entitylib.targetCheck = function(entity)
	if entity.TeamCheck then
		return entity:TeamCheck()
	end

	-- dead players lose their Team attribute here, so without this a corpse would come back as
	-- targetable for everyone
	if entity.Health <= 0 then return false end

	if entity.Player then
		if isFriend(entity.Player) then return false end
		if not select(2, whitelist:get(entity.Player)) then return false end
	end

	-- mirror the game's own isEnemy (Controllers/ESPController): Deathmatch is free-for-all, and
	-- a target whose team is neither Terrorists nor Counter-Terrorists (nil during warmup) is not
	-- a valid enemy either
	if teamsByServer.Enabled then
		if workspace:GetAttribute('Gamemode') == 'Deathmatch' then return true end

		local myTeam = bloxstrike.team(lplr)
		if entity.Team == 'Terrorists' or entity.Team == 'Counter-Terrorists' then
			return myTeam ~= entity.Team
		end

		return false
	end

	return true
end

entitylib.addPlayer = function(plr)
	if entitylib.PlayerConnections[plr] then return end

	-- the model is rebuilt on every death, and the character is a custom presentation model, so
	-- the entity is thrown away and rebuilt instead of being updated in place
	entitylib.PlayerConnections[plr] = {
		plr.CharacterAdded:Connect(function(char)
			task.wait(0.1)
			entitylib.refreshEntity(char, plr, os.clock() + 0.4)
		end),
		plr.CharacterRemoving:Connect(function(char)
			entitylib.removeEntity(char, plr == lplr)
		end),
		plr:GetAttributeChangedSignal('Team'):Connect(function()
			if plr == lplr then
				-- refresh() would remove and re-add every entity just to re-run the team gate,
				-- which drops and recreates every esp drawing on each side swap
				for _, entity in entitylib.List do
					entity.Targetable = entitylib.targetCheck(entity)
				end

				return
			end

			local entity = entitylib.getEntity(plr)
			if not entity then return end

			entity.Team = bloxstrike.team(plr)
			entity.Targetable = entitylib.targetCheck(entity)
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

	local characters = getCharacters()
	if characters then
		watchContainer(characters)
	end

	local culled = getCulled()
	if culled then
		watchContainer(culled)
	else
		table.insert(entitylib.Connections, replicatedStorage.ChildAdded:Connect(function(child)
			if child.Name ~= '_PVS_CulledCharacters' then return end

			watchContainer(child)
			scanContainer(child)
		end))
	end

	for _, plr in playersService:GetPlayers() do
		entitylib.addPlayer(plr)
	end

	if characters then
		scanContainer(characters)
	end

	if culled then
		scanContainer(culled)
	end

	local localCharacter = lplr.Character
	if localCharacter and not entitylib.character then
		entitylib.addEntity(localCharacter, lplr)
	end

	table.insert(entitylib.Connections, lplr.CharacterAdded:Connect(function(char)
		task.wait(0.1)
		entitylib.addEntity(char, lplr)
	end))

	entitylib.Running = true
end

run(function()
	entitylib.getEntityColor = function(ent)
		if not (ent.Player and useTeamColor.Enabled) then return end
		if isFriend(ent.Player, true) then
			return Color3.fromHSV(friendsColor.Hue, friendsColor.Sat, friendsColor.Value)
		end

		local team = ent.Team or bloxstrike.team(ent.Player)
		if team == 'Terrorists' then
			return Color3.fromRGB(214, 163, 74)
		elseif team == 'Counter-Terrorists' then
			return Color3.fromRGB(82, 148, 226)
		end
	end
end)

vape.Libraries.bloxstrike = bloxstrike
vape:Clean(function()
	vape.Libraries.bloxstrike = nil
	table.clear(bloxstrike)
end)

-- the local rig is an anchored presentation model with no Humanoid, so the physics-based
-- universal Blatant modules cannot drive it; drop every one of them, plus the inapplicable
-- Combat/Utility modules
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
local OriginalCreate
local rand = Random.new()

run(function()
	local components = replicatedStorage:FindFirstChild('Components')
	local weapon = components and components:FindFirstChild('Weapon')
	local classes = weapon and weapon:FindFirstChild('Classes')
	local module = classes and classes:FindFirstChild('Bullet')
	if not module then return end

	local suc, Bullet = pcall(require, module)
	if not suc or typeof(Bullet.create) ~= 'function' then return end

	local entityMouse = entitylib.EntityMouse
	local entityPosition = entitylib.EntityPosition

	-- the shot packet is built on the client: Weapon picks the muzzle, asks Bullet:create for
	-- one {Origin, Direction, Distance, Hits} per bullet and ships Direction to the server
	-- through Inventory.ShootWeapon, which raycasts along it. Rewriting Direction where the
	-- bullet object is returned is therefore enough to move the real shot, without touching
	-- the packet layout or the sequence counters the server checks.
	local function getTarget(origin)
		-- a failed roll leaves the shot untouched, so the aim lands as often as the chance
		-- allows and the misses look like ordinary bad aim
		if rand:NextNumber(0, 100) > HitChance.Value then return end

		local targetPart = rand:NextNumber(0, 100) < HeadshotChance.Value and 'Head' or 'RootPart'
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

	-- reused every shot so the wall check does not allocate a fresh ignore table
	local ignore = {}

	-- Autofire pulls the trigger through the weapon's own shoot(): it runs the ammo,
	-- cooldown and sequence bookkeeping a mouse1 press runs, so the packet is the same one
	-- a real click produces and SilentAim still rewrites Direction inside Bullet.create.
	local weapon, hookBullet

	-- Bullet.create is handed the weapon's own bullet instance, which points back at the
	-- weapon, so a real shot refreshes the reference without a collector scan
	local function findWeapon()
		if typeof(getgc) ~= 'function' then return end

		for _, v in getgc(true) do
			if type(v) == 'table' and rawget(v, 'IsEquipped') == true and type(rawget(v, 'Identifier')) == 'string' then
				return v
			end
		end
	end

	local function currentWeapon()
		local active = weapon
		if active and rawget(active, 'IsEquipped') == true and rawget(active, 'IsDestroyed') ~= true then
			return active
		end

		-- the inventory rebuilds the weapon on a respawn or a loadout change
		weapon = findWeapon()
		return weapon
	end

	-- the trigger only goes down when there is something to hit: the closest target in
	-- range whose body the bullet can reach, wood only like the shot itself
	local gateIgnore = {}

	local function reachable()
		local localEntity = entitylib.character
		if not (entitylib.isAlive and localEntity) then return false end

		local root = localEntity.RootPart
		if not root then return false end

		local origin = root.Position
		local entity = entityPosition({
			Part = 'RootPart',
			Range = Range.Value,
			Origin = origin,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled
		})

		if not entity or not entity.RootPart then return false end

		gateIgnore[1] = localEntity.Character
		gateIgnore[2] = entity.Character

		-- the trigger only goes down on a clear line
		return entitylib.Wallcheck(origin, entity.RootPart.Position, gateIgnore) == nil
	end

	-- the look-for-a-target pass is the expensive half (an entity sweep and a raycast), so
	-- it runs on its own clock while the trigger itself is pulled every frame
	local GATE_SECONDS = 0.15

	local function autoFireLoop()
		local gateUntil, gateOk = 0, false

		repeat
			task.wait()

			-- the hook being ours is what proves this loop still belongs to a live module:
			-- a re-inject installs its own, and this copy then stops shooting for good
			if AutoFire.Enabled and SilentAim.Enabled and Bullet.create == hookBullet then
				local now = os.clock()
				if now >= gateUntil then
					gateOk = reachable()
					gateUntil = now + GATE_SECONDS
				end

				local active = gateOk and currentWeapon()
				if active then
					pcall(active.shoot, active)
				end
			end
		until not AutoFire.Enabled
	end

	hookBullet = function(self, aimingOptions, isAiming)
		-- every real shot hands the weapon over, so the autofire reference survives a respawn
		weapon = rawget(self, 'Weapon') or weapon

		local bullet = OriginalCreate(self, aimingOptions, isAiming)
		if not SilentAim.Enabled or type(bullet) ~= 'table' then return bullet end

		local origin, direction = bullet.Origin, bullet.Direction
		if typeof(origin) ~= 'Vector3' or typeof(direction) ~= 'Vector3' then return bullet end

		local entity, part = getTarget(origin)
		if not part then return bullet end

		local position = part.Position
		ignore[1] = entity.Character

		-- a clear line only: anything the ray hits keeps the shot where the player pointed it
		if entitylib.Wallcheck(origin, position, ignore) then
			return bullet
		end

		bullet.Direction = (position - origin).Unit
		if ShowTarget.Enabled then
			targetinfo.Targets[entity] = os.clock() + 1
		end

		return bullet
	end

	-- a re-inject leaves the previous chunk alive, and a hook it left installed would otherwise be
	-- captured as the "original" and wrapped a second time, which ends with create calling a
	-- function that no longer exists. The original and the last hook are kept in shared, so a
	-- later copy of this file can still tell them apart.
	local function installHook()
		if Bullet.create == hookBullet then return end

		local previous = shared.__bloxstrikeBullet
		if previous and Bullet.create == previous.Hook then
			OriginalCreate = previous.Original
		else
			OriginalCreate = Bullet.create
		end

		Bullet.create = hookBullet
		shared.__bloxstrikeBullet = {
			Hook = hookBullet,
			Original = OriginalCreate
		}
	end

	local function removeHook()
		if not OriginalCreate then return end

		local previous = shared.__bloxstrikeBullet
		if Bullet.create == hookBullet or (previous and Bullet.create == previous.Hook) then
			Bullet.create = OriginalCreate
		end

		OriginalCreate = nil
		shared.__bloxstrikeBullet = nil
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
		Tooltip = 'Moves the shot direction onto the target, the crosshair itself never moves'
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
			-- the same slider drives the entity lookup: pixels around the crosshair in
			-- Mouse mode, studs around the character in Position mode
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
		Tooltip = 'Fires while a target is in range; the weapon keeps its own ammo and fire rate',
		Function = function(callback)
			if not callback then return end

			weapon = weapon or findWeapon()
			task.spawn(autoFireLoop)
		end
	})
end)


run(function()
	local AntiFog
	local Fog
	local Smoke
	local lightingService = cloneref(game:GetService('Lighting'))
	
	-- the game ships its lighting per map as a whole property table, so the fog is not set once and
	-- forgotten: every value is written back whenever something else moves it (Lighting.FogStart and
	-- FogEnd, or the Atmosphere under Lighting), and an Atmosphere added later is caught on ChildAdded
	local FOG_PROPERTIES = {
		FogStart = 100000,
		FogEnd = 100000
	}
	
	local ATMOSPHERE_PROPERTIES = {
		Density = 0,
		Haze = 0
	}
	
	local CONNECTIONS = {}
	local saved = setmetatable({}, {__mode = 'k'})
	local locked = setmetatable({}, {__mode = 'k'})
	local smokeSaved = setmetatable({}, {__mode = 'k'})
	
	local function lock(instance, prop, value)
		local props = saved[instance]
		if not props then
			props = {}
			saved[instance] = props
		end
	
		if props[prop] == nil then
			props[prop] = instance[prop]
		end
	
		local active = locked[instance]
		if not active then
			active = {}
			locked[instance] = active
		end
	
		if active[prop] then
			return
		end
	
		active[prop] = true
	
		if instance[prop] ~= value then
			instance[prop] = value
		end
	
		table.insert(CONNECTIONS, instance:GetPropertyChangedSignal(prop):Connect(function()
			if instance[prop] ~= value then
				instance[prop] = value
			end
		end))
	end
	
	local function lockAtmosphere(atmosphere)
		for prop, value in ATMOSPHERE_PROPERTIES do
			lock(atmosphere, prop, value)
		end
	end
	
	local function startFog()
		for prop, value in FOG_PROPERTIES do
			lock(lightingService, prop, value)
		end
	
		for _, instance in lightingService:GetChildren() do
			if instance:IsA('Atmosphere') then
				lockAtmosphere(instance)
			end
		end
	
		table.insert(CONNECTIONS, lightingService.ChildAdded:Connect(function(instance)
			if instance:IsA('Atmosphere') then
				lockAtmosphere(instance)
			end
		end))
	end
	
	-- a smoke grenade is a VoxelSmoke_ folder in Workspace.Debris holding SmokeVoxel parts, which is
	-- also the two names the game's own aim assist and mobile auto shoot use to test line of sight
	local function hideSmoke(instance)
		-- named first: Debris churns with pooled ragdolls, so this runs for far more parts than the
		-- clouds it is after and the name is the cheapest thing to reject on. A plain find keeps the
		-- prefix test allocation free, where sub would build a string per part it rejects.
		if instance.Name ~= 'SmokeVoxel' or smokeSaved[instance] or not instance:IsA('BasePart') then
			return
		end
	
		local parent = instance.Parent
		if not parent or parent.Name:find('VoxelSmoke_', 1, true) ~= 1 then
			return
		end
	
		smokeSaved[instance] = {
			CanCollide = instance.CanCollide,
			CanQuery = instance.CanQuery,
			LocalTransparencyModifier = instance.LocalTransparencyModifier
		}
	
		-- the modifier keeps the cloud hidden while the game fades the part itself, and the query
		-- flag is what makes the aura and the aim casts look straight through it
		instance.CanCollide = false
		instance.CanQuery = false
		instance.LocalTransparencyModifier = 1
	end
	
	local function watchDebris(debris)
		for _, instance in debris:GetDescendants() do
			hideSmoke(instance)
		end
	
		table.insert(CONNECTIONS, debris.DescendantAdded:Connect(hideSmoke))
	end
	
	local function startSmoke()
		local debris = workspace:FindFirstChild('Debris')
		if debris then
			watchDebris(debris)
		end
	
		-- the folder goes away and comes back with the map, so a fresh one has to be picked up again
		table.insert(CONNECTIONS, workspace.ChildAdded:Connect(function(instance)
			if instance.Name == 'Debris' then
				watchDebris(instance)
			end
		end))
	end
	
	local function stop()
		for _, connection in CONNECTIONS do
			connection:Disconnect()
		end
	
		table.clear(CONNECTIONS)
		table.clear(locked)
	
		for instance, props in saved do
			if instance.Parent then
				for prop, value in props do
					if instance[prop] ~= value then
						instance[prop] = value
					end
				end
			end
		end
	
		for instance, props in smokeSaved do
			if instance.Parent then
				instance.CanCollide = props.CanCollide
				instance.CanQuery = props.CanQuery
				instance.LocalTransparencyModifier = props.LocalTransparencyModifier
			end
		end
	
		table.clear(smokeSaved)
	end
	
	local function refresh()
		stop()
	
		if Fog.Enabled then
			startFog()
		end
	
		if Smoke.Enabled then
			startSmoke()
		end
	end
	
	AntiFog = vape.Categories.Render:CreateModule({
		Name = 'AntiFog',
		Function = function(callback)
			if callback then
				refresh()
			else
				stop()
			end
		end,
		Tooltip = 'Remove fog and smoke clouds'
	})
	Fog = AntiFog:CreateToggle({
		Name = 'Fog',
		Default = true,
		Function = function()
			if AntiFog.Enabled then
				refresh()
			end
		end
	})
	Smoke = AntiFog:CreateToggle({
		Name = 'Smoke',
		Default = true,
		Function = function()
			if AntiFog.Enabled then
				refresh()
			end
		end
	})
	
end)