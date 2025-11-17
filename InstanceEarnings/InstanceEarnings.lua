-- GLOBAL honor color function with faction colors
function HonorColorText(amount)
    local faction = UnitFactionGroup("player")

    if faction == "Alliance" then
        -- Alliance = blue
        return "|cff4696ec" .. tostring(amount) .. "|r"
    elseif faction == "Horde" then
        -- Horde = red
        return "|cffff5555" .. tostring(amount) .. "|r"
    else
        -- Neutral fallback = gold
        return "|cffffff00" .. tostring(amount) .. "|r"
    end
end
------------------------------------------------------------
-- Instance Earnings ...
------------------------------------------------------------
local addonName = ...
local f = CreateFrame("Frame")

-- State
local inInstance = false
local startXP, startMoney, startLevel, startTime
local currentInstanceName, lastMapID


------------------------------------------------------------
-- SavedVariables
------------------------------------------------------------
local function EnsureDB()
    if not InstanceEarningsDB then InstanceEarningsDB = {} end
    if InstanceEarningsDB.autoChatSwitch == nil then InstanceEarningsDB.autoChatSwitch = false end
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

-- GLOBAL honor color function with faction colors
function HonorColorText(amount)
    local faction = UnitFactionGroup("player")

    if faction == "Alliance" then
        -- Alliance = blue
        return "|cff4696ec" .. tostring(amount) .. "|r"
    elseif faction == "Horde" then
        -- Horde = red
        return "|cffff5555" .. tostring(amount) .. "|r"
    else
        -- Neutral fallback = gold
        return "|cffffff00" .. tostring(amount) .. "|r"
    end
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
-- Core Tracking + PvP (Battleground) Tracking
------------------------------------------------------------
-- Extra PvP state
local pvpActive = false
local pvpStartXP, pvpStartHonor, pvpStartTime
local pvpName, pvpMapID

local function GetCurrentHonor()
    if GetHonorCurrency then
        return GetHonorCurrency() or 0
    end
    return 0
end


------------------------------------------------------------
-- Dungeon / Raid Tracking (unchanged behavior)
------------------------------------------------------------
local function StartTracking()
    EnsureDB()
    inInstance = true
    startMoney = GetMoney()
    startLevel = UnitLevel("player")
    startXP = UnitXP("player")
    startTime = GetTime()
    SaveSession()
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    currentInstanceName = name or "Unknown"
    lastMapID = mapID
    IEPrint("|cffffff00Tracking started|r")
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
            -- Level ups within run
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
            when    = date("%Y-%m-%d %H:%M"),
            ts      = time(),
            level   = UnitLevel("player") or 1, -- store for future logic if needed
        })
    end

    IE_XPWindow_Update(false) -- stop ticking
end

------------------------------------------------------------
-- PvP (Battleground) Tracking
------------------------------------------------------------

-- Correct Ascension honor getter
local function GetCurrentHonor()
    if GetHonorCurrency then
        return GetHonorCurrency() or 0
    end
    return 0
end

-- Chat summary after BG ends (with icon)
local function PrintPvPSummary(name, honorGained, xpGained, elapsed)
    EnsureDB()

    local lvl = UnitLevel("player") or 1
    local showXP = (lvl < 60)

    local honorIconInline = "|TInterface\\PVPRankBadges\\PVPRank12:14:14:0:0|t"

    local function C(hex, s) return "|cff"..hex..s.."|r" end
    local V   = "ffffff"
    local SEP = "00ff88"

    DEFAULT_CHAT_FRAME:AddMessage(C(SEP,"-----------------------------"))
    DEFAULT_CHAT_FRAME:AddMessage(
        C("66ccff","BG Duration:").." "..C(V, FormatTimeHMS(elapsed or 0))
    )

    -- Honor (with faction color + icon)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffccccccHonor:|r "..HonorColorText(honorGained or 0).." "..honorIconInline
    )

    if showXP then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffff00XP gained:|r "..C(V, xpGained or 0)
        )
    end

    DEFAULT_CHAT_FRAME:AddMessage(C(SEP,"-----------------------------"))
end


-- Internal PvP state
local pvpActive = false
local pvpStartXP, pvpStartHonor, pvpStartTime
local pvpName, pvpMapID

-- Called when entering PvP instance
local function StartPvPTracking()
    EnsureDB()

    pvpActive     = true
    pvpStartTime  = GetTime()
    pvpStartXP    = UnitXP("player") or 0
    pvpStartHonor = GetCurrentHonor()

    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    pvpName  = name or "Battleground"
    pvpMapID = mapID

    IEPrint("|cffffff00PvP tracking started|r")
end

-- Called when leaving PvP instance
local function StopPvPTracking()
    if not pvpActive then return end
    pvpActive = false

    local honorNow   = GetCurrentHonor()
    local honorGained= (honorNow or 0) - (pvpStartHonor or 0)

    local lvl    = UnitLevel("player") or 1
    local xpNow  = UnitXP("player") or 0
    local xpGained = 0

    if lvl < 60 then
        xpGained = xpNow - (pvpStartXP or xpNow)
    end

    local elapsed = GetTime() - (pvpStartTime or GetTime())

    -- Print summary
    PrintPvPSummary(pvpName or "Battleground", honorGained, xpGained, elapsed)

    -- Store in history
    if InstanceEarnings_History and InstanceEarnings_History.AddPvPRun then
        InstanceEarnings_History.AddPvPRun({
            name    = pvpName or "Battleground",
            honor   = honorGained,
            xp      = xpGained,
            elapsed = elapsed,
            when    = date("%Y-%m-%d %H:%M"),
            ts      = time(),
        })
    end
