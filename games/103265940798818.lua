local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local starterPlayer = cloneref(game:GetService('StarterPlayer'))
local inputService = cloneref(game:GetService('UserInputService'))

local vape = shared.vape
local sessioninfo = vape.Libraries.sessioninfo

local Remotes
local FishingAction
local FishingEvent
local PlayerData
local FishingController
local StoreController
local GameConfig
local CastConfig
local Casts
local Catches

local function notif(...)
	return vape:CreateNotification(...)
end

local function getContext()
	for _, v in getgc(true) do
		if type(v) == 'table' and rawget(v, 'FishingController') and rawget(v, 'PlayerData') and rawget(v, 'StoreController') then
			return v
		end
	end
end

local function canCast()
	if not FishingController or not FishingAction then return false end
	if FishingController:GetState() ~= 'Idle' then return false end
	if not FishingController:IsInZone() then return false end
	if not PlayerData.Loaded or not PlayerData.Data then return false end
	local magnet = PlayerData.Data.EquippedMagnet
	return magnet ~= nil and magnet ~= ''
end

local function perfectHold(offset)
	local zone = CastConfig.PerfectZone
	local position = math.clamp(1 - (zone / 2) + ((offset or 0) / 100), 0, 1)
	return CastConfig.CycleTime / 2 * position
end

local function currentCastId()
	if not FishingController then return nil end
	local state = FishingController:QA()
	return type(state) == 'table' and state.CastId or nil
end

local function pressCast()
	if mouse1press then
		mouse1press()
	end
end

local function releaseCast()
	if mouse1release then
		mouse1release()
	end
end

local function castAndHold(offset)
	pressCast()
	task.wait(perfectHold(offset))
	releaseCast()
end

run(function()
	local controllers = starterPlayer.StarterPlayerScripts:WaitForChild('Controllers', workspace.StreamingEnabled and math.huge or 30)
	local sharedFolder = replicatedStorage:WaitForChild('Shared', 30)

	if not controllers or not sharedFolder then return end

	Remotes = replicatedStorage:WaitForChild('Remotes', 30)
	if not Remotes then return end

	FishingAction = Remotes:WaitForChild('FishingAction')
	FishingEvent = Remotes:WaitForChild('FishingEvent')

	GameConfig = require(sharedFolder.Config.GameConfig)
	CastConfig = GameConfig.Cast

	local ctx
	repeat
		ctx = getContext()
		if not ctx then task.wait(0.25) end
	until ctx or vape.Loaded == nil

	if vape.Loaded == nil then return end

	PlayerData = ctx.PlayerData
	FishingController = ctx.FishingController
	StoreController = ctx.StoreController

	Casts = sessioninfo:AddItem('Casts', 0, nil, false)
	Catches = sessioninfo:AddItem('Catches', 0, nil, false)

	vape:Clean(FishingEvent.OnClientEvent:Connect(function(message, data)
		if message == 'ChargeAck' then
			Casts:Increment()
		elseif message == 'Caught' then
			Catches:Increment()
		end
	end))
end)

for _, v in {'AimAssist', 'Reach', 'SilentAim', 'TriggerBot', 'Killaura', 'HitBoxes', 'TargetStrafe', 'AutoClicker', 'Speed'} do
	vape:Remove(v)
end


run(function()
	local AutoFish
	local HoldOffset
	local RecastDelay
	
	AutoFish = vape.Categories.Utility:CreateModule({
		Name = 'AutoFish',
		Function = function(callback)
			if callback then
				repeat
					if canCast() then
						castAndHold(HoldOffset.Value)
	
						local deadline = os.clock() + 10
						repeat task.wait(0.05) until FishingController:GetState() == 'Reeling' or os.clock() > deadline
	
						local reelStart = os.clock()
						while FishingController:GetState() == 'Reeling' and os.clock() - reelStart < 15 do
							FishingAction:FireServer('Tap', currentCastId())
							task.wait(0.1)
						end
	
						local settle = os.clock() + 5
						repeat task.wait(0.1) until FishingController:GetState() == 'Idle' or os.clock() > settle
						task.wait(RecastDelay.Value)
					end
	
					task.wait(0.1)
				until not AutoFish.Enabled
			end
		end,
		Tooltip = 'Casts, holds for a perfect meter and reels the magnet back in.'
	})
	HoldOffset = AutoFish:CreateSlider({
		Name = 'Hold Offset',
		Min = -20,
		Max = 20,
		Default = 0,
		Decimal = 1,
		Suffix = 'ms',
		Tooltip = 'Shifts the perfect hold timing when casts get rejected.'
	})
	RecastDelay = AutoFish:CreateSlider({
		Name = 'Recast Delay',
		Min = 0.1,
		Max = 3,
		Default = 0.8,
		Decimal = 10,
		Suffix = 's',
		Tooltip = 'Time to wait before casting again.'
	})
	
end)

