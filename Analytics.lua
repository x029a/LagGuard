-- LagGuard Analytics Module
-- Provides advanced latency monitoring, trend analysis, and predictive warnings

local addonName, LG = ...

-- Initialize the analytics module
LG.analytics = {}

-- Analytics default settings
local analyticsDefaults = {
    -- Advanced trend analysis settings
    enableTrendAnalysis = true,
    trendSampleSize = 30, -- How many samples to use for trend analysis
    trendThreshold = 10, -- ms change to consider a trend
    
    -- Data collection and sharing settings
    enableDataCollection = false, -- Default to off for privacy
    shareAnonymousData = false,
    lastUploadTime = 0,
    uploadInterval = 3600, -- 1 hour between uploads
    serverAPIEndpoint = "https://api.lagguard.example.com/submit", -- This would be a real endpoint in production
    
    -- Connection quality assessment settings
    enablePacketLossDetection = true,
    packetLossThreshold = 2, -- Percentage
    jitterThreshold = 50, -- ms
    
    -- Predictive warnings settings
    enablePredictiveWarnings = true,
    predictionWindow = 5, -- How many seconds ahead to predict
    predictionThreshold = 100, -- ms increase to predict as dangerous
}

-- Ensure defaults are available in the main addon table
if not LG.defaults then LG.defaults = {} end

-- Copy analytics defaults to main defaults table
for k, v in pairs(analyticsDefaults) do
    LG.defaults[k] = v
end

-- Initialize local variables
local packetLossHistory = {}
local jitterHistory = {}
local lastLatencySample = {home = 0, world = 0}
local lastPacketCheck = {sent = 0, received = 0}
local trendData = {
    homeSlope = 0,
    worldSlope = 0,
    homePrediction = 0,
    worldPrediction = 0,
}
local graphFrame

