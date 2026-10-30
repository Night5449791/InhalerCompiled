local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local inputService = cloneref(game:GetService('UserInputService'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local redwood = {
	Remotes = nil,
	Teams = {
		Fugitive = 'Fugitive',
		Guards = 'Guards',
		Neutral = 'Neutral',
		Prisoners = 'Prisoners',
		Krampus = 'Krampus',
		Military = 'Military'
	}
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

local function notif(...)
	return vape:CreateNotification(...)
end

local function waitForChildOfType(obj, name, timeout, prop)
	local checktick = tick() + timeout
	local returned
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if returned or checktick < tick() then break end
		task.wait()
	until false
	return returned
end

-- every character lives under Workspace.Characters and keeps its per player state in
-- <character>.AttributeFolder (Handcuffed_, Inside, ArrestCurrent, plus the stat values)
function redwood.attributeFolder(char)
	return char and char:FindFirstChild('AttributeFolder') or nil
end

function redwood.state(char, name)
	local folder = redwood.attributeFolder(char)
	local state = folder and folder:FindFirstChild(name)
	return state and state.Value or nil
end

function redwood.hasState(char, name)
	local folder = redwood.attributeFolder(char)
	return folder ~= nil and folder:FindFirstChild(name) ~= nil
end

function redwood.team(plr)
	return plr and plr.Team and plr.Team.Name or nil
end

function redwood.isTeam(plr, team)
	return redwood.team(plr) == team
end

function redwood.fire(name, ...)
	local remotes = redwood.Remotes
	local remote = remotes and remotes:FindFirstChild(name)
	if not remote or typeof(remote.FireServer) ~= 'function' then return end

	pcall(remote.FireServer, remote, ...)
end

function redwood.invoke(name, ...)
	local remotes = redwood.Remotes
	local remote = remotes and remotes:FindFirstChild(name)
	if not remote or typeof(remote.InvokeServer) ~= 'function' then return end

	local suc, result = pcall(remote.InvokeServer, remote, ...)
	return suc and result or nil
end

-- ignores dead characters so AutoReset does not keep firing at a guard corpse
function redwood.nearestPlayer(team, range)
	local character = lplr.Character
	local root = character and character:FindFirstChild('HumanoidRootPart')
	if not root then return end

	local closest, closestDistance = nil, range or math.huge
	for _, plr in playersService:GetPlayers() do
		if plr ~= lplr and (not team or redwood.isTeam(plr, team)) then
			local char = plr.Character
			local other = char and char:FindFirstChild('HumanoidRootPart')
			local humanoid = char and char:FindFirstChildOfClass('Humanoid')
			if other and humanoid and humanoid.Health > 0 then
				local magnitude = (other.Position - root.Position).Magnitude
				if magnitude < closestDistance then
					closest, closestDistance = plr, magnitude
				end
			end
		end
	end

	return closest
end

-- Adonis watches __namecall, so melee calls are built from the weapon's own Setting module
-- instead of being intercepted. BaseDamage is a {min, max} pair the game rolls per hit.
local function addressValue(value)
	if type(value) ~= 'table' then return tonumber(value) or 0 end

	local min, max = tonumber(value[1]), tonumber(value[2])
	if not min then return 0 end
	if max then return Random.new():NextNumber(min, max) end
	return min
end

function redwood.humanoid(character)
	return character and character:FindFirstChildOfClass('Humanoid') or nil
end

function redwood.isDead(plr)
	local character = plr and plr.Character
	local humanoid = redwood.humanoid(character)
	return humanoid == nil or humanoid.Health <= 0
end

-- Fugitive and Prisoners are both "criminal" teams: guards may attack them, and they may
-- attack guards. Neutral/Krampus are left alone by the team check so they stay optional.
local hostileTeams = {
	[redwood.Teams.Guards] = {[redwood.Teams.Prisoners] = true, [redwood.Teams.Fugitive] = true},
	[redwood.Teams.Prisoners] = {[redwood.Teams.Guards] = true},
	[redwood.Teams.Fugitive] = {[redwood.Teams.Guards] = true}
}

-- strict teams[] table is optional; without it anything not on your own team is a target
function redwood.isTarget(plr, strict)
	if not plr or plr == lplr or isFriend(plr) or redwood.isDead(plr) then return false end
	if redwood.hasState(plr.Character, 'Handcuffed_') then return false end

	local myTeam, team = redwood.team(lplr), redwood.team(plr)
	if strict and myTeam and team then
		local allowed = hostileTeams[myTeam]
		return allowed ~= nil and allowed[team] == true
	end

	return not (team and myTeam and team == myTeam)
end

-- entitylib target check: Friend list, dead bodies, handcuffed players and own team
function redwood.targetCheck(ent)
	if not ent or ent.NPC then return false end

	local plr = ent.Player
	if not plr or plr == lplr or isFriend(plr) then return false end
	if ent.Health and ent.Health <= 0 then return false end
	if ent.Character and redwood.hasState(ent.Character, 'Handcuffed_') then return false end

	local myTeam, team = redwood.team(lplr), redwood.team(plr)
	return not (team and myTeam and team == myTeam)
end

function redwood.meleeTool()
	local character = lplr.Character
	if not character then return end

	for _, tool in character:GetChildren() do
		if tool:IsA('Tool') then
			local server = tool:FindFirstChild('MeleeScriptServer')
			if server and server:FindFirstChild('InflictTarget') then
				return tool
			end
		end
	end
end

-- builds the same InflictTarget call the melee script sends, with the weapon's own numbers
function redwood.attack(target, partName)
	local tool = redwood.meleeTool()
	if not tool then return false end

	local remote = tool.MeleeScriptServer:FindFirstChild('InflictTarget')
	local setting = tool:FindFirstChild('Setting')
	local frame = setting and setting:FindFirstChild('1')
	local character = target and (target.Character or target)
	if not (remote and frame and character) then return false end

	local suc, config = pcall(require, frame)
	if not suc or type(config) ~= 'table' then return false end

	local humanoid = redwood.humanoid(character)
	local root = character:FindFirstChild('HumanoidRootPart')
	local part = (partName and character:FindFirstChild(partName)) or character:FindFirstChild('Head') or root
	if not (part and humanoid and root) then return false end
	if humanoid.Health <= 0 then return false end

	local combo = tool:FindFirstChild('Combo')

	return pcall(remote.FireServer, remote, part, part.Position, nil, humanoid, root, addressValue(config.BaseDamage), addressValue(config.BackstabDamage), gameCamera.CFrame.LookVector, false, combo and combo.Value or 1)
end

vape.Libraries.redwood = redwood
vape:Clean(function()
	vape.Libraries.redwood = nil
	redwood.Remotes = nil
end)

run(function()
	local storage = replicatedStorage:WaitForChild('Storage', 30)
	local remotes = storage and storage:WaitForChild('Remotes', 30)
	if not remotes then return end

	redwood.Remotes = remotes
end)

-- Adonis bypass, ported from the girls and boys vs zombies base. Adonis keeps every client
-- side check behind a single gc table holding Detected, RLocked, AddDetector, Detectors and
-- Launch, and every detector reports through Detected. Hanging those functions was what made
-- the game's own Anti script run past its 30 second budget and print "Script timeout:
-- exhausted allowed execution time", so nothing is hung here: Detected is replaced by a pass
-- through that reports nothing and returns false, which leaves the core's bookkeeping (and
-- whatever the detectors still do locally) intact while no check can come back positive.
-- rawset is used on purpose, so an __newindex metatable cannot see the write, and the pass is
-- repeated because the core is rebuilt from scratch when the anti script restarts.
local function gcTables(keys)
	if typeof(filtergc) == 'function' then
		return filtergc('table', {Keys = keys}, false)
	end

	local found = {}
	if typeof(getgc) ~= 'function' then return found end

	for _, object in getgc(true) do
		if type(object) ~= 'table' then continue end

		local matches = true
		for _, key in keys do
			if rawget(object, key) == nil then
				matches = false
				break
			end
		end

		if matches then
			table.insert(found, object)
		end
	end

	return found
end

run(function()
	task.delay(3, function()
		task.spawn(function()
			local patched = {}

			-- Loaded is false while the gui loads and nil after Uninject, so only nil ends this
			while shared.vape and shared.vape.Loaded ~= nil do
				for _, core in gcTables({'Detected', 'RLocked', 'AddDetector', 'Detectors'}) do
					if not patched[core] and type(core.Detectors) == 'table' and typeof(core.Detected) == 'function' then
						patched[core] = true

						rawset(core, 'Detected', function()
							return false
						end)
					end
				end

				task.wait(2)
			end
		end)
	end)
end)

run(function()
	entitylib.targetCheck = redwood.targetCheck

	entitylib.getEntityColor = function(ent)
		if not (ent.Player and vape.Settings.Modules.Options['Use team color'].Enabled) then return end
		if isFriend(ent.Player, true) then
			return Color3.fromHSV(vape.Categories.Friends.Options['Friends color'].Hue, vape.Categories.Friends.Options['Friends color'].Sat, vape.Categories.Friends.Options['Friends color'].Value)
		end

		local team = ent.Player.Team
		return team and team.TeamColor.Color
	end
end)

for _, v in {'MurderMystery'} do
	vape:Remove(v)
end


run(function()
	local SilentAim
	local FOV
	local Part
	local ShowTarget
	local connections = {}
	
	local function disconnectAll()
		for tool, connection in connections do
			connection:Disconnect()
			connections[tool] = nil
		end
	end
	
	-- entities carry their target part, so a renamed or missing part degrades to the root
	-- instead of erroring inside EntityMouse
	local function aimEntity()
		local part = Part.Value
		local entity = entitylib.EntityMouse({
			Range = FOV.Value,
			Part = part,
			Players = true,
			NPCs = true
		})
	
		if not entity and part ~= 'RootPart' then
			entity = entitylib.EntityMouse({
				Range = FOV.Value,
				Part = 'RootPart',
				Players = true,
				NPCs = true
			})
		end
	
		return entity
	end
	
	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			disconnectAll()
	
			if not callback then return end
	
			repeat
				local tool = redwood.meleeTool()
				if tool and not connections[tool] then
					connections[tool] = tool.Activated:Connect(function()
						if not SilentAim.Enabled then return end
	
						local entity = aimEntity()
						if not entity then return end
						if not redwood.attack(entity, Part.Value) then return end
	
						if ShowTarget.Enabled then
							targetinfo.Targets[entity] = os.clock() + 1
						end
					end)
				end
	
				task.wait(1)
			until not SilentAim.Enabled or vape.Loaded == nil
	
			disconnectAll()
		end,
		Tooltip = 'Adds a melee hit on the closest target inside the FOV every time you attack'
	})
	FOV = SilentAim:CreateSlider({
		Name = 'FOV',
		Min = 0,
		Max = 1000,
		Default = 150
	})
	Part = SilentAim:CreateDropdown({
		Name = 'Part',
		List = {'Head', 'RootPart'}
	})
	ShowTarget = SilentAim:CreateToggle({
		Name = 'Show target info'
	})
	
end)

