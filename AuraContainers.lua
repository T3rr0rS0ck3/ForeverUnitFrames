-- ForeverUnitFrames: Buffs und Debuffs über Blizzards AuraContainer
--
-- Warum: Im Kampf (und teils in Instanzen) verweigert der Client Addons jeden Zugriff
-- auf Aura-Daten ("Auras cannot be accessed when secret while tainted"). Der
-- AuraContainer ist Blizzards Baustein dafür: Das Addon bestimmt Lage, Filter und
-- Aussehen, Blizzard holt die Daten intern. Damit sind die Icons immer aktuell,
-- auch im Kampf. Vorbild: ThreatPlates (Widgets/AurasWidgetMidnight.lua).
--
-- Regeln, die der Client vorgibt:
-- * Container nur außerhalb des Kampfes anlegen.
-- * Icons werden in initializeFrame eingerichtet (läuft in Blizzards geschütztem Kontext);
--   danach nur noch Größe/Sichtbarkeit anfassen, und das nur außerhalb des Kampfes.
-- * Keine Aura-Daten selbst lesen: Farbe, Zeit, Stapel bindet Blizzard an unsere Regionen.
local _, ns = ...

local HasAuraContainers = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

function ns:HasAuraContainers() return HasAuraContainers end
if not HasAuraContainers then return end

local SIZE_BIG    = 26
local SIZE_SMALL  = 18
local GAP         = 4
local ROW_GAP     = 16   -- Platz für die Restzeit unter dem Icon
local BORDER      = 2
local WHITE       = "Interface\\Buttons\\WHITE8X8"

local GOLD_BORDER = { 0.90, 0.70, 0.30 }
local DARK_BORDER = { 0.11, 0.11, 0.13 }

local Flow = AnchorUtil.FlowDirection
local SortMethod = AuraContainerSortMethod or {}
local SortDirection = AuraContainerSortDirection or {}
local PreserveAsset = Enum.CustomAuraButtonDispelTypeTextureStyle
    and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

-- Rahmenfarben der Debuffs nach Typ (wie in Auras.lua); "None" = ohne Typ
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    None    = { 0.70, 0.15, 0.15 },
}
local DISPEL_COLOR_MAP = {}
for k, c in pairs(DISPEL_COLORS) do
    local src = (k ~= "None") and DebuffTypeColor and DebuffTypeColor[k]
    DISPEL_COLOR_MAP[k] = src and CreateColor(src.r, src.g, src.b, 1) or CreateColor(c[1], c[2], c[3], 1)
end

-- Restzeit wie bei den eigenen Icons: "12", "3m", "2h" (aufgerundet)
local Formatter
do
    local ok, f = pcall(function()
        local fmt = C_StringUtil.CreateNumericRuleFormatter()
        local up = Enum.NumericRuleFormatRounding.Up
        fmt:SetBreakpoints({
            { threshold = 0, step = 1, rounding = up, format = "%d" },
            { threshold = 60, format = "%dm", components = { { div = 60, step = 1, rounding = up } } },
            { threshold = 3600, format = "%dh", components = { { div = 3600, step = 1, rounding = up } } },
        })
        return fmt
    end)
    if ok then Formatter = f end
end

