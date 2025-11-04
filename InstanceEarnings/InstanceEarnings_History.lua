------------------------------------------------------------
-- Instance Earnings - History UI (Stripped: no copy popup, no sound)
------------------------------------------------------------
InstanceEarnings_History = InstanceEarnings_History or {}
local M = InstanceEarnings_History
local MAX_ENTRIES = 25

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
    local gi = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
    local si = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
    local ci = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
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

    -- keep widths consistent with the header above
    local widths = {200, 100, 100, 100, 30}  -- Name, Money, XP, When, [+]
    r.cols = {}

    -- Build column anchor frames at fixed positions
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

    -- Name (left aligned, small inset)
    local nameFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", col[1], "LEFT", 2, 0)
    nameFS:SetWidth(widths[1]-6)
    nameFS:SetJustifyH("LEFT")
    r.cols[1] = nameFS

    -- Money (right aligned)
    local totalFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalFS:SetPoint("RIGHT", col[2], "RIGHT", 2, 0)
    totalFS:SetWidth(widths[2]-6)
    totalFS:SetJustifyH("LEFT")
    r.cols[2] = totalFS

    -- XP (right aligned)
    local xpFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xpFS:SetPoint("RIGHT", col[3], "RIGHT", 2, 0)
    xpFS:SetWidth(widths[3]-6)
    xpFS:SetJustifyH("LEFT")
    r.cols[3] = xpFS

    -- When (right aligned so '+' sits after it cleanly)
    local whenFS = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whenFS:SetPoint("RIGHT", col[4], "RIGHT", 2, 0)
    whenFS:SetWidth(widths[4]-4)
    whenFS:SetJustifyH("LEFT")
    r.cols[4] = whenFS

    -- '+' button in its own tiny column
    local b = CreateFrame("Button", nil, r)
    b:SetSize(16, 16)
    b:SetPoint("LEFT", col[5], "LEFT", -4, 0)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetText("|cffFFD200+|r")
    r.plus = b

    -- row background
    local bg = r:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.08,0.08,0.08,(i%2==0) and 0.55 or 0.40)

    dRows[i] = r
end

------------------------------------------------------------
-- PvP Pane (unchanged layout)
------------------------------------------------------------
local pvpPane = CreateFrame("Frame", nil, ui)
pvpPane:SetPoint("TOPLEFT", 10, -66)
pvpPane:SetPoint("BOTTOMRIGHT", -10, 10)

local pvpHeader = CreateHeader(pvpPane, {
    {text="Battleground", w=200},
    {text="Honor",        w=100},
    {text="Kills",        w=100},
    {text="Date",         w=100},
    {text="",             w=30},
})

local pScroll = CreateFrame("ScrollFrame","IE_PvPScroll",pvpPane,"FauxScrollFrameTemplate")
pScroll:SetPoint("TOPLEFT",0,-18)
pScroll:SetPoint("BOTTOMRIGHT",-26,0)

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
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(widths[c])
            fs:SetJustifyH("CENTER")
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
-- Detail Popup (final) + Cogwheel + Plain-text Report
------------------------------------------------------------
InstanceEarnings_History = InstanceEarnings_History or {}
local M = InstanceEarnings_History

local detail = CreateFrame("Frame", "IE_DetailPopup", UIParent)
tinsert(UISpecialFrames, "IE_DetailPopup")
detail:SetSize(300, 160)
detail:SetPoint("TOPLEFT", ui, "TOPRIGHT", 8, 0)
detail:Hide()
SkinFrame(detail, 0.90)
detail:SetFrameStrata("HIGH")

-- Close button
local dClose = CreateFrame("Button", "IE_DetailClose", detail, "UIPanelCloseButton")
dClose:SetPoint("TOPRIGHT", -2, -2)

-- Title
local dTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dTitle:SetPoint("TOPLEFT", 12, -10)
dTitle:SetText("|cff00ff88Details|r")

-- Static, non-interactive text
local dText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dText:SetPoint("TOPLEFT", 12, -34)
dText:SetPoint("BOTTOMRIGHT", -12, 35)
dText:SetJustifyH("LEFT")
dText:SetJustifyV("TOP")
dText:SetSpacing(2)
detail.text = dText

-- Soft background behind text
local dBg = detail:CreateTexture(nil, "BACKGROUND")
dBg:SetPoint("TOPLEFT", dText, -4, 4)
dBg:SetPoint("BOTTOMRIGHT", dText, 4, -4)
dBg:SetColorTexture(0,0,0,0.2)

-- Channel selection defaults (session)
local announceChannel = "PARTY"
local announceTarget  = nil

-- Cogwheel (channel selector)
local cog = CreateFrame("Button", "IE_ReportCog", detail)
cog:SetSize(18, 18)
cog:SetPoint("BOTTOMLEFT", 10, 10)
cog:SetFrameStrata("DIALOG")

local cogIcon = cog:CreateTexture(nil, "ARTWORK")
cogIcon:SetAllPoints()
cogIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")

local cogHL = cog:CreateTexture(nil, "HIGHLIGHT")
cogHL:SetAllPoints()
cogHL:SetTexture("Interface\\Buttons\\UI-OptionsButton-Highlight")