run(function()
	local AutoReset
	local Distance
	local OnArrest
	local OnlyPrisoners
	
	AutoReset = vape.Categories.Blatant:CreateModule({
		Name = 'AutoReset',
		Function = function(callback)
			if not callback then return end
	
			-- the server drops Reset calls that arrive while a respawn is already pending, so
			-- the loop only fires once and then waits for the new character to spawn
			local lastReset = 0
	
			repeat
				local character = lplr.Character
				local humanoid = redwood.humanoid(character)
				local alive = humanoid ~= nil and humanoid.Health > 0
				local reset = false
	
				if alive and os.clock() - lastReset > 1 then
					reset = OnArrest.Enabled and redwood.hasState(character, 'ArrestCurrent')
	
					if not reset and Distance.Value > 0 then
						if not OnlyPrisoners.Enabled or redwood.isTeam(lplr, redwood.Teams.Prisoners) or redwood.isTeam(lplr, redwood.Teams.Fugitive) then
							reset = redwood.nearestPlayer(redwood.Teams.Guards, Distance.Value) ~= nil
						end
					end
	
					if reset then
						redwood.fire('Reset')
						lastReset = os.clock()
					end
				end
	
				task.wait(reset and 0.5 or 0.1)
			until not AutoReset.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Resets your character before a guard can arrest you'
	})
	Distance = AutoReset:CreateSlider({
		Name = 'Guard distance',
		Min = 0,
		Max = 60,
		Default = 12,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end,
		Tooltip = 'Resets when a guard gets this close, 0 disables the distance check'
	})
	OnArrest = AutoReset:CreateToggle({
		Name = 'Reset while being arrested',
		Default = true
	})
	OnlyPrisoners = AutoReset:CreateToggle({
		Name = 'Only as prisoner',
		Default = true,
		Tooltip = 'Only watches guards while you are a prisoner or a fugitive'
	})
	
end)

