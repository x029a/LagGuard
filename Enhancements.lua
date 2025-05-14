-- LagGuard Enhancements Module
-- Adds additional features to the base addon

local addonName, LG = ...

-- Initialize new default settings
local enhancementsDefaults = {
    -- Safe Zone Detection
    enableSafeZoneDetection = true,
    safeZoneThreshold = 150, -- ms threshold to consider a zone "safe"
    recordZoneLatency = true,
    
    -- Connection Quality Scoring
    enableConnectionScoring = true,
    scoreUpdateInterval = 10, -- seconds between score updates
    
    -- Latency Log
    enableLatencyLog = true,
    latencyLogSize = 50, -- number of entries to keep
    logSevereSpikeThreshold = 500, -- ms threshold to log as severe
    
    -- Auto Actions
    enableAutoActions = false, -- Off by default for safety
    autoActionsThreshold = 1000, -- ms to trigger auto actions
    stopFollowOnLag = true, -- Stop following on lag spike
    cancelCastingOnLag = true, -- Cancel current cast on severe lag
}

-- Register these defaults with the main addon
for k, v in pairs(enhancementsDefaults) do
    LG.defaults[k] = v
end

-- Initialize data structures
local zoneLatencyData = {}  -- Format: [zoneID] = {avgHome=x, avgWorld=y, samples=z}
local connectionScoreHistory = {}
local latencyLogEntries = {}
local lastZoneID = nil
local lastScoreUpdate = 0
local enhancementsFrame = CreateFrame("Frame")
local currentConnectionScore = 100  -- 0-100 scale, 100 is perfect

-- Combat Safety Features
local combatProtectionActive = false
local lastCombatNotification = 0
local defensiveCooldowns = {}

-- Advanced analytics and time-of-day tracking
local timeOfDayData = {}  -- [hour] = {avgLatency, samples}
local latencyPredictions = {}
local lastPredictionUpdate = 0
local predictionUpdateInterval = 300 -- Update predictions every 5 minutes
local historyDuration = 7 * 86400 -- Store 7 days of data

-- Initialize time analytics data
local function InitializeTimeAnalytics()
    -- Make sure we have a place to store time data
    LG.EnsureSavedVars()
    
    -- Initialize time of day data structure if it doesn't exist
    if not LagGuardDB.timeOfDayData then
        LagGuardDB.timeOfDayData = {}
        
        -- Initialize with empty data for each hour
        for hour = 0, 23 do
            LagGuardDB.timeOfDayData[hour] = {avgLatency = 0, samples = 0}
        end
    end
    
    -- Load saved data into local cache
    timeOfDayData = LagGuardDB.timeOfDayData
end

-- Update time of day data with current latency
local function UpdateTimeOfDayData()
    -- Get current time (in-game time would be better but using local for simplicity)
    local hour = tonumber(date("%H"))
    if not hour then return end
    
    -- Get current latency
    local _, _, homeLatency, worldLatency = GetNetStats()
    local currentLatency = math.max(homeLatency or 0, worldLatency or 0)
    
    -- Initialize hour data if needed
    if not timeOfDayData[hour] then
        timeOfDayData[hour] = {avgLatency = 0, samples = 0}
    end
    
    -- Update running average
    local current = timeOfDayData[hour]
    local newAvg = ((current.avgLatency * current.samples) + currentLatency) / (current.samples + 1)
    
    timeOfDayData[hour].avgLatency = newAvg
    timeOfDayData[hour].samples = current.samples + 1
    
    -- Save to persistent storage
    LG.EnsureSavedVars()
    LagGuardDB.timeOfDayData = timeOfDayData
end