end

------------------------------------------------------------
-- Instance State Dispatcher (Dungeon vs PvP)
------------------------------------------------------------
local function UpdateInstanceState()
    EnsureDB()
    local inInst, instType = IsInInstance()

    if inInst then
        local name, _, _, _, _, _, _, mapID = GetInstanceInfo()

        if instType == "pvp" then
            -- Leaving a dungeon and entering a BG
            if inInstance then
                StopTracking()
                inInstance = false
            end

            -- (Re)start PvP tracking if map changed or not active
            if not pvpActive or (pvpMapID and mapID and mapID ~= pvpMapID) then
                if pvpActive then
                    StopPvPTracking()
                end
                StartPvPTracking()
            end

        else
            -- Non-PvP instance: party/raid/etc.
            -- If we were in a BG, stop PvP tracking
            if pvpActive then
                StopPvPTracking()
            end

            if inInstance then
                if lastMapID and mapID and mapID ~= lastMapID then
                    -- Swapped instance
                    StopTracking()
                    StartTracking()
                end
            else
                -- Fresh instance entry
                StartTracking()
            end
            inInstance = true
        end

        lastMapID = mapID
        HandleTradeChannel(true)
    else
        -- Left all instances
        if inInstance then
            StopTracking()
        end
        if pvpActive then
            StopPvPTracking()
        end
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

        -- if you don't actually use `copper` anywhere anymore, this is just parsed and discarded, which is fine
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
---------------------
-- XP Window (lightweight, only runs when enabled)
---------------------
local xpWindow, xpText1, xpText2, xpText3, xpText4
local accum = 0

local function SkinSmallFrame(f)
    f:SetBackdrop({
        bgFile  = "Interface\\Buttons\\WHITE8x8",
        edgeFile= "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize= 12,
        insets  = { left=2, right=2, top=2, bottom=2 }
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
        InstanceEarningsDB.xpWindowPos = {
            point    = point,
            rel      = rel and rel:GetName() or "UIParent",
            relPoint = relPoint,
            x        = x,
            y        = y,
        }
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

-- Core update logic (no timers here, just pure math)
local function IE_XPWindow_DoUpdate()
    if not xpWindow or not xpWindow:IsShown() then return end

    local lvl   = UnitLevel("player") or 1
    local xpMax = UnitXPMax("player") or 1
    local xpCur = UnitXP("player") or 0
    local money = GetMoney() or 0

    -- Auto-correct invalid or negative baseline
    if not startXP or xpCur < startXP then
        startXP = xpCur
    end
    if not startMoney or money < startMoney then
        startMoney = money
    end
    if not startTime or startTime > GetTime() then
        startTime = GetTime()
    end

    local elapsed = GetTime() - startTime
    if elapsed < 1 then elapsed = 1 end

    local xpGained = 0
    if lvl < 60 then
        xpGained = xpCur - startXP
    end

    local xphr   = (lvl < 60) and math.floor(xpGained * 3600 / elapsed) or 0
    local pct    = (lvl < 60) and math.floor((xpCur / xpMax) * 100 + 0.5) or 0
    local remain = (lvl < 60) and math.max(0, xpMax - xpCur) or 0
    local minsTo = (lvl < 60 and xphr > 0) and math.floor((remain / xphr) * 60 + 0.5) or 0

    if lvl < 60 then
        xpText1:SetText(string.format("|cffffff00XP/hr:|r %d", xphr))
        xpText2:SetText(string.format("|cff66ff66XP:|r %d%%", pct))
        xpText3:SetText(string.format("|cffa0a0ffTo level:|r %dm", minsTo))
    else
        xpText1:SetText("|cffffff00XP/hr:|r —")
        xpText2:SetText("|cff66ff66XP:|r —")
        xpText3:SetText("|cffa0a0ffTo level:|r —")
    end

    xpText4:SetText("|cffffd700Gold earned:|r "..FormatGSC_Icons(money - startMoney))
end

-- OnUpdate driver, only attached when window is enabled
local function XPWindow_OnUpdate(self, elapsed)
    accum = accum + elapsed
    if accum < 0.5 then return end  -- update twice per second max
    accum = 0
    IE_XPWindow_DoUpdate()
end

-- Public show/hide used by config + slash + login
function IE_XPWindow_SetShown(show)
    EnsureDB()
    IE_CreateXPWindow()

    InstanceEarningsDB.showXPWindow = not not show

    if InstanceEarningsDB.showXPWindow then
        xpWindow:Show()
        accum = 0
        xpWindow:SetScript("OnUpdate", XPWindow_OnUpdate)
        IE_XPWindow_DoUpdate()  -- immediate refresh
    else
        xpWindow:SetScript("OnUpdate", nil)
        xpWindow:Hide()

    end
end

-- Kept for API compatibility (StartTracking/StopTracking/login call this)
-- We ignore the tick flag now and just sync to the DB flag.
function IE_XPWindow_Update(tick)
    EnsureDB()
    IE_XPWindow_SetShown(InstanceEarningsDB.showXPWindow)
end

-- initialize panel visibility on login/reload
C_Timer.After(1, function()
    EnsureDB()

    -- Restore last session if available
    startXP = UnitXP("player")
    startMoney = GetMoney()
    startTime = GetTime()


    IE_CreateXPWindow()
    IE_XPWindow_SetShown(InstanceEarningsDB.showXPWindow)
    IE_XPWindow_Update(true)
end)