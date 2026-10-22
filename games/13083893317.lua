-- Life Sentence (Real Heat Studios). Two per player state holders instead of one:
-- <player>.Backpack.Stats is a Tool whose values are the transient ones (Downed, RagDolled,
-- Carrying, BeingCarried, Dead) and ReplicatedStorage.PlayerStats.<name> holds the persistent
-- ones (Cash, Bounty, Strength, Cop, SolitaryTime). Both are replicated for every player, which
-- is what the game's own client reads, so the product reads them instead of the attributes.
-- Teams are the real Teams service (Guards / Inmates / Escaped) and every remote lives in
-- ReplicatedStorage.Events.
local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local whitelist = vape.Libraries.whitelist
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo

local sentence = {
	Teams = {
		Guards = 'Guards',
		Inmates = 'Inmates',
		Escaped = 'Escaped'
	},
	Events = nil
}

local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local playerStatsFolder = replicatedStorage:FindFirstChild('PlayerStats')

-- ReplicatedStorage.PlayerStats.<name>, the persistent value folder of one player
function sentence.playerStats(plr)
	if not plr then return end

	playerStatsFolder = playerStatsFolder or replicatedStorage:FindFirstChild('PlayerStats')
	return playerStatsFolder and playerStatsFolder:FindFirstChild(plr.Name) or nil
end

-- the "Stats" tool, normally inside the backpack and only moved into the character when it is
-- equipped, so both parents are checked
function sentence.stats(plr)
	if not plr then return end

	local backpack = plr:FindFirstChild('Backpack')
	local stats = backpack and backpack:FindFirstChild('Stats')
	if stats then return stats end

	local character = plr.Character
	return character and character:FindFirstChild('Stats') or nil
end

-- persistent value, e.g. sentence.value(plr, 'Cash')
function sentence.value(plr, name)
	local folder = sentence.playerStats(plr)
	local value = folder and folder:FindFirstChild(name)
	if value then
		return value.Value
	end
end

-- transient value, e.g. sentence.status(plr, 'Downed')
function sentence.status(plr, name)
	local stats = sentence.stats(plr)
	local value = stats and stats:FindFirstChild(name)
	if value then
		return value.Value
	end
end

function sentence.team(plr)
	return plr and plr.Team and plr.Team.Name or nil
end

function sentence.isTeam(plr, name)
	return sentence.team(plr) == name
end

function sentence.isCop(plr)
	return sentence.value(plr, 'Cop') == true
end

function sentence.isDowned(plr)
	return sentence.status(plr, 'Downed') == true
end

function sentence.root(plr)
	local character = plr and plr.Character
	return character and character:FindFirstChild('HumanoidRootPart') or nil
end

-- ArrestPrompt / SellPrompt are ProximityPrompts parented to the target's HumanoidRootPart and
-- the game only raises their MaxActivationDistance while the target is a valid arrest target
function sentence.prompt(plr, name)
	local root = sentence.root(plr)
	return root and root:FindFirstChild(name) or nil
end

function sentence.isTarget(plr)
	if not plr or plr == lplr then return false end
	if isFriend(plr) then return false end
	if not select(2, whitelist:get(plr)) then return false end
	if vape.Settings.Modules.Options['Teams by server'].Enabled then
		local team = sentence.team(plr)
		return team ~= nil and team ~= sentence.team(lplr)
	end
	return true
end

function sentence.nearestPlayer(team, range)
	local root = sentence.root(lplr)
	if not root then return end

	local closest, distance = nil, range or math.huge
	for _, plr in playersService:GetPlayers() do
		if plr ~= lplr and (not team or sentence.isTeam(plr, team)) then
			local other = sentence.root(plr)
			if other then
				local magnitude = (other.Position - root.Position).Magnitude
				if magnitude < distance then
					closest, distance = plr, magnitude
				end
			end
		end
	end

	return closest
end

