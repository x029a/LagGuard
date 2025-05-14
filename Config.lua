-- LagGuard Configuration Panel
local addonName, LG = ...

-- Make sure we have SavedVariables initialized
local function EnsureSavedVars()
    if not LagGuardDB then
        LagGuardDB = {}
    end
    
    -- Apply defaults for any missing values
    for k, v in pairs(LG.defaults or {}) do
        if LagGuardDB[k] == nil then
            LagGuardDB[k] = v
        end
    end
end

-- Forward declaration of the refresh function
local RefreshControls

-- Create a standalone config panel
local configFrame = CreateFrame("Frame", "LagGuardConfigFrame", UIParent)
configFrame:SetSize(550, 500)
configFrame:SetPoint("CENTER")
configFrame:SetFrameStrata("DIALOG")
configFrame:SetMovable(true)
configFrame:EnableMouse(true)
configFrame:RegisterForDrag("LeftButton")
configFrame:SetScript("OnDragStart", configFrame.StartMoving)
configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
configFrame:SetClampedToScreen(true)
configFrame:Hide()

-- Create a background
local bg = configFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.8)

-- Create a border
local border = CreateFrame("Frame", nil, configFrame, "BackdropTemplate")
border:SetPoint("TOPLEFT", configFrame, "TOPLEFT", -1, 1)
border:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", 1, -1)
border:SetBackdrop({
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    insets = { left = 11, right = 11, top = 12, bottom = 10 },
})

-- Create a close button
local closeButton = CreateFrame("Button", "LagGuardConfigCloseButton", configFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)
closeButton:SetScript("OnClick", function() configFrame:Hide() end)

-- Create a scroll frame
local scrollFrame = CreateFrame("ScrollFrame", "LagGuardScrollFrame", configFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 15, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

local scrollChild = CreateFrame("Frame", "LagGuardScrollChild", scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetWidth(scrollFrame:GetWidth())
scrollChild:SetHeight(700) -- Fixed height

-- Title and version
local title = configFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -15)
title:SetText("LagGuard Configuration")

local version = configFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
version:SetPoint("TOPRIGHT", -30, -15)
version:SetText("v" .. LG.version)

local description = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
description:SetPoint("TOPLEFT", 5, -5)
description:SetPoint("RIGHT", -5, 0)
description:SetJustifyH("LEFT")
description:SetText("LagGuard protects hardcore players from lag-related deaths by providing warnings when latency spikes occur.")

-- Helper function to create checkboxes
local function CreateCheckbox(parent, name, label, tooltip, onClick)
    local checkbox = CreateFrame("CheckButton", "LagGuardCheckbox" .. name, parent, "UICheckButtonTemplate")
    checkbox.text = _G[checkbox:GetName() .. "Text"]
    checkbox.text:SetText(label)
    checkbox.tooltipText = tooltip
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    checkbox:SetScript("OnClick", onClick)
    return checkbox
end

-- Helper function to create sliders
local function CreateSlider(parent, name, label, tooltip, minValue, maxValue, step, onValueChanged)
    local slider = CreateFrame("Slider", "LagGuardSlider" .. name, parent, "OptionsSliderTemplate")
    slider:SetWidth(240)
    slider:SetHeight(20)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    
    slider.Text = _G[slider:GetName() .. "Text"]
    slider.Low = _G[slider:GetName() .. "Low"]
    slider.High = _G[slider:GetName() .. "High"]
    
    slider.Text:SetText(label)
    slider.tooltipText = tooltip
    slider.Low:SetText(minValue)
    slider.High:SetText(maxValue)
    
    slider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    slider:SetScript("OnValueChanged", onValueChanged)
    
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    slider.valueText = valueText
    
    return slider
end

-- Create checkbox for enabling/disabling the addon
local enabledCheckbox = CreateCheckbox(
    scrollChild, 
    "Enabled", 
    "Enable LagGuard", 
    "Toggle the addon on or off",
    function(self)
        EnsureSavedVars()
        local wasEnabled = LagGuardDB.enabled
        LagGuardDB.enabled = self:GetChecked()
        
        -- If we're enabling the addon and it was previously disabled,
        -- make sure the UI is updated and shown
        if LagGuardDB.enabled and not wasEnabled then
            -- Force UI recreation/update if needed
            C_Timer.After(0.1, function()
                if _G["UpdateIndicator"] then
                    _G["UpdateIndicator"]()
                end
            end)
        else
            -- Standard update
            if _G["UpdateIndicator"] then
                _G["UpdateIndicator"]()
            end
        end
        
        -- Update interface options checkbox as well
        if ioEnabledCheckbox then
            ioEnabledCheckbox:SetChecked(LagGuardDB.enabled)
        end
        
        -- Print status message
        print("LagGuard " .. (LagGuardDB.enabled and "enabled" or "disabled"))
    end
)
enabledCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)

