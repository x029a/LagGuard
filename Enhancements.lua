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