-- ReplicatedStorage.Events.<name>:FireServer, guarded because the folder is rebuilt on teleport
function sentence.fire(name, ...)
	local events = sentence.Events
	local remote = events and events:FindFirstChild(name)
	if not remote or typeof(remote.FireServer) ~= 'function' then return end

	pcall(remote.FireServer, remote, ...)
end

vape.Libraries.sentence = sentence
vape:Clean(function()
	vape.Libraries.sentence = nil
	sentence.Events = nil
end)

run(function()
	local events = replicatedStorage:FindFirstChild('Events') or replicatedStorage:WaitForChild('Events', 30)
	if vape.Loaded == nil then return end
	sentence.Events = events
end)

run(function()
	entitylib.targetCheck = function(entity, skip)
		if entity.TeamCheck then
			return entity:TeamCheck()
		end
		if entity.NPC then return true end
		return sentence.isTarget(entity.Player)
	end

	-- the downed flag decides whether a player is arrestable, so render/targeting updates on it
	entitylib.getUpdateConnections = function(entity)
		local humanoid = entity.Humanoid
		local connections = {
			humanoid:GetPropertyChangedSignal('Health'),
			humanoid:GetPropertyChangedSignal('MaxHealth')
		}

		local stats = sentence.stats(entity.Player)
		if stats then
			for _, name in {'Downed', 'Ragdolled', 'Dead'} do
				local value = stats:FindFirstChild(name)
				if value then
					table.insert(connections, value:GetPropertyChangedSignal('Value'))
				end
			end
		end

		return connections
	end

	entitylib.isVulnerable = function(entity, attackCheck, skipCheck)
		if entity.Health <= 0 then return false end
		if entity.Character:FindFirstChildWhichIsA('ForceField') then return false end
		if entity.Humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
		return entity.SpawnTime < os.clock()
	end

	entitylib.getEntityColor = function(entity)
		if not (entity.Player and vape.Settings.Modules.Options['Use team color'].Enabled) then return end
		if isFriend(entity.Player, true) then
			return Color3.fromHSV(vape.Categories.Friends.Options['Friends color'].Hue, vape.Categories.Friends.Options['Friends color'].Sat, vape.Categories.Friends.Options['Friends color'].Value)
		end

		local team = entity.Player.Team
		return team and team.TeamColor.Color or nil
	end

	entitylib.start()
end)

-- jobs, showers, store fronts and the vents are all ProximityPrompts, and the ones that matter
-- carry a hold time between one and five seconds. The hold runs client side, so zeroing it makes
-- the prompt fire on the first frame while the server still sees a normal trigger. It lives here
-- rather than in a module because there is nothing to toggle, and the hold is rewritten every
-- time SetPromptsAndBuildBoards rebuilds a board, hence the loop
local instantPrompts = {}

local function instantPrompt(prompt)
	if instantPrompts[prompt] then return end

	instantPrompts[prompt] = true
	prompt.HoldDuration = 0
end

run(function()
	for _, object in workspace:GetDescendants() do
		if object:IsA('ProximityPrompt') then
			instantPrompt(object)
		end
	end

	vape:Clean(workspace.DescendantAdded:Connect(function(object)
		if object:IsA('ProximityPrompt') then
			instantPrompt(object)
		end
	end))

	vape:Clean(task.spawn(function()
		repeat
			for prompt in instantPrompts do
				if prompt.Parent then
					if prompt.HoldDuration > 0 then
						prompt.HoldDuration = 0
					end
				else
					instantPrompts[prompt] = nil
				end
			end

			task.wait(1)
		until vape.Loaded == nil
	end))
end)

run(function()
	sessioninfo:AddItem('Cash', 0, function()
		return tostring(sentence.value(lplr, 'Cash') or 0)
	end, false)

	sessioninfo:AddItem('Bounty', 0, function()
		return tostring(sentence.value(lplr, 'Bounty') or 0)
	end, false)

	sessioninfo:AddItem('Strength', 0, function()
		return tostring(sentence.value(lplr, 'Strength') or 0)
	end, false)

	table.insert(whitelist.tagcallback, function(plr, plrtag, rich)
		if not plr or not entitylib.getEntity(plr) then return end

		if sentence.isDowned(plr) then
			table.insert(plrtag, {text = rich and '💀' or 'Downed'})
		elseif sentence.isCop(plr) then
			table.insert(plrtag, {text = rich and '🛡️' or 'Guard'})
		end
	end)
end)

