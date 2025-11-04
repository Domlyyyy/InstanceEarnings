------------------------------------------------------------
-- Instance Earnings (Ascension 3.3.5) - FINAL (Accurate Totals + L60 XP mute + XP window + last-run tooltip)
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
    if InstanceEarningsDB.showXPWindow == nil then InstanceEarningsDB.showXPWindow = false end
    if not InstanceEarningsDB.xpWindowPos then InstanceEarningsDB.xpWindowPos = { point="TOPRIGHT", rel="UIParent", relPoint="TOPRIGHT", x=-10, y=-220 } end
end
------------------------------------------------------------
-- Saved Session (for /reload persistence)
------------------------------------------------------------
local function SaveSession()
    EnsureDB()
    InstanceEarningsDB.sessionXP = startXP
    InstanceEarningsDB.sessionMoney = startMoney
    InstanceEarningsDB.sessionTime = startTime
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

-- "time ago" helper for minimap tooltip (mirrors History’s Ago)
local function Ago(ts)
    if not ts then return "" end
    local d = time() - ts
    if d < 60 then return "just now" end
    local m = math.floor(d/60)
    if m < 60 then return m.."m ago" end
    local h = math.floor(m/60)
    if h < 24 then return h.."h ago" end
    return math.floor(h/24).."d ago"
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
-- Summary Print (with L60 XP mute)
------------------------------------------------------------
local function PrintDungeonSummary(name, moneyDiff, xpGained, elapsed)
    EnsureDB()

    local lvl = UnitLevel("player") or 1
    local showXP = (lvl < 60)

    local xpMax = UnitXPMax("player") or 1
    local pct   = math.floor((math.min(xpGained or 0, xpMax) / xpMax) * 100 + 0.5)
    local xphr  = (elapsed and elapsed > 0) and math.floor((xpGained or 0) * 3600 / elapsed) or 0
    local remain= (xphr > 0) and math.max(0, (xpMax) - UnitXP("player")) or 0
    local minsTo= (xphr > 0) and math.floor((remain / xphr) * 60 + 0.5) or 0

    local function C(hex, s) return "|cff"..hex..s.."|r" end
    local V = "ffffff"
    local SEP = "00ff88"

    local L_DURATION = "66ccff"
    local L_GOLD     = "ffd700"
    local L_XP       = "ffff00"
    local L_XPHR     = "00ff88"
    local L_TIME     = "b57dff"

    DEFAULT_CHAT_FRAME:AddMessage(C(SEP,"-----------------------------"))
    DEFAULT_CHAT_FRAME:AddMessage( C(L_DURATION,"Duration:").." "..C(V, FormatTimeHMS(elapsed or 0)) )
    DEFAULT_CHAT_FRAME:AddMessage( C(L_GOLD,    "Gold earned:").." "..C(V, FormatGSC_Icons(moneyDiff or 0)) )

    if showXP then
        DEFAULT_CHAT_FRAME:AddMessage( C(L_XP,      "XP:").." "..C(V, (xpGained or 0).." ("..pct.."%)") )
        DEFAULT_CHAT_FRAME:AddMessage( C(L_XPHR,    "XP/hr:").." "..C(V, xphr) )
        DEFAULT_CHAT_FRAME:AddMessage( C(L_TIME,    "Time until next level:").." "..C(V, minsTo.."m") )
    end

    DEFAULT_CHAT_FRAME:AddMessage(C(SEP,"-----------------------------"))
end

------------------------------------------------------------
-- Core Tracking
------------------------------------------------------------
local function ResetRunState()
    rawGoldLooted = 0
    mobsKilled = 0
end

local function StartTracking()
    EnsureDB()
    inInstance = true
    startMoney = GetMoney()
    startLevel = UnitLevel("player")
    startXP = UnitXP("player")
    startTime = GetTime()
    SaveSession()
    ResetRunState()
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    currentInstanceName = name or "Unknown"
    lastMapID = mapID
    if not InstanceEarningsDB.quietMode then IEPrint("|cffffff00Tracking started|r") end
    IE_XPWindow_Update(true) -- start ticking if window is enabled
