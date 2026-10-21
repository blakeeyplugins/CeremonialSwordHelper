-- Set to true to show the numbers box (for checking the maths)
local DEBUG = false

-- Set to false to turn off the "hit this next button" (Unsure if this violates the rules, so included this to disable it if needed)
local SHOW_NEXT_SPOT = true

-- Find the layer plugins can draw
local gameWindow = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

-- Debug box showing the raw numbers (only visible when DEBUG is on)
local box = ui.GroupBox.new(gameWindow)
box.stylesheetID = id.StyleSheet.DEFAULT
box:SetHeaderLayout(0, 0, 0, 0, 0)
box:SetSize(260, 170)
box:SetPos(0, 0, 0.6, 0.3)
local label = ui.Text.new(box)
label:SetSize(0, 0, 1.0, 1.0)
label:SetPos(0,0)
label.font = id.Font.MUSEO_SANS_15PT_REGULAR
label:AlignTo(ui.AlignMode.CENTRE)
label.content = "Sword Helper"

-- How much more one spot needs (target minus current)
local function getNeeds(spot)
	local current = var.VarPlayer["ARTISAN_POS_" .. spot].value
	local target = var.VarPlayer["ARTISAN_DEMO_" .. spot].value
	return target - current
end

-- Rebuild text in helper window
local function updateHelper()
	local topRow = "Top:"
	local bottomRow = "Bottom:"
	for spot = 1, 8 do
		topRow = topRow .. " " .. getNeeds(spot)
		bottomRow = bottomRow .. " " .. getNeeds(spot + 8)
	end
	local hitsLeft = var.VarPlayer.ARTISAN_COUNTDOWN.value
	label.content = topRow .. "<br>" .. bottomRow .. "<br>Hits left: " .. hitsLeft
end
updateHelper()

-- Find the first spot left to right that matches hit rule
-- wantHit: letter to look for or nil for any letter 
-- wantNeeds: how much it still needs, or nil for any amount
local function findSpot (plan, wantHit, wantNeeds)
	for spot = 1, 16 do
		local hitMatches = (wantHit == nil) or (plan[spot] == wantHit)
		local needsMatches = (wantNeeds == nil) or (getNeeds(spot) == wantNeeds)
		if plan[spot] ~= nil and hitMatches and needsMatches then
			return spot
		end
	end
	return nil
end

-- Which spot to hit next, using the method:
-- Hard first, then soft needing exactly 1, then medium, then anything else planned
local function pickNextSpot(plan)
	return findSpot(plan, "H", nil)
		or findSpot(plan, "S", 1)
		or findSpot(plan, "M", nil)
		or findSpot(plan, nil, nil)
end

-- How likely each hit is to make a dent of each size
-- making estimates based on 99 smithing. 
local HIT_CHANCES = {
	H = { {dent = 0, chance = 0.02}, {dent = 1, chance = 0.03}, {dent = 2, chance = 0.05},
	      {dent = 3, chance = 0.20}, {dent = 4, chance = 0.50}, {dent = 5, chance = 0.20} },
	M = { {dent = 0, chance = 0.05}, {dent = 1, chance = 0.10}, {dent = 2, chance = 0.65}, {dent = 3, chance = 0.20} },
	S = { {dent = 0, chance = 0.20}, {dent = 1, chance = 0.80} },
	C = { {dent = 0, chance = 0.10}, {dent = 1, chance = 0.90} },
}

-- How much cooldown each hit uses
local HIT_COOLDOWN = { H = 1, M = 1, S = 1, C = 2 }

-- Which hits are worth trying on a spot, none can go more than 1 too deep.
local function hitOptions(left)
	if left >= 5 then return { "H" }
	elseif left == 4 then return { "H", "M" }
	elseif left == 3 then return { "M" }
	elseif left == 2 then return { "M", "S" }
	elseif left == 1 then return { "S", "C"}
	else return {} end