for _, v in {'MurderMystery'} do
	vape:Remove(v)
end


run(function()
	local SilentAim
	local Targets
	local Mode
	local Range
	local HitChance
	local HeadshotChance
	local IgnoredScripts
	-- the previous metamethod lives in a table because this execution environment copies closure
	-- upvalues when a hook is installed, so a plain local filled in afterwards stays nil inside it
	local hook = {}
	local installed
	local rand = Random.new()
	
	-- every shot ends in workspace:Raycast(origin, direction), which the interpreter treats as a
	-- namecall, so the direction can be rewritten on the way out. Only the direction changes: the
	-- muzzle, the spread and the cooldown stay the game's, and the shot is still aimed at an enemy
	-- the crosshair already covers
	local function getTarget(origin)
		if rand.NextNumber(rand, 0, 100) > HitChance.Value then
			return
		end
	
		local part = rand.NextNumber(rand, 0, 100) < HeadshotChance.Value and 'Head' or 'RootPart'
		local entity = entitylib['Entity'..Mode.Value]({
			Range = Range.Value,
			Wallcheck = Targets.Walls.Enabled or nil,
			Part = part,
			Origin = origin,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled
		})
	
		if entity then
			targetinfo.Targets[entity] = os.clock() + 1
		end
	
		return entity, entity and entity[part], origin
	end
	
	local function raycast(args)
		if typeof(args[1]) ~= 'Vector3' or typeof(args[2]) ~= 'Vector3' then return end
		if args[3] and typeof(args[3]) ~= 'RaycastParams' then return end
	
		local entity, part, origin = getTarget(args[1])
		if not entity then return end
	
		args[2] = CFrame.lookAt(origin, part.Position).LookVector * args[2].Magnitude
	end
	
	local function namecallHook(...)
		if not hook.Active or getnamecallmethod() ~= 'Raycast' or checkcaller() then
			return hook.Method(...)
		end
	
		local caller = getcallingscript()
		if typeof(caller) == 'Instance' and caller then
			if table.find(IgnoredScripts.ListEnabled, tostring(caller)) then
				return hook.Method(...)
			end
		end
	
		local self, args = ..., {select(2, ...)}
		raycast(args)
		return hook.Method(self, unpack(args))
	end
	
	-- the hook is installed once and only its flag is flipped afterwards: restoring __namecall with
	-- restorefunction leaves the hook in place in this execution environment, and a second install
	-- would then capture our own closure as the "original" and recurse on every namecall
	local function installHook()
		if installed then return true end
		if typeof(hookmetamethod) ~= 'function' then return false end
	
		local rawMeta = getrawmetatable(game)
		if typeof(rawMeta) ~= 'table' or typeof(rawMeta.__namecall) ~= 'function' then return false end
	
		hook.Method = rawMeta.__namecall
		if hookmetamethod(game, '__namecall', namecallHook) == namecallHook then
			return false
		end
	
		installed = true
		return true
	end
	
	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if not callback then
				hook.Active = false
				return
			end
	
			if not installHook() then
				vape:CreateNotification('SilentAim', 'This executor cannot hook the namecall metamethod', 10, 'warning')
				return
			end
	
			hook.Active = true
		end,
		Tooltip = 'Moves the shot onto the closest enemy, the crosshair itself never moves'
	})
	Targets = SilentAim:CreateTargets({
		Players = true,
		Walls = true
	})
	Mode = SilentAim:CreateDropdown({
		Name = 'Mode',
		List = {'Mouse', 'Position'},
		Tooltip = 'Mouse - looks for targets around the crosshair\nPosition - looks for the closest target around you'
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
		Name = 'Hit chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	HeadshotChance = SilentAim:CreateSlider({
		Name = 'Headshot chance',
		Min = 0,
		Max = 100,
		Default = 65,
		Suffix = '%'
	})
	IgnoredScripts = SilentAim:CreateTextList({
		Name = 'Ignored scripts',
		Default = {'CameraModule'}
	})
	