run(function()
	local Killaura
	local Range
	local Part
	local Delay
	local TeamCheck
	
	-- picks the closest valid target once per tick instead of attacking everyone in range:
	-- one InflictTarget per swing is what the server expects, extra calls are wasted
	-- bandwidth and trip the Adonis rate checks
	local function closestTarget(root, range, teamCheck)
		local best, bestDistance
		for _, plr in playersService:GetPlayers() do
			if plr ~= lplr and (not teamCheck or redwood.isTarget(plr)) then
				local character = plr.Character
				local other = character and character:FindFirstChild('HumanoidRootPart')
				if other then
					local distance = (other.Position - root.Position).Magnitude
					if distance <= range and (not bestDistance or distance < bestDistance) then
						best, bestDistance = plr, distance
					end
				end
			end
		end
	
		return best
	end
	
	Killaura = vape.Categories.Blatant:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			if not callback then return end
	
			local swingAt = 0
	
			repeat
				local tool = redwood.meleeTool()
				local character = lplr.Character
				local root = character and character:FindFirstChild('HumanoidRootPart')
	
				if tool and root and os.clock() >= swingAt then
					local target = closestTarget(root, Range.Value, TeamCheck.Enabled)
					if target then
						redwood.attack(target, Part.Value)
						swingAt = os.clock() + Delay.Value
					end
				end
	
				task.wait(0.05)
			until not Killaura.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Hits everyone in range with your equipped melee weapon'
	})
	Range = Killaura:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 30,
		Default = 10,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end,
		Tooltip = 'Keep it close to the weapon range, the server still validates the distance'
	})
	Part = Killaura:CreateDropdown({
		Name = 'Part',
		List = {'Head', 'RootPart'}
	})
	Delay = Killaura:CreateSlider({
		Name = 'Attack delay',
		Min = 0.1,
		Max = 2,
		Decimal = 10,
		Default = 0.2,
		Suffix = function(val)
			return 's'
		end
	})
	TeamCheck = Killaura:CreateToggle({
		Name = 'Team check',
		Default = true,
		Tooltip = 'Skips teammates and friends'
	})
	