-- Alert Types
local alertTypeLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
alertTypeLabel:SetPoint("TOPLEFT", enabledCheckbox, "BOTTOMLEFT", 0, -20)
alertTypeLabel:SetText("Alert Types:")

-- Checkbox for sound alerts
local soundCheckbox = CreateCheckbox(
    scrollChild,
    "Sound",
    "Enable Sound Alerts",
    "Play a sound when latency exceeds thresholds",
    function(self)
        EnsureSavedVars()
        LagGuardDB.soundEnabled = self:GetChecked()
    end
)
soundCheckbox:SetPoint("TOPLEFT", alertTypeLabel, "BOTTOMLEFT", 20, -5)

-- Checkbox for text alerts
local textCheckbox = CreateCheckbox(
    scrollChild,
    "Text",
    "Enable Text Alerts",
    "Show text warnings when latency exceeds thresholds",
    function(self)
        EnsureSavedVars()
        LagGuardDB.textEnabled = self:GetChecked()
    end
)
textCheckbox:SetPoint("TOPLEFT", soundCheckbox, "BOTTOMLEFT", 0, -5)

-- Checkbox for screen flash
local flashCheckbox = CreateCheckbox(
    scrollChild,
    "Flash",
    "Flash Screen on Warnings",
    "Flash the screen with red when severe latency is detected",
    function(self)
        EnsureSavedVars()
        LagGuardDB.flashScreen = self:GetChecked()
    end
)
flashCheckbox:SetPoint("TOPLEFT", textCheckbox, "BOTTOMLEFT", 0, -5)

-- Checkbox for chat alerts
local chatCheckbox = CreateCheckbox(
    scrollChild,
    "Chat",
    "Show Alerts in Chat",
    "Print alert messages to the chat window",
    function(self)
        EnsureSavedVars()
        LagGuardDB.chatAlerts = self:GetChecked()
    end
)
chatCheckbox:SetPoint("TOPLEFT", flashCheckbox, "BOTTOMLEFT", 0, -5)

-- Monitoring settings
local monitorLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
monitorLabel:SetPoint("TOPLEFT", chatCheckbox, "BOTTOMLEFT", -20, -20)
monitorLabel:SetText("Latency Monitoring:")

-- Home latency checkbox
local homeCheckbox = CreateCheckbox(
    scrollChild,
    "Home",
    "Monitor Home Latency",
    "Monitor connection latency to the home server",
    function(self)
        EnsureSavedVars()
        LagGuardDB.warnOnHomeLatency = self:GetChecked()
    end
)
homeCheckbox:SetPoint("TOPLEFT", monitorLabel, "BOTTOMLEFT", 20, -5)

-- World latency checkbox
local worldCheckbox = CreateCheckbox(
    scrollChild,
    "World",
    "Monitor World Latency",
    "Monitor latency to the game world server",
    function(self)
        EnsureSavedVars()
        LagGuardDB.warnOnWorldLatency = self:GetChecked()
    end
)
worldCheckbox:SetPoint("TOPLEFT", homeCheckbox, "BOTTOMLEFT", 0, -5)

-- Thresholds section
local thresholdLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
thresholdLabel:SetPoint("TOPLEFT", worldCheckbox, "BOTTOMLEFT", -20, -20)
thresholdLabel:SetText("Latency Thresholds (ms):")

