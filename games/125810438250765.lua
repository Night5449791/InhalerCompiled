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

-- Deadly Delivery (place 125810438250765, universe 8950496606) keeps its lobby in this place:
-- Workspace.LobbyScene is the hub, Workspace.Match holds one model per match pad, and the
-- actual run happens after joining a match. Nothing here uses the Team service or the Humanoid
-- replacement the game performs on its monsters, so the entity library default stays untouched.
-- The lobby state is all in Shared.Core.Value:
--   Value.MatchId.Value       the match the client is in, nil while standing in the lobby
--   Value.MatchInfo.Value     matchId -> {matchState, mode, size, onlyFriends, playerList}
--   Value.Backpack.Value      {count, size, ...}, joining is blocked while count >= size
-- Match pads are models tagged MatchModel with a MatchId attribute, and the game joins one by
-- firing the JoinMatch remote through Shared.Core.TEvent when the local player walks on it.
local deadlydelivery = {
	Match = nil,
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
	deadlydelivery.Value = safeRequire(core, 'Value')
	deadlydelivery.TEvent = safeRequire(core, 'TEvent')
	deadlydelivery.Match = workspace:FindFirstChild('Match')
end)

function deadlydelivery.matchId()
	local module = deadlydelivery.Value
	return module and module.MatchId and module.MatchId.Value or nil
end

function deadlydelivery.matches()
	local module = deadlydelivery.Value
	local info = module and module.MatchInfo and module.MatchInfo.Value
	return type(info) == 'table' and info or {}
end

function deadlydelivery.backpackFull()
	local module = deadlydelivery.Value
	local backpack = module and module.Backpack and module.Backpack.Value
	return type(backpack) == 'table' and backpack.count >= backpack.size
end

-- matchId -> model, so a match can be picked by distance like the game does when you walk on
-- a pad, or simply by the first id
function deadlydelivery.models()
	local found = {}
	local folder = deadlydelivery.Match or workspace:FindFirstChild('Match')
	if not folder then return found end

	for _, model in folder:GetChildren() do
		local id = model:GetAttribute('MatchId')
		if id then
			found[id] = model
		end
	end

	return found
end

function deadlydelivery.joinable(match)
	if type(match) ~= 'table' then return false end
	if match.matchState == 'Creating' then return false end
	if match.onlyFriends then return false end

	return true
end

function deadlydelivery.fire(name, ...)
	local event = deadlydelivery.TEvent
	if not (event and typeof(event.FireRemote) == 'function') then return false end

	return (pcall(event.FireRemote, name, ...))
end

function deadlydelivery.join(id)
	return deadlydelivery.fire('JoinMatch', id)
end

function deadlydelivery.leave()
	return deadlydelivery.fire('LeaveMatch')
end

-- joining only creates the match: the client then opens the Match panel and the run starts once
-- UploadSetting arrives with the party settings, otherwise the server drops the match after a
-- few seconds and the player is put back in the lobby
function deadlydelivery.upload(settings)
	return deadlydelivery.fire('UploadSetting', settings)
end

function deadlydelivery.dungeonLevel()
	local module = deadlydelivery.Value
	local data = module and module.DungeonData and module.DungeonData.Value
	return type(data) == 'table' and data.highestLevel or 0
end

-- the panel the game opens for a match is UIManager's 'Match' screen and stays on top after a
-- direct upload, so it is closed the same way the Create button closes it
function deadlydelivery.closeMatchUI()
	local client = replicatedStorage:FindFirstChild('Client')
	local core = client and client:FindFirstChild('Core')
	local module = core and core:FindFirstChild('UIManager')
	if not module then return end

	local suc, manager = pcall(require, module)
	if suc and manager and typeof(manager.CloseUI) == 'function' then
		pcall(manager.CloseUI, 'Match')
	end
end

vape.Libraries.deadlydelivery = deadlydelivery
vape:Clean(function()
	vape.Libraries.deadlydelivery = nil
	table.clear(deadlydelivery)
end)


local AutoLobby
local Mode
local PickNearest
local PartySize
local Delay
local RequireSpace

