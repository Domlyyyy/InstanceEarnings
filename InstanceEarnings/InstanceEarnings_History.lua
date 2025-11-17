------------------------------------------------------------
-- Instance Earnings ...
------------------------------------------------------------
local addonName = ...
local f = CreateFrame("Frame")


------------------------------------------------------------
-- Instance Earnings - History UI (Stripped: no copy popup, no sound) + L60 XP mute in report/detail
------------------------------------------------------------
InstanceEarnings_History = InstanceEarnings_History or {}
local M = InstanceEarnings_History
local MAX_ENTRIES = 25
local HonorColorText = _G.HonorColorText



------------------------------------------------------------
-- SavedVariables helpers
------------------------------------------------------------
local function EnsureDB()
    if not InstanceEarningsDB then InstanceEarningsDB = {} end
    if not InstanceEarningsDB.history then InstanceEarningsDB.history = {} end
    if not InstanceEarningsDB.bgHistory then InstanceEarningsDB.bgHistory = {} end
    if InstanceEarningsDB.showTotal == nil then InstanceEarningsDB.showTotal = false end
    -- retired: playSound, autoCopyReport
    if InstanceEarningsDB.autoChatSwitch == nil then InstanceEarningsDB.autoChatSwitch = false end
    if InstanceEarningsDB.quietMode == nil then InstanceEarningsDB.quietMode = false end
end

local function ClampTable(t, maxn) while #t > maxn do table.remove(t, 1) end end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function SkinFrame(f, alpha)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left=2, right=2, top=2, bottom=2 }
    })
    f:SetBackdropColor(0.06,0.06,0.06, alpha or 0.90)
    f:SetBackdropBorderColor(0.2,0.2,0.2,1)
end

local function FormatGSC_Icons(c)
    c = c or 0
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cc = c % 100
    local gi = "|TInterface\\MoneyFrame\\UI-GoldIcon:16:16:0:0|t"
    local si = "|TInterface\\MoneyFrame\\UI-SilverIcon:16:16:0:0|t"
    local ci = "|TInterface\\MoneyFrame\\UI-CopperIcon:16:16:0:0|t"

    return string.format("%d%s %d%s %d%s", g, gi, s, si, cc, ci)
end

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

local HonorColorText = _G.HonorColorText

------------------------------------------------------------
-- Main Frame
------------------------------------------------------------
local ui = CreateFrame("Frame","InstanceEarnings_HistoryFrame",UIParent)
tinsert(UISpecialFrames, "InstanceEarnings_HistoryFrame")
ui:SetSize(560, 380)
ui:SetPoint("CENTER")
ui:Hide()
ui:SetMovable(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart",ui.StartMoving)
ui:SetScript("OnDragStop",ui.StopMovingOrSizing)
SkinFrame(ui, 0.90)

-- Dragon + title
local dragon = ui:CreateTexture(nil,"OVERLAY")
dragon:SetSize(27,27)
dragon:SetPoint("TOPLEFT",8,-8)
dragon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")

local title = ui:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
title:SetPoint("TOPLEFT",46,-10)
title:SetText("|cff00ff88InstanceEarnings|r")

-- Close
local close = CreateFrame("Button",nil,ui,"UIPanelCloseButton")
close:SetPoint("TOPRIGHT",0,0)

-- Gear
local gear=CreateFrame("Button",nil,ui)
gear:SetSize(18,18)
gear:SetPoint("TOPRIGHT",-33,-8)
local gearTex=gear:CreateTexture(nil,"ARTWORK")
gearTex:SetAllPoints()
gearTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")

------------------------------------------------------------
-- Tabs
------------------------------------------------------------
local tabs=CreateFrame("Frame",nil,ui)
tabs:SetPoint("TOPLEFT",10,-36)
tabs:SetSize(420,24)
local function MakeTab(p,text)
    local b=CreateFrame("Button",nil,p)
    b:SetHeight(20) b:SetWidth(120)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetText(text)
    b:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8x8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize=10, insets={left=2,right=2,top=2,bottom=2}
    })
    b:SetBackdropColor(0.1,0.1,0.1,0.9)
    b:SetBackdropBorderColor(0.25,0.25,0.25,1)
    return b
