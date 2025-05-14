-- LagGuard: Protect Hardcore Players from Lag-Related Deaths
local addonName, LG = ...
LG.version = GetAddOnMetadata(addonName, "Version")

-- Initialize the addon default state
local defaults = {
    enabled = true,
    latencyThreshold = 250, -- ms
    warningThreshold = 500, -- ms
    dangerThreshold = 1000, -- ms
    percentIncreaseThreshold = 200, -- percentage increase over baseline
    baselineRecords = 20, -- number of records to keep for baseline calculation
    soundEnabled = true,
    textEnabled = true,
    warnOnHomeLatency = true,
    warnOnWorldLatency = true,
    flashScreen = true,
    chatAlerts = true,
    historySize = 100,
}

-- Store reference to the defaults table for use by other files
LG.defaults = defaults

-- Variables
local frame = CreateFrame("Frame")
local homeLatencyHistory = {}
local worldLatencyHistory = {}
local homeLatencyBaseline = 0
local worldLatencyBaseline = 0
local lastWarningTime = 0
local warningCooldown = 3 -- seconds between warnings
local alertActive = false
local updateInterval = 0.5 -- seconds between checks

-- Function to ensure saved variables are properly initialized
local function EnsureSavedVars()
    if not LagGuardDB then LagGuardDB = {} end
    
    -- Apply defaults for any missing values
    for k, v in pairs(defaults) do
        if LagGuardDB[k] == nil then
            LagGuardDB[k] = v
        end
    end
end

-- Setup warning textures
local warningTexture = CreateFrame("Frame", "LagGuardWarningTexture", UIParent)
warningTexture:SetFrameStrata("BACKGROUND")
warningTexture:SetAllPoints(UIParent)
warningTexture.texture = warningTexture:CreateTexture(nil, "BACKGROUND")
warningTexture.texture:SetAllPoints(warningTexture)
warningTexture.texture:SetColorTexture(1, 0, 0, 0.3) -- red with 30% alpha
warningTexture:Hide()

