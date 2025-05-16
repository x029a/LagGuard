-- LagGuard Alerts Module
-- Provides visual status indicators for the current latency state

local addonName, LG = ...

-- Alerts Module - Provides visual indicators for latency status
local alertFrame

-- Create a local reference to the history tables for easier access
local homeLatencyHistory = LG.homeLatencyHistory or {}
local worldLatencyHistory = LG.worldLatencyHistory or {}

-- Initialize variables for tracking trends
local prevHomeLatency = 0 
local prevWorldLatency = 0

-- Create a frame for handling updates
local updateFrame = CreateFrame("Frame") 
local updateInterval = 0.5

-- Ensure required functions exist
LG.EnsureSavedVars = LG.EnsureSavedVars or function()
    if not LagGuardDB then LagGuardDB = {} end
    if not LG.defaults then LG.defaults = {} end
    
    -- Apply defaults for any missing values
    for k, v in pairs(LG.defaults) do
        if LagGuardDB[k] == nil then
            LagGuardDB[k] = v
        end
    end
end

LG.CalculateBaseline = LG.CalculateBaseline or function(history)
    if not history or #history == 0 then return 0 end
    
    local sum = 0
    local baselineRecords = LG.defaults and LG.defaults.baselineRecords or 20
    for i = 1, math.min(#history, baselineRecords) do
        sum = sum + history[i]
    end
    return sum / math.min(#history, baselineRecords)
end

-- Function to save the frame position
local function SaveFramePosition()
    if not alertFrame then return end
    
    -- Ensure saved vars exist
    LG.EnsureSavedVars()
    
    -- Get frame position
    local point, relativeTo, relativePoint, xOfs, yOfs = alertFrame:GetPoint()
    
    -- Save position data
    if not LagGuardDB.framePosition then
        LagGuardDB.framePosition = {}
    end
    
    LagGuardDB.framePosition = {
        point = point,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

-- Function to load the saved frame position
local function LoadFramePosition()
    if not alertFrame or not LagGuardDB or not LagGuardDB.framePosition then return end
    
    local pos = LagGuardDB.framePosition
    if pos and pos.point and pos.relativePoint and pos.xOfs and pos.yOfs then
        alertFrame:ClearAllPoints()
        alertFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    end
end

-- Function to update the layout based on compact mode setting
local function UpdateAlertFrameLayout()
    if not alertFrame then return end
    
    LG.EnsureSavedVars()
    local compactMode = LagGuardDB.enableCompactMode
    
    -- Set the frame size based on mode
    if compactMode then
        alertFrame:SetSize(40, 40) -- Smaller width for compact mode (reduced from 70 to 40)
        
        -- Update elements for compact mode
        alertFrame.homeText:SetText("H")
        alertFrame.worldText:SetText("W")
        
        -- Hide additional elements in compact mode
        alertFrame.packetLossLabel:Hide()
        alertFrame.jitterLabel:Hide()
        alertFrame.graphButton:Hide()
        alertFrame.logButton:Hide()
        alertFrame.scoreButton:Hide()
        alertFrame.liveDataButton:Hide()
    else
        alertFrame:SetSize(130, 60) -- Larger size for full mode
        
        -- Restore text for full mode
        local _, _, homeLatency, worldLatency = GetNetStats()
        alertFrame.homeText:SetText("H: " .. homeLatency .. "ms")
        alertFrame.worldText:SetText("W: " .. worldLatency .. "ms")
        
        -- Show additional elements in full mode
        alertFrame.packetLossLabel:Show()
        alertFrame.jitterLabel:Show()
        alertFrame.graphButton:Show()
        alertFrame.logButton:Show()
        alertFrame.scoreButton:Show()
        alertFrame.liveDataButton:Show()
    end
end

-- Function to initialize the visual components
local function Initialize()
    -- Check if the frame already exists to prevent duplicates
    if _G["LagGuardAlertFrame"] then
        -- Use the existing frame
        alertFrame = _G["LagGuardAlertFrame"]
        -- Run a full update on the existing frame
        if _G["UpdateIndicator"] then
            _G["UpdateIndicator"]()
        end
        return
    end
    
    -- Create the main display frame
    alertFrame = CreateFrame("Frame", "LagGuardAlertFrame", UIParent)
    alertFrame:SetSize(130, 60) -- Increased height to accommodate all elements
    alertFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -120, -200)
    alertFrame:SetMovable(true)
    alertFrame:EnableMouse(true)
    alertFrame:RegisterForDrag("LeftButton")
    alertFrame:SetScript("OnDragStart", alertFrame.StartMoving)
    alertFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition() -- Save position when user stops dragging
    end)
    alertFrame:SetClampedToScreen(true)
    
    -- Create background
    local bg = alertFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    
    -- Create border
    alertFrame.border = CreateFrame("Frame", nil, alertFrame, "BackdropTemplate")
    alertFrame.border:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", -1, 1)
    alertFrame.border:SetPoint("BOTTOMRIGHT", alertFrame, "BOTTOMRIGHT", 1, -1)
    alertFrame.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    alertFrame.border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    
    -- Create status indicators
    local homeStatus = alertFrame:CreateTexture(nil, "OVERLAY")
    homeStatus:SetSize(12, 12)
    homeStatus:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 5, -5)
    homeStatus:SetColorTexture(0, 1, 0, 1) -- Default to green
    alertFrame.homeStatus = homeStatus
    
    local worldStatus = alertFrame:CreateTexture(nil, "OVERLAY")
    worldStatus:SetSize(12, 12)
    worldStatus:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 5, -22)
    worldStatus:SetColorTexture(0, 1, 0, 1) -- Default to green
    alertFrame.worldStatus = worldStatus
    
    -- Create latency text
    local homeText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    homeText:SetPoint("LEFT", homeStatus, "RIGHT", 5, 0)
    homeText:SetText("H: 0ms")
    alertFrame.homeText = homeText
    
    local worldText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    worldText:SetPoint("LEFT", worldStatus, "RIGHT", 5, 0)
    worldText:SetText("W: 0ms")
    alertFrame.worldText = worldText
    
    -- Create trend indicators
    local homeTrend = alertFrame:CreateTexture(nil, "OVERLAY")
    homeTrend:SetSize(8, 8)
    homeTrend:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 80, -5) -- Fixed position
    homeTrend:SetTexture("Interface\\MINIMAP\\ROTATING-MINIMAPGUIDEARROW")
    homeTrend:Hide()
    alertFrame.homeTrend = homeTrend
    
    local worldTrend = alertFrame:CreateTexture(nil, "OVERLAY")
    worldTrend:SetSize(8, 8)
    worldTrend:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 80, -22) -- Vertically aligned with the same X position
    worldTrend:SetTexture("Interface\\MINIMAP\\ROTATING-MINIMAPGUIDEARROW")
    worldTrend:Hide()
    alertFrame.worldTrend = worldTrend
    
    -- Add packet loss indicator
    local packetLossLabel = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    packetLossLabel:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", -5, -5)
    packetLossLabel:SetText("PL: 0%")
    packetLossLabel:SetTextColor(1, 1, 1)
    alertFrame.packetLossLabel = packetLossLabel
    
    -- Add jitter indicator
    local jitterLabel = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    jitterLabel:SetPoint("TOPRIGHT", packetLossLabel, "BOTTOMRIGHT", 0, -5)
    jitterLabel:SetText("JT: 0ms")
    jitterLabel:SetTextColor(1, 1, 1)
    alertFrame.jitterLabel = jitterLabel
    
    -- Create action buttons (only shown in full mode)
    -- Create graph button (small icon to open graph)
    local graphButton = CreateFrame("Button", nil, alertFrame)
    graphButton:SetSize(16, 16)
    graphButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", 45, 5)
    
    local graphIcon = graphButton:CreateTexture(nil, "ARTWORK")
    graphIcon:SetAllPoints()
    graphIcon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    graphButton.icon = graphIcon
    
    graphButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Show Latency Graph")
        GameTooltip:Show()
    end)
    
    graphButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    graphButton:SetScript("OnClick", function()
        if LG.ToggleLatencyGraph then
            LG.ToggleLatencyGraph()
        else
            print("LagGuard: Analytics module not loaded.")
        end
    end)
    
    -- Create live data button
    local liveDataButton = CreateFrame("Button", nil, alertFrame)
    liveDataButton:SetSize(16, 16)
    liveDataButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", -50, 5)
    
    local liveDataIcon = liveDataButton:CreateTexture(nil, "ARTWORK")
    liveDataIcon:SetAllPoints()
    liveDataIcon:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow")
    liveDataButton.icon = liveDataIcon
    
    liveDataButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Show Live Data")
        GameTooltip:Show()
    end)
    
    liveDataButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    liveDataButton:SetScript("OnClick", function()
        if LG.ToggleLiveDataGraph then
            LG.ToggleLiveDataGraph()
        else
            LG.CreateLiveDataGraph()
        end
    end)
    
    -- Create log button
    local logButton = CreateFrame("Button", nil, alertFrame)
    logButton:SetSize(16, 16)
    logButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", -15, 5)
    
    local logIcon = logButton:CreateTexture(nil, "ARTWORK")
    logIcon:SetAllPoints()
    logIcon:SetTexture("Interface\\Buttons\\UI-GuildButton-MOTD-Up")
    logButton.icon = logIcon
    
    logButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Show Latency Log")
        GameTooltip:Show()
    end)
    
    logButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    logButton:SetScript("OnClick", function()
        if LG.ToggleLatencyLog then
            LG.ToggleLatencyLog()
        else
            print("LagGuard: Log module not loaded.")
        end
    end)
    
    -- Create score button
    local scoreButton = CreateFrame("Button", nil, alertFrame)
    scoreButton:SetSize(16, 16)
    scoreButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", 15, 5)
    
    local scoreIcon = scoreButton:CreateTexture(nil, "ARTWORK")
    scoreIcon:SetAllPoints()
    scoreIcon:SetTexture("Interface\\Buttons\\UI-GuildButton-OfficerNote-Up")
    scoreButton.icon = scoreIcon
    
    scoreButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Show Connection Score")
        GameTooltip:Show()
    end)
    
    scoreButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    scoreButton:SetScript("OnClick", function()
        if LG.ToggleScoreDisplay then
            LG.ToggleScoreDisplay()
        else
            print("LagGuard: Score module not loaded.")
        end
    end)
    
    -- Store references to action buttons
    alertFrame.graphButton = graphButton
    alertFrame.logButton = logButton
    alertFrame.scoreButton = scoreButton
    alertFrame.liveDataButton = liveDataButton
    
    -- Create tooltip
    alertFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("LagGuard Status")
        
        local _, _, homeLatency, worldLatency = GetNetStats()
        local homeBaseline = LG.CalculateBaseline(LG.homeLatencyHistory)
        local worldBaseline = LG.CalculateBaseline(LG.worldLatencyHistory)
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Home Latency: " .. homeLatency .. "ms")
        GameTooltip:AddLine("Baseline: " .. math.floor(homeBaseline) .. "ms")
        
        if #LG.homeLatencyHistory > 0 then
            local homeMin, homeMax = homeLatency, homeLatency
            for _, v in ipairs(LG.homeLatencyHistory) do
                homeMin = math.min(homeMin, v)
                homeMax = math.max(homeMax, v)
            end
            GameTooltip:AddLine("Min: " .. homeMin .. "ms, Max: " .. homeMax .. "ms")
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("World Latency: " .. worldLatency .. "ms")
        GameTooltip:AddLine("Baseline: " .. math.floor(worldBaseline) .. "ms")
        
        if #LG.worldLatencyHistory > 0 then
            local worldMin, worldMax = worldLatency, worldLatency
            for _, v in ipairs(LG.worldLatencyHistory) do
                worldMin = math.min(worldMin, v)
                worldMax = math.max(worldMax, v)
            end
            GameTooltip:AddLine("Min: " .. worldMin .. "ms, Max: " .. worldMax .. "ms")
        end
        
        -- Add connection quality info to tooltip
        if LG.analytics and LG.analytics.estimatePacketLoss then
            local packetLoss = LG.analytics.estimatePacketLoss()
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Estimated Packet Loss: " .. string.format("%.1f%%", packetLoss))
            
            if LG.analytics.calculateJitter and LG.homeLatencyHistory and LG.worldLatencyHistory then
                local homeJitter = LG.analytics.calculateJitter(LG.homeLatencyHistory, LG.defaults.trendSampleSize or 30)
                local worldJitter = LG.analytics.calculateJitter(LG.worldLatencyHistory, LG.defaults.trendSampleSize or 30)
                GameTooltip:AddLine("Home Jitter: " .. string.format("%.1fms", homeJitter))
                GameTooltip:AddLine("World Jitter: " .. string.format("%.1fms", worldJitter))
            end
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFF888888Left-click to drag|r")
        GameTooltip:AddLine("|cFF888888Right-click for options|r")
        GameTooltip:AddLine("|cFF888888Click graph icon to show trend|r")
        
        GameTooltip:Show()
    end)
    
    alertFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Create context menu
    alertFrame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            -- Open context menu
            if LG.ToggleConfig then
                LG.ToggleConfig()
            else
                print("LagGuard: Configuration module not loaded.")
            end
        end
    end)
    
    -- Setup update function
    _G["UpdateIndicator"] = function()
        LG.EnsureSavedVars()
        
        -- First check if the addon is enabled
        if not LagGuardDB.enabled then
            -- Hide the frame if addon is disabled
            if alertFrame then
                alertFrame:Hide()
            end
            return
        else
            -- Show the frame if addon is enabled
            if alertFrame then
                alertFrame:Show()
            else
                return -- Can't update if no frame exists
            end
        end
        
        -- Don't proceed if the frame isn't shown (e.g., during combat when frames can't be created)
        if not alertFrame:IsShown() then return end
        
        local _, _, homeLatency, worldLatency = GetNetStats()
        local homeBaseline = LG.CalculateBaseline(LG.homeLatencyHistory)
        local worldBaseline = LG.CalculateBaseline(LG.worldLatencyHistory)
        
        -- Determine latency trend direction
        if LG.homeLatencyHistory and #LG.homeLatencyHistory > 1 then
            local homeDiff = homeLatency - prevHomeLatency
            
            if math.abs(homeDiff) > 10 then
                alertFrame.homeTrend:Show()
                
                if homeDiff > 0 then
                    -- Increasing latency (bad) - point up
                    alertFrame.homeTrend:SetRotation(0)
                    alertFrame.homeTrend:SetVertexColor(1, 0, 0) -- Red
                else
                    -- Decreasing latency (good) - point down
                    alertFrame.homeTrend:SetRotation(math.pi)
                    alertFrame.homeTrend:SetVertexColor(0, 1, 0) -- Green
                end
            else
                alertFrame.homeTrend:Hide()
            end
        end
        
        if LG.worldLatencyHistory and #LG.worldLatencyHistory > 1 then
            local worldDiff = worldLatency - prevWorldLatency
            
            if math.abs(worldDiff) > 10 then
                alertFrame.worldTrend:Show()
                
                if worldDiff > 0 then
                    -- Increasing latency (bad) - point up
                    alertFrame.worldTrend:SetRotation(0)
                    alertFrame.worldTrend:SetVertexColor(1, 0, 0) -- Red
                else
                    -- Decreasing latency (good) - point down
                    alertFrame.worldTrend:SetRotation(math.pi)
                    alertFrame.worldTrend:SetVertexColor(0, 1, 0) -- Green
                end
            else
                alertFrame.worldTrend:Hide()
            end
        end
        
        -- Update packet loss and jitter indicators if analytics module is loaded
        if LG.analytics then
            if LG.analytics.estimatePacketLoss then
                local packetLoss = LG.analytics.estimatePacketLoss()
                alertFrame.packetLossLabel:SetText(string.format("PL: %.1f%%", packetLoss))
                
                -- Color code packet loss
                if packetLoss > (LG.defaults.packetLossThreshold or 2) then
                    alertFrame.packetLossLabel:SetTextColor(1, 0, 0) -- Red for high packet loss
                else
                    alertFrame.packetLossLabel:SetTextColor(1, 1, 1) -- White for normal
                end
            end
            
            if LG.analytics.calculateJitter and LG.homeLatencyHistory and LG.worldLatencyHistory then
                local homeJitter = LG.analytics.calculateJitter(LG.homeLatencyHistory, LG.defaults.trendSampleSize or 30)
                local worldJitter = LG.analytics.calculateJitter(LG.worldLatencyHistory, LG.defaults.trendSampleSize or 30)
                local maxJitter = math.max(homeJitter, worldJitter)
                
                alertFrame.jitterLabel:SetText(string.format("JT: %.1fms", maxJitter))
                
                -- Color code jitter
                if maxJitter > (LG.defaults.jitterThreshold or 50) then
                    alertFrame.jitterLabel:SetTextColor(1, 0, 0) -- Red for high jitter
                else
                    alertFrame.jitterLabel:SetTextColor(1, 1, 1) -- White for normal
                end
            end
        end
        
        -- Save current values for next comparison
        prevHomeLatency = homeLatency
        prevWorldLatency = worldLatency
        
        -- Update status indicators based on warning levels
        local homeWarningLevel = LG.ShouldWarn(homeLatency, homeBaseline)
        local worldWarningLevel = LG.ShouldWarn(worldLatency, worldBaseline)
        
        -- Set colors based on warning level
        if homeWarningLevel >= 3 then
            alertFrame.homeStatus:SetColorTexture(1, 0, 0, 1) -- Red for danger
        elseif homeWarningLevel >= 2 then
            alertFrame.homeStatus:SetColorTexture(1, 1, 0, 1) -- Yellow for warning
        elseif homeWarningLevel >= 1 then
            alertFrame.homeStatus:SetColorTexture(1, 0.65, 0, 1) -- Orange for caution
        else
            alertFrame.homeStatus:SetColorTexture(0, 1, 0, 1) -- Green for normal
        end
        
        if worldWarningLevel >= 3 then
            alertFrame.worldStatus:SetColorTexture(1, 0, 0, 1) -- Red for danger
        elseif worldWarningLevel >= 2 then
            alertFrame.worldStatus:SetColorTexture(1, 1, 0, 1) -- Yellow for warning
        elseif worldWarningLevel >= 1 then
            alertFrame.worldStatus:SetColorTexture(1, 0.65, 0, 1) -- Orange for caution
        else
            alertFrame.worldStatus:SetColorTexture(0, 1, 0, 1) -- Green for normal
        end
        
        -- Update text based on mode
        if LagGuardDB.enableCompactMode then
            alertFrame.homeText:SetText("H")
            alertFrame.worldText:SetText("W")
        else
            alertFrame.homeText:SetText("H: " .. homeLatency .. "ms")
            alertFrame.worldText:SetText("W: " .. worldLatency .. "ms")
        end
    end
    
    -- Load the saved position
    LoadFramePosition()
    
    -- Update the layout based on current settings
    UpdateAlertFrameLayout()
    
    -- Run a full update
    _G["UpdateIndicator"]()
    
    -- Final verification of enabled state
    LG.EnsureSavedVars()
    if LagGuardDB.enabled then
        alertFrame:Show()
    else
        alertFrame:Hide()
    end
end

-- Register for events
updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
updateFrame:RegisterEvent("PLAYER_LOGIN") -- Add login event to ensure positions are loaded

updateFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Initialize()
        -- Unregister to prevent multiple initializations
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_LOGIN" then
        -- If the frame already exists, ensure position is loaded
        if _G["LagGuardAlertFrame"] then
            alertFrame = _G["LagGuardAlertFrame"]
            LoadFramePosition()
        end
    end
end)