end
local tabDungeon=MakeTab(tabs,"Dungeons"); tabDungeon:SetPoint("LEFT",0,0)
local tabPvP=MakeTab(tabs,"PvP"); tabPvP:SetPoint("LEFT",tabDungeon,"RIGHT",8,0)

------------------------------------------------------------
-- Header factory
------------------------------------------------------------
local function CreateHeader(parent, labels)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(16)
    h:SetPoint("TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", 0, 0)
    local x = 8
    for _, v in ipairs(labels) do
        local fs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetText(v.text)
        x = x + v.w
    end
    return h
end

------------------------------------------------------------
-- Dungeon Pane
------------------------------------------------------------
local dungeonPane = CreateFrame("Frame", nil, ui)
dungeonPane:SetPoint("TOPLEFT", 10, -66)
dungeonPane:SetPoint("BOTTOMRIGHT", -10, 10)

local dungeonHeader = CreateHeader(dungeonPane, {
    {text="Name", w=200},
    {text="Gold Earned", w=100},
    {text="XP",    w=100},
    {text="When",  w=100},
    {text="",      w=30},
})

local dScroll = CreateFrame("ScrollFrame","IE_DungeonScroll",dungeonPane,"FauxScrollFrameTemplate")
dScroll:SetPoint("TOPLEFT",0,-18)
dScroll:SetPoint("BOTTOMRIGHT",-26,0)

local ROWS = 13
local dRows = {}
for i=1,ROWS do
    local r = CreateFrame("Button", nil, dungeonPane)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 0, -18 - (i-1)*18)
    r:SetPoint("RIGHT", -26, 0)

    local widths = {200, 100, 100, 100, 30}  -- Name, Money, XP, When, [+]

    r.cols = {}
    local col = {}
    local x = 0
    for c = 1, 5 do
        local a = CreateFrame("Frame", nil, r)
        a:SetPoint("LEFT", r, "LEFT", x, 0)
        a:SetWidth(widths[c])
        a:SetHeight(18)
        col[c] = a
        x = x + widths[c]
    end

    local nameFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", col[1], "LEFT", 2, 0)
    nameFS:SetWidth(widths[1]-6)
    nameFS:SetJustifyH("LEFT")
    r.cols[1] = nameFS

    local totalFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalFS:SetPoint("RIGHT", col[2], "RIGHT", 2, 0)
    totalFS:SetWidth(widths[2]-6)
    totalFS:SetJustifyH("LEFT")
    r.cols[2] = totalFS

    local xpFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xpFS:SetPoint("RIGHT", col[3], "RIGHT", 2, 0)
    xpFS:SetWidth(widths[3]-6)
    xpFS:SetJustifyH("LEFT")
    r.cols[3] = xpFS

    local whenFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whenFS:SetPoint("RIGHT", col[4], "RIGHT", 2, 0)
    whenFS:SetWidth(widths[4]-4)
    whenFS:SetJustifyH("LEFT")
    r.cols[4] = whenFS

    local b = CreateFrame("Button", nil, r)
    b:SetSize(16, 16)
    b:SetPoint("LEFT", col[5], "LEFT", -4, 0)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetText("|cffFFD200+|r")
    r.plus = b

    local bg = r:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.08,0.08,0.08,(i%2==0) and 0.55 or 0.40)

    dRows[i] = r
end

------------------------------------------------------------
-- Shared Helpers (Needed by both Dungeon + PvP)
------------------------------------------------------------

local function FormatTimeHMS(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)

    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end
_G.FormatTimeHMS = FormatTimeHMS -- expose globally so both panes can use