run(function()
	local function position()
		local character = entitylib.character
		local root = character and character.RootPart
		if root then return root.Position end

		local localCharacter = lplr.Character
		root = localCharacter and localCharacter:FindFirstChild('HumanoidRootPart')
		return root and root.Position
	end

	-- picks a match the way the lobby does: skip the ones still being created or locked to
	-- friends, then either the closest pad or the first id
	local function findMatch()
		local models = deadlydelivery.models()
		local origin = position()
		local bestId, bestDistance

		for id, match in deadlydelivery.matches() do
			if deadlydelivery.joinable(match) then
				local model = models[id]
				local pad = model and model.PrimaryPart

				if PickNearest.Enabled and origin and pad then
					local distance = (pad.Position - origin).Magnitude
					if not bestDistance or distance < bestDistance then
						bestId, bestDistance = id, distance
					end
				else
					bestId = bestId or id
				end
			end
		end

		return bestId
	end

	-- the difficulty the client itself allows: relaxed needs floor 5, hardcore needs floor 15
	local function difficulty()
		local level = deadlydelivery.dungeonLevel()
		local mode = Mode.Value
		if mode == 'Easy' and level < 5 then
			mode = 'Normal'
		elseif mode == 'Hard' and level < 15 then
			mode = 'Normal'
		end

		return mode == 'Any' and 'Normal' or mode
	end

	AutoLobby = vape.Categories.Utility:CreateModule({
		Name = 'AutoLobby',
		Function = function(callback)
			if not callback then return end

			local lastJoin = 0
			local uploaded

			repeat
				local id = deadlydelivery.matchId()

				if not id then
					uploaded = nil
					local hasSpace = not RequireSpace.Enabled or not deadlydelivery.backpackFull()
					if hasSpace and os.clock() - lastJoin >= Delay.Value then
						local target = findMatch()
						if target and deadlydelivery.join(target) then
							lastJoin = os.clock()
						end
					end
				elseif uploaded ~= id then
					-- the match only starts once the party settings are uploaded, and the game
					-- opens its Match panel for them; drop the panel after sending ours
					local match = deadlydelivery.matches()[id]
					if match and match.matchState == 'Creating' then
						uploaded = id
						deadlydelivery.upload({
							size = PartySize.Value,
							mode = difficulty(),
							onlyFriends = false
						})
						deadlydelivery.closeMatchUI()
					end
				end

				task.wait(0.5)
			until not AutoLobby.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Joins a match from the lobby by itself and uploads the party settings so the run starts'
	})

	Mode = AutoLobby:CreateDropdown({
		Name = 'Mode',
		List = {'Any', 'Normal', 'Easy', 'Hard'},
		Tooltip = 'Difficulty uploaded with the party, falls back to Normal when the floor is too low'
	})
	PickNearest = AutoLobby:CreateToggle({
		Name = 'Nearest pad',
		Default = true,
		Tooltip = 'Picks the closest pad, off picks the first joinable match'
	})
	PartySize = AutoLobby:CreateSlider({
		Name = 'Party size',
		Min = 1,
		Max = 5,
		Default = 5
	})
	Delay = AutoLobby:CreateSlider({
		Name = 'Delay',
		Min = 1,
		Max = 30,
		Default = 3,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end
	})
	RequireSpace = AutoLobby:CreateToggle({
		Name = 'Require space',
		Default = true,
		Tooltip = 'Does not join while the backpack is full, the lobby blocks that too'
	})
end)


local AutoOffline
local Delay
local MinHours
local ShowClaim

run(function()
	-- the lobby fridge (Workspace.Func.Fridge) is an interactable: touching it fires
	-- TEvent.FireRemote("OfflineReward", tick()) and the server rolls the reward from
	-- Value.OfflineTime.Value, then zeroes the timer. Nothing in that call is tied to the
	-- player standing at the fridge, so the remote can be fired directly.
	local function offlineTime()
		local value = deadlydelivery.Value and deadlydelivery.Value.OfflineTime
		return value and value.Value
	end

	AutoOffline = vape.Categories.Utility:CreateModule({
		Name = 'AutoOffline',
		Function = function(callback)
			if not callback then return end

			local lastClaim = 0

			repeat
				local time = offlineTime()
				local minimum = MinHours.Value * 3600
				if typeof(time) == 'number' and time > 0 and time >= minimum and os.clock() - lastClaim >= Delay.Value then
					lastClaim = os.clock()
					deadlydelivery.fire('OfflineReward', tick())

					if ShowClaim.Enabled then
						vape:CreateNotification('AutoOffline', 'Claimed ' .. string.format('%.1f', time / 3600) .. 'h of offline rewards', 5, 'info')
					end
				end

				task.wait(1)
			until not AutoOffline.Enabled or vape.Loaded == nil
		end,
		Tooltip = 'Claims the fridge offline reward in the lobby once it reaches the minimum hours'
	})

	Delay = AutoOffline:CreateSlider({
		Name = 'Delay',
		Min = 1,
		Max = 30,
		Default = 3,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end
	})
	MinHours = AutoOffline:CreateSlider({
		Name = 'Min hours',
		Min = 0,
		Max = 12,
		Decimal = 10,
		Default = 0,
		Suffix = function(val)
			return val == 1 and 'hour' or 'hours'
		end,
		Tooltip = 'Only claims once the fridge holds at least this much offline time'
	})
	ShowClaim = AutoOffline:CreateToggle({
		Name = 'Notify',
		Default = true
	})
end)