-- Latency threshold slider (minor warning level)
local latencyThresholdSlider = CreateSlider(
    scrollChild,
    "LatencyThreshold",
    "Caution Threshold",
    "Latency level for minor warnings",
    50, 500, 10,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.latencyThreshold = value
        self.valueText:SetText(value .. " ms")
    end
)
latencyThresholdSlider:SetPoint("TOPLEFT", thresholdLabel, "BOTTOMLEFT", 20, -30)

-- Warning threshold slider
local warningThresholdSlider = CreateSlider(
    scrollChild,
    "WarningThreshold",
    "Warning Threshold",
    "Latency level for moderate warnings",
    100, 1000, 25,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.warningThreshold = value
        self.valueText:SetText(value .. " ms")
    end
)
warningThresholdSlider:SetPoint("TOPLEFT", latencyThresholdSlider, "BOTTOMLEFT", 0, -30)

-- Danger threshold slider
local dangerThresholdSlider = CreateSlider(
    scrollChild,
    "DangerThreshold",
    "Danger Threshold",
    "Latency level for severe warnings",
    200, 2000, 50,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.dangerThreshold = value
        self.valueText:SetText(value .. " ms")
    end
)
dangerThresholdSlider:SetPoint("TOPLEFT", warningThresholdSlider, "BOTTOMLEFT", 0, -30)

-- Percentage increase threshold slider
local percentIncreaseSlider = CreateSlider(
    scrollChild,
    "PercentIncrease",
    "Baseline % Increase",
    "Warning when latency increases this much from baseline",
    110, 500, 10,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.percentIncreaseThreshold = value
        self.valueText:SetText(value .. "%")
    end
)
percentIncreaseSlider:SetPoint("TOPLEFT", dangerThresholdSlider, "BOTTOMLEFT", 0, -30)

-- Baseline records slider
local baselineRecordsSlider = CreateSlider(
    scrollChild,
    "BaselineRecords",
    "Baseline Sample Size",
    "Number of readings to use for baseline calculation",
    5, 50, 1,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.baselineRecords = value
        self.valueText:SetText(value .. " samples")
    end
)
baselineRecordsSlider:SetPoint("TOPLEFT", percentIncreaseSlider, "BOTTOMLEFT", 0, -30)

-- Current latency display
local latencyLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
latencyLabel:SetPoint("TOPLEFT", baselineRecordsSlider, "BOTTOMLEFT", -20, -30)
latencyLabel:SetText("Current Latency:")

local homeLatencyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
homeLatencyText:SetPoint("TOPLEFT", latencyLabel, "BOTTOMLEFT", 20, -5)
homeLatencyText:SetText("Home: -- ms (Baseline: -- ms)")

local worldLatencyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
worldLatencyText:SetPoint("TOPLEFT", homeLatencyText, "BOTTOMLEFT", 0, -5)
worldLatencyText:SetText("World: -- ms (Baseline: -- ms)")

-- Analytics section
local analyticsLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
analyticsLabel:SetPoint("TOPLEFT", worldLatencyText, "BOTTOMLEFT", -20, -20)
analyticsLabel:SetText("Analytics Features:")

-- Advanced trend analysis checkbox
local trendAnalysisCheckbox = CreateCheckbox(
    scrollChild,
    "TrendAnalysis",
    "Enable Trend Analysis",
    "Analyze latency trends to predict potential issues",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enableTrendAnalysis = self:GetChecked()
    end
)
trendAnalysisCheckbox:SetPoint("TOPLEFT", analyticsLabel, "BOTTOMLEFT", 20, -5)

-- Trend sample size slider
local trendSampleSizeSlider = CreateSlider(
    scrollChild,
    "TrendSampleSize",
    "Trend Sample Size",
    "Number of samples to use for trend analysis",
    10, 60, 5,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.trendSampleSize = value
        self.valueText:SetText(value .. " samples")
    end
)
trendSampleSizeSlider:SetPoint("TOPLEFT", trendAnalysisCheckbox, "BOTTOMLEFT", 0, -30)