------------------------------------------------------------
-- Dungeon Scroll Update (Required by tab switching + UI)
------------------------------------------------------------
function DungeonScroll_Update()
    EnsureDB()
    local data = InstanceEarningsDB.history
    local count = #data
    local off = FauxScrollFrame_GetOffset(dScroll)

    FauxScrollFrame_Update(dScroll, count, ROWS, 18)

    for i=1,ROWS do
        local idx = count - (i + off) + 1
        local row = dRows[i]
        local r = data[idx]

        if r then
            row.cols[1]:SetText("|cff00ffff"..(r.name or "").."|r")
            row.cols[2]:SetText("|cffffd700"..FormatGSC_Icons((r.money or 0)).."|r")
            row.cols[3]:SetText("|cffffff00"..(r.xp or 0).."|r")
            row.cols[4]:SetText("|cffaaaaaa"..(Ago(r.ts)).."|r")
            row.plus:SetScript("OnClick", function() M.ShowDetailRun(r) end)
            row:Show()
        else
            row:Hide()
        end
    end
end

------------------------------------------------------------
-- Dungeon Detail Popup (FULL) + Report System
------------------------------------------------------------

-- Create dungeon detail frame
local detail = CreateFrame("Frame", "IE_DetailPopup", UIParent)
tinsert(UISpecialFrames, "IE_DetailPopup")
detail:SetSize(300, 200)
detail:SetPoint("TOPLEFT", ui, "TOPRIGHT", 8, 0)
detail:Hide()
SkinFrame(detail, 0.90)
detail:SetFrameStrata("HIGH")

local dClose = CreateFrame("Button", nil, detail, "UIPanelCloseButton")
dClose:SetPoint("TOPRIGHT", -2, -2)

local dTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dTitle:SetPoint("TOPLEFT", 12, -10)
dTitle:SetText("|cff00ff88Details|r")

local dText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dText:SetPoint("TOPLEFT", 12, -34)
dText:SetPoint("BOTTOMRIGHT", -12, 35)
dText:SetJustifyH("LEFT")
dText:SetJustifyV("TOP")
dText:SetSpacing(2)
detail.text = dText

------------------------------------------------------------
-- Report Dropdown (Say / Party / Raid / BG / Whisper)
------------------------------------------------------------
local announceChannel = "PARTY"
local announceTarget = nil
local dropdown = CreateFrame("Frame", "IE_ReportDropdown", UIParent, "UIDropDownMenuTemplate")

local cog = CreateFrame("Button", "IE_DetailCog", detail)
cog:SetSize(18, 18)
cog:SetPoint("BOTTOMLEFT", 10, 10)

local cogTex = cog:CreateTexture(nil, "ARTWORK")
cogTex:SetAllPoints()
cogTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")

