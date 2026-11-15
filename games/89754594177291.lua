local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))

local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local whitelist = vape.Libraries.whitelist
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo

local friends = vape.Categories.Friends
local useFriends = friends.Options['Use friends']
local recolorFriends = friends.Options['Recolor visuals']
local friendsColor = friends.Options['Friends color']

local israel = {
	Tycoons = nil,
	Config = nil,
	Remotes = nil
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

function israel.tycoonsFolder()
	israel.Tycoons = israel.Tycoons or workspace:FindFirstChild('IsraelTycoons')
	return israel.Tycoons
end

-- the plot a player owns, read off PlotIndex so it survives them respawning
function israel.plot(plr)
	plr = plr or lplr
	if not plr then return end

	local folder = israel.tycoonsFolder()
	local index = plr:GetAttribute('PlotIndex')
	if not folder or not index then return end

	return folder:FindFirstChild('Plot'..index)
end

function israel.plotOwner(plot)
	local userId = plot and plot:GetAttribute('OwnerUserId')
	if typeof(userId) ~= 'number' or userId == 0 then return end

	for _, plr in playersService:GetPlayers() do
		if plr.UserId == userId then
			return plr
		end
	end
end

function israel.shielded(plr)
	local plot = israel.plot(plr)
	if not plot then return false end

	return plot:GetAttribute('NewbieShield') == true
end

function israel.cash(plr)
	plr = plr or lplr
	return plr and plr:GetAttribute('Cash') or 0
end

function israel.rebirths(plr)
	plr = plr or lplr
	return plr and plr:GetAttribute('Rebirths') or 0
end

run(function()
	local folder = replicatedStorage:WaitForChild('IsraelTycoon', 30)
	if not folder then return end

	local remotes = folder:WaitForChild('Remotes', 30)
	if remotes then
		israel.Remotes = remotes
	end

	local config = folder:FindFirstChild('Config')
	if config then
		local suc, loaded = pcall(require, config)
		if suc then
			israel.Config = loaded
		end
	end
end)

vape.Libraries.israel = israel
vape:Clean(function()
	vape.Libraries.israel = nil
	table.clear(israel)
end)

run(function()
	entitylib.targetCheck = function(entity)
		if entity.TeamCheck then
			return entity:TeamCheck()
		end

		if entity.Health <= 0 then return false end

		if entity.Player then
			if isFriend(entity.Player) then return false end
			if not select(2, whitelist:get(entity.Player)) then return false end
		end

		return true
	end

	entitylib.getEntityColor = function(ent)
		if isFriend(ent.Player, true) then
			return Color3.fromHSV(friendsColor.Hue, friendsColor.Sat, friendsColor.Value)
		end
	end
end)
entitylib.start()

sessioninfo:AddItem('Shekels', 0, function()
	return tostring(israel.cash())
end, false)
sessioninfo:AddItem('Rebirths', 0, function()
	return tostring(israel.rebirths())
end, false)

for _, v in {'MurderMystery'} do
	vape:Remove(v)
end


run(function()
	local PlayerFling
	local Targets
	local Range
	local Speed
	local Step
	
	local function rootOf(entity)
		if entity.RootPart then return entity.RootPart end
		return entity.Character and entity.Character:FindFirstChild('HumanoidRootPart')
	end
	
	-- A single big CFrame jump gets rolled back, but nudging the root a few studs each frame
	-- stays inside the server's replication tolerance and accumulates into a real lift.
	PlayerFling = vape.Categories.Blatant:CreateModule({
		Name = 'Player Fling',
		Function = function(callback)
			if not callback then return end
	
			repeat
				local character = lplr.Character
				local myRoot = character and character:FindFirstChild('HumanoidRootPart')
				if myRoot then
					local entity = entitylib.EntityPosition({
						Part = 'RootPart',
						Range = Range.Value,
						Origin = myRoot.Position,
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled
					})
	
					local root = entity and rootOf(entity)
					if root then
						root.CFrame = CFrame.new(root.Position + Vector3.new(0, Speed.Value, 0)) * root.CFrame.Rotation
					end
				end
	
				for _ = 1, Step.Value do
					task.wait()
				end
			until not PlayerFling.Enabled
		end,
		Tooltip = 'Lifts the closest player in small CFrame steps the server treats as movement instead of a teleport'
	})
	Targets = PlayerFling:CreateTargets({
		Players = true,
		NPCs = false
	})
	Range = PlayerFling:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 500,
		Default = 200,
		Suffix = 'studs'
	})
	Speed = PlayerFling:CreateSlider({
		Name = 'Step',
		Min = 0.5,
		Max = 20,
		Default = 1,
		Decimal = 10,
		Tooltip = 'Studs added per push; about 1 per frame survives, larger values get rolled back'
	})
	Step = PlayerFling:CreateSlider({
		Name = 'Delay Frames',
		Min = 1,
		Max = 30,
		Default = 1,
		Tooltip = 'Frames to wait between pushes'
	})
	