-- Create time of day analysis frame
local function ToggleTimeAnalysis()
    -- Create frame if it doesn't exist yet
    if not LG.timeAnalysisFrame then
        local frame = CreateFrame("Frame", "LagGuardTimeAnalysisFrame", UIParent)
        frame:SetSize(400, 300)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetClampedToScreen(true)
        frame:Hide() -- Hidden by default
        
        -- Create background
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
        
        -- Create border
        local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
        
        -- Create title
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -15)
        title:SetText("Latency by Time of Day")
        
        -- Close button
        local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        closeButton:SetScript("OnClick", function() frame:Hide() end)
        
        -- Create bar chart for time analysis
        frame.bars = {}
        frame.labels = {}
        
        -- Create header text for best and worst times
        local bestTimeHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bestTimeHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -45)
        bestTimeHeader:SetText("Best times to play (lowest latency):")
        
        local worstTimeHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        worstTimeHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -60)
        worstTimeHeader:SetText("Worst times to play (highest latency):")
        
        -- Create text for best and worst times
        frame.bestTimes = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.bestTimes:SetPoint("TOPLEFT", frame, "TOPLEFT", 200, -45)
        frame.bestTimes:SetText("Collecting data...")
        
        frame.worstTimes = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.worstTimes:SetPoint("TOPLEFT", frame, "TOPLEFT", 200, -60)
        frame.worstTimes:SetText("Collecting data...")
        
        -- Create current time indicator
        frame.currentHour = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.currentHour:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -45)
        frame.currentHour:SetText("Current hour: N/A")
        
        -- Create status text for data collection
        frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.status:SetPoint("BOTTOM", frame, "BOTTOM", 0, 15)
        frame.status:SetText("Data points collected: 0")
        
        -- Create prediction text
        frame.prediction = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.prediction:SetPoint("BOTTOM", frame, "BOTTOM", 0, 35)
        frame.prediction:SetText("Prediction: Collecting data...")
        
        -- Function to update the display
        frame.Update = function()
            -- Get current time
            local currentHour = tonumber(date("%H"))
            frame.currentHour:SetText("Current hour: " .. currentHour .. ":00")
            
            -- Calculate total data points
            local totalSamples = 0
            for hour, data in pairs(timeOfDayData) do
                totalSamples = totalSamples + (data.samples or 0)
            end
            frame.status:SetText("Data points collected: " .. totalSamples)
            
            -- Sort hours by latency for best/worst times
            local hoursByLatency = {}
            for hour, data in pairs(timeOfDayData) do
                if data.samples and data.samples > 0 then
                    table.insert(hoursByLatency, {hour = hour, latency = data.avgLatency})
                end
            end
            
            -- Sort hours by latency (ascending)
            table.sort(hoursByLatency, function(a, b) return a.latency < b.latency end)
            
            -- Update best/worst times
            local bestText = "Not enough data"
            local worstText = "Not enough data"
            
            if #hoursByLatency >= 3 then
                -- Format best times
                bestText = ""
                for i = 1, math.min(3, #hoursByLatency) do
                    local hourData = hoursByLatency[i]
                    bestText = bestText .. hourData.hour .. ":00 (" .. math.floor(hourData.latency) .. "ms)"
                    if i < 3 then bestText = bestText .. ", " end
                end
                
                -- Format worst times
                worstText = ""
                for i = #hoursByLatency, math.max(1, #hoursByLatency - 2), -1 do
                    local hourData = hoursByLatency[i]
                    worstText = worstText .. hourData.hour .. ":00 (" .. math.floor(hourData.latency) .. "ms)"
                    if i > #hoursByLatency - 2 then worstText = worstText .. ", " end
                end
            end
            
            frame.bestTimes:SetText(bestText)
            frame.worstTimes:SetText(worstText)
            
            -- Generate prediction for upcoming hours
            if #hoursByLatency >= 12 then -- Need at least half a day of data
                local nextHour = (currentHour + 1) % 24
                local next2Hours = (currentHour + 2) % 24
                
                -- Find latency for these hours
                local nextHourLatency = "unknown"
                local next2HoursLatency = "unknown"
                
                for _, hourData in ipairs(hoursByLatency) do
                    if hourData.hour == nextHour then
                        nextHourLatency = math.floor(hourData.latency)
                    elseif hourData.hour == next2Hours then
                        next2HoursLatency = math.floor(hourData.latency)
                    end
                end
                
                -- Format prediction text
                if nextHourLatency ~= "unknown" or next2HoursLatency ~= "unknown" then
                    local predictionText = "Connection quality forecast: "
                    
                    -- Upcoming hour
                    if nextHourLatency ~= "unknown" then
                        predictionText = predictionText .. "Next hour (" .. nextHour .. ":00): "
                        
                        if nextHourLatency < 100 then
                            predictionText = predictionText .. "|cFF00FF00Good (" .. nextHourLatency .. "ms)|r"
                        elseif nextHourLatency < 200 then
                            predictionText = predictionText .. "|cFFFFFF00Fair (" .. nextHourLatency .. "ms)|r"
                        else
                            predictionText = predictionText .. "|cFFFF0000Poor (" .. nextHourLatency .. "ms)|r"
                        end
                    end
                    
                    -- Two hours from now
                    if next2HoursLatency ~= "unknown" then
                        if nextHourLatency ~= "unknown" then
                            predictionText = predictionText .. ", "
                        end
                        
                        predictionText = predictionText .. "In two hours (" .. next2Hours .. ":00): "
                        
                        if next2HoursLatency < 100 then
                            predictionText = predictionText .. "|cFF00FF00Good (" .. next2HoursLatency .. "ms)|r"
                        elseif next2HoursLatency < 200 then
                            predictionText = predictionText .. "|cFFFFFF00Fair (" .. next2HoursLatency .. "ms)|r"
                        else
                            predictionText = predictionText .. "|cFFFF0000Poor (" .. next2HoursLatency .. "ms)|r"
                        end
                    end
                    
                    frame.prediction:SetText(predictionText)
                else
                    frame.prediction:SetText("Prediction: Not enough data for the upcoming hours")
                end
            else
                frame.prediction:SetText("Prediction: Need more data (at least 12 hours)")
            end
            
            -- Create or update the bar chart
            local chartTop = -90
            local chartHeight = 120
            local chartBottom = chartTop - chartHeight
            local barWidth = 11  -- 24 hours needs to fit within the frame width
            local barSpacing = 5
            local maxBarHeight = chartHeight - 20
            
            -- Find max latency for scaling
            local maxLatency = 50  -- Minimum baseline
            for hour = 0, 23 do
                if timeOfDayData[hour] and timeOfDayData[hour].samples and timeOfDayData[hour].samples > 0 then
                    maxLatency = math.max(maxLatency, timeOfDayData[hour].avgLatency)
                end
            end
            
            -- Draw hour labels and bars
            for hour = 0, 23 do
                local xPos = 20 + (hour * (barWidth + barSpacing))
                
                -- Create or update hour label
                if not frame.labels[hour+1] then
                    frame.labels[hour+1] = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    frame.labels[hour+1]:SetPoint("BOTTOM", frame, "TOPLEFT", xPos + (barWidth/2), chartBottom - 15)
                    -- Only show every 3 hours for clarity
                    if hour % 3 == 0 then
                        frame.labels[hour+1]:SetText(hour)
                    else
                        frame.labels[hour+1]:SetText("")
                    end
                end
                
                -- Create or update bar
                if not frame.bars[hour+1] then
                    frame.bars[hour+1] = frame:CreateTexture(nil, "ARTWORK")
                    frame.bars[hour+1]:SetPoint("BOTTOM", frame, "TOPLEFT", xPos, chartBottom)
                    frame.bars[hour+1]:SetWidth(barWidth)
                end
                
                -- Calculate bar height based on data
                local barHeight = 5  -- Minimum height when no data
                local barColor = {r = 0.5, g = 0.5, b = 0.5}  -- Gray for no data
                
                if timeOfDayData[hour] and timeOfDayData[hour].samples and timeOfDayData[hour].samples > 0 then
                    local latency = timeOfDayData[hour].avgLatency
                    barHeight = (latency / maxLatency) * maxBarHeight
                    barHeight = math.max(5, barHeight)  -- Ensure minimum visible height
                    
                    -- Color based on latency
                    if latency < 100 then
                        -- Good (green)
                        barColor = {r = 0, g = 1, b = 0}
                    elseif latency < 200 then
                        -- Medium (yellow)
                        barColor = {r = 1, g = 1, b = 0}
                    else
                        -- Bad (red)
                        barColor = {r = 1, g = 0, b = 0}
                    end
                end
                
                frame.bars[hour+1]:SetHeight(barHeight)
                frame.bars[hour+1]:SetColorTexture(barColor.r, barColor.g, barColor.b, 0.8)
                
                -- Highlight current hour
                if hour == currentHour then
                    -- Add highlight outline
                    if not frame.currentHourHighlight then
                        frame.currentHourHighlight = frame:CreateTexture(nil, "OVERLAY")
                        frame.currentHourHighlight:SetColorTexture(1, 1, 1, 0.5)
                    end
                    
                    frame.currentHourHighlight:ClearAllPoints()
                    frame.currentHourHighlight:SetPoint("BOTTOMLEFT", frame.bars[hour+1], "BOTTOMLEFT", -1, -1)
                    frame.currentHourHighlight:SetPoint("TOPRIGHT", frame.bars[hour+1], "TOPRIGHT", 1, 1)
                end
            end
            
            -- Add x-axis label
            if not frame.xAxisLabel then
                frame.xAxisLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                frame.xAxisLabel:SetPoint("BOTTOM", frame, "BOTTOM", 0, chartBottom - 30)
                frame.xAxisLabel:SetText("Hour of Day (24-hour format)")
            end
            
            -- Add y-axis label
            if not frame.yAxisLabel then
                frame.yAxisLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                frame.yAxisLabel:SetPoint("LEFT", frame, "LEFT", 10, chartBottom + (chartHeight/2))
                frame.yAxisLabel:SetText("Avg Latency (ms)")
            end
        end
        
        -- Update when shown
        frame:SetScript("OnShow", function()
            frame.Update()
        end)
        
        -- Set up a timer to refresh the frame regularly while it's shown
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.timer = (self.timer or 0) + elapsed
            if self.timer > 30 then  -- Update every 30 seconds
                self.timer = 0
                if self:IsShown() then
                    self.Update()
                end
            end
        end)
        
        -- Store reference to the frame
        LG.timeAnalysisFrame = frame
    end
    
    -- Toggle visibility
    if LG.timeAnalysisFrame:IsShown() then
        LG.timeAnalysisFrame:Hide()
    else
        LG.timeAnalysisFrame:Show()
        LG.timeAnalysisFrame.Update()
    end
end

-- Load class-specific defensive cooldowns
local function LoadDefensiveCooldowns()
    local _, class = UnitClass("player")
    defensiveCooldowns = {}
    
    -- Define defensive cooldowns by class
    if class == "WARRIOR" then
        defensiveCooldowns = {
            {spell = "Shield Wall", id = 871},
            {spell = "Last Stand", id = 12975},
            {spell = "Defensive Stance", id = 71},
        }
    elseif class == "PALADIN" then
        defensiveCooldowns = {
            {spell = "Divine Shield", id = 642},
            {spell = "Divine Protection", id = 498},
            {spell = "Lay on Hands", id = 633},
        }
    elseif class == "HUNTER" then
        defensiveCooldowns = {
            {spell = "Feign Death", id = 5384},
            {spell = "Aspect of the Turtle", id = 186265},
            {spell = "Exhilaration", id = 109304},
        }
    elseif class == "ROGUE" then
        defensiveCooldowns = {
            {spell = "Cloak of Shadows", id = 31224},
            {spell = "Evasion", id = 5277},
            {spell = "Crimson Vial", id = 185311},
        }
    elseif class == "PRIEST" then
        defensiveCooldowns = {
            {spell = "Desperate Prayer", id = 19236},
            {spell = "Power Word: Shield", id = 17},
            {spell = "Fade", id = 586},
        }
    elseif class == "SHAMAN" then
        defensiveCooldowns = {
            {spell = "Astral Shift", id = 108271},
            {spell = "Healing Surge", id = 8004},
            {spell = "Earth Shield", id = 974},
        }
    elseif class == "MAGE" then
        defensiveCooldowns = {
            {spell = "Ice Block", id = 45438},
            {spell = "Alter Time", id = 108978},
            {spell = "Ice Barrier", id = 11426},
        }
    elseif class == "WARLOCK" then
        defensiveCooldowns = {
            {spell = "Unending Resolve", id = 104773},
            {spell = "Dark Pact", id = 108416},
            {spell = "Healthstone", id = 5512},
        }
    elseif class == "MONK" then
        defensiveCooldowns = {
            {spell = "Fortifying Brew", id = 115203},
            {spell = "Zen Meditation", id = 115176},
            {spell = "Diffuse Magic", id = 122783},
        }
    elseif class == "DRUID" then
        defensiveCooldowns = {
            {spell = "Barkskin", id = 22812},
            {spell = "Survival Instincts", id = 61336},
            {spell = "Frenzied Regeneration", id = 22842},
        }
    elseif class == "DEATHKNIGHT" then
        defensiveCooldowns = {
            {spell = "Icebound Fortitude", id = 48792},
            {spell = "Anti-Magic Shell", id = 48707},
            {spell = "Death Strike", id = 49998},
        }
    elseif class == "DEMONHUNTER" then
        defensiveCooldowns = {
            {spell = "Blur", id = 198589},
            {spell = "Darkness", id = 196718},
            {spell = "Netherwalk", id = 196555},
        }
    end
end