end)

run(function()
	local CuffedESP
	local Color
	local ColorTeam
	local highlights = {}
	
	local function removeHighlight(character)
		local highlight = highlights[character]
		if highlight then
			highlight:Destroy()
			highlights[character] = nil
		end
	end
	
	local function clearHighlights()
		for character in highlights do
			removeHighlight(character)
		end
		table.clear(highlights)
	end
	
	local function highlightColor(character)
		if ColorTeam.Enabled then
			local plr = playersService:GetPlayerFromCharacter(character)
			local team = plr and plr.Team
			if team then return team.TeamColor.Color end
		end
	
		return Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	end
	
	local function updateColor()
		for character, highlight in highlights do
			local color = highlightColor(character)
			highlight.FillColor = color
			highlight.OutlineColor = color
		end
	end
	
	CuffedESP = vape.Categories.Render:CreateModule({
		Name = 'CuffedESP',
		Function = function(callback)
			clearHighlights()
	
			if not callback then return end
	
			-- characters that die or respawn leave the world without notifying us, so the
			-- per character highlight is dropped as soon as its adornee is gone
			local removed = workspace.ChildRemoved:Connect(function(child)
				removeHighlight(child)
			end)
	
			repeat
				for _, plr in playersService:GetPlayers() do
					local character = plr.Character
					if character and character ~= lplr.Character then
						local humanoid = redwood.humanoid(character)
						local alive = humanoid and humanoid.Health > 0
						local cuffed = alive and redwood.hasState(character, 'Handcuffed_')
						local highlight = highlights[character]
	
						if cuffed and not highlight then
							highlight = Instance.new('Highlight')
							local color = highlightColor(character)
							highlight.FillColor = color
							highlight.FillTransparency = 0.65
							highlight.OutlineColor = color
							highlight.OutlineTransparency = 0
							highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							highlight.Adornee = character
							highlight.Parent = character
							highlights[character] = highlight
						elseif not cuffed and highlight then
							removeHighlight(character)
						elseif highlight then
							local color = highlightColor(character)
							highlight.FillColor = color
							highlight.OutlineColor = color
						end
					end
				end
	
				for character in highlights do
					local plr = playersService:GetPlayerFromCharacter(character)
					if not plr or plr.Character ~= character then
						removeHighlight(character)
					end
				end
	
				task.wait(0.5)
			until not CuffedESP.Enabled or vape.Loaded == nil
	
			removed:Disconnect()
			clearHighlights()
		end,
		Tooltip = 'Highlights players that are already handcuffed'
	})
	Color = CuffedESP:CreateColorSlider({
		Name = 'Color',
		DefaultHue = 0.12,
		DefaultSat = 1,
		DefaultValue = 1,
		Function = function()
			updateColor()
		end
	})
	ColorTeam = CuffedESP:CreateToggle({
		Name = 'Use team color',
		Tooltip = 'Tints the highlight with the cuffed player team colour'
	})
	
end)