-- Store reference to the alertFrame for others to use
LG.alertFrame = alertFrame 
LG.SaveFramePosition = SaveFramePosition
LG.UpdateAlertFrameLayout = UpdateAlertFrameLayout

LG.ShouldWarn = LG.ShouldWarn or function(current, baseline)
    if not LagGuardDB then
        LG.EnsureSavedVars()
    end
    
    -- Use defaults if LagGuardDB is still nil
    local thresholds = LagGuardDB or LG.defaults or {
        latencyThreshold = 250,
        warningThreshold = 500,
        dangerThreshold = 1000,
        percentIncreaseThreshold = 200
    }
    
    -- Check if we exceed absolute thresholds
    if current >= thresholds.dangerThreshold then
        return 3 -- danger level
    elseif current >= thresholds.warningThreshold then
        return 2 -- warning level
    elseif current >= thresholds.latencyThreshold then
        return 1 -- caution level
    end
    
    -- Check if we exceed percentage increase threshold
    if baseline > 0 and ((current - baseline) / baseline * 100 >= thresholds.percentIncreaseThreshold) then
        return 2 -- warning level
    end
    
    return 0 -- no warning
end

-- Live Data Graph functionality
local liveDataFrame
local liveDataUpdateFrequency = 0.05  -- Update every 50ms for smooth animation
local maxDataPoints = 30  -- Reduced further from 60 to 30 for better performance
local dataCollectionInterval = 1  -- Collect a data point every second
local timeSinceLastDataPoint = 0
local homeLatencyData = {}
local worldLatencyData = {}
local dataSampleTimes = {}
local isAnimating = false
local maxVisiblePoints = 20  -- Reduced from 30 to 20 for better performance