end

local function ComputeRunNumbers()
    local moneyDiff = GetMoney() - (startMoney or 0)

    local currentLevel = UnitLevel("player") or 1
    local xpGained = 0
    if currentLevel < 60 then
        if currentLevel == (startLevel or currentLevel) then
            xpGained = UnitXP("player") - (startXP or 0)
        else
            -- Level ups within run (rare on Ascension 60 cap context, but keep logic)
            xpGained = (currentLevel - (startLevel or currentLevel)) * UnitXPMax("player")
                        + UnitXP("player") - (startXP or 0)
        end
    else
        -- Level 60: XP muted
        xpGained = 0
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
            xp      = xpGained,                 -- will be 0 at level 60
            elapsed = elapsed,
            kills   = mobsKilled,
            when    = date("%Y-%m-%d %H:%M"),
            ts      = time(),
            rawGoldOnly = rawGoldLooted,
            level   = UnitLevel("player") or 1, -- store for future logic if needed
        })
    end

    IE_XPWindow_Update(false) -- stop ticking
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
    elseif msg == "xpwindow" then
        InstanceEarningsDB.showXPWindow = not InstanceEarningsDB.showXPWindow
        IEPrint("XP window: "..(InstanceEarningsDB.showXPWindow and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
        IE_XPWindow_SetShown(InstanceEarningsDB.showXPWindow)
    else
        IEPrint("Commands: /ie history, /ie config, /ie xpwindow")
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
        -- (intentionally silent here; gold is parsed via MONEY)
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
    EnsureDB()
    tooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    tooltip:ClearLines()
    tooltip:AddLine("InstanceEarnings", 1, 1, 1)
    tooltip:AddLine("Click to open Dungeon & PvP History", 0.9, 0.9, 0.9)

    -- Last run info (from history)
    local hist = InstanceEarningsDB.history
    if hist and #hist > 0 then
        local last = hist[#hist]
        tooltip:AddLine(" ")
        tooltip:AddLine("|cff00ff88Last run|r", 0.3, 1, 0.6)
        tooltip:AddLine(string.format("%s |cffaaaaaa(%s)|r", last.name or "Unknown", Ago(last.ts)), 0.9, 0.9, 0.9)
        local money = last.money or 0
        tooltip:AddLine("Gold: "..FormatGSC_Icons(money), 1, 0.95, 0.5)
        local lvl = UnitLevel("player") or 1
        if (lvl < 60) and (last.xp or 0) > 0 then
            tooltip:AddLine(string.format("XP: %d", last.xp or 0), 1, 1, 0.4)
        end
    end

    tooltip:Show()
end)
minimap:SetScript("OnLeave", function() tooltip:Hide() end)
minimap:SetScript("OnClick", function()
    tooltip:Hide()
    if InstanceEarnings_History and InstanceEarnings_History.Toggle then
        InstanceEarnings_History.Toggle()
    end
end)

------------------------------------------------------------
-- ElvUI-style XP Window (draggable, toggleable)
------------------------------------------------------------
local xpWindow, xpText1, xpText2, xpText3, xpText4
local accum = 0

local function SkinSmallFrame(f)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left=2, right=2, top=2, bottom=2 }
    })
    f:SetBackdropColor(0.06,0.06,0.06, 0.92)
    f:SetBackdropBorderColor(0.2,0.2,0.2,1)
end

