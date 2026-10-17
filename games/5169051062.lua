local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end
local vapeEvents = setmetatable({}, {
	__index = function(self, index)
		self[index] = Instance.new('BindableEvent')
		return self[index]
	end
})

local playersService = cloneref(game:GetService('Players'))
local inputService = cloneref(game:GetService('UserInputService'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local collectionService = cloneref(game:GetService('CollectionService'))
local runService = cloneref(game:GetService('RunService'))
local coreGui = cloneref(game:GetService('CoreGui'))

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local whitelist = vape.Libraries.whitelist
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo

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

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function notif(...)
	return vape:CreateNotification(...)
end

-- Futuretops: Rework (universe 1801716281) is a hub spread over several place ids, so the
-- product keeps one entry per place the way bedwars does:
--   5169051062      lobby, the hub itself (this base)
--   5411969757      VIP server, same hub
--   111037302411487 FT test server, same hub
-- The gamemode places it sends you to live under other place ids and need their own.
-- Nothing game specific is hooked yet, so the universal modules run as they are and
-- entitylib keeps its default team check (Player.Team); anything team based is a guess.


run(function()
	local AutoJoin
	
	-- the hub runs its own lobby browser: the server answers GET_PUBLIC_SERVERS with
	-- ("PUBLIC_SERVERS", {{Owner = userId, PlaceId = place, Players = {userIds}, ...}, ...})
	-- and JOIN_SERVER teleports into that lobby, so no roblox web request is involved
	local function requestLobbies(remote, timeout)
		local lobbies, connection
	
		connection = remote.OnClientEvent:Connect(function(kind, list)
			if kind == 'PUBLIC_SERVERS' and type(list) == 'table' then
				lobbies = list
			end
		end)
	
		remote:FireServer('GET_PUBLIC_SERVERS')
	
		local deadline = os.clock() + timeout
		repeat task.wait() until lobbies or os.clock() > deadline
		connection:Disconnect()
	
		return lobbies
	end
	
	local function findFullest(lobbies)
		local best
	
		for _, entry in lobbies do
			local players = type(entry.Players) == 'table' and #entry.Players or 0
			if players > 0 and (not best or players > best.Players) then
				best = {
					Owner = entry.Owner,
					PlaceId = entry.PlaceId,
					Players = players
				}
			end
		end
	
		return best
	end
	
	AutoJoin = vape.Categories.Utility:CreateModule({
		Name = 'AutoJoin',
		Function = function(callback)
			if not callback then return end
	
			-- acts once, so the toggle is dropped instead of staying lit
			AutoJoin:Toggle()
			notif('AutoJoin', 'Looking for the fullest lobby.', 2)
	
			local remote = replicatedStorage:FindFirstChild('Server')
			if not remote then
				notif('AutoJoin', 'Lobby remote not found', 5, 'warning')
				return
			end
	
			local lobbies = requestLobbies(remote, 3)
			if not lobbies then
				notif('AutoJoin', 'The lobby list did not arrive', 5, 'warning')
				return
			end
	
			local lobby = findFullest(lobbies)
			if not lobby then
				notif('AutoJoin', 'No joinable lobby found', 5, 'warning')
				return
			end
	
			-- the hub's own browser requests the details of a lobby and keeps them open for a
			-- moment before the accept button is even usable, so the same order is followed
			-- here instead of firing JOIN_SERVER straight off the list
			remote:FireServer('GET_SERVER_DATA', lobby.Owner, lobby.PlaceId)
			task.wait(1.3)
	
			notif('AutoJoin', 'Joining a '..lobby.Players..' player lobby.', 5)
			remote:FireServer('JOIN_SERVER', lobby.Owner, lobby.PlaceId)
		end,
		Tooltip = 'Joins the public lobby with the most players'
	})
	
end)