cog:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Select report channel", 1,1,1)
    GameTooltip:AddLine("Say / Party / Raid / Battleground / Whisper", .7,.7,.7)
    GameTooltip:Show()
end)
cog:SetScript("OnLeave", function() GameTooltip:Hide() end)

local dropdown = CreateFrame("Frame", "IE_ReportDropdown", UIParent, "UIDropDownMenuTemplate")
local function SetAnnounce(channel)
    if channel == "WHISPER" then
        StaticPopupDialogs["IE_WHISPER_TARGET"] = {
            text = "Enter player name to whisper:",
            button1 = "OK", button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                announceTarget = self.editBox:GetText()
                announceChannel = "WHISPER"
                print("IE: Whisper target set to "..announceTarget)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("IE_WHISPER_TARGET")
    else
        announceChannel = channel
        announceTarget  = nil
        print("IE: Report channel set to "..channel)
    end
end

cog:SetScript("OnClick", function(self)
    local menu = {
        { text = "Say",          func = function() SetAnnounce("SAY") end },
        { text = "Party",        func = function() SetAnnounce("PARTY") end },
        { text = "Raid",         func = function() SetAnnounce("RAID") end },
        { text = "Battleground", func = function() SetAnnounce("BATTLEGROUND") end },
        { text = "Whisper...",   func = function() SetAnnounce("WHISPER") end },
    }
    EasyMenu(menu, dropdown, self, 0, 0, "MENU", 2)
end)

-- Report button (plain text)
local reportBtn = CreateFrame("Button", "IE_ReportButton", detail, "UIPanelButtonTemplate")
reportBtn:SetSize(70, 20)
reportBtn:SetPoint("BOTTOMRIGHT", -10, 10)
reportBtn:SetText("Report")
reportBtn:EnableMouse(true)

local function FormatTimeHMS(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

-- Public: show details for a run (no vendor/total)
local function ShowDetailRun(run)
    local xp   = run.xp or 0
    local dur  = run.elapsed and FormatTimeHMS(run.elapsed) or "?"
    local money= run.money or 0
    local xpMax= UnitXPMax("player") or 1
    local pct  = math.floor((math.min(xp, xpMax) / xpMax) * 100 + 0.5)
    local xphr = (run.elapsed and run.elapsed > 0) and math.floor(xp * 3600 / run.elapsed) or 0
    local minsTo = (xphr > 0) and math.floor(((xpMax - UnitXP("player")) / xphr) * 60 + 0.5) or 0

    -- color helper
    local function C(hex, s) return "|cff"..hex..s.."|r" end
    local V   = "ffffff"   -- values (white)
    local SEP = "00ff88"   -- separator teal

    -- label palette
    local L_DURATION = "66ccff"
    local L_GOLD     = "ffd700"
    local L_XP       = "ffff00"
    local L_XPHR     = "00ff88"
    local L_TIME     = "b57dff"

    local lines = {
        C(L_DURATION,"Duration:").." "..C(V, dur),
        C(L_GOLD,"Gold earned:").." "..C(V, FormatGSC_Icons(money)),
        C(L_XP,"XP:").." "..C(V, xp.." ("..pct.."%)"),
        C(L_XPHR,"XP/hr:").." "..C(V, xphr),
    }

    detail.text:SetText(table.concat(lines, "\n"))
    detail.runData = run
    detail:Show()
end

M.ShowDetailRun = ShowDetailRun  -- expose for row '+' buttons

-- Report sender (plain text, no total line)
reportBtn:SetScript("OnClick", function()
    local run = detail.runData
    if not run then print("IE: No run data to report."); return end

    local xp   = run.xp or 0
    local dur  = run.elapsed and FormatTimeHMS(run.elapsed) or "?"
    local money= run.money or 0
    local kills= run.kills or 0
    local xpMax= UnitXPMax("player") or 1
    local pct  = math.floor((math.min(xp, xpMax) / xpMax) * 100 + 0.5)
    local xphr = (run.elapsed and run.elapsed > 0) and math.floor(xp * 3600 / run.elapsed) or 0
    local minsTo= (xphr > 0) and math.floor(((xpMax - UnitXP("player")) / xphr) * 60 + 0.5) or 0

    local lines = {
        "-------------------------------",
        "IE: Dungeon Results — "..(run.name or "Unknown"),
        "Duration: "..dur,
        string.format("Gold Earned: %dg %ds %dc", math.floor(money/10000), math.floor(money/100)%100, money%100),
        string.format("XP: %d (%d%%)", xp, pct),
        string.format("XP/hr: %d", xphr),
        string.format("Time until next level: %dm", minsTo),
        "-------------------------------",
    }

    local channel = announceChannel or "PARTY"
    local target  = announceTarget
    for _, line in ipairs(lines) do
        if channel == "WHISPER" and target then
            SendChatMessage(line, "WHISPER", nil, target)
        else
            SendChatMessage(line, channel)
        end
    end
    print("IE: Report sent to "..channel..(target and (" ("..target..")") or "")..".")
end)
------------------------------------------------------------
-- Scroll Update (Newest first)
------------------------------------------------------------
local function DungeonScroll_Update()
    EnsureDB()
    local data = InstanceEarningsDB.history
    local count = #data
    local off = FauxScrollFrame_GetOffset(dScroll)
    FauxScrollFrame_Update(dScroll, count, ROWS, 18)

    for i=1,ROWS do
        local idx = count - (i + off) + 1 -- newest first
        local row = dRows[i]
        if data[idx] then
            local r = data[idx]
            row.cols[1]:SetText("|cff00ffff"..(r.name or "").."|r")
            -- show only net run money (no combined/vendor totals)
            row.cols[2]:SetText("|cffffd700"..FormatGSC_Icons((r.money or 0)).."|r")
            row.cols[3]:SetText("|cffffff00"..(r.xp or 0).."|r")
            row.cols[4]:SetText("|cffaaaaaa"..(Ago(r.ts)).."|r")
            row.plus:SetScript("OnClick", function() ShowDetailRun(r) end)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function PvPScroll_Update()
    EnsureDB()
    local data = InstanceEarningsDB.bgHistory
    local count = #data
    local off = FauxScrollFrame_GetOffset(pScroll)
    FauxScrollFrame_Update(pScroll, count, ROWS, 18)

    local honorIcon = "|TInterface\\PVPFrame\\PVP-Currency-Honor:0:0:0:0|t"
    for i=1,ROWS do
        local idx = count - (i + off) + 1
        local row = pRows[i]
        if data[idx] then
            local r = data[idx]
            row.cols[1]:SetText("|cff00ffff"..(r.name or "").."|r")
            row.cols[2]:SetText("|cffff5555"..(r.honor or 0).."|r "..honorIcon)
            row.cols[3]:SetText("|cffffffff"..(r.kills or 0).."|r")
            row.cols[4]:SetText("|cffaaaaaa"..(Ago(r.ts)).."|r")
            row.plus:SetScript("OnClick", function() ShowDetailRun({
                name = r.name, xp = 0, elapsed = r.elapsed, itemValueOnly = 0, rawGoldOnly = 0, ts = r.ts, lootValue = 0
            }) end)
            row:Show()
        else row:Hide() end
    end
end

dScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 18, DungeonScroll_Update)
end)
pScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, 18, PvPScroll_Update)
end)