-- Predictive warnings checkbox
local predictiveWarningsCheckbox = CreateCheckbox(
    scrollChild,
    "PredictiveWarnings",
    "Enable Predictive Warnings",
    "Show warnings based on predicted future latency",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enablePredictiveWarnings = self:GetChecked()
    end
)
predictiveWarningsCheckbox:SetPoint("TOPLEFT", trendSampleSizeSlider, "BOTTOMLEFT", 0, -5)

-- Prediction threshold slider
local predictionThresholdSlider = CreateSlider(
    scrollChild,
    "PredictionThreshold",
    "Prediction Threshold",
    "Minimum predicted increase to trigger a warning",
    50, 500, 25,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.predictionThreshold = value
        self.valueText:SetText(value .. " ms")
    end
)
predictionThresholdSlider:SetPoint("TOPLEFT", predictiveWarningsCheckbox, "BOTTOMLEFT", 0, -30)

-- Connection quality section
local connectionLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
connectionLabel:SetPoint("TOPLEFT", predictionThresholdSlider, "BOTTOMLEFT", -20, -20)
connectionLabel:SetText("Connection Quality Assessment:")

-- Packet loss detection checkbox
local packetLossCheckbox = CreateCheckbox(
    scrollChild,
    "PacketLoss",
    "Enable Packet Loss Detection",
    "Detect and warn about packet loss",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enablePacketLossDetection = self:GetChecked()
    end
)
packetLossCheckbox:SetPoint("TOPLEFT", connectionLabel, "BOTTOMLEFT", 20, -5)

-- Packet loss threshold slider
local packetLossSlider = CreateSlider(
    scrollChild,
    "PacketLossThreshold",
    "Packet Loss Threshold",
    "Percentage of packet loss to trigger warnings",
    1, 10, 0.5,
    function(self, value)
        EnsureSavedVars()
        LagGuardDB.packetLossThreshold = value
        self.valueText:SetText(string.format("%.1f%%", value))
    end
)
packetLossSlider:SetPoint("TOPLEFT", packetLossCheckbox, "BOTTOMLEFT", 0, -30)

-- Jitter threshold slider
local jitterThresholdSlider = CreateSlider(
    scrollChild,
    "JitterThreshold",
    "Jitter Threshold",
    "Latency variation threshold for warnings",
    25, 200, 5,
    function(self, value)
        EnsureSavedVars()
        value = math.floor(value)
        LagGuardDB.jitterThreshold = value
        self.valueText:SetText(value .. " ms")
    end
)
jitterThresholdSlider:SetPoint("TOPLEFT", packetLossSlider, "BOTTOMLEFT", 0, -30)

-- Data collection section
local dataCollectionLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
dataCollectionLabel:SetPoint("TOPLEFT", jitterThresholdSlider, "BOTTOMLEFT", -20, -20)
dataCollectionLabel:SetText("Anonymous Data Collection:")

-- Data collection checkbox
local dataCollectionCheckbox = CreateCheckbox(
    scrollChild,
    "DataCollection",
    "Enable Data Collection",
    "Collect latency data for analysis (no personal information collected)",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enableDataCollection = self:GetChecked()
    end
)
dataCollectionCheckbox:SetPoint("TOPLEFT", dataCollectionLabel, "BOTTOMLEFT", 20, -5)

-- Data sharing checkbox
local dataShareCheckbox = CreateCheckbox(
    scrollChild,
    "DataShare",
    "Share Anonymous Data",
    "Share collected data to help improve the addon (no personal information shared)",
    function(self)
        EnsureSavedVars()
        LagGuardDB.shareAnonymousData = self:GetChecked()
    end
)
dataShareCheckbox:SetPoint("TOPLEFT", dataCollectionCheckbox, "BOTTOMLEFT", 0, -5)

-- UI Options section
local uiOptionsLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
uiOptionsLabel:SetPoint("TOPLEFT", dataShareCheckbox, "BOTTOMLEFT", -20, -20)
uiOptionsLabel:SetText("UI Options:")