local function SetReportChannel(ch)
    if ch == "WHISPER" then
        StaticPopupDialogs["IE_WHISPER_TARGET"] = {
            text = "Enter whisper target:",
            button1 = "OK",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                announceTarget = self.editBox:GetText()
                announceChannel = "WHISPER"
                print("Whisper target set: "..announceTarget)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("IE_WHISPER_TARGET")
    else
        announceChannel = ch
        announceTarget = nil
        print("Report channel set to: "..ch)
    end
end

cog:SetScript("OnClick", function(self)
    local menu = {
        { text = "Say", func = function() SetReportChannel("SAY") end },
        { text = "Party", func = function() SetReportChannel("PARTY") end },
        { text = "Raid", func = function() SetReportChannel("RAID") end },
        { text = "Battleground", func = function() SetReportChannel("BATTLEGROUND") end },
        { text = "Whisper…", func = function() SetReportChannel("WHISPER") end },
    }
    EasyMenu(menu, dropdown, self, 0, 0, "MENU")
end)

------------------------------------------------------------
-- Dungeon Report Button
------------------------------------------------------------
local dReportBtn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
dReportBtn:SetSize(70, 20)
dReportBtn:SetPoint("BOTTOMRIGHT", -10, 10)
dReportBtn:SetText("Report")

------------------------------------------------------------
-- ShowDetailRun (Dungeon)
------------------------------------------------------------
function M.ShowDetailRun(run)
    local xp     = run.xp or 0
    local money  = run.money or 0
    local elapsed = run.elapsed or 0

    local lvl    = UnitLevel("player") or 1
    local xpMax  = UnitXPMax("player") or 1
    local showXP = lvl < 60

    local pct  = showXP and math.floor((math.min(xp, xpMax) / xpMax) * 100 + 0.5) or 0
    local xphr = (elapsed > 0 and showXP) and math.floor(xp * 3600 / elapsed) or 0
    local remain = showXP and math.max(0, xpMax - UnitXP("player")) or 0
    local minsTo = (showXP and xphr > 0) and math.floor((remain / xphr) * 60 + 0.5) or 0

    local dur = FormatTimeHMS(elapsed)
    local GSC = FormatGSC_Icons(money)

    local function C(hex, s) return "|cff"..hex..s.."|r" end
    local V = "ffffff"

    local L_DUR  = "66ccff"
    local L_GOLD = "ffd700"
    local L_XP   = "ffff00"
    local L_XPHR = "00ff88"
    local L_TIME = "aa88ff"

    local lines = {
        C(L_DUR, "Duration:").." "..C(V, dur),
        C(L_GOLD, "Gold earned:").." "..GSC,
    }

    if showXP then
        table.insert(lines, C(L_XP, "XP gained:").." "..C(V, xp.." ("..pct.."%)"))
        table.insert(lines, C(L_XPHR, "XP/hr:").." "..C(V, xphr))
        table.insert(lines, C(L_TIME, "To level:").." "..C(V, minsTo.."m"))
    end

    detail.text:SetText(table.concat(lines, "\n"))
    detail.runData = run
    detail:Show()
end

------------------------------------------------------------
-- DUNGEON REPORT BUTTON HANDLER (NO ICONS)
------------------------------------------------------------
dReportBtn:SetScript("OnClick", function()
    local run = detail.runData
    if not run then return end

    local xp     = run.xp or 0
    local money  = run.money or 0
    local elapsed = run.elapsed or 0

    local lvl    = UnitLevel("player") or 1
    local xpMax  = UnitXPMax("player") or 1
    local showXP = lvl < 60

    local pct  = showXP and math.floor((math.min(xp, xpMax) / xpMax) * 100 + 0.5) or 0
    local xphr = (elapsed > 0 and showXP) and math.floor(xp * 3600 / elapsed) or 0
    local remain = showXP and math.max(0, xpMax - UnitXP("player")) or 0
    local minsTo = (showXP and xphr > 0) and math.floor((remain / xphr) * 60 + 0.5) or 0
    local dur = FormatTimeHMS(elapsed)

    -- Convert copper → g/s/c text
    local g = math.floor(money / 10000)
    local s = math.floor((money % 10000) / 100)
    local c = math.floor(money % 100)
    local moneyText = string.format("%dg %ds %dc", g, s, c)

    local lines = {
        "-------------------------------",
        "IE: Dungeon Results — "..(run.name or "Unknown"),
        "Duration: "..dur,
        "Gold Earned: "..moneyText,
    }

    if showXP then
        table.insert(lines, "XP: "..xp.." ("..pct.."%)")
        table.insert(lines, "XP/hr: "..xphr)
        table.insert(lines, "To level: "..minsTo.."m")
    end

    table.insert(lines, "-------------------------------")

    local chan = announceChannel
    local target = announceTarget

    for _, line in ipairs(lines) do
        if chan == "WHISPER" and target then
            SendChatMessage(line, "WHISPER", nil, target)
        else
            SendChatMessage(line, chan)
        end
    end
end)

------------------------------------------------------------
-- PvP Pane (Honor + XP only)
------------------------------------------------------------
local pvpPane = CreateFrame("Frame", nil, ui)
pvpPane:SetPoint("TOPLEFT", 10, -66)
pvpPane:SetPoint("BOTTOMRIGHT", -10, 10)
pvpPane:Hide()

local pvpHeader = CreateHeader(pvpPane, {
    {text="Battleground", w=200},
    {text="Honor",        w=100},
    {text="XP",           w=100},
    {text="Date",         w=100},
    {text="",             w=30},
})

local pScroll = CreateFrame("ScrollFrame","IE_PvPScroll",pvpPane,"FauxScrollFrameTemplate")
pScroll:SetPoint("TOPLEFT",0,-18)
pScroll:SetPoint("BOTTOMRIGHT",-26,0)

local honorIconInline = "|TInterface\\PVPRankBadges\\PVPRank12:16:16:0:0|t"

local pRows = {}
for i=1,ROWS do
    local r = CreateFrame("Button", nil, pvpPane)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 0, -18 - (i-1)*18)
    r:SetPoint("RIGHT", -26, 0)

    local widths = {200,100,100,100,30}
    r.cols = {}
    local x=6
    for c=1,5 do
        if c < 5 then
            local fs = r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            fs:SetPoint("LEFT", x+2, 0)
            fs:SetWidth(widths[c])
            fs:SetJustifyH("LEFT")
            r.cols[c] = fs
        else
            local b = CreateFrame("Button", nil, r)
            b:SetSize(16,16)
            b:SetPoint("LEFT", x+2, 0)
            b:SetNormalFontObject(GameFontHighlightSmall)
            b:SetText("|cffFFD200+|r")
            r.plus = b
        end
        x = x + widths[c]
    end

    local bg = r:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.08,0.08,0.08,(i%2==0) and 0.55 or 0.40)

    pRows[i] = r