end)

run(function()
	local BuyableESP
	local ShowPrice
	local OnlyAffordable
	local Color
	local AffordableColor
	local Scale
	local getfontbounds = vape.Libraries.getfontbounds
	local uipallet = vape.Libraries.uipallet
	local parented = {}
	local nextRefresh = 0
	local Folder = Instance.new('Folder')
	Folder.Name = 'BuyableESP'
	Folder.Parent = vape.holder
	
	-- Button_<Id> is the only link back to Config, which is where the price and label live
	local function itemFor(button)
		local config = israel.Config
		if not config or not config.Items then return end
	
		local id = button.Name:match('^Button_(.+)$')
		if not id then return end
	
		for _, item in config.Items do
			if item.Id == id then
				return item
			end
		end
	end
	
	local function affordable(item)
		return israel.cash() >= (item.Price or 0)
	end
	
	local function colorFor(item)
		if affordable(item) then
			return Color3.fromHSV(AffordableColor.Hue, AffordableColor.Sat, AffordableColor.Value)
		end
	
		return Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	end
	
	local function Removed(button)
		local data = parented[button]
		if not data then return end
	
		if data.connection then
			data.connection:Disconnect()
		end
	
		if data.billboard then
			data.billboard:Destroy()
		end
	
		parented[button] = nil
	end
	
	local function Added(button)
		if parented[button] then return end
	
		local item = itemFor(button)
		if not item then return end
		if OnlyAffordable.Enabled and not affordable(item) then return end
	
		local target = button:FindFirstChildWhichIsA('BasePart', true)
		if not target then return end
	
		local label = ShowPrice.Enabled and (item.Name..' - '..(item.Price or 0)) or item.Name
		local size = getfontbounds(label, 14 * Scale.Value, uipallet.Font, Vector2.new(100000, 100000))
	
		local billboard = Instance.new('BillboardGui')
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
		billboard.Adornee = target
		billboard.Parent = Folder
	
		local text = Instance.new('TextLabel')
		text.BackgroundTransparency = 1
		text.BorderSizePixel = 0
		text.FontFace = uipallet.Font
		text.Size = billboard.Size
		text.Text = label
		text.TextColor3 = colorFor(item)
		text.TextSize = 14 * Scale.Value
		text.TextStrokeTransparency = 1
		text.TextStrokeColor3 = Color3.new()
		text.Parent = billboard
	
		parented[button] = {
			billboard = billboard,
			text = text,
			item = item,
			connection = button.Destroying:Connect(function()
				Removed(button)
			end)
		}
	end
	
	local function Rescan()
		for button in parented do
			Removed(button)
		end
	
		local plot = israel.plot(lplr)
		local buttons = plot and plot:FindFirstChild('Buttons')
		if not buttons then return end
	
		for _, button in buttons:GetChildren() do
			Added(button)
		end
	end
	
	BuyableESP = vape.Categories.Render:CreateModule({
		Name = 'BuyableESP',
		Function = function(callback)
			if callback then
				BuyableESP:Clean(runService.Heartbeat:Connect(function()
					local now = os.clock()
					if now < nextRefresh then return end
	
					nextRefresh = now + 0.5
					for button, data in parented do
						data.text.TextColor3 = colorFor(data.item)
					end
				end))
	
				Rescan()
			else
				for button in parented do
					Removed(button)
				end
			end
		end,
		Tooltip = 'Labels every buyable on your plot with its name and price'
	})
	ShowPrice = BuyableESP:CreateToggle({
		Name = 'Show Price',
		Function = function()
			if BuyableESP.Enabled then
				BuyableESP:Toggle()
				BuyableESP:Toggle()
			end
		end,
		Default = true
	})
	OnlyAffordable = BuyableESP:CreateToggle({
		Name = 'Only Affordable',
		Function = function()
			if BuyableESP.Enabled then
				BuyableESP:Toggle()
				BuyableESP:Toggle()
			end
		end
	})
	Color = BuyableESP:CreateColorSlider({
		Name = 'Too Expensive Color',
		DefaultValue = 0,
		DefaultSat = 1,
		Function = function()
			if BuyableESP.Enabled then
				BuyableESP:Toggle()
				BuyableESP:Toggle()
			end
		end
	})
	AffordableColor = BuyableESP:CreateColorSlider({
		Name = 'Affordable Color',
		DefaultValue = 0.33,
		Function = function()
			if BuyableESP.Enabled then
				BuyableESP:Toggle()
				BuyableESP:Toggle()
			end
		end
	})
	Scale = BuyableESP:CreateSlider({
		Name = 'Text Scale',
		Min = 0.1,
		Max = 1.5,
		Default = 0.8,
		Function = function()
			if BuyableESP.Enabled then
				BuyableESP:Toggle()
				BuyableESP:Toggle()
			end
		end,
		Decimal = 10
	})
	
end)