run(function()
	local AutoJoinTeam
	local Team
	local Retry
	
	-- the team chooser buttons carry an ObjectValue named Team pointing at game.Teams.<name>,
	-- and the game invokes ChangeTeam:InvokeServer(team, button name)
	local function teamButtonName(teamName)
		local gui = lplr.PlayerGui:FindFirstChild('IntroGui')
		local intro = gui and gui:FindFirstChild('IntroFrame')
		local holder = intro and intro:FindFirstChild('Frame')
		local buttons = holder and holder:FindFirstChild('Buttons')
		if not buttons then return end
	
		for _, button in buttons:GetChildren() do
			local value = button:FindFirstChild('Team')
			if value and value:IsA('ObjectValue') and value.Value and value.Value.Name == teamName then
				return button.Name
			end
		end
	end
	
	local function joinTeam(teamName)
		local team = game.Teams:FindFirstChild(teamName)
		if not team then return end
	
		return redwood.invoke('ChangeTeam', team, teamButtonName(teamName) or teamName)
	end
	
	AutoJoinTeam = vape.Categories.Utility:CreateModule({
		Name = 'AutoJoinTeam',
		Function = function(callback)
			if not callback then return end
	
			repeat
				if redwood.team(lplr) ~= Team.Value then
					joinTeam(Team.Value)
				end
	
				task.wait(Retry.Value)
			until not AutoJoinTeam.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Joins the selected team through the game team changer'
	})
	Team = AutoJoinTeam:CreateDropdown({
		Name = 'Team',
		List = {'Prisoners', 'Guards', 'Fugitive', 'Military', 'Krampus'},
		Function = function()
			if AutoJoinTeam.Enabled then
				AutoJoinTeam:Toggle()
				AutoJoinTeam:Toggle()
			end
		end
	})
	Retry = AutoJoinTeam:CreateSlider({
		Name = 'Retry delay',
		Min = 1,
		Max = 30,
		Default = 3,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end,
		Tooltip = 'The server rejects teams that are not balanced, so the request is repeated'
	})
	
end)