-- Check for available defensive cooldowns
local function GetAvailableDefensives()
    local available = {}
    for _, cd in ipairs(defensiveCooldowns) do
        local start, duration = GetSpellCooldown(cd.id)
        -- If the spell is ready or will be ready in less than 1 second
        if start == 0 or (start > 0 and (start + duration - GetTime()) < 1) then
            table.insert(available, cd.spell)
        end
    end
    return available
end

-- Display defensive cooldown suggestions during high latency
local function SuggestDefensives(latency)
    -- Only show suggestions in combat
    if not UnitAffectingCombat("player") then return end
    
    -- Don't spam suggestions
    local now = GetTime()
    if now - lastCombatNotification < 5 then return end
    lastCombatNotification = now
    
    -- Get available defensive abilities
    local availableCDs = GetAvailableDefensives()
    
    if #availableCDs > 0 then
        local message = "|cFFFF0000HIGH LATENCY WARNING!|r Consider using: "
        for i, cd in ipairs(availableCDs) do
            if i > 1 then message = message .. " or " end
            message = message .. "|cFFFFFF00" .. cd .. "|r"
        end
        
        -- Show as raid warning style message (since this is important)
        RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
        -- Also add to chat
        if LagGuardDB.chatAlerts then
            print(message)
        end
        
        -- Play sound
        if LagGuardDB.soundEnabled then
            PlaySound(8959, "Master") -- RAID_WARNING sound
        end
        
        -- Log the suggestion
        LogLatencyEvent(3, "Defensive cooldown suggestion during high latency (" .. latency .. "ms)")
    end
end

-- Notify party members about lag issues
local function NotifyPartyOfLag(latency)
    -- Don't notify if the player is not in a group
    if not IsInGroup() then return end
    
    -- Don't spam notifications
    local now = GetTime()
    if now - lastCombatNotification < 30 then return end
    lastCombatNotification = now
    
    -- Only notify for severe lag
    if latency < LagGuardDB.dangerThreshold then return end
    
    -- Only notify if enabled
    if not LagGuardDB.notifyGroupOfLag then return end
    
    -- Send a whisper to party/raid members
    local message = "LagGuard Alert: I'm experiencing high latency (" .. latency .. "ms). Please be aware."
    
    if IsInRaid() then
        SendChatMessage(message, "RAID")
    else
        SendChatMessage(message, "PARTY")
    end
    
    -- Log the notification
    LogLatencyEvent(3, "Notified group of severe latency (" .. latency .. "ms)")
end

-- Combat entry warning
local function WarnOnCombatEntry()
    -- Check for entry to combat
    if UnitAffectingCombat("player") and not combatProtectionActive then
        combatProtectionActive = true
        
        -- Get current latency
        local _, _, homeLatency, worldLatency = GetNetStats()
        local maxLatency = math.max(homeLatency, worldLatency)
        
        -- Only warn if latency is above threshold
        if maxLatency >= LagGuardDB.warningThreshold then
            -- Show warning
            local message = "|cFFFF0000WARNING:|r Entering combat with high latency (" .. maxLatency .. "ms)"
            RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
            
            -- Play alert sound
            if LagGuardDB.soundEnabled then
                PlaySound(8959, "Master") -- RAID_WARNING sound
            end
            
            -- Log the warning
            LogLatencyEvent(3, "Entered combat with high latency (" .. maxLatency .. "ms)")
            
            -- Suggest defensive cooldowns immediately
            SuggestDefensives(maxLatency)
            
            -- Notify party if enabled
            NotifyPartyOfLag(maxLatency)
        end
    elseif not UnitAffectingCombat("player") and combatProtectionActive then
        -- Reset combat state
        combatProtectionActive = false
    end
end

-- Set up combat protection frame
local combatProtectionFrame = CreateFrame("Frame")
combatProtectionFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering combat
combatProtectionFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving combat

combatProtectionFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        WarnOnCombatEntry()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        combatProtectionActive = false
    end
end)

-- Add to the UpdateEnhancements function to check during combat
local originalUpdateEnhancements = UpdateEnhancements
UpdateEnhancements = function()
    -- Call original function
    originalUpdateEnhancements()
    
    -- Get current latency
    local _, _, homeLatency, worldLatency = GetNetStats()
    local maxLatency = math.max(homeLatency or 0, worldLatency or 0)
    
    -- Check if we need to take combat protective actions
    if UnitAffectingCombat("player") and maxLatency >= LagGuardDB.dangerThreshold then
        -- Suggest defensive cooldowns
        SuggestDefensives(maxLatency)
    end
end

-- Safe Zone Detection
local function RecordZoneLatency()
    if not LG.defaults.recordZoneLatency then return end
    
    local zoneID = C_Map.GetBestMapForUnit("player")
    if not zoneID then return end
    
    -- Skip if we're in the same zone
    if lastZoneID == zoneID then return end
    lastZoneID = zoneID
    
    -- Get current latency
    local _, _, homeLatency, worldLatency = GetNetStats()
    
    -- Initialize zone data if needed
    if not zoneLatencyData[zoneID] then
        zoneLatencyData[zoneID] = {avgHome = 0, avgWorld = 0, samples = 0}
    end
    
    -- Update running average
    local zoneData = zoneLatencyData[zoneID]
    local newSamples = zoneData.samples + 1
    zoneData.avgHome = ((zoneData.avgHome * zoneData.samples) + homeLatency) / newSamples
    zoneData.avgWorld = ((zoneData.avgWorld * zoneData.samples) + worldLatency) / newSamples
    zoneData.samples = newSamples
    
    -- Save data to current session
    if LagGuardDB then
        if not LagGuardDB.zoneLatencyData then
            LagGuardDB.zoneLatencyData = {}
        end
        LagGuardDB.zoneLatencyData = zoneLatencyData
    end
end

-- Check if current location is a "safe zone" with good latency
local function IsSafeZone()
    local zoneID = C_Map.GetBestMapForUnit("player")
    if not zoneID or not zoneLatencyData[zoneID] then return nil end
    
    local zoneData = zoneLatencyData[zoneID]
    
    -- Need at least a few samples to be reliable
    if zoneData.samples < 3 then return nil end
    
    -- Check if both latencies are below threshold
    return (zoneData.avgHome <= LG.defaults.safeZoneThreshold and 
            zoneData.avgWorld <= LG.defaults.safeZoneThreshold)
end