-- Function to create the live data visualization
function LG.CreateLiveDataGraph()
    if liveDataFrame then
        LG.ToggleLiveDataGraph()
        return
    end
    
    -- Create frame
    liveDataFrame = CreateFrame("Frame", "LagGuardLiveDataFrame", UIParent)
    liveDataFrame:SetSize(700, 500)  -- Restore original size
    liveDataFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    liveDataFrame:SetFrameStrata("DIALOG")
    liveDataFrame:SetMovable(true)
    liveDataFrame:EnableMouse(true)
    liveDataFrame:RegisterForDrag("LeftButton")
    liveDataFrame:SetScript("OnDragStart", liveDataFrame.StartMoving)
    liveDataFrame:SetScript("OnDragStop", liveDataFrame.StopMovingOrSizing)
    liveDataFrame:SetClampedToScreen(true)
    liveDataFrame:Hide()
    
    -- Create background
    local bg = liveDataFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    
    -- Create border
    local border = CreateFrame("Frame", nil, liveDataFrame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", liveDataFrame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", liveDataFrame, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets = {left = 11, right = 11, top = 12, bottom = 10},
    })
    
    -- Create a STANDARD WOW SYSTEM FONT TITLE that will always be visible
    local titleString = liveDataFrame:CreateFontString(nil, "OVERLAY")
    titleString:SetFontObject(GameFontHighlightLarge)  -- Using default WoW font that's guaranteed to be visible
    titleString:SetPoint("TOP", liveDataFrame, "TOP", 0, -20)
    titleString:SetText("LagGuard Live Data")
    
    -- Create close button
    local closeButton = CreateFrame("Button", nil, liveDataFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() liveDataFrame:Hide(); isAnimating = false; end)
    
    -- Create a container frame for the graph area
    local graphContainer = CreateFrame("Frame", nil, liveDataFrame)
    graphContainer:SetPoint("TOPLEFT", 50, -60)
    graphContainer:SetPoint("BOTTOMRIGHT", -50, 100)
    
    -- Add a background to the graph area
    local graphBackground = graphContainer:CreateTexture(nil, "BACKGROUND")
    graphBackground:SetAllPoints()
    graphBackground:SetColorTexture(0.05, 0.05, 0.05, 0.5)
    
    -- Create graph area directly inside container
    local graphArea = CreateFrame("Frame", nil, graphContainer)
    graphArea:SetAllPoints()
    liveDataFrame.graphArea = graphArea
    
    -- Add border to graph area
    local graphBorder = CreateFrame("Frame", nil, graphContainer, "BackdropTemplate")
    graphBorder:SetPoint("TOPLEFT", graphContainer, "TOPLEFT", -1, 1)
    graphBorder:SetPoint("BOTTOMRIGHT", graphContainer, "BOTTOMRIGHT", 1, -1)
    graphBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    
    -- Simple fixed grid lines without any labels
    local gridLines = {}
    -- Horizontal grid lines
    for i = 1, 4 do
        local line = graphContainer:CreateLine()
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        line:SetThickness(1)
        
        -- Calculate height based on simple percentage
        local height = (i / 5) * graphContainer:GetHeight()
        line:SetStartPoint("TOPLEFT", 0, -height)
        line:SetEndPoint("TOPRIGHT", 0, -height)
        table.insert(gridLines, line)
    end
    
    -- Add vertical grid lines
    for i = 1, 4 do
        local line = graphContainer:CreateLine()
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        line:SetThickness(1)
        
        -- Calculate x position based on simple percentage
        local xPos = (i / 5) * graphContainer:GetWidth()
        line:SetStartPoint("TOPLEFT", xPos, 0)
        line:SetEndPoint("BOTTOMLEFT", xPos, 0)
        table.insert(gridLines, line)
    end
    
    -- Pre-create line objects for better performance
    liveDataFrame.homeLatencyLines = {}
    liveDataFrame.worldLatencyLines = {}
    
    for i = 1, maxVisiblePoints do
        -- Create lines as children of the graph container for proper anchoring
        local homeLine = graphContainer:CreateLine()
        homeLine:SetThickness(3)
        homeLine:SetColorTexture(0, 1, 0, 1.0)
        homeLine:Hide()
        table.insert(liveDataFrame.homeLatencyLines, homeLine)
        
        local worldLine = graphContainer:CreateLine()
        worldLine:SetThickness(3)
        worldLine:SetColorTexture(0, 0.7, 1, 1.0)
        worldLine:Hide()
        table.insert(liveDataFrame.worldLatencyLines, worldLine)
    end
    
    -- Create simple legend labels that are guaranteed to be visible
    local greenSquare = liveDataFrame:CreateTexture(nil, "ARTWORK")
    greenSquare:SetSize(15, 15)
    greenSquare:SetPoint("BOTTOMLEFT", liveDataFrame, "BOTTOMLEFT", 20, 20)
    greenSquare:SetColorTexture(0, 1, 0, 1)
    
    local greenLabel = liveDataFrame:CreateFontString(nil, "OVERLAY")
    greenLabel:SetFontObject(GameFontNormal)  -- Using default WoW font that's guaranteed to be visible
    greenLabel:SetPoint("LEFT", greenSquare, "RIGHT", 5, 0)
    greenLabel:SetText("Home")
    
    local blueSquare = liveDataFrame:CreateTexture(nil, "ARTWORK")
    blueSquare:SetSize(15, 15)
    blueSquare:SetPoint("LEFT", greenLabel, "RIGHT", 20, 0)
    blueSquare:SetColorTexture(0, 0.7, 1, 1)
    
    local blueLabel = liveDataFrame:CreateFontString(nil, "OVERLAY")
    blueLabel:SetFontObject(GameFontNormal)  -- Using default WoW font that's guaranteed to be visible
    blueLabel:SetPoint("LEFT", blueSquare, "RIGHT", 5, 0)
    blueLabel:SetText("World")
    
    -- Scale information using standard WoW UI font
    local scaleLabel = liveDataFrame:CreateFontString(nil, "OVERLAY")
    scaleLabel:SetFontObject(GameFontNormal)  -- Using default WoW font that's guaranteed to be visible
    scaleLabel:SetPoint("BOTTOM", liveDataFrame, "BOTTOM", 0, 50)
    scaleLabel:SetText("Latency Graph: 0-800ms scale (30 seconds of data)")
    
    -- Current values text field
    local currentValues = liveDataFrame:CreateFontString(nil, "OVERLAY")
    currentValues:SetFontObject(GameFontNormal)  -- Using default WoW font that's guaranteed to be visible
    currentValues:SetPoint("BOTTOM", liveDataFrame, "BOTTOM", 0, 20)
    currentValues:SetText("Current - Home: 0ms  World: 0ms")
    liveDataFrame.currentValuesText = currentValues
    
    -- Throttled animation logic - highly optimized
    local updateCounter = 0
    local function UpdateLiveGraph(self, elapsed)
        if not isAnimating then return end
        
        -- Get latency values
        local _, _, homeLatency, worldLatency = GetNetStats()
        
        -- Update time since last data point
        timeSinceLastDataPoint = timeSinceLastDataPoint + elapsed
        
        -- Throttle visual updates
        updateCounter = updateCounter + elapsed
        
        -- Collect data at regular intervals
        if timeSinceLastDataPoint >= dataCollectionInterval then
            -- Add new data point
            table.insert(homeLatencyData, 1, homeLatency)
            table.insert(worldLatencyData, 1, worldLatency)
            table.insert(dataSampleTimes, 1, GetTime())
            
            -- Trim data arrays to max points
            if #homeLatencyData > maxDataPoints then
                table.remove(homeLatencyData, #homeLatencyData)
                table.remove(worldLatencyData, #worldLatencyData)
                table.remove(dataSampleTimes, #dataSampleTimes)
            end
            
            timeSinceLastDataPoint = 0
            
            -- Force redraw after collecting data
            updateCounter = 1
        end
        
        -- Only update display at throttled rate (10fps)
        if updateCounter >= 0.1 then
            updateCounter = 0
            
            -- Format the text with color coding
            local function formatLatency(value)
                if value < 100 then
                    return "|cFF00FF00" .. value .. "ms|r" -- Green for good latency
                elseif value < 300 then
                    return "|cFFFFFF00" .. value .. "ms|r" -- Yellow for medium latency
                else
                    return "|cFFFF0000" .. value .. "ms|r" -- Red for high latency
                end
            end
            
            -- Update current values text - very simple approach
            self.currentValuesText:SetText("Current - Home: " .. homeLatency .. "ms  World: " .. worldLatency .. "ms")
            
            -- Draw graph if we have data
            if #homeLatencyData > 1 then
                -- Get container dimensions once
                local containerWidth = graphContainer:GetWidth()
                local containerHeight = graphContainer:GetHeight()
                
                -- Hide all lines first
                for i = 1, maxVisiblePoints do
                    self.homeLatencyLines[i]:Hide()
                    self.worldLatencyLines[i]:Hide()
                end
                
                -- Use fixed scale of 0-800ms for simplicity and consistency
                local maxLatency = 800
                
                -- Calculate how many data points we can draw
                local dataPoints = math.min(#homeLatencyData-1, maxVisiblePoints)
                
                -- Calculate point spacing across full width of container
                local pointSpacing = containerWidth / maxVisiblePoints
                
                -- Draw both home and world latency lines
                for i = 1, dataPoints do
                    -- Get lines from pool
                    local homeLine = self.homeLatencyLines[i]
                    local worldLine = self.worldLatencyLines[i]
                    
                    -- Simple x position calculation
                    local x1 = containerWidth - ((i - 1) * pointSpacing)
                    local x2 = containerWidth - (i * pointSpacing)
                    
                    -- Calculate Y values with simple normalization
                    -- Home latency
                    local homeY1 = (1 - math.min(homeLatencyData[i] / maxLatency, 1.0)) * containerHeight
                    local homeY2 = (1 - math.min(homeLatencyData[i+1] / maxLatency, 1.0)) * containerHeight
                    
                    -- World latency 
                    local worldY1 = (1 - math.min(worldLatencyData[i] / maxLatency, 1.0)) * containerHeight
                    local worldY2 = (1 - math.min(worldLatencyData[i+1] / maxLatency, 1.0)) * containerHeight
                    
                    -- Set lines using TOPLEFT anchor for consistency
                    homeLine:SetStartPoint("TOPLEFT", x1, -homeY1)
                    homeLine:SetEndPoint("TOPLEFT", x2, -homeY2)
                    homeLine:Show()
                    
                    worldLine:SetStartPoint("TOPLEFT", x1, -worldY1)
                    worldLine:SetEndPoint("TOPLEFT", x2, -worldY2)
                    worldLine:Show()
                end
            end
        end
    end
    
    -- Set script for updates with less frequent full updates
    liveDataFrame:SetScript("OnUpdate", UpdateLiveGraph)
    
    -- Toggle visibility and animation
    LG.ToggleLiveDataGraph()
end

-- Function to toggle live data graph
function LG.ToggleLiveDataGraph()
    if not liveDataFrame then
        LG.CreateLiveDataGraph()
        return
    end
    
    if liveDataFrame:IsShown() then
        liveDataFrame:Hide()
        isAnimating = false
    else
        -- Reset data when showing
        homeLatencyData = {}
        worldLatencyData = {}
        dataSampleTimes = {}
        timeSinceLastDataPoint = 0
        
        -- Force initial data points to ensure something displays immediately
        local _, _, homeLatency, worldLatency = GetNetStats()
        -- Add a few initial data points
        for i = 1, 3 do
            table.insert(homeLatencyData, homeLatency)
            table.insert(worldLatencyData, worldLatency)
            table.insert(dataSampleTimes, GetTime() - (i-1))
        end
        
        liveDataFrame:Show()
        isAnimating = true
    end
end 