run(function()
	local PlotESP
	local ShowText
	local Color
	local OwnColor
	local ShieldColor
	local FillTransparency
	local OutlineTransparency
	local Scale
	local referenced = {}
	local nextRefresh = 0
	local getfontbounds = vape.Libraries.getfontbounds
	local uipallet = vape.Libraries.uipallet
	local Folder = Instance.new('Folder')
	Folder.Name = 'PlotESP'
	Folder.Parent = vape.holder
	
	local function plotLabel(plot)
		local owner = israel.plotOwner(plot)
		local name = owner and owner.DisplayName or 'Empty'
		if plot:GetAttribute('NewbieShield') == true then
			name = name..' (shield)'
		end
	
		return name
	end
	
	local function plotColor(plot)
		if israel.plotOwner(plot) == lplr then
			return Color3.fromHSV(OwnColor.Hue, OwnColor.Sat, OwnColor.Value)
		end
	
		if plot:GetAttribute('NewbieShield') == true then
			return Color3.fromHSV(ShieldColor.Hue, ShieldColor.Sat, ShieldColor.Value)
		end
	
		return Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	end
	
	local function refreshText()
		for plot, data in referenced do
			if data.text then
				data.text.Text = plotLabel(plot)
				data.text.TextColor3 = plotColor(plot)
			end
			if data.highlight then
				data.highlight.OutlineColor = plotColor(plot)
			end
		end
	end
	
	local function Removed(plot)
		local data = referenced[plot]
		if not data then return end
	
		if data.connection then
			data.connection:Disconnect()
		end
	
		if data.highlight then
			data.highlight:Destroy()
		end
	
		if data.billboard then
			data.billboard:Destroy()
		end
	
		referenced[plot] = nil
	end
	
	local function Added(plot)
		if referenced[plot] then return end
	
		local target = plot.PrimaryPart or plot:FindFirstChild('Base')
		if not target then return end
	
		local highlight = Instance.new('Highlight')
		highlight.Adornee = target
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = plotColor(plot)
		highlight.OutlineColor = plotColor(plot)
		highlight.FillTransparency = FillTransparency.Value
		highlight.OutlineTransparency = OutlineTransparency.Value
		highlight.Parent = Folder
	
		local billboard
		local text
		if ShowText.Enabled then
			local size = getfontbounds('Empty (shield)', 14 * Scale.Value, uipallet.Font, Vector2.new(100000, 100000))
			billboard = Instance.new('BillboardGui')
			billboard.AlwaysOnTop = true
			billboard.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
			billboard.Adornee = target
			billboard.Parent = Folder
	
			text = Instance.new('TextLabel')
			text.BackgroundTransparency = 1
			text.BorderSizePixel = 0
			text.FontFace = uipallet.Font
			text.RichText = true
			text.Size = billboard.Size
			text.Text = plotLabel(plot)
			text.TextColor3 = plotColor(plot)
			text.TextSize = 14 * Scale.Value
			text.TextStrokeTransparency = 1
			text.TextStrokeColor3 = Color3.new()
			text.Parent = billboard
		end
	
		referenced[plot] = {
			highlight = highlight,
			billboard = billboard,
			text = text,
			titleConnection = plot:GetAttributeChangedSignal('OwnerUserId'):Connect(refreshText),
			shieldConnection = plot:GetAttributeChangedSignal('NewbieShield'):Connect(refreshText),
			connection = plot.Destroying:Connect(function()
				Removed(plot)
			end)
		}
	end
	
	local function Rescan()
		for plot in referenced do
			Removed(plot)
		end
	
		local folder = israel.tycoonsFolder()
		if not folder then return end
	
		for _, plot in folder:GetChildren() do
			Added(plot)
		end
	end
	
	PlotESP = vape.Categories.Render:CreateModule({
		Name = 'PlotESP',
		Function = function(callback)
			if callback then
				local folder = israel.tycoonsFolder()
				if folder then
					PlotESP:Clean(folder.ChildAdded:Connect(Added))
					PlotESP:Clean(folder.ChildRemoved:Connect(Removed))
				end
	
				PlotESP:Clean(playersService.PlayerAdded:Connect(function()
					refreshText()
				end))
				PlotESP:Clean(playersService.PlayerRemoving:Connect(function()
					refreshText()
				end))
				PlotESP:Clean(runService.Heartbeat:Connect(function()
					if not ShowText.Enabled then return end
	
					local now = os.clock()
					if now < nextRefresh then return end
	
					nextRefresh = now + 0.25
					refreshText()
				end))
	
				Rescan()
			else
				for plot in referenced do
					Removed(plot)
				end
			end
		end,
		Tooltip = 'Highlights every tycoon plot with its owner'
	})
	ShowText = PlotESP:CreateToggle({
		Name = 'Owner',
		Function = function()
			if PlotESP.Enabled then
				PlotESP:Toggle()
				PlotESP:Toggle()
			end
		end,
		Default = true
	})
	Color = PlotESP:CreateColorSlider({
		Name = 'Color',
		Function = function()
			refreshText()
		end
	})
	OwnColor = PlotESP:CreateColorSlider({
		Name = 'Own Plot Color',
		DefaultValue = 0.35,
		Function = function()
			refreshText()
		end
	})
	ShieldColor = PlotESP:CreateColorSlider({
		Name = 'Shielded Color',
		DefaultValue = 0.6,
		Function = function()
			refreshText()
		end
	})
	FillTransparency = PlotESP:CreateSlider({
		Name = 'Fill Transparency',
		Min = 0,
		Max = 1,
		Default = 0.8,
		Function = function(val)
			for plot, data in referenced do
				data.highlight.FillTransparency = val
			end
		end,
		Decimal = 10
	})
	OutlineTransparency = PlotESP:CreateSlider({
		Name = 'Outline Transparency',
		Min = 0,
		Max = 1,
		Default = 0,
		Function = function(val)
			for plot, data in referenced do
				data.highlight.OutlineTransparency = val
			end
		end,
		Decimal = 10
	})
	Scale = PlotESP:CreateSlider({
		Name = 'Text Scale',
		Min = 0.1,
		Max = 1.5,
		Default = 1,
		Function = function()
			if PlotESP.Enabled then
				PlotESP:Toggle()
				PlotESP:Toggle()
			end
		end,
		Decimal = 10
	})
	
end)