-- Calculate a connection quality score (0-100)
local function CalculateConnectionScore()
    if not LG.homeLatencyHistory or #LG.homeLatencyHistory < 5 or not LG.worldLatencyHistory or #LG.worldLatencyHistory < 5 then
        return 100  -- Default to perfect if not enough data
    end
    
    local score = 100  -- Start with perfect score
    
    -- Get current latency values
    local _, _, homeLatency, worldLatency = GetNetStats()
    
    -- Factor 1: Raw latency values (lower is better)
    local latencyScore = 100 - (math.min(homeLatency, 500) / 5)
    
    -- Factor 2: Jitter (lower is better)
    local homeJitter = 0
    local worldJitter = 0
    
    if LG.analytics and LG.analytics.calculateJitter then
        homeJitter = LG.analytics.calculateJitter(LG.homeLatencyHistory, 10)
        worldJitter = LG.analytics.calculateJitter(LG.worldLatencyHistory, 10)
    else
        -- Simple jitter calculation if analytics not available
        for i = 1, math.min(5, #LG.homeLatencyHistory-1) do
            homeJitter = homeJitter + math.abs(LG.homeLatencyHistory[i] - LG.homeLatencyHistory[i+1])
        end
        homeJitter = homeJitter / math.min(5, #LG.homeLatencyHistory-1)
        
        for i = 1, math.min(5, #LG.worldLatencyHistory-1) do
            worldJitter = worldJitter + math.abs(LG.worldLatencyHistory[i] - LG.worldLatencyHistory[i+1])
        end
        worldJitter = worldJitter / math.min(5, #LG.worldLatencyHistory-1)
    end
    
    local maxJitter = math.max(homeJitter, worldJitter)
    local jitterScore = 100 - math.min(maxJitter * 2, 50)  -- Jitter penalizes up to 50 points
    
    -- Factor 3: Packet loss (lower is better)
    local packetLossScore = 100
    if LG.analytics and LG.analytics.estimatePacketLoss then
        local packetLoss = LG.analytics.estimatePacketLoss()
        packetLossScore = 100 - (packetLoss * 10)  -- Each 1% packet loss reduces score by 10
    end
    
    -- Factor 4: Trend direction (stable or improving is better)
    local trendScore = 100
    if LG.analytics and LG.analytics.trendData then
        if LG.analytics.trendData.homeSlope > 0 or LG.analytics.trendData.worldSlope > 0 then
            trendScore = 80  -- Penalize if trending upward (worse)
        end
    end
    
    -- Combine scores with weightings
    score = (latencyScore * 0.4) + (jitterScore * 0.25) + (packetLossScore * 0.25) + (trendScore * 0.1)
    
    -- Ensure score stays within 0-100 range
    score = math.max(0, math.min(100, score))
    
    -- Update history and current score
    table.insert(connectionScoreHistory, 1, score)
    if #connectionScoreHistory > 10 then
        table.remove(connectionScoreHistory)
    end
    
    currentConnectionScore = score
    return score
end

-- Add entry to latency log
local function LogLatencyEvent(severity, message)
    -- Check if logging is explicitly disabled (default to enabled)
    if LG.defaults.enableLatencyLog == false then return end
    
    -- Format timestamp with date and time
    local timestamp = date("%m/%d %H:%M:%S")
    local entry = {
        timestamp = timestamp,
        severity = severity,  -- 1=info, 2=warning, 3=severe
        message = message
    }
    
    -- Only add the entry if it's not a duplicate of the most recent entry
    local isDuplicate = false
    if #latencyLogEntries > 0 then
        local lastEntry = latencyLogEntries[1]
        if lastEntry.message == message and lastEntry.severity == severity then
            -- Check if it's within 10 seconds (to avoid rapid duplicates)
            local lastTime = lastEntry.timestamp
            if lastTime and (timestamp:sub(8) == lastTime:sub(8)) then
                isDuplicate = true
            end
        end
    end
    
    if not isDuplicate then
        table.insert(latencyLogEntries, 1, entry)
        if #latencyLogEntries > (LG.defaults.latencyLogSize or 50) then
            table.remove(latencyLogEntries)
        end
        
        -- Save to persistent storage
        if LagGuardDB then
            if not LagGuardDB.latencyLog then
                LagGuardDB.latencyLog = {}
            end
            LagGuardDB.latencyLog = latencyLogEntries
            
            -- If the log frame is visible, update it
            if LG.logFrame and LG.logFrame:IsShown() then
                LG.logFrame.Update()
            end
        end
    end
end

-- Automatically take action based on latency
local function PerformAutoActions(latency)
    if not LG.defaults.enableAutoActions then return end
    
    -- Only take action if latency is above threshold
    if latency < LG.defaults.autoActionsThreshold then return end
    
    -- Stop following if enabled
    if LG.defaults.stopFollowOnLag and IsFollowing() then
        FollowUnit("player")  -- This will cancel follow
        LogLatencyEvent(2, "Auto-cancelled follow due to high latency (" .. latency .. "ms)")
    end
    
    -- Cancel casting if enabled
    if LG.defaults.cancelCastingOnLag and UnitCastingInfo("player") then
        SpellStopCasting()
        LogLatencyEvent(2, "Auto-cancelled spellcast due to high latency (" .. latency .. "ms)")
    end
end

-- Create the Latency Log UI
local function CreateLatencyLogFrame()
    local logFrame = CreateFrame("Frame", "LagGuardLogFrame", UIParent)
    logFrame:SetSize(600, 400) -- Increased width and height for better readability
    logFrame:SetPoint("CENTER")
    logFrame:SetFrameStrata("DIALOG")
    logFrame:SetMovable(true)
    logFrame:EnableMouse(true)
    logFrame:RegisterForDrag("LeftButton")
    logFrame:SetScript("OnDragStart", logFrame.StartMoving)
    logFrame:SetScript("OnDragStop", logFrame.StopMovingOrSizing)
    logFrame:SetClampedToScreen(true)
    logFrame:Hide()
    
    -- Create background
    local bg = logFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    
    -- Create border
    local border = CreateFrame("Frame", nil, logFrame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", logFrame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", logFrame, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = { left = 11, right = 11, top = 12, bottom = 10 },
    })
    
    -- Create title
    local title = logFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("LagGuard Latency Log")
    
    -- Create scroll frame for log entries
    local scrollFrame = CreateFrame("ScrollFrame", "LagGuardLogScrollFrame", logFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 40)
    
    local scrollChild = CreateFrame("Frame", "LagGuardLogScrollChild", scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(800) -- Tall enough for many entries
    
    -- Create column headers
    local timestampHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    timestampHeader:SetPoint("TOPLEFT", 5, 10)
    timestampHeader:SetWidth(100) -- Increased width for date/time format
    timestampHeader:SetJustifyH("LEFT")
    timestampHeader:SetText("Timestamp")
    
    local messageHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    messageHeader:SetPoint("LEFT", timestampHeader, "RIGHT", 5, 0)
    messageHeader:SetPoint("RIGHT", -5, 0)
    messageHeader:SetJustifyH("LEFT")
    messageHeader:SetText("Message")
    
    -- Add a divider line below headers
    local divider = scrollChild:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(2)
    divider:SetPoint("TOPLEFT", timestampHeader, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", messageHeader, "BOTTOMRIGHT", 0, -2)
    divider:SetColorTexture(0.7, 0.7, 0.7, 0.6)
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, logFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() logFrame:Hide() end)
    
    -- Clear log button
    local clearButton = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(80, 24)
    clearButton:SetPoint("BOTTOMRIGHT", -10, 10)
    clearButton:SetText("Clear Log")
    clearButton:SetScript("OnClick", function()
        latencyLogEntries = {}
        if LagGuardDB and LagGuardDB.latencyLog then
            LagGuardDB.latencyLog = {}
        end
        logFrame.Update()
    end)
    
    -- Export log button
    local exportButton = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
    exportButton:SetSize(80, 24)
    exportButton:SetPoint("RIGHT", clearButton, "LEFT", -10, 0)
    exportButton:SetText("Export")
    exportButton:SetScript("OnClick", function()
        -- Create a formatted text of all log entries
        local exportText = "LagGuard Latency Log Export\n\n"
        for _, entry in ipairs(latencyLogEntries) do
            local severity = ""
            if entry.severity >= 3 then
                severity = "[SEVERE] "
            elseif entry.severity >= 2 then
                severity = "[WARNING] "
            end
            exportText = exportText .. entry.timestamp .. " " .. severity .. entry.message .. "\n"
        end
        
        -- Display in a simple popup
        if _G["LagGuardExportFrame"] then
            _G["LagGuardExportFrame"]:Hide()
        end
        
        local exportFrame = CreateFrame("Frame", "LagGuardExportFrame", UIParent)
        exportFrame:SetSize(600, 400)
        exportFrame:SetPoint("CENTER")
        exportFrame:SetFrameStrata("DIALOG")
        exportFrame:SetMovable(true)
        exportFrame:EnableMouse(true)
        exportFrame:RegisterForDrag("LeftButton")
        exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
        exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
        exportFrame:SetClampedToScreen(true)
        
        local exportBg = exportFrame:CreateTexture(nil, "BACKGROUND")
        exportBg:SetAllPoints()
        exportBg:SetColorTexture(0, 0, 0, 0.9)
        
        local exportBorder = CreateFrame("Frame", nil, exportFrame, "BackdropTemplate")
        exportBorder:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", -1, 1)
        exportBorder:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", 1, -1)
        exportBorder:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 32,
            insets = { left = 11, right = 11, top = 12, bottom = 10 },
        })
        
        local exportTitle = exportFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        exportTitle:SetPoint("TOP", 0, -15)
        exportTitle:SetText("Latency Log Export")
        
        local exportScrollFrame = CreateFrame("ScrollFrame", "LagGuardExportScrollFrame", exportFrame, "UIPanelScrollFrameTemplate")
        exportScrollFrame:SetPoint("TOPLEFT", 15, -40)
        exportScrollFrame:SetPoint("BOTTOMRIGHT", -35, 40)
        
        local exportScrollChild = CreateFrame("EditBox", "LagGuardExportScrollChild", exportScrollFrame)
        exportScrollFrame:SetScrollChild(exportScrollChild)
        exportScrollChild:SetWidth(exportScrollFrame:GetWidth())
        exportScrollChild:SetHeight(800)
        exportScrollChild:SetMultiLine(true)
        exportScrollChild:SetAutoFocus(false)
        exportScrollChild:SetFontObject("ChatFontNormal")
        exportScrollChild:SetText(exportText)
        
        local exportCloseButton = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
        exportCloseButton:SetPoint("TOPRIGHT", -5, -5)
        exportCloseButton:SetScript("OnClick", function() exportFrame:Hide() end)
        
        exportFrame:Show()
    end)
    
    -- Function to update log entries display
    logFrame.Update = function()
        -- Clear existing entries
        for i = 1, scrollChild:GetNumChildren() do
            local child = select(i, scrollChild:GetChildren())
            if child and child:GetObjectType() == "Frame" and not child:GetName() then
                child:Hide()
            end
        end
        
        -- Create or update entries
        local entryFrames = {}
        
        -- Get all existing entry frames
        for i = 1, scrollChild:GetNumChildren() do
            local frame = select(i, scrollChild:GetChildren())
            if frame and frame:GetObjectType() == "Frame" and not frame:GetName() then
                table.insert(entryFrames, frame)
            end
        end
        
        -- Create or update entries
        for i, entry in ipairs(latencyLogEntries) do
            local entryFrame = entryFrames[i]
            
            -- Create a new frame if needed
            if not entryFrame then
                entryFrame = CreateFrame("Frame", nil, scrollChild)
                entryFrame:SetSize(scrollChild:GetWidth(), 20)
                
                local timestamp = entryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                timestamp:SetPoint("LEFT", 5, 0)
                timestamp:SetWidth(100) -- Increased width for date/time format
                timestamp:SetJustifyH("LEFT")
                entryFrame.timestamp = timestamp
                
                local message = entryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                message:SetPoint("LEFT", timestamp, "RIGHT", 5, 0)
                message:SetPoint("RIGHT", -5, 0)
                message:SetJustifyH("LEFT")
                entryFrame.message = message
            end
            
            -- Position the entry (account for headers)
            entryFrame:SetPoint("TOPLEFT", 0, -((i) * 20))
            
            -- Set the text
            entryFrame.timestamp:SetText(entry.timestamp)
            
            -- Set the message with color based on severity
            local messageText = entry.message
            if entry.severity >= 3 then
                entryFrame.message:SetText("|cFFFF0000" .. messageText .. "|r")
            elseif entry.severity >= 2 then
                entryFrame.message:SetText("|cFFFFFF00" .. messageText .. "|r")
            else
                entryFrame.message:SetText(messageText)
            end
            
            entryFrame:Show()
        end
        
        -- Add a "No entries" message if the log is empty
        if #latencyLogEntries == 0 then
            local noEntriesFrame = CreateFrame("Frame", nil, scrollChild)
            noEntriesFrame:SetSize(scrollChild:GetWidth(), 20)
            noEntriesFrame:SetPoint("TOPLEFT", 0, -20)
            
            local noEntriesText = noEntriesFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            noEntriesText:SetPoint("CENTER", 0, 0)
            noEntriesText:SetText("No log entries to display")
            
            noEntriesFrame:Show()
        end
    end
    
    LG.logFrame = logFrame
    return logFrame
end

-- Create Connection Quality Score Display
local function CreateScoreFrame()
    local scoreFrame = CreateFrame("Frame", "LagGuardScoreFrame", UIParent)
    scoreFrame:SetSize(140, 50)
    scoreFrame:SetPoint("TOP", UIParent, "TOP", 0, -50)
    scoreFrame:SetMovable(true)
    scoreFrame:EnableMouse(true)
    scoreFrame:RegisterForDrag("LeftButton")
    scoreFrame:SetScript("OnDragStart", scoreFrame.StartMoving)
    scoreFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Also save position here if needed
    end)
    scoreFrame:SetClampedToScreen(true)
    scoreFrame:Hide() -- Hidden by default
    
    -- Create background with rounded corners using a texture
    local bg = scoreFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Create border
    local border = CreateFrame("Frame", nil, scoreFrame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", scoreFrame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", scoreFrame, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    
    -- Create title
    local title = scoreFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -7)
    title:SetText("Connection Quality")
    
    -- Create score text
    local scoreText = scoreFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    scoreText:SetPoint("CENTER", 0, -5)
    scoreText:SetText("100")
    scoreFrame.scoreText = scoreText
    
    -- Function to update score display
    scoreFrame.Update = function(score)
        score = score or currentConnectionScore
        
        -- Set color based on score
        if score >= 80 then
            scoreText:SetText("|cFF00FF00" .. math.floor(score) .. "|r") -- Green for good
        elseif score >= 50 then
            scoreText:SetText("|cFFFFFF00" .. math.floor(score) .. "|r") -- Yellow for medium
        else
            scoreText:SetText("|cFFFF0000" .. math.floor(score) .. "|r") -- Red for bad
        end
    end
    
    scoreFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Connection Quality Score")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Score: " .. math.floor(currentConnectionScore))
        
        -- Add info about what affects the score
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Factors affecting score:")
        
        local _, _, homeLatency, worldLatency = GetNetStats()
        GameTooltip:AddLine("- Latency: " .. math.max(homeLatency, worldLatency) .. "ms")
        
        local maxJitter = 0
        if LG.analytics and LG.analytics.calculateJitter then
            local homeJitter = LG.analytics.calculateJitter(LG.homeLatencyHistory, 10)
            local worldJitter = LG.analytics.calculateJitter(LG.worldLatencyHistory, 10)
            maxJitter = math.max(homeJitter, worldJitter)
        end
        GameTooltip:AddLine("- Jitter: " .. string.format("%.1fms", maxJitter))
        
        local packetLoss = 0
        if LG.analytics and LG.analytics.estimatePacketLoss then
            packetLoss = LG.analytics.estimatePacketLoss()
        end
        GameTooltip:AddLine("- Packet Loss: " .. string.format("%.1f%%", packetLoss))
        
        -- Add safety advice
        GameTooltip:AddLine(" ")
        if currentConnectionScore >= 80 then
            GameTooltip:AddLine("|cFF00FF00Safe for combat and dungeons|r")
        elseif currentConnectionScore >= 50 then
            GameTooltip:AddLine("|cFFFFFF00Use caution in combat situations|r")
        else
            GameTooltip:AddLine("|cFFFF0000High risk - avoid combat if possible|r")
        end
        
        -- Add zone info if available
        GameTooltip:AddLine(" ")
        local zoneIsSafe = IsSafeZone()
        if zoneIsSafe ~= nil then
            if zoneIsSafe then
                GameTooltip:AddLine("Current zone: |cFF00FF00Usually stable|r")
            else
                GameTooltip:AddLine("Current zone: |cFFFFFF00Historically unstable|r")
            end
        end
        
        GameTooltip:Show()
    end)
    
    scoreFrame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Update once at creation
    scoreFrame.Update()
    
    LG.scoreFrame = scoreFrame
    return scoreFrame