end

------------------------------------------------------------
-- PvP Detail Popup (with cog + working report)
------------------------------------------------------------
local pvpDetail = CreateFrame("Frame", "IE_PvPDetailPopup", UIParent)
tinsert(UISpecialFrames, "IE_PvPDetailPopup")
pvpDetail:SetSize(300, 150)
pvpDetail:SetPoint("TOPLEFT", ui, "TOPRIGHT", 8, 0)
pvpDetail:Hide()
SkinFrame(pvpDetail, 0.90)
pvpDetail:SetFrameStrata("HIGH")

local pClose = CreateFrame("Button", nil, pvpDetail, "UIPanelCloseButton")
pClose:SetPoint("TOPRIGHT", -2, -2)

local pTitle = pvpDetail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
pTitle:SetPoint("TOPLEFT", 12, -10)
pTitle:SetText("|cff00ff88PvP Details|r")

local pText = pvpDetail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pText:SetPoint("TOPLEFT", 12, -34)
pText:SetPoint("BOTTOMRIGHT", -12, 35)
pText:SetJustifyH("LEFT")
pText:SetJustifyV("TOP")
pText:SetSpacing(2)
pvpDetail.text = pText

------------------------------------------------------------
-- PvP Cog (same as dungeon)
------------------------------------------------------------
local pCog = CreateFrame("Button", "IE_PvPCog", pvpDetail)
pCog:SetSize(18, 18)
pCog:SetPoint("BOTTOMLEFT", 10, 10)

local pCogTex = pCog:CreateTexture(nil, "ARTWORK")
pCogTex:SetAllPoints()
pCogTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")

pCog:SetScript("OnClick", function(self)
    local menu = {
        { text = "Say",         func = function() SetReportChannel("SAY") end },
        { text = "Party",       func = function() SetReportChannel("PARTY") end },
        { text = "Raid",        func = function() SetReportChannel("RAID") end },
        { text = "Battleground",func = function() SetReportChannel("BATTLEGROUND") end },
        { text = "Whisper…",    func = function() SetReportChannel("WHISPER") end },
    }
    EasyMenu(menu, dropdown, self, 0, 0, "MENU")
end)

------------------------------------------------------------
-- PvP Report Button
------------------------------------------------------------
local pvpReportBtn = CreateFrame("Button", nil, pvpDetail, "UIPanelButtonTemplate")
pvpReportBtn:SetSize(70, 20)
pvpReportBtn:SetPoint("BOTTOMRIGHT", -10, 10)
pvpReportBtn:SetText("Report")

pvpReportBtn:SetScript("OnClick", function()
    local run = pvpDetail.runData
    if not run then return end

    local honor = run.honor or 0
    local dur   = FormatTimeHMS(run.elapsed or 0)

    local lines = {
        "-------------------------------",
        "IE: Battleground — "..(run.name or "Unknown"),
        "Duration: "..dur,
        "Honor gained: "..honor,
        "-------------------------------",
    }

    local chan = announceChannel
    local target = announceTarget

    for _, line in ipairs(lines) do
        if chan == "WHISPER" and target then
            SendChatMessage(line, "WHISPER", nil, target)
        else
            SendChatMessage(line, chan)
        end
    end
end)

