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
local targetinfo = vape.Libraries.targetinfo

-- Deadly Delivery run place (Underground, 93044798454681). The lobby is a separate product, this
-- half is the dungeon the match teleports into.
-- Everything is routed through one Remote_Event with a name string, the wrappers are in
-- Shared.Core.TEvent (FireRemote(name, ...)) and the shared client state in Shared.Core.Value.
-- Loot and containers are models under Workspace.GameSystem (Loots, InteractiveItem) and carry
-- their own attributes (Looted, Open, w, sz) instead of ProximityPrompts.
local dungeon = {
	TEvent = nil,
	Value = nil
}

local function safeRequire(parent, name)
	local module = parent and parent:FindFirstChild(name)
	if not module then return end

	local suc, value = pcall(require, module)
	if suc and type(value) == 'table' then
		return value
	end
end

run(function()
	local shared = replicatedStorage:WaitForChild('Shared', 30)
	local core = shared and shared:WaitForChild('Core', 30)
	dungeon.Value = safeRequire(core, 'Value')
	dungeon.TEvent = safeRequire(core, 'TEvent')
end)

function dungeon.fire(name, ...)
	local event = dungeon.TEvent
	if not (event and typeof(event.FireRemote) == 'function') then return false end

	return (pcall(event.FireRemote, name, ...))
end

function dungeon.value(name)
	local module = dungeon.Value
	local value = module and module[name]
	return value and value.Value or nil
end

function dungeon.backpack()
	return dungeon.value('Backpack')
end

function dungeon.interactTarget()
	return dungeon.value('InteractTarget')
end

function dungeon.gameSystem(name)
	local system = workspace:FindFirstChild('GameSystem')
	return system and system:FindFirstChild(name) or nil
end

function dungeon.character()
	local character = lplr.Character
	if not character then return end

	return character, character:FindFirstChildOfClass('Humanoid'), character:FindFirstChild('HumanoidRootPart')
end

function dungeon.position()
	local _, _, root = dungeon.character()
	return root and root.Position
end

local function interactableOf(item)
	if item:IsA('Model') then
		return item:FindFirstChild('Interactable') or item.PrimaryPart
	end
end

-- loot that dropped in the level: every model in Loots.World that carries an Interactable part
function dungeon.loot()
	local folder = dungeon.gameSystem('Loots')
	folder = folder and folder:FindFirstChild('World')

	local found = {}
	if not folder then return found end

	for _, item in folder:GetChildren() do
		local part = interactableOf(item)
		if part then
			table.insert(found, {Model = item, Part = part})
		end
	end

	return found
end

-- containers the level generates (crates, cabinets, soil mounds, oil buckets); Looted marks the
-- ones that already gave their loot up
function dungeon.containers()
	local folder = dungeon.gameSystem('InteractiveItem')

	local found = {}
	if not folder then return found end

	for _, item in folder:GetChildren() do
		local part = interactableOf(item)
		if part and item:GetAttribute('Looted') ~= true then
			table.insert(found, {Model = item, Part = part})
		end
	end

	return found
end

function dungeon.interact(model)
	return dungeon.fire('Interactable', model)
end

-- picked up loot does not go to Value.Item (that table is the money and resource counters:
-- 101 money, 201/301/1301 materials). The character physically carries each piece, and the
-- client sees them as tools in GameSystem.Loots.Player.
function dungeon.carried()
	local folder = dungeon.gameSystem('Loots')
	folder = folder and folder:FindFirstChild('Player')

	local found = {}
	if not folder then return found end

	for _, item in folder:GetChildren() do
		table.insert(found, item)
	end

	return found
end

function dungeon.itemCount()
	return #dungeon.carried()
end

-- The game drives the humanoid itself: MoveTo does nothing and any velocity written to the root
-- is zeroed on the next step, so the only way to move the character is to step its CFrame. The
-- step is kept small (4 studs) and paced, which looks like fast walking instead of one long jump.
function dungeon.walkTo(position, timeout)
	local _, humanoid, root = dungeon.character()
	if not (humanoid and root) then return false end

	local deadline = os.clock() + (timeout or 12)
	local attempts = 0

	while os.clock() < deadline do
		local current = root.Position
		local delta = position - current
		local distance = delta.Magnitude
		if distance <= 4 then return true end

		local step = math.min(4, distance)
		root.CFrame = CFrame.lookAt(current + delta.Unit * step, position)
		task.wait(0.12)

		-- a step that did not move the character means the way is blocked: nudge it sideways,
		-- then backwards, and jump on the way so a step or a low prop does not park the loop
		if (root.Position - current).Magnitude < 1 then
			attempts = attempts + 1
			local side = delta.Unit:Cross(Vector3.yAxis)
			if side.Magnitude > 0 then
				side = side.Unit
			else
				side = Vector3.xAxis
			end

			humanoid.Jump = true
			local offset
			if attempts % 3 == 1 then
				offset = side * 4
			elseif attempts % 3 == 2 then
				offset = -side * 4
			else
				offset = -delta.Unit * 5
			end

			root.CFrame = root.CFrame + offset
			task.wait(0.1)

			if attempts >= 9 then return false end
		else
			attempts = 0
		end
	end

	return (root.Position - position).Magnitude <= 6