end

-- Toggle latency log visibility
local function ToggleLatencyLog()
    if not LG.logFrame then
        CreateLatencyLogFrame()
        
        -- Add entries if the log is empty or only has the startup message
        if #latencyLogEntries <= 1 then
            local _, _, homeLatency, worldLatency = GetNetStats()
            LogLatencyEvent(1, "Latency log created")
            LogLatencyEvent(1, string.format("Current latency - Home: %dms, World: %dms", homeLatency, worldLatency))
            
            -- Add info about connection quality
            if LG.CalculateConnectionScore then
                local score = LG.CalculateConnectionScore()
                LogLatencyEvent(1, string.format("Connection quality score: %d/100", math.floor(score)))
            end
            
            -- Add info about how the log works
            LogLatencyEvent(1, "Log will record latency spikes and connection events")
            LogLatencyEvent(1, "Yellow entries indicate moderate latency spikes")
            LogLatencyEvent(1, "Red entries indicate severe latency spikes")
            
            -- Add packet loss info if available
            if LG.analytics and LG.analytics.estimatePacketLoss then
                local packetLoss = LG.analytics.estimatePacketLoss()
                LogLatencyEvent(1, string.format("Current packet loss estimate: %.1f%%", packetLoss))
            end
            
            -- Check for safe zone status
            if LG.IsSafeZone then
                local isSafe = LG.IsSafeZone()
                if isSafe ~= nil then
                    LogLatencyEvent(1, "Current zone is " .. (isSafe and "historically stable" or "historically unstable"))
                end
            end
        end
    end
    
    if LG.logFrame:IsShown() then
        LG.logFrame:Hide()
    else
        LG.logFrame:Show()
        LG.logFrame.Update()
    end
end

-- Toggle connection score display
local function ToggleScoreDisplay()
    if not LG.scoreFrame then
        CreateScoreFrame()
    end
    
    if LG.scoreFrame:IsShown() then
        LG.scoreFrame:Hide()
    else
        LG.scoreFrame:Show()
        LG.scoreFrame.Update()
    end
end