run(function()
	local ZoneESP
	local ShowText
	local Color
	local HeldColor
	local FillTransparency
	local OutlineTransparency
	local referenced = {}
	local nextRefresh = 0
	local getfontbounds = vape.Libraries.getfontbounds
	local uipallet = vape.Libraries.uipallet
	local Folder = Instance.new('Folder')
	Folder.Name = 'ZoneESP'
	Folder.Parent = vape.holder
	
	local function zoneColor(zone)
		-- HolderUserId is the only stable signal: State is a display word (Neutral/Held/...)
		local holderId = zone:GetAttribute('HolderUserId')
		if typeof(holderId) == 'number' and holderId ~= 0 then
			return Color3.fromHSV(HeldColor.Hue, HeldColor.Sat, HeldColor.Value)
		end
	
		return Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	end
	
	local function zoneLabel(zone)
		local state = zone:GetAttribute('State') or 'Neutral'
		local holder = zone:GetAttribute('HolderName')
		local capturer = zone:GetAttribute('CapturerName')
		local progress = zone:GetAttribute('Progress')
	
		if typeof(capturer) == 'string' and capturer ~= '' then
			return 'Capturing: '..capturer..(typeof(progress) == 'number' and (' '..math.floor(progress)..'%') or '')
		end
	
		if typeof(holder) == 'string' and holder ~= '' then
			return holder..' ('..state..')'
		end
	
		return state
	end
	
	local function refreshText()
		for zone, data in referenced do
			if data.text then
				data.text.Text = zoneLabel(zone)
				data.text.TextColor3 = zoneColor(zone)
			end
	
			if data.highlight then
				data.highlight.OutlineColor = zoneColor(zone)
			end
		end
	end
	
	local function Removed(zone)
		local data = referenced[zone]
		if not data then return end
	
		if data.connections then
			for _, connection in data.connections do
				connection:Disconnect()
			end
		end
	
		if data.connection then
			data.connection:Disconnect()
		end
	
		if data.highlight then
			data.highlight:Destroy()
		end
	
		if data.billboard then
			data.billboard:Destroy()
		end
	
		referenced[zone] = nil
	end
	
	local function Added(zone)
		if referenced[zone] then return end
	
		local target = zone.PrimaryPart or zone:FindFirstChildWhichIsA('BasePart', true)
		if not target then return end
	
		local highlight = Instance.new('Highlight')
		highlight.Adornee = target
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = zoneColor(zone)
		highlight.OutlineColor = zoneColor(zone)
		highlight.FillTransparency = FillTransparency.Value
		highlight.OutlineTransparency = OutlineTransparency.Value
		highlight.Parent = Folder
	
		local billboard
		local text
		if ShowText.Enabled then
			local size = getfontbounds('Neutral 100%', 14, uipallet.Font, Vector2.new(100000, 100000))
			billboard = Instance.new('BillboardGui')
			billboard.AlwaysOnTop = true
			billboard.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
			billboard.Adornee = target
			billboard.Parent = Folder
	
			text = Instance.new('TextLabel')
			text.BackgroundTransparency = 1
			text.BorderSizePixel = 0
			text.FontFace = uipallet.Font
			text.Size = billboard.Size
			text.Text = zoneLabel(zone)
			text.TextColor3 = zoneColor(zone)
			text.TextSize = 14
			text.TextStrokeTransparency = 1
			text.TextStrokeColor3 = Color3.new()
			text.Parent = billboard
		end
	
		local connections = {}
		for _, attribute in {'State', 'Progress', 'HolderName', 'HolderUserId', 'CapturerName'} do
			table.insert(connections, zone:GetAttributeChangedSignal(attribute):Connect(refreshText))
		end
	
		referenced[zone] = {
			highlight = highlight,
			billboard = billboard,
			text = text,
			connections = connections,
			connection = zone.Destroying:Connect(function()
				Removed(zone)
			end)
		}
	end
	
	ZoneESP = vape.Categories.Render:CreateModule({
		Name = 'ZoneESP',
		Function = function(callback)
			if callback then
				local map = workspace:FindFirstChild('Map')
				local zone = map and map:FindFirstChild('CaptureZone')
				if zone then
					Added(zone)
				end
	
				if map then
					ZoneESP:Clean(map.ChildAdded:Connect(function(child)
						if child.Name == 'CaptureZone' then
							Added(child)
						end
					end))
				end
	
				ZoneESP:Clean(runService.Heartbeat:Connect(function()
					if not ShowText.Enabled then return end
	
					local now = os.clock()
					if now < nextRefresh then return end
	
					nextRefresh = now + 0.25
					refreshText()
				end))
			else
				for zone in referenced do
					Removed(zone)
				end
			end
		end,
		Tooltip = 'Highlights the capture zone and shows who holds it'
	})
	ShowText = ZoneESP:CreateToggle({
		Name = 'Status',
		Function = function()
			if ZoneESP.Enabled then
				ZoneESP:Toggle()
				ZoneESP:Toggle()
			end
		end,
		Default = true
	})
	Color = ZoneESP:CreateColorSlider({
		Name = 'Color',
		Function = function()
			refreshText()
		end
	})
	HeldColor = ZoneESP:CreateColorSlider({
		Name = 'Held Color',
		DefaultValue = 0.55,
		Function = function()
			refreshText()
		end
	})
	FillTransparency = ZoneESP:CreateSlider({
		Name = 'Fill Transparency',
		Min = 0,
		Max = 1,
		Default = 0.85,
		Function = function(val)
			for zone, data in referenced do
				data.highlight.FillTransparency = val
			end
		end,
		Decimal = 10
	})
	OutlineTransparency = ZoneESP:CreateSlider({
		Name = 'Outline Transparency',
		Min = 0,
		Max = 1,
		Default = 0,
		Function = function(val)
			for zone, data in referenced do
				data.highlight.OutlineTransparency = val
			end
		end,
		Decimal = 10
	})
	
end)