---------------------------------------------------------------------------
-- Ein Icon einrichten (läuft in Blizzards initializeFrame)
-- style: "debuff" (Typfarbe), "own" (gold), "other" (dunkel), "otherDim" (dunkel, entsättigt)
---------------------------------------------------------------------------
local function InitButton(btn, style, size)
    btn.border = btn:CreateTexture(nil, "BACKGROUND")
    btn.border:SetAllPoints(btn)
    if style == "debuff" and PreserveAsset and btn.AddDispelTypeTexture then
        btn.border:SetTexture(WHITE)
        btn:AddDispelTypeTexture(btn.border, {
            style = PreserveAsset,
            showWhenHarmful = true, showWhenHelpful = true, showWithoutDispelType = true,
            customDispelColorMap = DISPEL_COLOR_MAP,
        })
    else
        local c = (style == "own") and GOLD_BORDER or DARK_BORDER
        btn.border:SetColorTexture(c[1], c[2], c[3], 1)
    end

    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    btn.Icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if style == "otherDim" then
        btn.Icon:SetDesaturated(true)
        btn.Icon:SetAlpha(0.8)
    end
    btn:SetIcon(btn.Icon)

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn.Icon)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    cd.noCooldownCount = true   -- OmniCC und ähnliche Addons ignorieren das
    cd:SetFrameLevel(btn:GetFrameLevel())
    btn.Cooldown = cd
    btn:SetDurationCooldown(cd)

    -- Schrift vor dem Binden setzen: Blizzard schreibt sofort hinein
    btn.Count = btn:CreateFontString(nil, "OVERLAY")
    btn.Count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    btn.Count:SetPoint("BOTTOMRIGHT", 1, 0)
    btn:SetApplicationCount(btn.Count)

    btn.Time = btn:CreateFontString(nil, "OVERLAY")
    btn.Time:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    btn.Time:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    btn:SetDurationText(btn.Time, Formatter and { textFormatter = Formatter } or nil)

    if btn.SetTooltipAnchorPoint then btn:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT") end
    if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(true) end
    if btn.SetHideTooltipInCombat then btn:SetHideTooltipInCombat(false) end

    PixelUtil.SetSize(btn, size, size)
    btn.fufSize = size
end

---------------------------------------------------------------------------
-- Gruppen je Container. Reihenfolge = Anzeigereihenfolge; Gruppen lassen sich
-- später nicht mehr hinzufügen, nur über die Anzahl (0) abschalten.
---------------------------------------------------------------------------
-- Debuffs Spieler: alle, nach Restzeit
-- Debuffs Ziel:    eigene groß zuerst, fremde klein und entsättigt
-- Buffs:           eigene (gold) zuerst, dann fremde (dunkel)
local GROUPS = {
    playerDebuffs = { { key = "all",   style = "debuff" } },
    targetDebuffs = { { key = "own",   style = "debuff" }, { key = "other", style = "otherDim" } },
    buffs         = { { key = "own",   style = "own" },    { key = "other", style = "other" } },
}

local function CreateContainer(parent, kind, sizeFn)
    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    local effect = (kind == "buffs") and "HELPFUL" or "HARMFUL"
    c.fufKind, c.fufGroups = kind, GROUPS[kind]
    for _, g in ipairs(c.fufGroups) do
        local style = g.style
        c:AddAuraGroup(g.key, effect, {
            initializeFrame = function(btn) InitButton(btn, style, sizeFn(g.key)) end,
            sortMethod = SortMethod.Default,
            sortDirection = SortDirection.Normal,
        })
    end
    c:SetEnabled(false)
    return c
end

---------------------------------------------------------------------------
-- Pro Unit-Frame: zwei Container (Debuffs, Buffs)
---------------------------------------------------------------------------
local function BuffSize(f) return ns.profile[f.key].buffSize or 22 end

local function DebuffSize(f, groupKey)
    if f.isTarget and groupKey == "other" then return SIZE_SMALL end
    return SIZE_BIG
end

-- Legt die Container an (nur außerhalb des Kampfes möglich). true = vorhanden
function ns:EnsureAuraContainers(f)
    if f.ac then return true end
    if f.preview or InCombatLockdown() then return false end
    local ok, err = pcall(function()
        f.ac = {
            debuffs = CreateContainer(f, f.isTarget and "targetDebuffs" or "playerDebuffs",
                function(key) return DebuffSize(f, key) end),
            buffs = CreateContainer(f, "buffs", function() return BuffSize(f) end),
        }
    end)
    if not ok then
        f.ac = nil
        geterrorhandler()(err)
        return false
    end
    return true
end

-- Größe bereits angelegter Icons nachziehen (nur außerhalb des Kampfes, siehe oben)
local function ResizeButtons(c, sizeFn)
    if InCombatLockdown() then return end
    for _, g in ipairs(c.fufGroups) do
        local want = sizeFn(g.key)
        local n = c.GetAuraGroupFrameCount and c:GetAuraGroupFrameCount(g.key) or 0
        for i = 1, n do
            local btn = c:GetAuraGroupFrame(g.key, i)
            if btn and btn.fufSize ~= want then
                if pcall(PixelUtil.SetSize, btn, want, want) then btn.fufSize = want end
            end
        end
    end