------------------------------------------------------------
-- PvP Detail Display Function
------------------------------------------------------------
local function ShowPvPDetail(run)
    pvpDetail.runData = run

    local dur = FormatTimeHMS(run.elapsed or 0)
    local honor = run.honor or 0
    local xp = run.xp or 0

    local function C(hex, s) return "|cff"..hex..s.."|r" end
    local V   = "ffffff"

    local lines = {
        C("66ccff","Duration:")     .." "..C(V, dur),
        C("ff5555","Honor gained:") .." "..C(V, honor.." "..honorIconInline),
        C("ffff00","XP gained:")    .." "..C(V, xp),
    }

    pvpDetail.text:SetText(table.concat(lines, "\n"))
    pvpDetail:Show()
end

------------------------------------------------------------
-- PvP Scroll Update (fixed honor icon display)
------------------------------------------------------------
local function PvPScroll_Update()
    EnsureDB()
    local data = InstanceEarningsDB.bgHistory
    local count = #data

    local off = FauxScrollFrame_GetOffset(pScroll)
    FauxScrollFrame_Update(pScroll, count, ROWS, 18)

    -- honor icon (universal, visible at 14px)
    local honorIconInline = "|TInterface\\PVPRankBadges\\PVPRank12:16:16:0:0|t"

    for i=1,ROWS do
        local idx = count - (i + off) + 1
        local row = pRows[i]

        if data[idx] then
            local r = data[idx]

            -- Name (cyan)
            row.cols[1]:SetText("|cff00ffff"..(r.name or "").."|r")

            -- Honor with icon (red)
            row.cols[2]:SetText(HonorColorText(r.honor or 0).." "..honorIconInline)

            -- XP (yellow)
            row.cols[3]:SetText("|cffffff00"..(r.xp or 0).."|r")

            -- When (gray)
            row.cols[4]:SetText("|cffaaaaaa"..(Ago(r.ts)).."|r")

            -- Detail button
            row.plus:SetScript("OnClick", function()
                ShowPvPDetail(r)
            end)

            row:Show()
        else
            row:Hide()
        end
    end
end

pScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 18, PvPScroll_Update)
end)

------------------------------------------------------------
-- Config Sidebar
------------------------------------------------------------
local cfg = CreateFrame("Frame","InstanceEarnings_Config",UIParent)
tinsert(UISpecialFrames, "InstanceEarnings_Config")
cfg:SetSize(300, ui:GetHeight())
cfg:SetPoint("TOPLEFT", ui, "TOPRIGHT", 8, 0)
cfg:Hide()
SkinFrame(cfg, 0.90)

local cfgTitle = cfg:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
cfgTitle:SetPoint("TOPLEFT",12,-10)
cfgTitle:SetText("|cff00ff88InstanceEarnings Settings|r")

