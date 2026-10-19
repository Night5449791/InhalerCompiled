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

function redwood.nearestPlayer(team, range)
	local character = entitylib.character
	if not character then return end

	local root, closest, distance = character.RootPart, nil, range or math.huge
	for _, plr in playersService:GetPlayers() do
		if plr ~= lplr and (not team or redwood.isTeam(plr, team)) then
			local char = plr.Character
			local other = char and char:FindFirstChild('HumanoidRootPart')
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

-- Adonis watches __namecall, so melee calls are built from the weapon's own Setting module
-- instead of being intercepted. BaseDamage is a {min, max} pair the game rolls per hit.
local function addressValue(value)
	if type(value) ~= 'table' then return tonumber(value) or 0 end

	local min, max = tonumber(value[1]), tonumber(value[2])
	if not min then return 0 end
	if max then return Random.new():NextNumber(min, max) end
	return min
end

function redwood.isTarget(plr)
	if plr == lplr or isFriend(plr) then return false end

	local character = plr.Character
	local humanoid = character and character:FindFirstChildOfClass('Humanoid')
	if not humanoid or humanoid.Health <= 0 then return false end

	local team = plr.Team
	return not (team and lplr.Team and team == lplr.Team)
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

	local humanoid = character:FindFirstChildOfClass('Humanoid')
	local root = character:FindFirstChild('HumanoidRootPart')
	local part = character:FindFirstChild(partName) or character:FindFirstChild('Head') or root
	if not (part and humanoid and root) then return false end

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
	
	SilentAim = vape.Categories.Combat:CreateModule({
		Name = 'SilentAim',
		Function = function(callback)
			if not callback then return end
	
			local connected = {}
	
			repeat
				local tool = redwood.meleeTool()
				if tool and not connected[tool] then
					connected[tool] = true
	
					SilentAim:Clean(tool.Activated:Connect(function()
						if not SilentAim.Enabled then return end
	
						local entity = entitylib.EntityMouse({
							Range = FOV.Value,
							Part = Part.Value,
							Players = true,
							NPCs = true
						})
	
						if not entity or not redwood.attack(entity, Part.Value) then return end
	
						if ShowTarget.Enabled then
							targetinfo.Targets[entity] = os.clock() + 1
						end
					end))
				end
	
				task.wait(1)
			until not SilentAim.Enabled or vape.Loaded == nil
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
	
			repeat
				local character = lplr.Character
				local reset = character ~= nil and OnArrest.Enabled and redwood.hasState(character, 'ArrestCurrent')
	
				if not reset and Distance.Value > 0 then
					if not OnlyPrisoners.Enabled or redwood.isTeam(lplr, redwood.Teams.Prisoners) or redwood.isTeam(lplr, redwood.Teams.Fugitive) then
						reset = redwood.nearestPlayer(redwood.Teams.Guards, Distance.Value) ~= nil
					end
				end
	
				if reset then
					redwood.fire('Reset')
					task.wait(0.5)
				else
					task.wait(0.1)
				end
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
	
	Killaura = vape.Categories.Blatant:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			if not callback then return end
	
			repeat
				local tool = redwood.meleeTool()
				local character = lplr.Character
				local root = character and character:FindFirstChild('HumanoidRootPart')
	
				if tool and root then
					for _, plr in playersService:GetPlayers() do
						if not Killaura.Enabled then break end
						if not TeamCheck.Enabled or redwood.isTarget(plr) then
							local targetCharacter = plr.Character
							local other = targetCharacter and targetCharacter:FindFirstChild('HumanoidRootPart')
							if other and (other.Position - root.Position).Magnitude <= Range.Value then
								redwood.attack(plr, Part.Value)
							end
						end
					end
				end
	
				task.wait(Delay.Value)
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
	local highlights = {}
	
	local function clearHighlights()
		for character, highlight in highlights do
			highlight:Destroy()
			highlights[character] = nil
		end
	end
	
	local function updateColor()
		local color = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	
		for _, highlight in highlights do
			highlight.FillColor = color
			highlight.OutlineColor = color
		end
	end
	
	CuffedESP = vape.Categories.Render:CreateModule({
		Name = 'CuffedESP',
		Function = function(callback)
			clearHighlights()
	
			if not callback then return end
	
			repeat
				for _, plr in playersService:GetPlayers() do
					local character = plr.Character
					if character and character ~= lplr.Character then
						local highlight = highlights[character]
						local cuffed = redwood.state(character, 'Handcuffed_')
	
						if cuffed and not highlight then
							highlight = Instance.new('Highlight')
							highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
							highlight.FillTransparency = 0.65
							highlight.OutlineColor = highlight.FillColor
							highlight.OutlineTransparency = 0
							highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							highlight.Adornee = character
							highlight.Parent = character
							highlights[character] = highlight
						elseif not cuffed and highlight then
							highlight:Destroy()
							highlights[character] = nil
						end
					end
				end
	
				task.wait(0.5)
			until not CuffedESP.Enabled or vape.Loaded == nil
	
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