run(function()
	local AutoFarm
	local Collect
	local Buy
	local BuyDelay
	
	local function touch(part)
		local hrp = lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart')
		if not hrp then return end
	
		local fire = getgenv().firetouchinterest
		if typeof(fire) ~= 'function' then return end
	
		pcall(fire, hrp, part, 0)
		pcall(fire, hrp, part, 1)
	end
	
	-- the cash pad pays out on touch, and PendingCash tells us whether there is anything to take
	local function collectPad(plot)
		if (plot:GetAttribute('PendingCash') or 0) <= 0 then return end
	
		local cashPad = plot:FindFirstChild('CashPad')
		local pad = cashPad and cashPad:FindFirstChild('Pad')
		if pad then
			touch(pad)
		end
	end
	
	-- buttons are Button_<ItemId> pads and Config holds the price, so only offer what we can
	-- afford and take the cheapest first
	local function cheapestAffordable(plot)
		local config = israel.Config
		local buttons = plot:FindFirstChild('Buttons')
		if not config or not buttons then return end
	
		local byId = {}
		for _, item in config.Items do
			if item.Id then
				byId[item.Id] = item
			end
		end
	
		local cash = israel.cash()
		local best, bestPrice
		for _, button in buttons:GetChildren() do
			local id = button.Name:match('^Button_(.+)$')
			local item = id and byId[id]
			local price = item and (item.Price or 0)
			if price and price <= cash and (not bestPrice or price < bestPrice) then
				local pad = button:FindFirstChild('Pad')
				if pad then
					best, bestPrice = pad, price
				end
			end
		end
	
		return best
	end
	
	AutoFarm = vape.Categories.Utility:CreateModule({
		Name = 'AutoFarm',
		Function = function(callback)
			if not callback then return end
	
			local nextBuy = 0
	
			repeat
				local plot = israel.plot(lplr)
				if plot then
					if Collect.Enabled then
						collectPad(plot)
					end
	
					if Buy.Enabled and os.clock() >= nextBuy then
						local pad = cheapestAffordable(plot)
						if pad then
							touch(pad)
							nextBuy = os.clock() + (BuyDelay.Value / 60)
						end
					end
				end
	
				task.wait()
			until not AutoFarm.Enabled
		end,
		Tooltip = 'Collects the cash pad and buys the cheapest upgrade it can afford'
	})
	Collect = AutoFarm:CreateToggle({
		Name = 'Collect',
		Default = true,
		Tooltip = 'Fires the cash pad touch whenever there is something to collect'
	})
	Buy = AutoFarm:CreateToggle({
		Name = 'Buy Upgrades',
		Default = true,
		Tooltip = 'Buys the cheapest button you can currently afford'
	})
	BuyDelay = AutoFarm:CreateSlider({
		Name = 'Buy Delay',
		Min = 1,
		Max = 60,
		Default = 6,
		Tooltip = 'Frames between purchases so the server does not drop them'
	})
	
end)