end)

run(function()
	local AutoArrest
	local ArrestRange
	local ArrestDelay
	
	-- the game sells the arrest itself: every character carries an ArrestPrompt on its root part and
	-- ArrestPrompts() raises MaxActivationDistance to 10 while the local player is a cop and the
	-- target is downed. Triggering that prompt is the normal arrest, so nothing is spoofed here, the
	-- module only walks the prompt through its own hold
	AutoArrest = vape.Categories.Blatant:CreateModule({
		Name = 'AutoArrest',
		Function = function(callback)
			if not callback then return end
	
			repeat
				local root = sentence.root(lplr)
	
				if root and sentence.isCop(lplr) then
					for _, plr in playersService:GetPlayers() do
						if plr == lplr or not sentence.isDowned(plr) or not sentence.isTarget(plr) then continue end
	
						local other = sentence.root(plr)
						local prompt = sentence.prompt(plr, 'ArrestPrompt')
						if not prompt or not other then continue end
						if (other.Position - root.Position).Magnitude > ArrestRange.Value then continue end
	
						prompt.MaxActivationDistance = ArrestRange.Value
						prompt.HoldDuration = 0
						pcall(prompt.InputHoldBegin, prompt)
						task.wait()
						pcall(prompt.InputHoldEnd, prompt)
						task.wait(ArrestDelay.Value)
						break
					end
				end
	
				task.wait(0.2)
			until not AutoArrest.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Arrests downed enemies in range through their own arrest prompt'
	})
	ArrestRange = AutoArrest:CreateSlider({
		Name = 'Range',
		Min = 5,
		Max = 30,
		Default = 12,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end,
		Tooltip = 'Keep it close, the server still rejects arrests made from too far away'
	})
	ArrestDelay = AutoArrest:CreateSlider({
		Name = 'Arrest delay',
		Min = 0.1,
		Max = 2,
		Decimal = 10,
		Default = 0.3,
		Suffix = function(val)
			return 's'
		end
	})
	
end)

run(function()
	local AutoReset
	local ResetDistance
	local ResetWhileDowned
	
	-- the reset button is wired to WeaponEvent:FireServer('Reset'), which is also the cheapest way
	-- out of an arrest: a downed player that respawns cannot be handcuffed any more
	AutoReset = vape.Categories.Blatant:CreateModule({
		Name = 'AutoReset',
		Function = function(callback)
			if not callback then return end
	
			repeat
				local reset = ResetWhileDowned.Enabled and sentence.status(lplr, 'Downed') == true
	
				if not reset and ResetDistance.Value > 0 then
					reset = sentence.nearestPlayer(sentence.Teams.Guards, ResetDistance.Value) ~= nil
				end
	
				if reset then
					sentence.fire('WeaponEvent', 'Reset')
					task.wait(0.5)
				else
					task.wait(0.1)
				end
			until not AutoReset.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Resets your character before a guard can arrest you'
	})
	ResetDistance = AutoReset:CreateSlider({
		Name = 'Guard distance',
		Min = 0,
		Max = 60,
		Default = 12,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end,
		Tooltip = 'Resets when a guard gets this close, 0 disables the distance check'
	})
	ResetWhileDowned = AutoReset:CreateToggle({
		Name = 'Reset while downed',
		Default = true
	})
	
end)