-- Compact mode checkbox
local compactModeCheckbox = CreateCheckbox(
    scrollChild,
    "CompactMode",
    "Enable Compact Mode",
    "Show a simplified display with just status indicators and minimal text",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enableCompactMode = self:GetChecked()
        -- Update the alert frame if it exists and the layout function is available
        if LG.alertFrame and LG.UpdateAlertFrameLayout then
            LG.UpdateAlertFrameLayout()
        else
            -- Queue the update for when the alert frame is created
            C_Timer.After(0.5, function() 
                if LG.UpdateAlertFrameLayout then
                    LG.UpdateAlertFrameLayout()
                end
            end)
        end
    end
)
compactModeCheckbox:SetPoint("TOPLEFT", uiOptionsLabel, "BOTTOMLEFT", 20, -5)

-- Minimap button checkbox
local minimapButtonCheckbox = CreateCheckbox(
    scrollChild,
    "MinimapButton",
    "Show Minimap Button",
    "Display a button on the minimap for quick access to LagGuard features",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enableMinimapButton = self:GetChecked()
        
        -- Sync with interface options
        if ioMinimapCheckbox then
            ioMinimapCheckbox:SetChecked(LagGuardDB.enableMinimapButton)
        end
        
        print("LagGuard minimap button " .. (LagGuardDB.enableMinimapButton and "enabled" or "disabled") .. 
            ". Reload UI to apply change.")
    end
)
minimapButtonCheckbox:SetPoint("TOPLEFT", compactModeCheckbox, "BOTTOMLEFT", 0, -5)

-- View graph button
local graphButton = CreateFrame("Button", "LagGuardGraphButton", scrollChild, "UIPanelButtonTemplate")
graphButton:SetSize(150, 24)
graphButton:SetPoint("TOPLEFT", minimapButtonCheckbox, "BOTTOMLEFT", 0, -20)
graphButton:SetText("View Latency Graph")
graphButton:SetScript("OnClick", function()
    if LG.ToggleLatencyGraph then
        LG.ToggleLatencyGraph()
    else
        print("LagGuard: Analytics module not loaded.")
    end
end)

-- Test area
local testAreaLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
testAreaLabel:SetPoint("TOPLEFT", graphButton, "BOTTOMLEFT", -20, -20)
testAreaLabel:SetText("Test Alerts:")

-- Create test buttons for different alert levels
local testCautionButton = CreateFrame("Button", "LagGuardTestCautionButton", scrollChild, "UIPanelButtonTemplate")
testCautionButton:SetSize(100, 24)
testCautionButton:SetPoint("TOPLEFT", testAreaLabel, "BOTTOMLEFT", 20, -5)
testCautionButton:SetText("Test Caution")
testCautionButton:SetScript("OnClick", function()
    local _, _, homeLatency, worldLatency = GetNetStats()
    LG.DisplayWarning(1, "Test", homeLatency, 0)
end)

local testWarningButton = CreateFrame("Button", "LagGuardTestWarningButton", scrollChild, "UIPanelButtonTemplate")
testWarningButton:SetSize(100, 24)
testWarningButton:SetPoint("LEFT", testCautionButton, "RIGHT", 10, 0)
testWarningButton:SetText("Test Warning")
testWarningButton:SetScript("OnClick", function()
    local _, _, homeLatency, worldLatency = GetNetStats()
    LG.DisplayWarning(2, "Test", homeLatency, 0)
end)

local testDangerButton = CreateFrame("Button", "LagGuardTestDangerButton", scrollChild, "UIPanelButtonTemplate")
testDangerButton:SetSize(100, 24)
testDangerButton:SetPoint("LEFT", testWarningButton, "RIGHT", 10, 0)
testDangerButton:SetText("Test Danger")
testDangerButton:SetScript("OnClick", function()
    local _, _, homeLatency, worldLatency = GetNetStats()
    LG.DisplayWarning(3, "Test", homeLatency, 0)
end)

-- Update the display of current latency values
local latencyUpdateFrame = CreateFrame("Frame")
latencyUpdateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not configFrame:IsShown() then return end
    
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 1 then return end
    self.elapsed = 0
    
    local _, _, homeLatency, worldLatency = GetNetStats()
    homeLatencyText:SetText(string.format("Home: %d ms (Baseline: %.1f ms)", 
        homeLatency, LG.CalculateBaseline(LG.homeLatencyHistory or {})))
    worldLatencyText:SetText(string.format("World: %d ms (Baseline: %.1f ms)", 
        worldLatency, LG.CalculateBaseline(LG.worldLatencyHistory or {})))
