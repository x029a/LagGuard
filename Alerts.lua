-- LagGuard Alerts Module
-- Provides visual status indicators for the current latency state

local addonName, LG = ...

-- Alerts Module - Provides visual indicators for latency status
local alertFrame

-- Create a local reference to the history tables for easier access
local homeLatencyHistory = LG.homeLatencyHistory
local worldLatencyHistory = LG.worldLatencyHistory

-- Initialize variables for tracking trends
local prevHomeLatency = 0 
local prevWorldLatency = 0

-- Create a frame for handling updates
local updateFrame = CreateFrame("Frame") 
local updateInterval = 0.5

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
    graphButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", -30, 5)
    
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
    
    -- Create log button
    local logButton = CreateFrame("Button", nil, alertFrame)
    logButton:SetSize(16, 16)
    logButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", 0, 5)
    
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
    scoreButton:SetPoint("BOTTOM", alertFrame, "BOTTOM", 30, 5)
    
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