run(function()
	local AutoStomp
	local StompRange
	local StompDelay
	local StompTeamCheck
	
	-- E is the stomp key, the client sends CarryStompEvent:FireServer('EPress') from both the
	-- StompButton and the keyboard binding, so the module repeats that call while a downed player is
	-- close enough to be finished
	AutoStomp = vape.Categories.Blatant:CreateModule({
		Name = 'AutoStomp',
		Function = function(callback)
			if not callback then return end
	
			repeat
				local root = sentence.root(lplr)
	
				if root then
					for _, plr in playersService:GetPlayers() do
						if plr == lplr or not sentence.isDowned(plr) then continue end
						if StompTeamCheck.Enabled and not sentence.isTarget(plr) then continue end
	
						local other = sentence.root(plr)
						if other and (other.Position - root.Position).Magnitude <= StompRange.Value then
							sentence.fire('CarryStompEvent', 'EPress')
							break
						end
					end
				end
	
				task.wait(StompDelay.Value)
			until not AutoStomp.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Presses the stomp key on downed players in range'
	})
	StompRange = AutoStomp:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 20,
		Default = 6,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	StompDelay = AutoStomp:CreateSlider({
		Name = 'Stomp delay',
		Min = 0.1,
		Max = 2,
		Decimal = 10,
		Default = 0.3,
		Suffix = function(val)
			return 's'
		end
	})
	StompTeamCheck = AutoStomp:CreateToggle({
		Name = 'Team check',
		Default = true,
		Tooltip = 'Skips teammates and friends'
	})
	
end)

run(function()
	local DownedESP
	local DownedColor
	local highlights = {}
	
	local function clearHighlights()
		for character, highlight in highlights do
			highlight:Destroy()
			highlights[character] = nil
		end
	end
	
	local function updateHighlightColor()
		local color = Color3.fromHSV(DownedColor.Hue, DownedColor.Sat, DownedColor.Value)
	
		for _, highlight in highlights do
			highlight.FillColor = color
			highlight.OutlineColor = color
		end
	end
	
	DownedESP = vape.Categories.Render:CreateModule({
		Name = 'DownedESP',
		Function = function(callback)
			clearHighlights()
	
			if not callback then return end
	
			repeat
				local localCharacter = lplr.Character
	
				for _, plr in playersService:GetPlayers() do
					local character = plr.Character
					if character and character ~= localCharacter then
						local highlight = highlights[character]
						local downed = sentence.isDowned(plr)
	
						if downed and not highlight then
							highlight = Instance.new('Highlight')
							highlight.FillColor = Color3.fromHSV(DownedColor.Hue, DownedColor.Sat, DownedColor.Value)
							highlight.FillTransparency = 0.65
							highlight.OutlineColor = highlight.FillColor
							highlight.OutlineTransparency = 0
							highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							highlight.Adornee = character
							highlight.Parent = character
							highlights[character] = highlight
						elseif not downed and highlight then
							highlight:Destroy()
							highlights[character] = nil
						end
					end
				end
	
				task.wait(0.5)
			until not DownedESP.Enabled or vape.Loaded == nil
	
			clearHighlights()
		end,
		Tooltip = 'Highlights players that are downed and can be arrested or stomped'
	})
	DownedColor = DownedESP:CreateColorSlider({
		Name = 'Color',
		DefaultHue = 0.02,
		DefaultSat = 1,
		DefaultValue = 1,
		Function = function()
			updateHighlightColor()
		end
	})
	
end)

run(function()
	local AutoJoinGuards
	local JoinDelay
	
	-- becoming a guard is a single CopEvent('Join') call, the same one both guard computers send, so
	-- the retry is just repeated until the server balances the teams and accepts it
	AutoJoinGuards = vape.Categories.Utility:CreateModule({
		Name = 'AutoJoinGuards',
		Function = function(callback)
			if not callback then return end
	
			repeat
				if not sentence.isTeam(lplr, sentence.Teams.Guards) then
					sentence.fire('CopEvent', 'Join')
				end
	
				task.wait(JoinDelay.Value)
			until not AutoJoinGuards.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Joins the guard team through the game cop computer'
	})
	JoinDelay = AutoJoinGuards:CreateSlider({
		Name = 'Retry delay',
		Min = 1,
		Max = 30,
		Default = 3,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end,
		Tooltip = 'The server refuses teams that are not balanced, so the request is repeated'
	})
	
end)