-- Function to display a comprehensive list of commands
local function ShowLoginCommands()
    -- Create a message frame that will show and then fade out
    local messageFrame = CreateFrame("Frame", "LagGuardCommandsFrame", UIParent)
    messageFrame:SetSize(600, 350)
    messageFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    messageFrame:SetFrameStrata("HIGH")
    
    -- Create a semi-transparent background
    local bg = messageFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Create a border
    local border = CreateFrame("Frame", nil, messageFrame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", messageFrame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", messageFrame, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    
    -- Create title
    local title = messageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cFF00FF00LagGuard Commands|r")
    
    -- Create message text
    local message = messageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOPLEFT", 20, -40)
    message:SetPoint("BOTTOMRIGHT", -20, 40)
    message:SetJustifyH("LEFT")
    message:SetJustifyV("TOP")
    message:SetText(
        "|cFFFFFF00Basic Commands:|r\n" ..
        "/lg or /lagguard - Show this help message\n" ..
        "/lg toggle - Toggle the addon on/off\n" ..
        "/lg config - Open the configuration panel\n\n" ..
        
        "|cFFFFFF00Visual Tools:|r\n" ..
        "/lg graph - Display the latency trend graph\n" ..
        "/lg score - Show/hide connection quality score\n" ..
        "/lg map - Show zone latency map\n" ..
        "/lg time - Show time of day analysis\n\n" ..
        
        "|cFFFFFF00Data Tools:|r\n" ..
        "/lg log - Show latency event log\n" ..
        "/lg safezone - Check if your current zone has stable latency\n" ..
        "/lg analytics - Show current analytics stats\n" ..
        "/lg minimap - Toggle minimap button\n\n" ..
        
        "|cFFFFFF00Safety Features:|r\n" ..
        "- Combat warnings based on latency\n" ..
        "- Defensive ability suggestions\n" ..
        "- Time-based latency predictions\n" ..
        "- Party/raid notifications\n" ..
        "- Safe zone detection\n" ..
        "- Latency forecasting"
    )
    
    -- Create close button
    local closeButton = CreateFrame("Button", nil, messageFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() messageFrame:Hide() end)
    
    -- Create "Don't show again" checkbox
    local hideCheckbox = CreateFrame("CheckButton", "LagGuardHideStartupMsg", messageFrame, "UICheckButtonTemplate")
    hideCheckbox:SetPoint("BOTTOMLEFT", 15, 15)
    _G[hideCheckbox:GetName() .. "Text"]:SetText("Don't show at login")
    hideCheckbox:SetScript("OnClick", function(self)
        LG.EnsureSavedVars()
        LagGuardDB.hideLoginCommands = self:GetChecked()
    end)
    
    -- Set checkbox state from saved variable
    if LagGuardDB and LagGuardDB.hideLoginCommands then
        hideCheckbox:SetChecked(true)
        messageFrame:Hide() -- Don't show if user chose to hide
    end
    
    -- Auto-hide after 20 seconds
    C_Timer.After(20, function()
        if not messageFrame or not messageFrame:IsShown() then return end
        
        -- Initialize alpha value
        messageFrame.fadeAlpha = 1
        
        -- Fade out animation
        messageFrame:SetScript("OnUpdate", function(self, elapsed)
            self.timer = (self.timer or 0) + elapsed
            if self.timer > 0.05 then
                -- Decrement the alpha value
                self.fadeAlpha = (self.fadeAlpha or 1) - 0.05
                
                -- Ensure alpha is valid (between 0 and 1)
                if self.fadeAlpha < 0 then self.fadeAlpha = 0 end
                
                -- Apply the alpha
                self:SetAlpha(self.fadeAlpha)
                self.timer = 0
                
                -- When fully transparent, hide the frame
                if self.fadeAlpha <= 0 then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                end
            end
        end)
    end)
end

-- Create zone latency map display
local function ToggleLatencyMap()
    -- Create map frame if it doesn't exist yet
    if not LG.latencyMapFrame then
        local frame = CreateFrame("Frame", "LagGuardLatencyMapFrame", UIParent)
        frame:SetSize(600, 400)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetClampedToScreen(true)
        frame:Hide() -- Hidden by default
        
        -- Create background
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
        
        -- Create border
        local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
        
        -- Create title
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -15)
        title:SetText("Zone Latency Map")
        
        -- Close button
        local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        closeButton:SetScript("OnClick", function() frame:Hide() end)
        
        -- Create scroll frame to hold zone list
        local scrollFrame = CreateFrame("ScrollFrame", "LagGuardMapScrollFrame", frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -40)
        scrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
        
        local scrollChild = CreateFrame("Frame", "LagGuardMapScrollChild", scrollFrame)
        scrollChild:SetSize(scrollFrame:GetWidth(), 800) -- Height will be adjusted dynamically
        scrollFrame:SetScrollChild(scrollChild)
        
        -- Add headers
        local zoneHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        zoneHeader:SetPoint("TOPLEFT", 10, 0)
        zoneHeader:SetWidth(200)
        zoneHeader:SetJustifyH("LEFT")
        zoneHeader:SetText("Zone")
        
        local avgHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        avgHeader:SetPoint("LEFT", zoneHeader, "RIGHT", 20, 0)
        avgHeader:SetWidth(80)
        avgHeader:SetJustifyH("RIGHT")
        avgHeader:SetText("Avg Latency")
        
        local samplesHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        samplesHeader:SetPoint("LEFT", avgHeader, "RIGHT", 20, 0)
        samplesHeader:SetWidth(60)
        samplesHeader:SetJustifyH("RIGHT")
        samplesHeader:SetText("Samples")
        
        local statusHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusHeader:SetPoint("LEFT", samplesHeader, "RIGHT", 20, 0)
        statusHeader:SetWidth(80)
        statusHeader:SetJustifyH("CENTER")
        statusHeader:SetText("Status")
        
        -- Add separator line
        local separator = scrollChild:CreateTexture(nil, "ARTWORK")
        separator:SetHeight(1)
        separator:SetWidth(scrollChild:GetWidth() - 20)
        separator:SetPoint("TOPLEFT", zoneHeader, "BOTTOMLEFT", 0, -5)
        separator:SetColorTexture(0.7, 0.7, 0.7, 0.5)
        
        -- Function to update map display
        frame.Update = function()
            -- Clear existing entries
            for i = 1, scrollChild:GetNumChildren() do
                local child = select(i, scrollChild:GetChildren())
                if child and child:GetObjectType() == "Frame" and not child:GetName() then
                    child:Hide()
                end
            end
            
            -- Create sorted list of zones
            local zoneList = {}
            for zoneID, data in pairs(zoneLatencyData) do
                -- Only add zones with enough samples
                if data.samples and data.samples >= 3 then
                    local zoneName = GetMapNameByID and GetMapNameByID(zoneID) or ("Zone " .. zoneID)
                    if zoneName then
                        table.insert(zoneList, {
                            id = zoneID,
                            name = zoneName,
                            avgLatency = (data.avgHome + data.avgWorld) / 2,
                            samples = data.samples
                        })
                    end
                end
            end
            
            -- Sort by latency (low to high)
            table.sort(zoneList, function(a, b) return a.avgLatency < b.avgLatency end)
            
            -- Add "no data" message if list is empty
            if #zoneList == 0 then
                local noDataText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                noDataText:SetPoint("TOP", separator, "BOTTOM", 0, -20)
                noDataText:SetText("No zone data collected yet. Visit different zones to collect data.")
                return
            end
            
            -- Add zone entries
            local yOffset = -30  -- Start below the separator
            
            for i, zone in ipairs(zoneList) do
                local entryFrame = CreateFrame("Frame", nil, scrollChild)
                entryFrame:SetSize(scrollChild:GetWidth() - 20, 30)
                entryFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
                
                -- Alternate row backgrounds
                if i % 2 == 0 then
                    local rowBg = entryFrame:CreateTexture(nil, "BACKGROUND")
                    rowBg:SetAllPoints()
                    rowBg:SetColorTexture(0.15, 0.15, 0.15, 0.3)
                end
                
                -- Zone name
                local nameText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                nameText:SetPoint("LEFT", 0, 0)
                nameText:SetWidth(200)
                nameText:SetJustifyH("LEFT")
                nameText:SetText(zone.name)
                
                -- Average latency
                local avgText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                avgText:SetPoint("LEFT", nameText, "RIGHT", 20, 0)
                avgText:SetWidth(80)
                avgText:SetJustifyH("RIGHT")
                
                -- Color based on latency
                local latencyText = string.format("%.1fms", zone.avgLatency)
                if zone.avgLatency < 100 then
                    avgText:SetText("|cFF00FF00" .. latencyText .. "|r")
                elseif zone.avgLatency < 200 then
                    avgText:SetText("|cFFFFFF00" .. latencyText .. "|r")
                else
                    avgText:SetText("|cFFFF0000" .. latencyText .. "|r")
                end
                
                -- Samples count
                local samplesText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                samplesText:SetPoint("LEFT", avgText, "RIGHT", 20, 0)
                samplesText:SetWidth(60)
                samplesText:SetJustifyH("RIGHT")
                samplesText:SetText(zone.samples)
                
                -- Status indicator
                local statusText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                statusText:SetPoint("LEFT", samplesText, "RIGHT", 20, 0)
                statusText:SetWidth(80)
                statusText:SetJustifyH("CENTER")
                
                if zone.avgLatency < LG.defaults.safeZoneThreshold then
                    statusText:SetText("|cFF00FF00Stable|r")
                else
                    statusText:SetText("|cFFFF0000Unstable|r")
                end
                
                -- Make the row highlight on hover
                entryFrame:SetScript("OnEnter", function(self)
                    if i % 2 == 0 then
                        rowBg:SetColorTexture(0.3, 0.3, 0.3, 0.3)
                    else
                        local rowHighlight = self:CreateTexture(nil, "BACKGROUND")
                        rowHighlight:SetAllPoints()
                        rowHighlight:SetColorTexture(0.3, 0.3, 0.3, 0.3)
                        self.highlight = rowHighlight
                    end
                    
                    -- Add tooltip with more info
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(zone.name)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Home Latency: " .. string.format("%.1fms", zoneLatencyData[zone.id].avgHome))
                    GameTooltip:AddLine("World Latency: " .. string.format("%.1fms", zoneLatencyData[zone.id].avgWorld))
                    GameTooltip:AddLine("Samples Collected: " .. zone.samples)
                    GameTooltip:AddLine(" ")
                    
                    if zone.avgLatency < LG.defaults.safeZoneThreshold then
                        GameTooltip:AddLine("|cFF00FF00This zone has historically stable latency|r")
                    else
                        GameTooltip:AddLine("|cFFFF0000This zone has historically unstable latency|r")
                    end
                    
                    GameTooltip:Show()
                end)
                
                entryFrame:SetScript("OnLeave", function(self)
                    if i % 2 == 0 then
                        rowBg:SetColorTexture(0.15, 0.15, 0.15, 0.3)
                    elseif self.highlight then
                        self.highlight:Hide()
                        self.highlight = nil
                    end
                    
                    GameTooltip:Hide()
                end)
                
                -- Update y offset for next row
                yOffset = yOffset - 30
                
                -- Show the frame
                entryFrame:Show()
            end
            
            -- Adjust scrollChild height
            scrollChild:SetHeight(math.max(scrollFrame:GetHeight(), -yOffset + 20))
        end
        
        -- Add info text about data collection
        local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
        infoText:SetWidth(500)
        infoText:SetText("Zones with better connection quality appear at the top. Data is collected as you visit zones.")
        
        -- Update when shown
        frame:SetScript("OnShow", function()
            frame.Update()
        end)
        
        -- Store reference to the frame
        LG.latencyMapFrame = frame
    end
    
    -- Toggle visibility
    if LG.latencyMapFrame:IsShown() then
        LG.latencyMapFrame:Hide()
    else
        LG.latencyMapFrame:Show()
        LG.latencyMapFrame.Update()
    end