end

vape.Libraries.dungeon = dungeon
vape:Clean(function()
	vape.Libraries.dungeon = nil
	table.clear(dungeon)
end)


local AutoFarm
local FarmRange
local FarmDelay
local DeliverAt
local OpenContainers

run(function()
	-- One loop for the whole run: grab loot (or open a container when the floor is empty), then
	-- walk the carried piece(s) to the elevator. Carried loot is a tool under
	-- GameSystem.Loots.Player, and the elevator is the only hand over spot in the run, so the
	-- loop waits there and pokes the elevator model if the loot did not leave by itself. After a
	-- few failed hand overs it stops standing at the lift and keeps farming instead of hanging.
	local elevatorCenter
	local elevatorModel

	local function elevator()
		if elevatorCenter and elevatorCenter.Parent then return elevatorCenter end

		local folder = workspace:FindFirstChild('电梯')
		if not folder then return end

		for _, descendant in folder:GetDescendants() do
			if descendant:IsA('BasePart') and descendant.Name == 'ElevatorCenter' then
				elevatorCenter = descendant
				return descendant
			end
		end
	end

	local function lift()
		if elevatorModel and elevatorModel.Parent then return elevatorModel end

		local folder = workspace:FindFirstChild('电梯')
		if not folder then return end

		for _, descendant in folder:GetDescendants() do
			if descendant:IsA('Model') and descendant.Name == 'Elevator' then
				elevatorModel = descendant
				return descendant
			end
		end
	end

	local function nearest(entries, origin, range)
		local best, bestDistance
		for _, entry in entries do
			local distance = (entry.Part.Position - origin).Magnitude
			if distance <= range and (not bestDistance or distance < bestDistance) then
				best, bestDistance = entry, distance
			end
		end

		return best
	end

	local function deliver(home)
		local center = elevator()
		local target = home or (center and center.Position)
		if not target then return false end

		-- the lift sits on another floor of the maze, so the spot the character started on is
		-- tried first and the lift center is only the fallback
		if not dungeon.walkTo(target, 25) and center then
			dungeon.walkTo(center.Position, 20)
		end

		for _ = 1, 16 do
			if dungeon.itemCount() == 0 then return true end
			task.wait(0.3)
		end

		local model = lift()
		if model then
			dungeon.interact(model)
			for _ = 1, 10 do
				if dungeon.itemCount() == 0 then return true end
				task.wait(0.3)
			end
		end

		return dungeon.itemCount() == 0
	end

	local blocked = {}

	AutoFarm = vape.Categories.Utility:CreateModule({
		Name = 'AutoFarm',
		Function = function(callback)
			if not callback then return end

			local home = dungeon.position()
			local failures = 0

			repeat
				local carried = dungeon.itemCount()

				if carried >= DeliverAt.Value and failures < 3 then
					if deliver(home) then
						failures = 0
					else
						failures = failures + 1
					end
				else
					local origin = dungeon.position()
					if origin then
						local now = os.clock()
						local target = nearest(dungeon.loot(), origin, FarmRange.Value)

						if not target and OpenContainers.Enabled then
							local entries = {}
							for _, entry in dungeon.containers() do
								local unlock = blocked[entry.Model]
								if not (unlock and unlock > now) then
									table.insert(entries, entry)
								end
							end

							target = nearest(entries, origin, FarmRange.Value)
						end

						if target and not (blocked[target.Model] and blocked[target.Model] > now) then
							if dungeon.walkTo(target.Part.Position, 20) then
								dungeon.interact(target.Model)
								task.wait(0.6)
							else
								blocked[target.Model] = now + 5
							end
						end
					end
				end

				task.wait(FarmDelay.Value)
			until not AutoFarm.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Grabs loot, carries it to the elevator and starts over'
	})

	FarmRange = AutoFarm:CreateSlider({
		Name = 'Range',
		Min = 20,
		Max = 500,
		Default = 300,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	FarmDelay = AutoFarm:CreateSlider({
		Name = 'Delay',
		Min = 0.1,
		Max = 2,
		Decimal = 10,
		Default = 0.3,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end
	})
	DeliverAt = AutoFarm:CreateSlider({
		Name = 'Deliver at',
		Min = 1,
		Max = 10,
		Default = 3,
		Tooltip = 'Walks back to the elevator once this many pieces are carried'
	})
	OpenContainers = AutoFarm:CreateToggle({
		Name = 'Open containers',
		Default = true,
		Tooltip = 'Also opens crates, cabinets and soil mounds when there is no loot on the floor'
	})
end)