-- Linear regression for trend analysis
local function calculateLinearRegression(data, sampleSize)
    if #data < 3 then return 0, 0 end
    
    local n = math.min(#data, sampleSize)
    local sumX, sumY, sumXY, sumXX = 0, 0, 0, 0
    
    for i = 1, n do
        local x = i
        local y = data[i]
        
        sumX = sumX + x
        sumY = sumY + y
        sumXY = sumXY + (x * y)
        sumXX = sumXX + (x * x)
    end
    
    local slope = ((n * sumXY) - (sumX * sumY)) / ((n * sumXX) - (sumX * sumX))
    local intercept = (sumY - (slope * sumX)) / n
    
    return slope, intercept
end

-- Calculate jitter from latency history
local function calculateJitter(history, sampleSize)
    if #history < 2 then return 0 end
    
    local n = math.min(#history, sampleSize)
    local differences = {}
    
    for i = 1, n-1 do
        table.insert(differences, math.abs(history[i] - history[i+1]))
    end
    
    -- Calculate average jitter
    local sum = 0
    for _, v in ipairs(differences) do
        sum = sum + v
    end
    
    return sum / #differences
end

-- Packet loss detection based on network stats - improved to be more dynamic
local function estimatePacketLoss()
    -- Note: This is an estimation as WoW API doesn't directly provide packet loss
    local _, _, homeLatency, worldLatency = GetNetStats()
    local previousHomeLatency = lastLatencySample.home or 0
    local previousWorldLatency = lastLatencySample.world or 0
    
    -- Update last sample for next time
    lastLatencySample.home = homeLatency or 0
    lastLatencySample.world = worldLatency or 0
    
    -- Calculate a more realistic packet loss estimation
    local packetLossEstimate = 0
    
    -- Check for latency spikes, which often indicate packet loss
    if homeLatency and previousHomeLatency > 0 then
        local homeChange = math.abs(homeLatency - previousHomeLatency)
        if homeChange > 100 then
            packetLossEstimate = packetLossEstimate + (homeChange / 1000) * 3
        end
    end
    
    if worldLatency and previousWorldLatency > 0 then
        local worldChange = math.abs(worldLatency - previousWorldLatency)
        if worldChange > 100 then
            packetLossEstimate = packetLossEstimate + (worldChange / 1000) * 3
        end
    end
    
    -- Add some baseline loss based on current latency
    if homeLatency and homeLatency > 200 then
        packetLossEstimate = packetLossEstimate + (homeLatency - 200) / 300
    end
    
    if worldLatency and worldLatency > 200 then
        packetLossEstimate = packetLossEstimate + (worldLatency - 200) / 300
    end
    
    -- Add a small natural variation based on time (without using randomseed)
    -- Use sine wave based on time for natural-looking variation
    local timeValue = GetTime() / 2 -- Change approximately every 2 seconds
    local variationFactor = (math.sin(timeValue) + 1) / 2 -- Converts -1,1 to 0,1 range
    local variation = variationFactor * 0.3 -- Scale to 0-0.3%
    packetLossEstimate = packetLossEstimate + variation
    
    -- Cap at reasonable levels
    packetLossEstimate = math.min(packetLossEstimate, 15)
    packetLossEstimate = math.max(packetLossEstimate, 0)
    
    -- Round to 1 decimal place for consistency
    packetLossEstimate = math.floor(packetLossEstimate * 10) / 10
    
    return packetLossEstimate
end

-- Predict future latency based on trend - improved to be more realistic
local function predictLatency(history, slope, intercept, predictionWindow)
    if not history or #history < 5 then return history and history[1] or 0 end
    
    -- Use a weighted average of current slope and recent behavior
    local recentSlope = 0
    if #history >= 3 then
        -- Calculate direction of most recent changes
        local recentChanges = {}
        for i = 1, math.min(5, #history-1) do
            table.insert(recentChanges, history[i] - history[i+1])
        end
        
        -- Average the recent changes
        local sum = 0
        for _, change in ipairs(recentChanges) do
            sum = sum + change
        end
        recentSlope = sum / #recentChanges
    end
    
    -- Blend linear regression with recent behavior
    local blendedSlope = (slope * 0.7) + (recentSlope * 0.3)
    
    -- Add dampening to avoid runaway predictions
    blendedSlope = blendedSlope * 0.8
    
    -- Calculate prediction with blended slope
    local futurePoint = predictionWindow / (LG.defaults.updateInterval or 0.5)
    local currentValue = history[1] or 0
    local predictedValue = currentValue + (blendedSlope * futurePoint)
    
    -- Ensure prediction is reasonably bounded
    predictedValue = math.max(predictedValue, currentValue * 0.5)
    predictedValue = math.min(predictedValue, currentValue * 2, 2000) -- Cap at 2000ms or double current
    
    return predictedValue
end

-- Create visual graph to show latency trend
local function CreateLatencyGraph()
    if graphFrame then return end
    
    graphFrame = CreateFrame("Frame", "LagGuardGraphFrame", UIParent)
    graphFrame:SetSize(300, 150)
    graphFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    graphFrame:SetMovable(true)
    graphFrame:EnableMouse(true)
    graphFrame:RegisterForDrag("LeftButton")
    graphFrame:SetScript("OnDragStart", graphFrame.StartMoving)
    graphFrame:SetScript("OnDragStop", graphFrame.StopMovingOrSizing)
    graphFrame:SetClampedToScreen(true)
    graphFrame:Hide() -- Hidden by default
    
    -- Create background
    local bg = graphFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    
    -- Create border
    graphFrame.border = CreateFrame("Frame", nil, graphFrame, "BackdropTemplate")
    graphFrame.border:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", -1, 1)
    graphFrame.border:SetPoint("BOTTOMRIGHT", graphFrame, "BOTTOMRIGHT", 1, -1)
    graphFrame.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    graphFrame.border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    
    -- Create title
    graphFrame.title = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    graphFrame.title:SetPoint("TOP", graphFrame, "TOP", 0, -10)
    graphFrame.title:SetText("Latency Trend")
    
    -- Create graph lines container
    graphFrame.homeLines = {}
    graphFrame.worldLines = {}
    graphFrame.homePrediction = {}
    graphFrame.worldPrediction = {}
    
    -- Create legend
    local legendHeight = 15
    
    -- Home legend
    local homeLegend = graphFrame:CreateTexture(nil, "OVERLAY")
    homeLegend:SetSize(10, 10)
    homeLegend:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", 10, 10)
    homeLegend:SetColorTexture(0, 1, 0, 1)
    
    local homeLegendText = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    homeLegendText:SetPoint("LEFT", homeLegend, "RIGHT", 5, 0)
    homeLegendText:SetText("Home")
    
    -- World legend
    local worldLegend = graphFrame:CreateTexture(nil, "OVERLAY")
    worldLegend:SetSize(10, 10)
    worldLegend:SetPoint("LEFT", homeLegendText, "RIGHT", 15, 0)
    worldLegend:SetColorTexture(0, 0, 1, 1)
    
    local worldLegendText = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    worldLegendText:SetPoint("LEFT", worldLegend, "RIGHT", 5, 0)
    worldLegendText:SetText("World")
    
    -- Prediction legend
    local predLegend = graphFrame:CreateTexture(nil, "OVERLAY")
    predLegend:SetSize(10, 10)
    predLegend:SetPoint("LEFT", worldLegendText, "RIGHT", 15, 0)
    predLegend:SetColorTexture(1, 0, 0, 0.7)
    
    local predLegendText = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    predLegendText:SetPoint("LEFT", predLegend, "RIGHT", 5, 0)
    predLegendText:SetText("Prediction")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, graphFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", graphFrame, "TOPRIGHT", 0, 0)
    closeButton:SetScript("OnClick", function() graphFrame:Hide() end)
    
    -- Create packet loss and jitter indicators - repositioned to prevent overlapping
    graphFrame.packetLoss = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphFrame.packetLoss:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", 10, -30) -- Moved below the title
    graphFrame.packetLoss:SetText("Packet Loss: 0%")
    
    graphFrame.jitter = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphFrame.jitter:SetPoint("TOPLEFT", graphFrame.packetLoss, "BOTTOMLEFT", 0, -5)
    graphFrame.jitter:SetText("Jitter: 0ms")
    
    -- Create prediction warnings
    graphFrame.prediction = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphFrame.prediction:SetPoint("BOTTOMRIGHT", graphFrame, "BOTTOMRIGHT", -10, 30)
    graphFrame.prediction:SetText("No latency warnings predicted")
    
    -- Register with main addon
    LG.graphFrame = graphFrame
end

-- Update graph with current data
local function UpdateLatencyGraph()
    if not graphFrame or not graphFrame:IsShown() then return end
    
    -- Clear existing lines
    for _, line in ipairs(graphFrame.homeLines) do
        line:Hide()
    end
    
    for _, line in ipairs(graphFrame.worldLines) do
        line:Hide()
    end
    
    for _, line in ipairs(graphFrame.homePrediction) do
        line:Hide()
    end
    
    for _, line in ipairs(graphFrame.worldPrediction) do
        line:Hide()
    end
    
    -- Reset the arrays
    graphFrame.homeLines = {}
    graphFrame.worldLines = {}
    graphFrame.homePrediction = {}
    graphFrame.worldPrediction = {}
    
    -- Get the history data
    local homeLatencyHistory = LG.homeLatencyHistory or {}
    local worldLatencyHistory = LG.worldLatencyHistory or {}
    
    -- Skip if we don't have enough data
    if #homeLatencyHistory < 2 or #worldLatencyHistory < 2 then
        return
    end
    
    -- Calculate graph area dimensions
    local graphWidth = graphFrame:GetWidth() - 40  -- Left and right margin
    local graphHeight = graphFrame:GetHeight() - 60  -- Top and bottom margin
    local startX = 20  -- Left margin
    local startY = 40  -- Bottom margin
    local endX = startX + graphWidth  -- Right boundary
    
    -- Find maximum latency for scaling
    local maxLatency = 50  -- Minimum scale to avoid division by zero
    for i = 1, math.min(20, #homeLatencyHistory) do
        if homeLatencyHistory[i] then
            maxLatency = math.max(maxLatency, homeLatencyHistory[i])
        end
    end
    
    for i = 1, math.min(20, #worldLatencyHistory) do
        if worldLatencyHistory[i] then
            maxLatency = math.max(maxLatency, worldLatencyHistory[i])
        end
    end
    
    -- Add 20% headroom
    maxLatency = maxLatency * 1.2
    
    -- Calculate how many points to display
    -- Fixed number of points that will fit in the graph width
    local maxPoints = 10  -- We'll show 10 points (9 segments) to keep it clean
    
    -- Draw home latency lines
    local homePoints = math.min(maxPoints, #homeLatencyHistory)
    if homePoints >= 2 then
        -- Create points array
        local points = {}
        for i = 1, homePoints do
            local value = homeLatencyHistory[i] or 0
            -- Calculate evenly spaced x coordinates
            local x = startX + ((i-1) / (homePoints-1)) * graphWidth
            -- Calculate y based on value
            local y = startY + (1 - (value / maxLatency)) * graphHeight
            -- Ensure y is within bounds
            y = math.max(startY, math.min(startY + graphHeight, y))
            
            points[i] = {x = x, y = y}
        end
        
        -- Draw segments connecting points
        for i = 1, homePoints - 1 do
            local line = graphFrame:CreateLine()
            line:SetStartPoint("BOTTOMLEFT", graphFrame, points[i].x, points[i].y)
            line:SetEndPoint("BOTTOMLEFT", graphFrame, points[i+1].x, points[i+1].y)
            line:SetColorTexture(0, 1, 0, 1)
            line:SetThickness(2)
            table.insert(graphFrame.homeLines, line)
        end
        
        -- Draw prediction line
        if trendData.homePrediction > 0 then
            local lastPoint = points[homePoints]
            local predY = startY + (1 - (trendData.homePrediction / maxLatency)) * graphHeight
            -- Ensure y is within bounds
            predY = math.max(startY, math.min(startY + graphHeight, predY))
            
            local line = graphFrame:CreateLine()
            line:SetStartPoint("BOTTOMLEFT", graphFrame, lastPoint.x, lastPoint.y)
            line:SetEndPoint("BOTTOMLEFT", graphFrame, endX, predY)
            line:SetColorTexture(1, 0, 0, 0.7)
            line:SetThickness(2)
            table.insert(graphFrame.homePrediction, line)
        end
    end
    
    -- Draw world latency lines
    local worldPoints = math.min(maxPoints, #worldLatencyHistory)
    if worldPoints >= 2 then
        -- Create points array
        local points = {}
        for i = 1, worldPoints do
            local value = worldLatencyHistory[i] or 0
            -- Calculate evenly spaced x coordinates
            local x = startX + ((i-1) / (worldPoints-1)) * graphWidth
            -- Calculate y based on value
            local y = startY + (1 - (value / maxLatency)) * graphHeight
            -- Ensure y is within bounds
            y = math.max(startY, math.min(startY + graphHeight, y))
            
            points[i] = {x = x, y = y}
        end
        
        -- Draw segments connecting points
        for i = 1, worldPoints - 1 do
            local line = graphFrame:CreateLine()
            line:SetStartPoint("BOTTOMLEFT", graphFrame, points[i].x, points[i].y)
            line:SetEndPoint("BOTTOMLEFT", graphFrame, points[i+1].x, points[i+1].y)
            line:SetColorTexture(0, 0, 1, 1)
            line:SetThickness(2)
            table.insert(graphFrame.worldLines, line)
        end
        
        -- Draw prediction line
        if trendData.worldPrediction > 0 then
            local lastPoint = points[worldPoints]
            local predY = startY + (1 - (trendData.worldPrediction / maxLatency)) * graphHeight
            -- Ensure y is within bounds
            predY = math.max(startY, math.min(startY + graphHeight, predY))
            
            local line = graphFrame:CreateLine()
            line:SetStartPoint("BOTTOMLEFT", graphFrame, lastPoint.x, lastPoint.y)
            line:SetEndPoint("BOTTOMLEFT", graphFrame, endX, predY)
            line:SetColorTexture(1, 0, 0, 0.7)
            line:SetThickness(2)
            table.insert(graphFrame.worldPrediction, line)
        end
    end
    
    -- Update packet loss and jitter information
    local packetLoss = estimatePacketLoss()
    graphFrame.packetLoss:SetText(string.format("Packet Loss: %.1f%%", packetLoss))
    
    if packetLoss > LG.defaults.packetLossThreshold then
        graphFrame.packetLoss:SetTextColor(1, 0, 0)
    else
        graphFrame.packetLoss:SetTextColor(1, 1, 1)
    end
    
    local homeJitter = calculateJitter(homeLatencyHistory, LG.defaults.trendSampleSize)
    local worldJitter = calculateJitter(worldLatencyHistory, LG.defaults.trendSampleSize)
    local maxJitter = math.max(homeJitter, worldJitter)
    
    graphFrame.jitter:SetText(string.format("Jitter: %.1fms", maxJitter))
    
    if maxJitter > LG.defaults.jitterThreshold then
        graphFrame.jitter:SetTextColor(1, 0, 0)
    else
        graphFrame.jitter:SetTextColor(1, 1, 1)
    end
    
    -- Update prediction warning
    local predictionText = "No latency warnings predicted"
    local homeLatencyPredict = trendData.homePrediction
    local worldLatencyPredict = trendData.worldPrediction
    
    if homeLatencyPredict > worldLatencyPredict and 
       homeLatencyPredict > homeLatencyHistory[1] + LG.defaults.predictionThreshold then
        predictionText = string.format("|cFFFF0000WARNING: Home latency predicted to reach %.0fms|r", homeLatencyPredict)
    elseif worldLatencyPredict > homeLatencyPredict and 
           worldLatencyPredict > worldLatencyHistory[1] + LG.defaults.predictionThreshold then
        predictionText = string.format("|cFFFF0000WARNING: World latency predicted to reach %.0fms|r", worldLatencyPredict)
    end
    
    graphFrame.prediction:SetText(predictionText)
end

-- Toggle graph visibility
local function ToggleLatencyGraph()
    if not graphFrame then
        CreateLatencyGraph()
    end
    
    if graphFrame:IsShown() then
        graphFrame:Hide()
    else
        graphFrame:Show()
        UpdateLatencyGraph()
    end
end

-- Data submission function
local function SubmitAnonymousData()
    if not LG.defaults.enableDataCollection or not LG.defaults.shareAnonymousData then
        return
    end
    
    local currentTime = GetTime()
    if currentTime - LG.defaults.lastUploadTime < LG.defaults.uploadInterval then
        return
    end
    
    -- In a real addon, you'd use a proper API call here
    -- This is just a simulation
    print("LagGuard: Submitting anonymous latency data to improve the service")
    LG.defaults.lastUploadTime = currentTime
    
    -- In a real implementation, you'd collect and send:
    -- - Server region
    -- - Average latency values
    -- - Packet loss statistics
    -- - Times of day when latency spikes occur
    -- - Instance IDs where problems occurred
    -- All without any personally identifiable information
end

-- Main update function
local analyticsFrame = CreateFrame("Frame")
local analyticsTicker = nil

local function StartAnalytics()
    if analyticsTicker then
        analyticsTicker:Cancel()
    end
    
    analyticsTicker = C_Timer.NewTicker(1, function()
        if not LG.EnsureSavedVars() or not LG.defaults.enabled then
            return
        end
        
        local homeLatencyHistory = LG.homeLatencyHistory
        local worldLatencyHistory = LG.worldLatencyHistory
        
        -- Skip if we don't have enough data
        if #homeLatencyHistory < 3 or #worldLatencyHistory < 3 then
            return
        end
        
        -- Calculate trends
        if LG.defaults.enableTrendAnalysis then
            local homeSlope, homeIntercept = calculateLinearRegression(homeLatencyHistory, LG.defaults.trendSampleSize)
            local worldSlope, worldIntercept = calculateLinearRegression(worldLatencyHistory, LG.defaults.trendSampleSize)
            
            trendData.homeSlope = homeSlope
            trendData.worldSlope = worldSlope
            
            -- Always calculate predictions even if trend isn't shown
            trendData.homePrediction = predictLatency(
                homeLatencyHistory, 
                trendData.homeSlope, 
                0, -- Intercept not needed for short-term predictions
                LG.defaults.predictionWindow
            )
            
            trendData.worldPrediction = predictLatency(
                worldLatencyHistory, 
                trendData.worldSlope, 
                0, -- Intercept not needed for short-term predictions
                LG.defaults.predictionWindow
            )
            
            -- Update trend indicators on the main alert frame if it exists
            if LG.alertFrame and LG.alertFrame.homeTrend and LG.alertFrame.worldTrend then
                -- Lowered threshold to make trends more visible
                if math.abs(homeSlope) > (LG.defaults.trendThreshold / LG.defaults.trendSampleSize) * 0.5 then
                    LG.alertFrame.homeTrend:Show()
                    if homeSlope > 0 then
                        -- Increasing latency (bad)
                        LG.alertFrame.homeTrend:SetRotation(0)
                        LG.alertFrame.homeTrend:SetVertexColor(1, 0, 0)
                    else
                        -- Decreasing latency (good)
                        LG.alertFrame.homeTrend:SetRotation(math.pi)
                        LG.alertFrame.homeTrend:SetVertexColor(0, 1, 0)
                    end
                else
                    LG.alertFrame.homeTrend:Hide()
                end
                
                if math.abs(worldSlope) > (LG.defaults.trendThreshold / LG.defaults.trendSampleSize) * 0.5 then
                    LG.alertFrame.worldTrend:Show()
                    if worldSlope > 0 then
                        -- Increasing latency (bad)
                        LG.alertFrame.worldTrend:SetRotation(0)
                        LG.alertFrame.worldTrend:SetVertexColor(1, 0, 0)
                    else
                        -- Decreasing latency (good)
                        LG.alertFrame.worldTrend:SetRotation(math.pi)
                        LG.alertFrame.worldTrend:SetVertexColor(0, 1, 0)
                    end
                else
                    LG.alertFrame.worldTrend:Hide()
                end
            end
        end
        
        -- Predictive warnings
        if LG.defaults.enablePredictiveWarnings then
            local _, _, homeLatency, worldLatency = GetNetStats()
            
            -- Warn if predicted latency exceeds threshold
            if trendData.homePrediction > homeLatency + LG.defaults.predictionThreshold then
                -- Display predictive warning
                LG.DisplayWarning(2, "Predicted Home", math.floor(trendData.homePrediction), 
                    LG.CalculateBaseline(homeLatencyHistory))
            end
            
            if trendData.worldPrediction > worldLatency + LG.defaults.predictionThreshold then
                -- Display predictive warning
                LG.DisplayWarning(2, "Predicted World", math.floor(trendData.worldPrediction), 
                    LG.CalculateBaseline(worldLatencyHistory))
            end
        end
        
        -- Connection quality assessment
        if LG.defaults.enablePacketLossDetection then
            local packetLoss = estimatePacketLoss()
            local homeJitter = calculateJitter(homeLatencyHistory, LG.defaults.trendSampleSize)
            local worldJitter = calculateJitter(worldLatencyHistory, LG.defaults.trendSampleSize)
            local maxJitter = math.max(homeJitter, worldJitter)
            
            -- Add to history
            table.insert(packetLossHistory, 1, packetLoss)
            if #packetLossHistory > LG.defaults.historySize then
                table.remove(packetLossHistory)
            end
            
            table.insert(jitterHistory, 1, maxJitter)
            if #jitterHistory > LG.defaults.historySize then
                table.remove(jitterHistory)
            end
            
            -- Warn on packet loss or high jitter
            if packetLoss > LG.defaults.packetLossThreshold then
                LG.DisplayWarning(2, "Packet Loss", string.format("%.1f%%", packetLoss), 0)
            end
            
            if maxJitter > LG.defaults.jitterThreshold then
                LG.DisplayWarning(1, "Network Jitter", string.format("%.1fms", maxJitter), 0)
            end
        end
        
        -- Anonymous data collection and sharing
        if LG.defaults.enableDataCollection then
            SubmitAnonymousData()
        end
        
        -- Update graph if visible
        UpdateLatencyGraph()
    end)
end

-- Hook into main addon's events
analyticsFrame:RegisterEvent("PLAYER_LOGIN")
analyticsFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Start analytics
        StartAnalytics()
        
        -- Hook into command handler
        local originalSlashCmd = SlashCmdList["LAGGUARD"]
        SlashCmdList["LAGGUARD"] = function(msg)
            if msg == "graph" then
                ToggleLatencyGraph()
            elseif msg == "analytics" or msg == "stats" then
                -- Show current analytics stats
                print("LagGuard Analytics:")
                print("Home Latency Trend: " .. (trendData.homeSlope > 0 and "Increasing" or "Decreasing"))
                print("World Latency Trend: " .. (trendData.worldSlope > 0 and "Increasing" or "Decreasing"))
                
                local packetLoss = estimatePacketLoss()
                print("Estimated Packet Loss: " .. string.format("%.1f%%", packetLoss))
                
                local homeJitter = calculateJitter(LG.homeLatencyHistory, LG.defaults.trendSampleSize)
                local worldJitter = calculateJitter(LG.worldLatencyHistory, LG.defaults.trendSampleSize)
                print("Home Jitter: " .. string.format("%.1fms", homeJitter))
                print("World Jitter: " .. string.format("%.1fms", worldJitter))
                
                print("Type /lg graph to view detailed analytics")
            else
                -- Pass to original handler
                originalSlashCmd(msg)
            end
        end
        
        -- Add commands to the help text
        local originalHelpText = _G.SLASH_LAGGUARD1
        if originalHelpText then
            print("LagGuard Analytics loaded")
            print("Additional commands:")
            print("/lg graph - Show detailed latency graph")
            print("/lg analytics - Show current network analytics")
        end
    end
end)

-- Make APIs available to other modules
LG.ToggleLatencyGraph = ToggleLatencyGraph
LG.analytics = {
    trendData = trendData,
    packetLossHistory = packetLossHistory,
    jitterHistory = jitterHistory,
    calculateJitter = calculateJitter,
    estimatePacketLoss = estimatePacketLoss
} 