run(function()
	local PlotSpy
	local FontOption
	local TextSize
	local HideMine
	local holder
	local label
	
	local function formatCash(value)
		local suffix = ''
		for _, unit in {{1e12, 'T'}, {1e9, 'B'}, {1e6, 'M'}, {1e3, 'K'}} do
			if value >= unit[1] then
				suffix = unit[2]
				value = value / unit[1]
				break
			end
		end
	
		return string.format(value >= 100 and '%.0f' or '%.1f', value)..suffix
	end
	
	-- PendingCash is the income sitting uncollected on a plot, which is the only public number
	-- that hints at how rich its owner is
	local function buildLines()
		local folder = israel.tycoonsFolder()
		if not folder then return {} end
	
		local list = {}
		for _, plot in folder:GetChildren() do
			local owner = israel.plotOwner(plot)
			if owner ~= lplr or not HideMine.Enabled then
				local items = plot:FindFirstChild('Items')
				table.insert(list, {
					owner = owner and owner.DisplayName or 'Empty',
					cash = plot:GetAttribute('PendingCash') or 0,
					items = items and #items:GetChildren() or 0,
					shield = plot:GetAttribute('NewbieShield') == true,
					mine = owner == lplr
				})
			end
		end
	
		table.sort(list, function(a, b)
			return a.cash > b.cash
		end)
	
		local lines = {}
		for _, row in list do
			local text = row.owner..': '..formatCash(row.cash)..' / '..row.items..' items'
			if row.shield then
				text = text..' [shield]'
			end
			if row.mine then
				text = text..' [you]'
			end
	
			table.insert(lines, text)
		end
	
		return lines
	end
	
	local function render()
		if not label then return end
	
		local lines = buildLines()
		label.Text = #lines > 0 and table.concat(lines, '\n') or 'No plots found'
		label.FontFace = FontOption.Value
		label.TextSize = TextSize.Value
	
		local size = getfontbounds(label.Text, label.TextSize, label.FontFace, Vector2.new(100000, 100000))
		holder.Size = UDim2.fromOffset(size.X + 16, size.Y + 16)
	end
	
	PlotSpy = vape:CreateOverlay({
		Name = 'Plot Spy',
		Icon = getvapeasset('newvape/assets/new/textgui.png'),
		Size = UDim2.fromOffset(16, 12),
		Position = UDim2.fromOffset(12, 14),
		Function = function(callback)
			if not callback then return end
	
			repeat
				render()
				task.wait(1)
			until not PlotSpy.Button or not PlotSpy.Button.Enabled
		end
	})
	FontOption = PlotSpy:CreateFont({
		Name = 'Font',
		Blacklist = 'Arial'
	})
	TextSize = PlotSpy:CreateSlider({
		Name = 'Text Size',
		Min = 10,
		Max = 24,
		Default = 14,
		Function = function()
			render()
		end
	})
	HideMine = PlotSpy:CreateToggle({
		Name = 'Hide Own Plot',
		Function = function()
			render()
		end
	})
	PlotSpy:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			holder.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
			holder.BackgroundTransparency = 1 - opacity
		end
	})
	
	holder = Instance.new('Frame')
	holder.BackgroundColor3 = Color3.new()
	holder.BackgroundTransparency = 0.5
	holder.Parent = PlotSpy.Children
	vape:Clean(PlotSpy.Children:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
		if vape.ThreadFix then
			setthreadidentity(8)
		end
	
		local right = PlotSpy.Children.AbsolutePosition.X > (vape.gui.AbsoluteSize.X / 2)
		holder.Position = UDim2.fromScale(right and 1 or 0, 0)
		holder.AnchorPoint = Vector2.new(right and 1 or 0, 0)
	end))
	local corner = Instance.new('UICorner')
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = holder
	label = Instance.new('TextLabel')
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arial
	label.Position = UDim2.fromOffset(8, 8)
	label.Size = UDim2.new(1, -16, 1, -16)
	label.Text = ''
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 14
	label.TextStrokeColor3 = Color3.new()
	label.TextStrokeTransparency = 0.8
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = holder
	
end)