------------------------------------------------------------
-- Config Sidebar (no sound/copy options)
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
    local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    t:SetPoint("LEFT",b,"RIGHT",4,0); t:SetText(label)
    b:SetScript("OnShow",function(self) self:SetChecked(getter()) end)
    b:SetScript("OnClick",function(self)
        local on=self:GetChecked() and true or false
        setter(on)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88IE:|r "..fb..": "..(on and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
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

-- Clear buttons
StaticPopupDialogs["IE_CLEAR_DUNGEONS"]={
    text="Clear Dungeon History? This cannot be undone.",
    button1=YES, button2=CANCEL,
    OnAccept=function() EnsureDB(); InstanceEarningsDB.history={}; M.RefreshUI() end,
    timeout=0, whileDead=1, hideOnEscape=1,
}
StaticPopupDialogs["IE_CLEAR_BGS"]={
    text="Clear PvP History? This cannot be undone.",
    button1=YES, button2=CANCEL,
    OnAccept=function() EnsureDB(); InstanceEarningsDB.bgHistory={}; M.RefreshUI() end,
    timeout=0, whileDead=1, hideOnEscape=1,
}

local clrD=CreateFrame("Button",nil,cfg,"UIPanelButtonTemplate")
clrD:SetSize(140,20); clrD:SetPoint("BOTTOMLEFT",12,12)
clrD:SetText("Clear Dungeon History")
clrD:SetScript("OnClick",function() StaticPopup_Show("IE_CLEAR_DUNGEONS") end)

local clrB=CreateFrame("Button",nil,cfg,"UIPanelButtonTemplate")
clrB:SetSize(140,20); clrB:SetPoint("BOTTOMRIGHT",-12,12)
clrB:SetText("Clear PvP History")
clrB:SetScript("OnClick",function() StaticPopup_Show("IE_CLEAR_BGS") end)

-- Open/close behavior
gear:SetScript("OnClick", function()
    if cfg:IsShown() then cfg:Hide() else cfg:Show() end
end)
ui:HookScript("OnHide", function() cfg:Hide(); detail:Hide() end)

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

-- Default show state
tabDungeon:SetScript("OnClick", function()
    dungeonPane:Show(); pvpPane:Hide()
    tabDungeon:SetBackdropColor(0.18,0.18,0.18,1)
    tabPvP:SetBackdropColor(0.1,0.1,0.1,0.9)
    DungeonScroll_Update()
end)
tabPvP:SetScript("OnClick", function()
    dungeonPane:Hide(); pvpPane:Show()
    tabPvP:SetBackdropColor(0.18,0.18,0.18,1)
    tabDungeon:SetBackdropColor(0.1,0.1,0.1,0.9)
    PvPScroll_Update()
end)

ui:SetScript("OnShow", function()
    dungeonPane:Show(); pvpPane:Hide()
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