end

-- Score for a finished spot: lower is better. Over-denting is penalised more than under-denting.
local function finishCost(left, atMax)
	if left >= 0 then return left end
	if atMax then return 100 end
	return -2 * left
end

-- Best first hit for a spot given how many hits we can spend
-- For each hit, averages the outcome of every possible dent (weighted by chance)
-- planning the remaining hits recursively. Returns expected score (lower is better) and hit letter (nil = don't hit)
local function bestPlan(left, hitsLeft, atMax)
	local bestCost = finishCost(left, atMax)
	local bestHit = nil
	for _, hit in ipairs(hitOptions(left)) do
		local cooldown = HIT_COOLDOWN[hit]
		if cooldown <= hitsLeft then
			local cost = 0
			for _, outcome in ipairs(HIT_CHANCES[hit]) do
				local laterCost = bestPlan(left - outcome.dent, hitsLeft - cooldown, atMax)
				cost = cost + outcome.chance * laterCost
			end
			if bestHit == nil or cost < bestCost then
				bestCost = cost
				bestHit = hit
			end
		end
	end
	return bestCost, bestHit
end

-- Decide a hit for each spot by spending the cooldown where it improves the sword most.
-- returns a table: plan[spot] = "H"/"M"/"S"/"C", or nil if that spot shouldn't be hit.
local function planSword()
	local upgrades = {}
	for spot = 1, 16 do
		local left = getNeeds(spot)
		if left > 0 then
			local target = var.VarPlayer["ARTISAN_DEMO_" .. spot].value
			local isTip = (spot == 8 or spot == 16)
			local atMax = (isTip and target == 8) or (not isTip and target == 6)
			local prevCost, prevHit, prevHits = left, nil, 0
			for hits = 1, 4 do
				local cost, hit = bestPlan(left, hits, atMax)
				if hit ~= prevHit then
					table.insert(upgrades, {
						spot = spot,
						hit = hit,
						hits = hits - prevHits,
						value = (prevCost - cost) / (hits - prevHits),
					})
					prevCost, prevHit, prevHits = cost, hit, hits
				end
			end
		end
	end

	-- best value per cooldown
	table.sort(upgrades, function(a, b) return a.value > b.value end)

	local plan = {}
	local cooldownLeft = var.VarPlayer.ARTISAN_COUNTDOWN.value
	local spent = 0
	for _, upgrade in ipairs(upgrades) do
		cooldownLeft = cooldownLeft - upgrade.hits
		if cooldownLeft < 0 and spent > 0 then break end
		spent = spent + upgrade.hits
		plan[upgrade.spot] = upgrade.hit
	end
	return plan
end

-- Letter Colours by hit type: red = Hard, orange = Medium, green = soft, blue = careful
local LETTER_COLOURS = { H = 0xFF0000, M = 0xFF8800, S = 0x00FF00, C = 0x00AAFF }
local WHITE = 0xFFFFFF
local PANEL_GREY = 0x322E28FF
local HIGHLIGHT = 0x6B5A2EFF

-- Write the suggestion on a letter and colour it
local function setLetter(letter, hit)
	letter.content = hit or ""
	letter.rgb = LETTER_COLOURS[hit] or WHITE
end

-- Letters and boxes we add to each hammer so we can update them later
local letters = {}
local backgrounds = {}

-- Suggested hit letter goes on every hammer button
local function showLetters()
	for spot = 1, 16 do
		local buttonName = "ARTISAN_BUILD_SWORD__BUTTON" .. spot
		local hammer = ui.Interfaces:GetComponent(id.Component[buttonName])
		if hammer ~= nil then
			--grey box behind the letter so it can be read
			local background = ui.Rectangle.new(hammer)
			background:SetSize(-6, -4, 1.0, 1.0)
			background:SetPos(3, 2)
			background.fill = true
			background.rgba = PANEL_GREY
			local letter = ui.Text.new(hammer)
			letter:SetSize(0, 0, 1.0, 1.0)
			letter.font = id.Font.MUSEO_SANS_15PT_REGULAR
			letter:AlignTo(ui.AlignMode.CENTRE)
			letters[spot] = letter
			backgrounds[spot] = background
		end
	end
end

-- Rewrite every hammer letter with the current suggestion
local function updateLetters()
	local plan = planSword()
	for spot = 1, 16 do
		if letters[spot] ~= nil then
			setLetter(letters[spot], plan[spot])
		end
	end
	local nextSpot = pickNextSpot(plan)
	for spot = 1, 16 do
		if backgrounds[spot] ~= nil then
			if spot == nextSpot and SHOW_NEXT_SPOT then
				backgrounds[spot].rgba = HIGHLIGHT
			else
				backgrounds[spot].rgba = PANEL_GREY
			end
		end
	end
end

-- Run updateLetters when a sword variable changes
local function onSwordChanged(event)
	local name = tostring(event.var.configName)
	if string.find(name, "ARTISAN") then
		updateHelper()
		updateLetters()
	end
end
Event.VarTransmit.Subscribe("swordChanged", onSwordChanged)

-- Hit logger - Eventually we want to crowdsource accurate hit chances instead of assuming 99.
-- for now we're just storing locally for testing purposes
local lastCooldown = nil
local pendingStrength = nil
local pendingTotal = nil

-- SMITH_STRENGTH number to hit letter
local STRENGTH_LETTER = {[0] = "C", [1] = "S", [2] = "M", [3] = "H"}

-- Set to true to log results
local hitLog = {}
if DEBUG then
	hitLog = PersistentDB:GetStructuredData("hitLog") or {}
	for key, count in pairs(hitLog) do
		print("Saved", key, count)
	end
end

-- Add up the current depth of all 16 spots
local function totalDepth()
	local total = 0
	for spot = 1, 16 do
		total = total + var.VarPlayer["ARTISAN_POS_"..spot].value
	end
	return total
end

local function recordHit(strength, dent)
	local letter = STRENGTH_LETTER[strength] or "?"
	local level = Player.GetLevelGameplay(SkillType.SMITHING)
	local key = level .. ":" .. letter .. dent
	hitLog[key] = (hitLog[key] or 0) + 1
	PersistentDB:SetStructuredData("hitLog", hitLog)
	print("Logged", key, "- seen", hitLog[key], "times")
end

local function onServerTick()
	local cooldown = var.VarPlayer.ARTISAN_COUNTDOWN.value
	local total = totalDepth()
	-- the depth updates a tick after the cooldown, so finish the waiting hit once it moves
	if pendingStrength ~= nil and total ~= pendingTotal then
		recordHit(pendingStrength, total - pendingTotal)
		pendingStrength = nil
	end
	if lastCooldown ~= nil and cooldown < lastCooldown then
		-- A new hit while one is still waiting means that one dented 0
		if pendingStrength ~= nil then
			recordHit(pendingStrength, 0)
		end
		pendingStrength = var.VarPlayer.SMITH_STRENGTH.value
		pendingTotal = total
	end
	lastCooldown = cooldown
end
if DEBUG then
	Event.ServerLogic.Subscribe("hitLogger", onServerTick)
end

-- Was the window open last frame?
local wasOpen = false

-- Every Frame show or hide the debug numbers box and add letters when the window opens.
local function watchSwordWindow()
	local isOpen = ui.Interfaces:GetInterface(id.Interface.ARTISAN_BUILD_SWORD) ~= nil
	box.hidden = not isOpen or not DEBUG
	if isOpen and not wasOpen then
		showLetters()
		updateLetters()
	end
	if not isOpen then
		letters = {}
		backgrounds = {}
	end
	wasOpen = isOpen
end
Event.Draw.Subscribe("hammerWindow", watchSwordWindow)