run(function()
	local AutoSell
	local Threshold
	
	local SellRequest
	local TravelRequest
	
	local function isBagFull()
		local capacity = StoreController:BagCapacity()
		return PlayerData:InventoryCount() >= math.floor(capacity * (Threshold.Value / 100))
	end
	
	local function travel(where)
		local ok, result = pcall(function()
			return TravelRequest:InvokeServer(where)
		end)
		return ok and type(result) == 'table' and result.Ok
	end
	
	local function sellAll()
		local ok, result = pcall(function()
			return SellRequest:InvokeServer({Action = 'SellAll'})
		end)
		return ok and type(result) == 'table' and result.Ok and result.Payout or 0
	end
	
	AutoSell = vape.Categories.Utility:CreateModule({
		Name = 'AutoSell',
		Function = function(callback)
			if callback then
				SellRequest = SellRequest or Remotes:WaitForChild('SellRequest')
				TravelRequest = TravelRequest or Remotes:WaitForChild('TravelRequest')
	
				repeat
					if isBagFull() and FishingController:GetState() == 'Idle' then
						travel('Sell')
						task.wait(0.6)
						local payout = sellAll()
	
						if payout > 0 then
							notif('AutoSell', 'Sold for $'..tostring(math.floor(payout)), 3)
						end
	
						task.wait(0.4)
						travel('Base')
						task.wait(1)
					end
	
					task.wait(0.5)
				until not AutoSell.Enabled
			end
		end,
		Tooltip = 'Travels to the sell station and sells everything when the bag is full.'
	})
	Threshold = AutoSell:CreateSlider({
		Name = 'Bag Threshold',
		Min = 50,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Suffix = '%',
		Tooltip = 'Bag fullness at which AutoSell triggers.'
	})
	
end)

run(function()
	local AutoUpgrade
	local Priority
	local UpgradeRequest
	local UpgradeConfig
	
	local levelKeys = {
		BaseLuck = 'BaseLuckLevel',
		Rope = 'RopeLevel',
		ReelPower = 'ReelPowerLevel'
	}
	
	local function getLevel(upgrade)
		local data = PlayerData.Data
		return data and data[levelKeys[upgrade]] or 1
	end
	
	local function tryUpgrade(upgrade)
		local level = getLevel(upgrade)
		local nextLevel = UpgradeConfig.GetLevel(upgrade, level + 1)
		if not nextLevel then return false end
	
		local cash = PlayerData.Data and PlayerData.Data.Cash or 0
		if cash < nextLevel.Price then return false end
	
		local ok, result = pcall(function()
			return UpgradeRequest:InvokeServer({Key = upgrade})
		end)
	
		if ok and type(result) == 'table' and result.Ok then
			notif('AutoUpgrade', upgrade..' upgraded to '..tostring(level + 1), 3)
			return true
		end
	
		return false
	end
	
	AutoUpgrade = vape.Categories.Utility:CreateModule({
		Name = 'AutoUpgrade',
		Function = function(callback)
			if callback then
				UpgradeRequest = UpgradeRequest or Remotes:WaitForChild('UpgradeRequest')
				UpgradeConfig = UpgradeConfig or require(replicatedStorage.Shared.Config.UpgradeConfig)
	
				repeat
					if PlayerData.Loaded then
						local order = Priority.Value == 'Cash Value' and {'ReelPower', 'Rope', 'BaseLuck'} or UpgradeConfig.Order
	
						for _, upgrade in order do
							if tryUpgrade(upgrade) then break end
						end
					end
	
					task.wait(1)
				until not AutoUpgrade.Enabled
			end
		end,
		Tooltip = 'Buys the next upgrade whenever you can afford it.'
	})
	Priority = AutoUpgrade:CreateDropdown({
		Name = 'Priority',
		List = {'Default', 'Cash Value'},
		Function = function(val)
			if AutoUpgrade.Enabled then
				AutoUpgrade:Toggle()
				AutoUpgrade:Toggle()
			end
		end
	})
	
end)

run(function()
	local PerfectCast
	local Notify
	
	PerfectCast = vape.Categories.Utility:CreateModule({
		Name = 'PerfectCast',
		Function = function(callback)
			if callback then
				PerfectCast:Clean(inputService.InputBegan:Connect(function(input, processed)
					if processed then return end
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end
					if not canCast() then return end
	
					castAndHold(0)
	
					if Notify.Enabled then
						notif('PerfectCast', 'Released at '..string.format('%.2f', perfectHold(0))..'s', 1)
					end
				end))
			end
		end,
		Tooltip = 'Releases your cast at the perfect meter position every time.'
	})
	Notify = PerfectCast:CreateToggle({
		Name = 'Notifications',
		Default = true
	})
	
end)