-- Helper functions
local function CalculateBaseline(history)
    if not history or #history == 0 then return 0 end
    
    local sum = 0
    for i = 1, math.min(#history, LagGuardDB.baselineRecords) do
        sum = sum + history[i]
    end
    return sum / math.min(#history, LagGuardDB.baselineRecords)
end

local function AddToHistory(history, value)
    table.insert(history, 1, value)
    if #history > LagGuardDB.historySize then
        table.remove(history)
    end
end

local function ShouldWarn(current, baseline)
    EnsureSavedVars() -- Make sure we have valid settings
    
    -- Check if we exceed absolute thresholds
    if current >= LagGuardDB.dangerThreshold then
        return 3 -- danger level
    elseif current >= LagGuardDB.warningThreshold then
        return 2 -- warning level
    elseif current >= LagGuardDB.latencyThreshold then
        return 1 -- caution level
    end
    
    -- Check if we exceed percentage increase threshold
    if baseline > 0 and ((current - baseline) / baseline * 100 >= LagGuardDB.percentIncreaseThreshold) then
        return 2 -- warning level
    end
    
    return 0 -- no warning
end

local function DisplayWarning(level, latencyType, value, baseline)
    if GetTime() - lastWarningTime < warningCooldown then return end
    lastWarningTime = GetTime()
    
    -- Set alert state
    alertActive = true
    
    -- Prepare text for alert
    local percentIncrease = baseline > 0 and math.floor((value / baseline * 100) - 100) or 0
    local message = "|cFFFF0000LagGuard:|r " .. latencyType .. " latency " .. value .. "ms"
    
    if percentIncrease > 0 then
        message = message .. " (+" .. percentIncrease .. "% from baseline)"
    end
    
    -- Show text warning if enabled
    if LagGuardDB.textEnabled then
        if level >= 3 then
            message = "|cFFFF0000DANGER! " .. message .. "|r"
        elseif level >= 2 then
            message = "|cFFFFFF00WARNING! " .. message .. "|r"
        else
            message = "|cFFFF9900Caution: " .. message .. "|r"
        end
        
        -- Print to chat if enabled
        if LagGuardDB.chatAlerts then
            print(message)
        end
        
        -- Show on screen
        if _G["LagGuardAlertText"] then
            _G["LagGuardAlertText"]:SetText(message)
            _G["LagGuardAlertText"]:Show()
            C_Timer.After(3, function() _G["LagGuardAlertText"]:Hide() end)
        end
    end
    
    -- Play sound if enabled
    if LagGuardDB.soundEnabled then
        if level >= 3 then
            PlaySound(8959, "Master") -- RAID_WARNING
        elseif level >= 2 then
            PlaySound(37666, "Master") -- GarrMissionComplete
        else
            PlaySound(18019, "Master") -- READY_CHECK
        end
    end
    
    -- Flash screen if enabled and high level warning
    if LagGuardDB.flashScreen and level >= 2 then
        warningTexture:Show()
        C_Timer.After(0.5, function() 
            warningTexture:Hide()
            alertActive = false
        end)
    end
end

-- Initialize addon
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize saved variables
        EnsureSavedVars()
        
        -- Create OnScreen alert text frame
        local alertText = CreateFrame("Frame", "LagGuardAlertText", UIParent)
        alertText:SetFrameStrata("HIGH")
        alertText:SetWidth(600)
        alertText:SetHeight(50)
        alertText:SetPoint("TOP", UIParent, "TOP", 0, -100)
        
        local text = alertText:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetAllPoints()
        alertText.text = text
        alertText:Hide()
        
        alertText.SetText = function(self, msg)
            self.text:SetText(msg)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Set history tables in LG namespace after initialization
        LG.homeLatencyHistory = homeLatencyHistory
        LG.worldLatencyHistory = worldLatencyHistory
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Start monitoring
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed < updateInterval then return end
            self.elapsed = 0
            
            -- Ensure we have valid settings
            EnsureSavedVars()
            
            -- If disabled, update UI if needed but don't process latency
            if not LagGuardDB or not LagGuardDB.enabled then
                -- Update the indicator to reflect disabled state
                if _G["UpdateIndicator"] then
                    _G["UpdateIndicator"]() 
                end
                return
            end
            
            -- Get current latency values
            local _, _, homeLatency, worldLatency = GetNetStats()
            
            -- Update histories
            AddToHistory(homeLatencyHistory, homeLatency)
            AddToHistory(worldLatencyHistory, worldLatency)
            
            -- Calculate baselines
            homeLatencyBaseline = CalculateBaseline(homeLatencyHistory)
            worldLatencyBaseline = CalculateBaseline(worldLatencyHistory)
            
            -- Check for warnings
            if LagGuardDB.warnOnHomeLatency then
                local homeWarningLevel = ShouldWarn(homeLatency, homeLatencyBaseline)
                if homeWarningLevel > 0 then
                    DisplayWarning(homeWarningLevel, "Home", homeLatency, homeLatencyBaseline)
                end
            end
            
            if LagGuardDB.warnOnWorldLatency then
                local worldWarningLevel = ShouldWarn(worldLatency, worldLatencyBaseline)
                if worldWarningLevel > 0 and not alertActive then
                    DisplayWarning(worldWarningLevel, "World", worldLatency, worldLatencyBaseline)
                end
            end
            
            -- Update the indicator if it exists
            if _G["UpdateIndicator"] then
                _G["UpdateIndicator"]()
            end
        end)
        
        print("|cFF00FF00LagGuard v" .. LG.version .. " loaded. Type /lg or /lagguard for options.|r")
    end
end)

-- Slash command handler
SLASH_LAGGUARD1 = "/lg"
SLASH_LAGGUARD2 = "/lagguard"
SlashCmdList["LAGGUARD"] = function(msg)
    -- Basic slash command handling, we'll expand this in the Config.lua file
    if msg == "toggle" then
        EnsureSavedVars()
        LagGuardDB.enabled = not LagGuardDB.enabled
        print("LagGuard " .. (LagGuardDB.enabled and "enabled" or "disabled"))
        
        -- Update indicator after toggling
        if _G["UpdateIndicator"] then
            _G["UpdateIndicator"]()
        end
    elseif msg == "config" and LG.ToggleConfig then
        LG.ToggleConfig()
    else
        -- This will be replaced with proper configuration panel in Config.lua
        print("LagGuard commands:")
        print("/lg toggle - Toggle addon on/off")
        print("/lg config - Open configuration panel")
    end
end

-- Make API available to other files
LG.AddToHistory = AddToHistory
LG.CalculateBaseline = CalculateBaseline
LG.ShouldWarn = ShouldWarn
LG.DisplayWarning = DisplayWarning
LG.EnsureSavedVars = EnsureSavedVars
LG.homeLatencyHistory = homeLatencyHistory
LG.worldLatencyHistory = worldLatencyHistory 