local function MakeCheckbox(parent,label,y,getter,setter,fb)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    b:SetPoint("TOPLEFT",14,y)

    local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t:SetPoint("LEFT",b,"RIGHT",6,0)
    t:SetText("|cff00ff88"..label.."|r")
    b.label = t

    b:SetScript("OnShow",function(self) self:SetChecked(getter()) end)
    b:SetScript("OnClick",function(self)
        local on=self:GetChecked() and true or false
        setter(on)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88IE:|r ".."|cffffffff"..fb.."|r"..": "
            ..(on and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
    end)

    return b
end

local cb1=MakeCheckbox(cfg,"Auto-switch chat in dungeons/BGs",-42,
    function() EnsureDB(); return InstanceEarningsDB.autoChatSwitch end,
    function(v) EnsureDB(); InstanceEarningsDB.autoChatSwitch=v end,
    "Auto chat switching")

local cb2=MakeCheckbox(cfg,"Quiet Mode (hide notifications)",-72,
    function() EnsureDB(); return InstanceEarningsDB.quietMode end,
    function(v) EnsureDB(); InstanceEarningsDB.quietMode=v end,
    "Quiet mode")

local cb3=MakeCheckbox(cfg,"Show XP Window",-102,
    function() EnsureDB(); return InstanceEarningsDB.showXPWindow end,
    function(v)
        EnsureDB()
        InstanceEarningsDB.showXPWindow = v
        if IE_XPWindow_SetShown then IE_XPWindow_SetShown(v) end
    end,
    "XP Window display")

StaticPopupDialogs["IE_CLEAR_DUNGEONS"]={
    text="Clear Dungeon History? This cannot be undone.",
    button1=YES, button2=CANCEL,
    OnAccept=function()
        EnsureDB()
        InstanceEarningsDB.history={}
        M.RefreshUI()
    end,
    timeout=0, whileDead=1, hideOnEscape=1,
}

StaticPopupDialogs["IE_CLEAR_BGS"]={
    text="Clear PvP History? This cannot be undone.",
    button1=YES, button2=CANCEL,
    OnAccept=function()
        EnsureDB()
        InstanceEarningsDB.bgHistory={}
        M.RefreshUI()
    end,
    timeout=0, whileDead=1, hideOnEscape=1,
}

local clrD=CreateFrame("Button",nil,cfg,"UIPanelButtonTemplate")
clrD:SetSize(140,20)
clrD:SetPoint("BOTTOMLEFT",12,12)
clrD:SetText("Clear Dungeon History")
clrD:SetScript("OnClick",function() StaticPopup_Show("IE_CLEAR_DUNGEONS") end)

local clrB=CreateFrame("Button",nil,cfg,"UIPanelButtonTemplate")
clrB:SetSize(140,20)
clrB:SetPoint("BOTTOMRIGHT",-12,12)
clrB:SetText("Clear PvP History")
clrB:SetScript("OnClick",function() StaticPopup_Show("IE_CLEAR_BGS") end)

gear:SetScript("OnClick", function()
    if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end)

ui:HookScript("OnHide", function()
    cfg:Hide()

    -- Hide dungeon detail popup if it exists
    if _G["IE_DetailPopup"] then
        _G["IE_DetailPopup"]:Hide()
    end

    -- Hide PvP detail popup if it exists
    if _G["IE_PvPDetailPopup"] then
        _G["IE_PvPDetailPopup"]:Hide()
    end
end)

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function M.Toggle()
    if ui:IsShown() then ui:Hide() else ui:Show() end
end

function M.ToggleConfig()
    if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end

function M.RefreshUI()
    if not ui:IsShown() then return end
    DungeonScroll_Update()
    PvPScroll_Update()
end

------------------------------------------------------------
-- Tab switching
------------------------------------------------------------
tabDungeon:SetScript("OnClick", function()
    dungeonPane:Show()
    pvpPane:Hide()

    tabDungeon:SetBackdropColor(0.18,0.18,0.18,1)
    tabPvP:SetBackdropColor(0.1,0.1,0.1,0.9)

    DungeonScroll_Update()
end)

tabPvP:SetScript("OnClick", function()
    dungeonPane:Hide()
    pvpPane:Show()

    tabPvP:SetBackdropColor(0.18,0.18,0.18,1)
    tabDungeon:SetBackdropColor(0.1,0.1,0.1,0.9)

    PvPScroll_Update()
end)

ui:SetScript("OnShow", function()
    dungeonPane:Show()
    pvpPane:Hide()
    DungeonScroll_Update()
end)

------------------------------------------------------------
-- Data Injection APIs (called from core)
------------------------------------------------------------
function M.AddDungeonRun(run)
    EnsureDB()
    table.insert(InstanceEarningsDB.history, run)
    ClampTable(InstanceEarningsDB.history, MAX_ENTRIES)
    M.RefreshUI()
end

function M.AddPvPRun(run)
    EnsureDB()
    table.insert(InstanceEarningsDB.bgHistory, run)
    ClampTable(InstanceEarningsDB.bgHistory, MAX_ENTRIES)
    M.RefreshUI()
end