end

-- Create minimap button for LagGuard
local function CreateMinimapButton()
    -- Create the minimap button frame
    local minimapButton = CreateFrame("Button", "LagGuardMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Create icon texture
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\AddOns\\LagGuard\\Textures\\icon") -- You may need to create this texture
    -- If the custom texture doesn't exist, use a default one
    if not icon:GetTexture() then
        icon:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_30")
    end
    minimapButton.icon = icon
    
    -- Create border texture
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Set initial position (0 degrees on the minimap)
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", 80, 0)
    
    -- Variables for minimap button dragging
    local minimapShapes = {
        ["ROUND"] = {true, true, true, true},
        ["SQUARE"] = {false, false, false, false},
        ["CORNER-TOPLEFT"] = {false, false, false, true},
        ["CORNER-TOPRIGHT"] = {false, false, true, false},
        ["CORNER-BOTTOMLEFT"] = {false, true, false, false},
        ["CORNER-BOTTOMRIGHT"] = {true, false, false, false},
        ["SIDE-LEFT"] = {false, true, false, true},
        ["SIDE-RIGHT"] = {true, false, true, false},
        ["SIDE-TOP"] = {false, false, true, true},
        ["SIDE-BOTTOM"] = {true, true, false, false},
        ["TRICORNER-TOPLEFT"] = {false, true, true, true},
        ["TRICORNER-TOPRIGHT"] = {true, false, true, true},
        ["TRICORNER-BOTTOMLEFT"] = {true, true, false, true},
        ["TRICORNER-BOTTOMRIGHT"] = {true, true, true, false},
    }
    
    -- Function to update button position
    local function UpdateButtonPosition()
        local angle = math.rad(LagGuardDB.minimapButtonPosition or 0)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    
    -- Set up initial position from saved variables
    LG.EnsureSavedVars()
    if not LagGuardDB.minimapButtonPosition then
        LagGuardDB.minimapButtonPosition = 0
    end
    UpdateButtonPosition()
    
    -- Make the button draggable
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function()
        minimapButton:StartMoving()
    end)
    
    minimapButton:SetScript("OnDragStop", function()
        minimapButton:StopMovingOrSizing()
        
        -- Calculate the angle based on position
        local centerX, centerY = Minimap:GetCenter()
        local buttonX, buttonY = minimapButton:GetCenter()
        local angle = math.deg(math.atan2(buttonY - centerY, buttonX - centerX))
        
        -- Save position to settings
        LagGuardDB.minimapButtonPosition = angle
        
        -- Update position to snap to the minimap circle
        UpdateButtonPosition()
    end)
    
    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("LagGuard")
        
        -- Get current latency
        local _, _, homeLatency, worldLatency = GetNetStats()
        local maxLatency = math.max(homeLatency, worldLatency)
        
        -- Get current connection score
        local score = currentConnectionScore or 100
        
        -- Add status to tooltip
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Current Status:")
        
        -- Latency info
        if maxLatency < 100 then
            GameTooltip:AddLine("Latency: |cFF00FF00" .. maxLatency .. "ms|r")
        elseif maxLatency < 300 then
            GameTooltip:AddLine("Latency: |cFFFFFF00" .. maxLatency .. "ms|r")
        else
            GameTooltip:AddLine("Latency: |cFFFF0000" .. maxLatency .. "ms|r")
        end
        
        -- Connection score
        if score >= 80 then
            GameTooltip:AddLine("Connection Quality: |cFF00FF00" .. math.floor(score) .. "/100|r")
        elseif score >= 50 then
            GameTooltip:AddLine("Connection Quality: |cFFFFFF00" .. math.floor(score) .. "/100|r")
        else
            GameTooltip:AddLine("Connection Quality: |cFFFF0000" .. math.floor(score) .. "/100|r")
        end
        
        -- Add usage tips
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-Click: Toggle Connection Score")
        GameTooltip:AddLine("Right-Click: Show Commands")
        GameTooltip:AddLine("Shift-Click: Toggle Latency Log")
        
        GameTooltip:Show()
    end)
    
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handlers
    minimapButton:SetScript("OnClick", function(self, button)
        if IsShiftKeyDown() then
            -- Shift-click to toggle latency log
            ToggleLatencyLog()
        elseif button == "RightButton" then
            -- Right-click for commands menu
            ShowLoginCommands()
        else
            -- Left-click to toggle connection score
            ToggleScoreDisplay()
        end
    end)
    
    -- Update color based on connection status
    minimapButton.UpdateStatus = function()
        local score = currentConnectionScore or 100
        
        -- Update color based on score
        if score >= 80 then
            -- Good (green)
            icon:SetVertexColor(0, 1, 0)
        elseif score >= 50 then
            -- Medium (yellow)
            icon:SetVertexColor(1, 1, 0)
        else
            -- Bad (red)
            icon:SetVertexColor(1, 0, 0)
        end
    end
    
    -- Make the button movable
    minimapButton:SetMovable(true)
    minimapButton:SetClampedToScreen(true)
    
    -- Store global reference
    LG.minimapButton = minimapButton
    
    -- Initialize with current status
    minimapButton.UpdateStatus()
    
    return minimapButton
end

-- Predict upcoming latency based on historical data
local function PredictUpcomingLatency()
    -- Get current time
    local currentHour = tonumber(date("%H"))
    if not currentHour then return nil end
    
    -- Check if we have enough historical data
    local timeData = timeOfDayData
    if not timeData or not next(timeData) then return nil end
    
    -- Look at the next hour's historical pattern
    local nextHour = (currentHour + 1) % 24
    local nextData = timeData[nextHour]
    
    -- If we don't have data for the next hour, check current hour
    if not nextData or not nextData.samples or nextData.samples < 3 then
        nextData = timeData[currentHour]
        if not nextData or not nextData.samples or nextData.samples < 3 then
            return nil -- Not enough data
        end
    end
    
    -- Return the predicted latency based on historical average
    return nextData.avgLatency
end

