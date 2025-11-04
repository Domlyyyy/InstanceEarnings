------------------------------------------------------------
-- Instance Earnings (Ascension 3.3.5) - FINAL (Accurate Totals)
------------------------------------------------------------
local addonName = ...
local f = CreateFrame("Frame")

-- State
local inInstance = false
local startXP, startMoney, startLevel, startTime
local currentInstanceName, lastMapID
local rawGoldLooted = 0
local mobsKilled = 0


------------------------------------------------------------
-- SavedVariables
------------------------------------------------------------
local function EnsureDB()
    if not InstanceEarningsDB then InstanceEarningsDB = {} end
    if InstanceEarningsDB.showTotal == nil then InstanceEarningsDB.showTotal = false end
    if InstanceEarningsDB.autoChatSwitch == nil then InstanceEarningsDB.autoChatSwitch = false end
    if InstanceEarningsDB.quietMode == nil then InstanceEarningsDB.quietMode = false end
end

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function FormatGSC_Icons(copper)
    copper = copper or 0
    if copper < 0 then copper = 0 end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local gi = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
    local si = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
    local ci = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
    return string.format("%d%s %d%s %d%s", g, gi, s, si, c, ci)
end

local function FormatTimeHMS(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

local function IEPrint(msg)
    if InstanceEarningsDB and InstanceEarningsDB.quietMode then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88IE:|r "..msg)
end

------------------------------------------------------------
-- Trade / Chat Handlers (silent)
------------------------------------------------------------
local AUTO_LEAVE_TRADE = true
local NEED_TRADE_REJOIN = false

local function FindTradeChannelName()
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local name = list[i+1]
        if name and string.find(string.lower(name), "trade") then
            return name
        end
    end
    return "Trade"
end

local function TryRejoinTrade()
    local tradeName = FindTradeChannelName()
    if NEED_TRADE_REJOIN and GetChannelName(tradeName) == 0 then
        JoinPermanentChannel(tradeName, nil, DEFAULT_CHAT_FRAME:GetID(), 1)
        NEED_TRADE_REJOIN = false
    end
end

local function HandleTradeChannel(isEnteringInstance)
    local tradeName = FindTradeChannelName()
    if isEnteringInstance then
        if AUTO_LEAVE_TRADE and GetChannelName(tradeName) > 0 then
            LeaveChannelByName(tradeName)
        end
        NEED_TRADE_REJOIN = true
    else
        TryRejoinTrade()
    end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:SetScript("OnEvent", function(_, evt)
    if evt == "ZONE_CHANGED_NEW_AREA" or evt == "PLAYER_ENTERING_WORLD" then
        TryRejoinTrade()
    end
end)

------------------------------------------------------------
-- Auto Chat Type Switch (silent)
------------------------------------------------------------
local lastChatType = "SAY"
local function SwitchChatForInstance(isInside)
    EnsureDB()
    if not InstanceEarningsDB.autoChatSwitch then return end
    if not ChatFrame1 or not ChatFrame1.editBox then return end

    if isInside then
        local _, instanceType = IsInInstance()
        if instanceType == "party" or instanceType == "raid" then
            lastChatType = ChatFrame1.editBox.chatType or "SAY"
            ChatFrame1.editBox:SetAttribute("chatType", "PARTY")
        elseif instanceType == "pvp" then
            lastChatType = ChatFrame1.editBox.chatType or "SAY"
            ChatFrame1.editBox:SetAttribute("chatType", "BATTLEGROUND")
        end
    else
        if lastChatType and ChatFrame1 and ChatFrame1.editBox then
            ChatFrame1.editBox:SetAttribute("chatType", lastChatType)
        end
    end
end

local _oldHandleTrade = HandleTradeChannel
HandleTradeChannel = function(isEnteringInstance)
    if _oldHandleTrade then _oldHandleTrade(isEnteringInstance) end
    SwitchChatForInstance(isEnteringInstance)
end

------------------------------------------------------------
-- Summary Print (cleaned)
------------------------------------------------------------
-- Consistent, colorized chat summary
local function PrintDungeonSummary(name, moneyDiff, xpGained, elapsed)
    EnsureDB()

    local xpMax = UnitXPMax("player") or 1
    local pct   = math.floor((math.min(xpGained or 0, xpMax) / xpMax) * 100 + 0.5)
    local xphr  = (elapsed and elapsed > 0) and math.floor((xpGained or 0) * 3600 / elapsed) or 0
    local remain= (xphr > 0) and math.max(0, (xpMax) - UnitXP("player")) or 0
    local minsTo= (xphr > 0) and math.floor((remain / xphr) * 60 + 0.5) or 0

    -- tiny helpers for consistent style
    local function C(hex, s) return "|cff"..hex..s.."|r" end
    local V = "ffffff"   -- values all white
    local SEP = "00ff88" -- separator teal

    -- label colors (distinct per module)
    local L_DURATION = "66ccff"  -- light blue
    local L_GOLD     = "ffd700"  -- gold
    local L_XP       = "ffff00"  -- bright yellow
    local L_XPHR     = "00ff88"  -- soft green
    local L_TIME     = "b57dff"  -- lavender

    DEFAULT_CHAT_FRAME:AddMessage(C(SEP,"-----------------------------"))
    DEFAULT_CHAT_FRAME:AddMessage( C(L_DURATION,"Duration:").." "..C(V, FormatTimeHMS(elapsed or 0)) )
    DEFAULT_CHAT_FRAME:AddMessage( C(L_GOLD,    "Gold earned:").." "..C(V, FormatGSC_Icons(moneyDiff or 0)) )
    DEFAULT_CHAT_FRAME:AddMessage( C(L_XP,      "XP:").." "..C(V, (xpGained or 0).." ("..pct.."%)") )
    DEFAULT_CHAT_FRAME:AddMessage( C(L_XPHR,    "XP/hr:").." "..C(V, xphr) )
    DEFAULT_CHAT_FRAME:AddMessage( C(L_TIME,    "Time until next level:").." "..C(V, minsTo.."m") )
    DEFAULT_CHAT_FRAME:AddMessage(C(SEP,"-----------------------------"))
end
------------------------------------------------------------
-------------------------------------------------------------
-- Core Tracking
------------------------------------------------------------
local function ResetRunState()
    rawGoldLooted = 0
    mobsKilled = 0
end

local function StartTracking()
    inInstance = true
    startMoney = GetMoney()
    startLevel = UnitLevel("player")
    startXP = UnitXP("player")
    startTime = GetTime()
    ResetRunState()
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    currentInstanceName = name or "Unknown"
    lastMapID = mapID
    if not InstanceEarningsDB.quietMode then IEPrint("|cffffff00Tracking started|r") end
end

local function ComputeRunNumbers()
    local moneyDiff = GetMoney() - (startMoney or 0)
    local currentLevel = UnitLevel("player")
    local xpGained
    if currentLevel == (startLevel or currentLevel) then
        xpGained = UnitXP("player") - (startXP or 0)
    else
        xpGained = (currentLevel - (startLevel or currentLevel)) * UnitXPMax("player")
                    + UnitXP("player") - (startXP or 0)
    end
    local elapsed = GetTime() - (startTime or GetTime())
    return moneyDiff, xpGained, elapsed
end

local function StopTracking()
    if not inInstance then return end
    inInstance = false

    local moneyDiff, xpGained, elapsed = ComputeRunNumbers()

    PrintDungeonSummary(currentInstanceName, moneyDiff, xpGained, elapsed)

    if InstanceEarnings_History and InstanceEarnings_History.AddDungeonRun then
        InstanceEarnings_History.AddDungeonRun({
            name    = currentInstanceName or "Unknown",
            money   = moneyDiff,
            xp      = xpGained,
            elapsed = elapsed,
            kills   = mobsKilled,      -- << add this
            when    = date("%Y-%m-%d %H:%M"),
            ts      = time(),
            rawGoldOnly = rawGoldLooted,
        })

    end
end

local function UpdateInstanceState()
    EnsureDB()
    local inInst, instType = IsInInstance()

    if inInst then
        local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
        if inInstance then
            if lastMapID and mapID and mapID ~= lastMapID then
                StopTracking()
                StartTracking()
            end
        else
            StartTracking()
        end
        lastMapID = mapID
        HandleTradeChannel(true)
    else
        if inInstance then StopTracking() end
        HandleTradeChannel(false)
    end
end
------------------------------------------------------------
-- Slash
------------------------------------------------------------
SLASH_INSTANCEEARNINGS1 = "/ie"
SlashCmdList["INSTANCEEARNINGS"] = function(msg)
    EnsureDB()
    msg = string.lower(msg or "")
    if msg == "history" then
        if InstanceEarnings_History and InstanceEarnings_History.Toggle then
            InstanceEarnings_History.Toggle()
        end
    elseif msg == "config" then
        if InstanceEarnings_History and InstanceEarnings_History.ToggleConfig then
            InstanceEarnings_History.ToggleConfig()
        end
    else
        IEPrint("Commands: /ie history, /ie config")
    end
end
------------------------------------------------------------
-- Events
------------------------------------------------------------
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("CHAT_MSG_MONEY")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    UpdateInstanceState()
    -- Solo-entry fix: Ascension reports 'none' for ~2s before the instance flag updates
    C_Timer.After(3, UpdateInstanceState)


    elseif event == "CHAT_MSG_LOOT" and inInstance then
    elseif event == "CHAT_MSG_MONEY" and inInstance then
        local msg = ...
        local copper = 0
        local g = msg:match("(%d+)%s?Gold")
        local s = msg:match("(%d+)%s?Silver")
        local c = msg:match("(%d+)%s?Copper")
        if g then copper = copper + (tonumber(g) or 0) * 10000 end
        if s then copper = copper + (tonumber(s) or 0) * 100 end
        if c then copper = copper + (tonumber(c) or 0) end
        rawGoldLooted = rawGoldLooted + copper

    end
end)

------------------------------------------------------------
-- Minimap Button
------------------------------------------------------------
local minimap = CreateFrame("Button", "InstanceEarnings_MinimapButton", Minimap)
minimap:SetSize(32, 32)
minimap:SetFrameStrata("MEDIUM")
minimap:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 10, -10)
minimap:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = minimap:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints()
icon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")

local tooltip = CreateFrame("GameTooltip", "InstanceEarnings_Tooltip", UIParent, "GameTooltipTemplate")
minimap:SetScript("OnEnter", function(self)
    tooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    tooltip:ClearLines()
    tooltip:AddLine("InstanceEarnings", 1, 1, 1)
    tooltip:AddLine("Click to open Dungeon & PvP History", 0.9, 0.9, 0.9)
    tooltip:Show()
end)
minimap:SetScript("OnLeave", function() tooltip:Hide() end)
minimap:SetScript("OnClick", function()
    tooltip:Hide()
    if InstanceEarnings_History and InstanceEarnings_History.Toggle then
        InstanceEarnings_History.Toggle()
    end
end)