end

local function ConfigureGroup(c, key, filter, candidates, max, size, sort)
    c:SetAuraGroupFilterString(key, filter)
    c:SetAuraGroupCandidateFilters(key, candidates or {})
    c:SetAuraGroupMaxFrameCount(key, max)
    if sort then c:SetAuraGroupSortMethod(key, sort, SortDirection.Normal) end
    c:SetAuraGroupLayout(key, {
        elementWidth = size, elementHeight = size,
        elementSpacing = GAP, lineSpacing = ROW_GAP,
    })
end

-- Lage, Filter und Größen aus den Einstellungen (nur außerhalb des Kampfes)
-- debuffAnchor/buffAnchor: die eigenen (leeren) Container aus Frames.lua, die schon richtig liegen
function ns:LayoutAuraContainers(f, auraW)
    if not f.ac or InCombatLockdown() then return end
    local s = ns.profile[f.key]
    local d, b = f.ac.debuffs, f.ac.buffs

    -- Debuffs: unter dem Rahmen, nach rechts und unten
    if f.isTarget then
        ConfigureGroup(d, "own", "HARMFUL|PLAYER", nil, 16, SIZE_BIG)
        ConfigureGroup(d, "other", "HARMFUL|!PLAYER", nil, s.onlyOwnDebuffs and 0 or 16, SIZE_SMALL)
    else
        ConfigureGroup(d, "all", "HARMFUL", nil, 16, SIZE_BIG, SortMethod.Expiration)
    end
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", f.auras, "TOPLEFT", 0, 0)
    d:SetFlowLayoutAnchorPoint("TOPLEFT")
    d:SetFlowLayoutGrowthDirection(Flow.Right, Flow.Down)
    d:SetFlowLayoutMaximumLineSize(auraW)

    -- Buffs: Filter aus den Einstellungen
    local size, max = s.buffSize or 22, s.buffMax or 12
    local filter = s.buffFilter
    local own, other = "HELPFUL|PLAYER", "HELPFUL|!PLAYER"
    local candidates
    if filter == "short" then candidates = { maxDuration = 60 } end
    if filter == "steal" then own, other = "HELPFUL|PLAYER|DISPELLABLE", "HELPFUL|!PLAYER|DISPELLABLE" end
    ConfigureGroup(b, "own", own, candidates, max, size, SortMethod.Expiration)
    ConfigureGroup(b, "other", other, candidates, (filter == "own") and 0 or max, size, SortMethod.Expiration)

    b:ClearAllPoints()
    if s.buffPos == "side" then
        if f.isTarget then
            b:SetPoint("TOPRIGHT", f.buffs, "TOPRIGHT", 0, 0)
            b:SetFlowLayoutAnchorPoint("TOPRIGHT")
            b:SetFlowLayoutGrowthDirection(Flow.Left, Flow.Down)
        else
            b:SetPoint("TOPLEFT", f.buffs, "TOPLEFT", 0, 0)
            b:SetFlowLayoutAnchorPoint("TOPLEFT")
            b:SetFlowLayoutGrowthDirection(Flow.Right, Flow.Down)
        end
        b:SetFlowLayoutMaximumLineSize(4 * (size + GAP))
    elseif s.buffPos == "bottom" then
        -- Die Höhe der Debuffs ist von außen nicht lesbar: Platz für eine Debuff-Reihe lassen
        b:SetPoint("TOPLEFT", f.auras, "TOPLEFT", 0, -(SIZE_BIG + ROW_GAP))
        b:SetFlowLayoutAnchorPoint("TOPLEFT")
        b:SetFlowLayoutGrowthDirection(Flow.Right, Flow.Down)
        b:SetFlowLayoutMaximumLineSize(auraW)
    else -- "top": unterste Reihe sitzt über dem Kasten, mit Platz für die Restzeit
        b:SetPoint("BOTTOMLEFT", f.buffs, "BOTTOMLEFT", 0, ROW_GAP)
        b:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
        b:SetFlowLayoutGrowthDirection(Flow.Right, Flow.Up)
        b:SetFlowLayoutMaximumLineSize(auraW)
    end

    ResizeButtons(d, function(key) return DebuffSize(f, key) end)
    ResizeButtons(b, function() return size end)