-- Check for upcoming latency predictions and warn if needed
local function CheckLatencyPredictionWarning()
    if not LG.defaults.enablePredictiveWarnings then return end
    
    -- Only update predictions every few minutes to avoid spamming
    local currentTime = GetTime()
    if currentTime - lastPredictionUpdate < predictionUpdateInterval then return end
    lastPredictionUpdate = currentTime
    
    -- Get predicted latency based on time of day and historical patterns
    local prediction = PredictUpcomingLatency()
    if not prediction or prediction < LG.defaults.warningThreshold then return end
    
    -- Log the prediction
    LogLatencyEvent(2, string.format("Latency prediction: Expected increase to %dms in upcoming period", prediction))
    
    -- Only show warning to user if it's significantly higher than current latency
    local _, _, homeLatency, worldLatency = GetNetStats()
    local currentLatency = math.max(homeLatency or 0, worldLatency or 0)
    
    if prediction > currentLatency * 1.5 and prediction > LG.defaults.warningThreshold then
        -- Show warning message
        local msg = string.format("LagGuard Warning: Historical data suggests latency may increase to ~%dms within the next hour", prediction)
        
        -- Add to chat
        if LG.defaults.chatAlerts then
            print("|cFFFFFF00" .. msg .. "|r")
        end
        
        -- Show raid warning style message
        if LG.defaults.screenAlerts then
            RaidNotice_AddMessage(RaidWarningFrame, "|cFFFFFF00" .. msg .. "|r", ChatTypeInfo["RAID_WARNING"])
        end
        
        -- Play sound
        if LG.defaults.soundEnabled then
            PlaySound(8959)
        end
    end
end

-- Periodic update for enhancements
local function UpdateEnhancements()
    -- Check for zone changes and record latency data
    RecordZoneLatency()
    
    -- Update time of day data
    UpdateTimeOfDayData()
    
    -- Check for predictive warnings
    CheckLatencyPredictionWarning()
    
    -- Update connection score periodically
    local currentTime = GetTime()
    if currentTime - lastScoreUpdate > LG.defaults.scoreUpdateInterval then
        CalculateConnectionScore()
        lastScoreUpdate = currentTime
        
        -- Update score display if it exists and is shown
        if LG.scoreFrame and LG.scoreFrame:IsShown() then
            LG.scoreFrame.Update()
        end
        
        -- Log periodic latency info (every 30 seconds instead of every minute)
        if math.floor(currentTime) % 30 == 0 then
            local _, _, homeLatency, worldLatency = GetNetStats()
            LogLatencyEvent(1, string.format("Status - Home: %dms, World: %dms, Score: %d", 
                homeLatency, worldLatency, math.floor(currentConnectionScore)))
        end
    end
    
    -- Check for latency spikes to log
    local _, _, homeLatency, worldLatency = GetNetStats()
    local maxLatency = math.max(homeLatency or 0, worldLatency or 0)
    
    -- Define threshold levels
    local moderateThreshold = LG.defaults.warningThreshold or 500
    local severeThreshold = LG.defaults.logSevereSpikeThreshold or 1000
    
    -- Log severe spikes
    if maxLatency >= severeThreshold then
        local spikeType = (homeLatency > worldLatency) and "Home" or "World"
        LogLatencyEvent(3, "Severe " .. spikeType .. " latency spike: " .. maxLatency .. "ms")
        
        -- Add additional diagnostic info for severe spikes
        if LG.analytics and LG.analytics.estimatePacketLoss then
            local packetLoss = LG.analytics.estimatePacketLoss()
            if packetLoss > 0.5 then
                LogLatencyEvent(3, string.format("Detected packet loss: %.1f%%", packetLoss))
            end
        end
    -- Log moderate spikes
    elseif maxLatency >= moderateThreshold then
        local spikeType = (homeLatency > worldLatency) and "Home" or "World"
        LogLatencyEvent(2, "Moderate " .. spikeType .. " latency spike: " .. maxLatency .. "ms")
    end
    
    -- Automatic actions if enabled
    if maxLatency >= LG.defaults.autoActionsThreshold then
        PerformAutoActions(maxLatency)
    end
    
    -- Check if we need to take combat protective actions
    if UnitAffectingCombat("player") and maxLatency >= LG.defaults.dangerThreshold then
        -- Suggest defensive cooldowns
        SuggestDefensives(maxLatency)
        
        -- Notify party if severe
        if maxLatency >= LG.defaults.dangerThreshold then
            NotifyPartyOfLag(maxLatency)
        end
    end
end

-- Register slash command hooks
local function RegisterCommands()
    local originalSlashCmd = SlashCmdList["LAGGUARD"]
    SlashCmdList["LAGGUARD"] = function(msg)
        if msg == "log" then
            ToggleLatencyLog()
        elseif msg == "score" then
            ToggleScoreDisplay()
        elseif msg == "safezone" then
            local isSafe = IsSafeZone()
            if isSafe == nil then
                print("LagGuard: Not enough data for current zone yet.")
            elseif isSafe then
                print("LagGuard: Current zone appears to be a safe zone with stable latency.")
            else
                print("LagGuard: Current zone has historically had unstable latency.")
            end
        elseif msg == "map" or msg == "zonemap" then
            -- New command to show the zone latency map
            ToggleLatencyMap()
        elseif msg == "time" or msg == "analytics" then
            -- New command to show time analysis
            ToggleTimeAnalysis()
        elseif msg == "minimap" then
            -- Toggle minimap button
            LG.EnsureSavedVars()
            LagGuardDB.enableMinimapButton = not LagGuardDB.enableMinimapButton
            print("LagGuard minimap button " .. (LagGuardDB.enableMinimapButton and "enabled" or "disabled") .. 
                ". Reload UI to apply change.")
        elseif msg == "help" or msg == "" then
            -- Show the commands help frame when "/lg help" or just "/lg" is used
            ShowLoginCommands()
        else
            -- Pass to original handler
            originalSlashCmd(msg)
        end
    end
    
    -- Add commands to the help text
    print("LagGuard Enhancements loaded")
    print("Additional commands:")
    print("/lg log - Show latency event log")
    print("/lg score - Toggle connection quality score")
    print("/lg safezone - Check if current zone is historically stable")
    print("/lg map - Show latency map by zone")
    print("/lg time - Show time of day analysis")
    print("/lg help - Show all available commands")
end

-- Main initialization
enhancementsFrame:RegisterEvent("PLAYER_LOGIN")
enhancementsFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Initialize from saved variables
        LG.EnsureSavedVars()
        
        -- Add new default settings
        LG.defaults.enableMinimapButton = true -- Enable minimap button by default
        LG.defaults.notifyGroupOfLag = false -- Disabled by default to avoid annoyance
        LG.defaults.enablePredictiveWarnings = true -- Enable predictive warnings by default
        
        -- Load existing zone data if available
        if LagGuardDB.zoneLatencyData then
            zoneLatencyData = LagGuardDB.zoneLatencyData
        end
        
        -- Load existing log if available
        if LagGuardDB.latencyLog then
            latencyLogEntries = LagGuardDB.latencyLog
        end
        
        -- Load time of day data
        InitializeTimeAnalytics()
        
        -- Load class-specific defensive cooldowns
        LoadDefensiveCooldowns()
        
        -- Create minimap button if enabled
        if LagGuardDB.enableMinimapButton then
            local minimapButton = CreateMinimapButton()
            if minimapButton then
                -- Initialize with current status
                minimapButton:UpdateStatus()
            end
        end
        
        -- Register slash commands
        RegisterCommands()
        
        -- Set up periodic updates
        enhancementsFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed < 1 then return end
            self.elapsed = 0
            
            if not LagGuardDB or not LagGuardDB.enabled then return end
            
            UpdateEnhancements()
            
            -- Update minimap button status if exists
            if LG.minimapButton then
                LG.minimapButton:UpdateStatus()
            end
        end)
        
        -- Log startup
        LogLatencyEvent(1, "LagGuard Enhancements loaded with advanced features")
        
        -- Show login message with all available commands
        C_Timer.After(2, function() -- Delay to let other addons load first
            ShowLoginCommands()
        end)
    end
end)

-- Make APIs available
LG.ToggleLatencyLog = ToggleLatencyLog
LG.ToggleScoreDisplay = ToggleScoreDisplay
LG.ToggleLatencyMap = ToggleLatencyMap
LG.ToggleTimeAnalysis = ToggleTimeAnalysis
LG.IsSafeZone = IsSafeZone
LG.CalculateConnectionScore = CalculateConnectionScore
LG.LogLatencyEvent = LogLatencyEvent
LG.ShowLoginCommands = ShowLoginCommands
LG.UpdateTimeOfDayData = UpdateTimeOfDayData
LG.SuggestDefensives = SuggestDefensives
LG.NotifyPartyOfLag = NotifyPartyOfLag
LG.CheckLatencyPredictionWarning = CheckLatencyPredictionWarning
LG.WarnOnCombatEntry = WarnOnCombatEntry
LG.PredictUpcomingLatency = PredictUpcomingLatency