end)

-- Create reset button
local resetButton = CreateFrame("Button", "LagGuardResetButton", scrollChild, "UIPanelButtonTemplate")
resetButton:SetSize(150, 24)
resetButton:SetPoint("TOPLEFT", testCautionButton, "BOTTOMLEFT", 0, -30)
resetButton:SetText("Reset to Defaults")
resetButton:SetScript("OnClick", function()
    StaticPopupDialogs["LAGGUARD_RESET_CONFIRM"] = {
        text = "Are you sure you want to reset all LagGuard settings to defaults?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            EnsureSavedVars()
            for k, v in pairs(LG.defaults or {}) do
                LagGuardDB[k] = v
            end
            RefreshControls()
            print("LagGuard settings have been reset to defaults.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("LAGGUARD_RESET_CONFIRM")
end)

-- Refresh function to update all controls to reflect saved settings
RefreshControls = function()
    EnsureSavedVars()
    
    enabledCheckbox:SetChecked(LagGuardDB.enabled)
    soundCheckbox:SetChecked(LagGuardDB.soundEnabled)
    textCheckbox:SetChecked(LagGuardDB.textEnabled)
    flashCheckbox:SetChecked(LagGuardDB.flashScreen)
    chatCheckbox:SetChecked(LagGuardDB.chatAlerts)
    homeCheckbox:SetChecked(LagGuardDB.warnOnHomeLatency)
    worldCheckbox:SetChecked(LagGuardDB.warnOnWorldLatency)
    
    latencyThresholdSlider:SetValue(LagGuardDB.latencyThreshold)
    latencyThresholdSlider.valueText:SetText(LagGuardDB.latencyThreshold .. " ms")
    
    warningThresholdSlider:SetValue(LagGuardDB.warningThreshold)
    warningThresholdSlider.valueText:SetText(LagGuardDB.warningThreshold .. " ms")
    
    dangerThresholdSlider:SetValue(LagGuardDB.dangerThreshold)
    dangerThresholdSlider.valueText:SetText(LagGuardDB.dangerThreshold .. " ms")
    
    percentIncreaseSlider:SetValue(LagGuardDB.percentIncreaseThreshold)
    percentIncreaseSlider.valueText:SetText(LagGuardDB.percentIncreaseThreshold .. "%")
    
    baselineRecordsSlider:SetValue(LagGuardDB.baselineRecords)
    baselineRecordsSlider.valueText:SetText(LagGuardDB.baselineRecords .. " samples")
    
    -- Analytics controls
    if trendAnalysisCheckbox then
        trendAnalysisCheckbox:SetChecked(LagGuardDB.enableTrendAnalysis)
    end
    
    if trendSampleSizeSlider then
        trendSampleSizeSlider:SetValue(LagGuardDB.trendSampleSize)
        trendSampleSizeSlider.valueText:SetText(LagGuardDB.trendSampleSize .. " samples")
    end
    
    if predictiveWarningsCheckbox then
        predictiveWarningsCheckbox:SetChecked(LagGuardDB.enablePredictiveWarnings)
    end
    
    if predictionThresholdSlider then
        predictionThresholdSlider:SetValue(LagGuardDB.predictionThreshold)
        predictionThresholdSlider.valueText:SetText(LagGuardDB.predictionThreshold .. " ms")
    end
    
    if packetLossCheckbox then
        packetLossCheckbox:SetChecked(LagGuardDB.enablePacketLossDetection)
    end
    
    if packetLossSlider then
        packetLossSlider:SetValue(LagGuardDB.packetLossThreshold)
        packetLossSlider.valueText:SetText(string.format("%.1f%%", LagGuardDB.packetLossThreshold))
    end
    
    if jitterThresholdSlider then
        jitterThresholdSlider:SetValue(LagGuardDB.jitterThreshold)
        jitterThresholdSlider.valueText:SetText(LagGuardDB.jitterThreshold .. " ms")
    end
    
    if dataCollectionCheckbox then
        dataCollectionCheckbox:SetChecked(LagGuardDB.enableDataCollection)
    end
    
    if dataShareCheckbox then
        dataShareCheckbox:SetChecked(LagGuardDB.shareAnonymousData)
    end
    
    if compactModeCheckbox then
        compactModeCheckbox:SetChecked(LagGuardDB.enableCompactMode)
    end
    
    if minimapButtonCheckbox then
        minimapButtonCheckbox:SetChecked(LagGuardDB.enableMinimapButton)
    end
end

-- Function to toggle config visibility
local function ToggleConfig()
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
        RefreshControls() -- Refresh settings when showing
    end
end

-- Register slash command to open config
local originalSlashCmd = SlashCmdList["LAGGUARD"]
SlashCmdList["LAGGUARD"] = function(msg)
    if msg == "config" then
        ToggleConfig()
    else
        originalSlashCmd(msg)
    end
end

-- Configure the panel to close on Escape
tinsert(UISpecialFrames, "LagGuardConfigFrame")

-- Interface Options Integration
-- Create a panel for the Interface Options
local interfacePanel = CreateFrame("Frame", "LagGuardInterfacePanel")
interfacePanel.name = "LagGuard"

local interfaceTitle = interfacePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
interfaceTitle:SetPoint("TOPLEFT", 16, -16)
interfaceTitle:SetText("LagGuard")

local interfaceVersion = interfacePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
interfaceVersion:SetPoint("TOPLEFT", interfaceTitle, "BOTTOMLEFT", 0, -8)
interfaceVersion:SetText("Version " .. LG.version)

local interfaceDesc = interfacePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
interfaceDesc:SetPoint("TOPLEFT", interfaceVersion, "BOTTOMLEFT", 0, -20)
interfaceDesc:SetWidth(500)
interfaceDesc:SetJustifyH("LEFT")
interfaceDesc:SetText("LagGuard protects hardcore players from lag-related deaths by providing warnings when latency spikes occur. Click the button below to open the full configuration panel.")

-- Button to open the standalone config
local openConfigButton = CreateFrame("Button", "LagGuardOpenConfigButton", interfacePanel, "UIPanelButtonTemplate")
openConfigButton:SetSize(200, 30)
openConfigButton:SetPoint("TOPLEFT", interfaceDesc, "BOTTOMLEFT", 0, -20)
openConfigButton:SetText("Open Configuration Panel")
openConfigButton:SetScript("OnClick", function()
    -- Hide the Interface Options panel
    if InterfaceOptionsFrame_Hide then
        InterfaceOptionsFrame_Hide()
    elseif InterfaceOptionsFrame then
        InterfaceOptionsFrame:Hide()
    end
    
    -- Show our config
    ToggleConfig()
end)

-- Toggle main features directly from Interface Options
local ioEnabledCheckbox = CreateCheckbox(
    interfacePanel,
    "IOEnabled",
    "Enable LagGuard",
    "Toggle the addon on or off",
    function(self)
        EnsureSavedVars()
        local wasEnabled = LagGuardDB.enabled
        LagGuardDB.enabled = self:GetChecked()
        
        -- If we're enabling the addon and it was previously disabled,
        -- make sure the UI is updated and shown
        if LagGuardDB.enabled and not wasEnabled then
            -- Force UI recreation/update if needed
            C_Timer.After(0.1, function()
                if _G["UpdateIndicator"] then
                    _G["UpdateIndicator"]()
                end
            end)
        else
            -- Standard update
            if _G["UpdateIndicator"] then
                _G["UpdateIndicator"]()
            end
        end
        
        -- Update main config panel checkbox if visible
        if enabledCheckbox then
            enabledCheckbox:SetChecked(LagGuardDB.enabled)
        end
        
        -- Print status message
        print("LagGuard " .. (LagGuardDB.enabled and "enabled" or "disabled"))
    end
)
ioEnabledCheckbox:SetPoint("TOPLEFT", openConfigButton, "BOTTOMLEFT", 0, -20)

-- Main alert types in the Interface Options
local ioSoundCheckbox = CreateCheckbox(
    interfacePanel,
    "IOSound",
    "Enable Sound Alerts",
    "Play a sound when latency exceeds thresholds",
    function(self)
        EnsureSavedVars()
        LagGuardDB.soundEnabled = self:GetChecked()
    end
)
ioSoundCheckbox:SetPoint("TOPLEFT", ioEnabledCheckbox, "BOTTOMLEFT", 20, -5)

local ioTextCheckbox = CreateCheckbox(
    interfacePanel,
    "IOText",
    "Enable Text Alerts",
    "Show text warnings when latency exceeds thresholds",
    function(self)
        EnsureSavedVars()
        LagGuardDB.textEnabled = self:GetChecked()
    end
)
ioTextCheckbox:SetPoint("TOPLEFT", ioSoundCheckbox, "BOTTOMLEFT", 0, -5)

local ioFlashCheckbox = CreateCheckbox(
    interfacePanel,
    "IOFlash",
    "Flash Screen on Warnings",
    "Flash the screen with red when severe latency is detected",
    function(self)
        EnsureSavedVars()
        LagGuardDB.flashScreen = self:GetChecked()
    end
)
ioFlashCheckbox:SetPoint("TOPLEFT", ioTextCheckbox, "BOTTOMLEFT", 0, -5)

-- Add minimap button checkbox to interface options
local ioMinimapCheckbox = CreateCheckbox(
    interfacePanel,
    "IOMinimapButton",
    "Show Minimap Button",
    "Display a LagGuard button on the minimap for quick access",
    function(self)
        EnsureSavedVars()
        LagGuardDB.enableMinimapButton = self:GetChecked()
        
        -- Sync with main config panel
        if minimapButtonCheckbox then
            minimapButtonCheckbox:SetChecked(LagGuardDB.enableMinimapButton)
        end
        
        print("LagGuard minimap button " .. (LagGuardDB.enableMinimapButton and "enabled" or "disabled") .. 
            ". Reload UI to apply change.")
    end
)
ioMinimapCheckbox:SetPoint("TOPLEFT", ioFlashCheckbox, "BOTTOMLEFT", 0, -5)

-- Function to refresh the Interface Options panel
local function RefreshInterfaceOptions()
    if not interfacePanel:IsVisible() then return end
    
    ioEnabledCheckbox:SetChecked(LagGuardDB.enabled)
    ioSoundCheckbox:SetChecked(LagGuardDB.soundEnabled)
    ioTextCheckbox:SetChecked(LagGuardDB.textEnabled)
    ioFlashCheckbox:SetChecked(LagGuardDB.flashScreen)
    ioMinimapCheckbox:SetChecked(LagGuardDB.enableMinimapButton)
end

-- Update Interface Options whenever it's shown
interfacePanel:SetScript("OnShow", RefreshInterfaceOptions)

-- Try to register with Interface Options system
local function RegisterInterfaceOptions()
    -- Try to register with both classic and retail Interface Options systems
    if Settings and Settings.RegisterCanvasLayoutCategory then
        -- Retail (Dragonflight+)
        local category = Settings.RegisterCanvasLayoutCategory(interfacePanel, "LagGuard")
        Settings.RegisterAddOnCategory(category)
    else
        -- Classic
        if InterfaceOptions_AddCategory then
            InterfaceOptions_AddOnCategory(interfacePanel)
        end
    end
end

-- Register for init event
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Initialize saved variables
        EnsureSavedVars()
        
        -- Update the version displays
        version:SetText("v" .. LG.version)
        interfaceVersion:SetText("Version " .. LG.version)
        
        -- Register with Interface Options if available
        RegisterInterfaceOptions()
        
        -- Print help message
        print("|cFF00FF00LagGuard|r: Type /lg config to open settings or right-click the indicator")
    end
end)

-- Export functions for other files to use
LG.RefreshConfig = RefreshControls
LG.ToggleConfig = ToggleConfig
LG.EnsureSavedVars = EnsureSavedVars 

-- Initialize new default settings
local enhancementsDefaults = {
    -- UI Options
    enableCompactMode = false, -- Default to full UI mode
}

-- Register these defaults with the main addon
for k, v in pairs(enhancementsDefaults) do
    LG.defaults[k] = v
end 