end

-- Ein/aus und Einheit setzen (geht auch im Kampf)
-- unitChanged: andere Einheit hinter demselben Token (Zielwechsel). Der Container merkt
-- das nicht von selbst, weil "target" gleich bleibt: dann komplett zurücksetzen,
-- wie ThreatPlates es bei wiederverwendeten Namensplaketten macht.
-- Container von der Einheit lösen. SetUnit mit demselben Token ("target") ignoriert
-- der Container offenbar, daher erst auf eine andere Einheit umhängen ("none", sonst nil).
local function Detach(c)
    pcall(c.SetEnabled, c, false)
    if not pcall(c.SetUnit, c, "none") then pcall(c.SetUnit, c, nil) end
    c.fufUnit = nil
end

local function Attach(c, unit)
    pcall(c.SetUnit, c, unit)
    pcall(c.SetEnabled, c, true)
    c.fufUnit = unit
end

function ns:UpdateAuraContainers(f, unitChanged)
    if not f.ac then return end
    local s = ns.profile[f.key]
    local exists = UnitExists(f.unit)
    for kind, c in pairs(f.ac) do
        local on = exists and ((kind == "debuffs") and s.showDebuffs or (kind == "buffs") and s.showBuffs) and true or false
        if not on then
            c.fufGen = (c.fufGen or 0) + 1   -- ausstehendes Wieder-Einschalten verwerfen
            c.fufPending = nil
            Detach(c)
        elseif unitChanged then
            -- Neues Ziel: sofort leeren, im nächsten Frame neu verbinden. Blizzard wertet
            -- Änderungen gesammelt aus; aus/an im selben Frame käme dort nicht an.
            Detach(c)
            local gen = (c.fufGen or 0) + 1
            c.fufGen = gen
            local unit = f.unit
            c.fufPending = true
            C_Timer.After(0, function()
                if c.fufGen ~= gen then return end
                c.fufPending = nil
                if UnitExists(unit) then Attach(c, unit) end
            end)
        elseif c.fufUnit ~= f.unit and not c.fufPending then
            Attach(c, f.unit)
        end
    end
end

-- Für /ff auras: was der Container kann und wie er steht
function ns:DebugAuraContainers(out)
    for _, unit in ipairs({ "player", "target" }) do
        local fr = ns.frames and ns.frames[unit]
        local ac = fr and fr.ac
        if not ac then
            out("AuraContainer", unit, "nicht angelegt")
        else
            for kind, c in pairs(ac) do
                local counts = {}
                for _, g in ipairs(c.fufGroups) do
                    local ok, n = pcall(c.GetAuraGroupFrameCount, c, g.key)
                    local shown = 0
                    if ok and type(n) == "number" then
                        for i = 1, n do
                            local b = c:GetAuraGroupFrame(g.key, i)
                            if b and b:IsShown() then shown = shown + 1 end
                        end
                    end
                    counts[#counts + 1] = g.key .. "=" .. tostring(n) .. "/" .. shown
                end
                local okU, u = pcall(function() return c.GetUnit and c:GetUnit() end)
                local okE, e = pcall(function() return c.IsEnabled and c:IsEnabled() end)
                out("AuraContainer", unit, kind, "Unit:", okU and u or "?", "an:", okE and e or "?",
                    "sichtbar:", c:IsVisible(), "Icons(angelegt/sichtbar):", table.concat(counts, " "))
            end
            -- Methoden einmal auflisten (Suche nach Refresh/Update o. ä.)
            local c = ac.buffs
            local mt = getmetatable(c)
            local idx = mt and mt.__index
            local names = {}
            if type(idx) == "table" then
                for k, v in pairs(idx) do
                    if type(v) == "function" and type(k) == "string"
                        and (k:find("Aura") or k:find("Unit") or k:find("Update") or k:find("Refresh")
                            or k:find("Enable") or k:find("Dirty") or k:find("Mark")) then
                        names[#names + 1] = k
                    end
                end
            end
            for k, v in pairs(c) do
                if type(v) == "function" and type(k) == "string" then names[#names + 1] = k end
            end
            table.sort(names)
            out("AuraContainer Methoden:", table.concat(names, ", "))
        end
    end
end