local function IE_CreateXPWindow()
    if xpWindow then return end
    EnsureDB()

    xpWindow = CreateFrame("Frame", "IE_XPWindow", UIParent)
    xpWindow:SetSize(170, 85)
    SkinSmallFrame(xpWindow)
    xpWindow:SetMovable(true)
    xpWindow:EnableMouse(true)
    xpWindow:RegisterForDrag("LeftButton")
    xpWindow:SetScript("OnDragStart", xpWindow.StartMoving)
    xpWindow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, rel, relPoint, x, y = self:GetPoint(1)
        InstanceEarningsDB.xpWindowPos = { point=point, rel=rel and rel:GetName() or "UIParent", relPoint=relPoint, x=x, y=y }
    end)

    local pos = InstanceEarningsDB.xpWindowPos
    local rel = _G[pos.rel] or UIParent
    xpWindow:ClearAllPoints()
    xpWindow:SetPoint(pos.point, rel, pos.relPoint, pos.x, pos.y)

    xpText1 = xpWindow:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    xpText2 = xpWindow:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    xpText3 = xpWindow:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    xpText4 = xpWindow:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")

    xpText1:SetPoint("TOPLEFT", 8, -12)  -- XP/hr
    xpText2:SetPoint("TOPLEFT", 8, -28)  -- XP
    xpText3:SetPoint("TOPLEFT", 8, -44)  -- To level
    xpText4:SetPoint("TOPLEFT", 8, -60)  -- Gold
    xpText1:SetJustifyH("LEFT")
    xpText2:SetJustifyH("LEFT")
    xpText3:SetJustifyH("LEFT")
    xpText4:SetJustifyH("LEFT")


    xpWindow:Hide()
end

function IE_XPWindow_SetShown(show)
    IE_CreateXPWindow()
    if show then
        xpWindow:Show()
    else
        xpWindow:Hide()
    end
end

-- call with tick=true on StartTracking, false on StopTracking
function IE_XPWindow_Update(tick)
    EnsureDB()
    IE_CreateXPWindow()
    IE_XPWindow_SetShown(InstanceEarningsDB.showXPWindow)

    -- always tick if shown, even outside instances
    if not xpWindow:IsShown() then return end

    if not xpWindow.ticker then
        xpWindow.ticker = xpWindow:CreateAnimationGroup()
        local a = xpWindow.ticker:CreateAnimation("Animation")
        a:SetDuration(0.5)
        xpWindow.ticker:SetLooping("REPEAT")
        xpWindow.ticker:SetScript("OnLoop", function()
            local lvl = UnitLevel("player") or 1
            local xpMax = UnitXPMax("player") or 1
            local xpCur = UnitXP("player") or 0
            local money = GetMoney() or 0

            -- compute XP/hr using session time
            accum = accum + 0.5
            if not startTime then startTime = GetTime() end
            local elapsed = GetTime() - startTime
            local xpGained = xpCur - (startXP or xpCur)
            if elapsed < 1 then elapsed = 1 end

            local xphr = (lvl < 60) and math.floor(xpGained * 3600 / elapsed) or 0
            local pct  = (lvl < 60) and math.floor((xpCur / xpMax) * 100 + 0.5) or 0
            local remain = (lvl < 60) and math.max(0, xpMax - xpCur) or 0
            local minsTo = (xphr > 0) and math.floor((remain / xphr) * 60 + 0.5) or 0

            if lvl < 60 then
            xpText1:SetText(string.format("|cffffff00XP/hr:|r %d", xphr))
            xpText2:SetText(string.format("|cff66ff66XP:|r %d%%", pct))
            xpText3:SetText(string.format("|cffa0a0ffTo level:|r %dm", minsTo))
            else
            xpText1:SetText("|cffffff00XP/hr:|r —")
            xpText2:SetText("|cff66ff66XP:|r —")
            xpText3:SetText("|cffa0a0ffTo level:|r —")
	end
            xpText4:SetText("|cffffd700Gold earned:|r "..FormatGSC_Icons(money - (startMoney or money)))

        end)
        xpWindow.ticker:Play()
    end
end

-- initialize panel visibility on login/reload
C_Timer.After(1, function()
    EnsureDB()

    -- Restore last session if available
    startXP = InstanceEarningsDB.sessionXP or UnitXP("player")
    startMoney = InstanceEarningsDB.sessionMoney or GetMoney()
    startTime = InstanceEarningsDB.sessionTime or GetTime()

    IE_CreateXPWindow()
    IE_XPWindow_SetShown(InstanceEarningsDB.showXPWindow)
    IE_XPWindow_Update(true)
end)
