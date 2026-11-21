-- ForeverUnitFrames: Spieler- und Ziel-Frame (Design "Schiefer")
local ADDON, ns = ...
local L = ns.L

local W        = 260   -- Breite des Balkenkastens
local HP_H     = 30
local PW_H     = 7
local PAD      = 2     -- Innenrand oben/unten
local PAD_X    = 1     -- Innenrand links/rechts
local BOX_H    = PAD + HP_H + PAD + PW_H + PAD
local PORTRAIT = 70    -- Startgröße, je Frame einstellbar
local P_OVER   = 12    -- so weit ragt das Portrait ohne Versatz in den Kasten hinein
local TEXT_PAD = 7     -- Abstand der Texte zum Balkenrand
-- Grundgröße je Frame: Skalierung 1 entspricht diesem Faktor (Ziel des Ziels ist kleiner)
local BASE_SCALE = { player = 1, target = 1, targettarget = 0.7 }
local FONT     = STANDARD_TEXT_FONT
local FLAT     = "Interface\\Buttons\\WHITE8X8"
local MASK     = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MEDIA    = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Formen für das Portrait (Masken liegen im Media-Ordner)
ns.PORTRAIT_SHAPES = {
    { "round",   L["Round"] },
    { "square",  L["Square"] },
    { "rounded", L["Rounded"] },
    { "hexagon", L["Hexagon"] },
    { "octagon", L["Octagon"] },
    { "diamond", L["Diamond"] },
}

local REACTION = {
    hostile  = { 0.79, 0.19, 0.17 },
    neutral  = { 0.89, 0.76, 0.23 },
    friendly = { 0.25, 0.70, 0.35 },
    tapped   = { 0.50, 0.50, 0.50 },
}
-- Anzeigenamen der Frames (Platzhalter ohne Einheit, Markierung im Bearbeitungsmodus)
local FRAME_LABEL = {
    player = L["Player"], target = L["Target"], targettarget = L["Target of Target"],
}
local MOVE_LABEL = {
    player = L["ForeverUnitFrames: Player"], target = L["ForeverUnitFrames: Target"],
    targettarget = L["ForeverUnitFrames: Target of Target"],
}

local CLASSIFICATION = {
    elite = L["Elite"], rare = L["Rare"], rareelite = L["Rare Elite"], worldboss = L["Boss"],
}

---------------------------------------------------------------------------
-- Balkentexturen: eingebaute + alles aus LibSharedMedia (falls ein anderes Addon sie mitbringt)
-- { gespeicherter Schlüssel, Pfad, Anzeigename } - Schlüssel bleiben unverändert, damit alte Profile passen
---------------------------------------------------------------------------
local BUILTIN_TEXTURES = {
    { "Flach",            FLAT, L["Flat"] },
    { "Blizzard",         "Interface\\TargetingFrame\\UI-StatusBar" },
    { "Blizzard Raid",    "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { "Glanz",            "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", L["Gloss"] },
}

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- Liste aller Texturen als { name, pfad }
function ns:GetBarTextures()
    local list, seen = {}, {}
    for _, t in ipairs(BUILTIN_TEXTURES) do
        list[#list + 1] = t
        seen[t[1]] = true
    end
    local lsm = LSM()
    if lsm then
        for _, name in ipairs(lsm:List("statusbar")) do
            if not seen[name] then
                list[#list + 1] = { name, lsm:Fetch("statusbar", name) }
                seen[name] = true
            end
        end
    end
    return list
end

function ns:GetBarTexturePath(name)
    for _, t in ipairs(BUILTIN_TEXTURES) do
        if t[1] == name then return t[2] end
    end
    local lsm = LSM()
    if lsm and lsm:IsValid("statusbar", name) then
        return lsm:Fetch("statusbar", name)
    end
    return FLAT
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
local function Abbrev(n)
    if AbbreviateLargeNumbers then return AbbreviateLargeNumbers(n) end
    if n >= 1e6 then return format("%.1fM", n / 1e6) end
    if n >= 1e4 then return format("%.1fk", n / 1e3) end
    return tostring(n)
end

local function Circle(parent, layer, sublevel, size)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetSize(size, size)
    local m = parent:CreateMaskTexture()
    m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

-- Textur mit austauschbarer Formmaske (für Portrait, Ring, Schatten)
local function Shaped(parent, layer, sublevel, size, masks)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetSize(size, size)
    local m = parent:CreateMaskTexture()
    m:SetTexture(MEDIA .. "mask_round", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    masks[#masks + 1] = m
    return t
end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Bar(parent, height)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetHeight(height)
    b:SetStatusBarTexture(FLAT)
    b:SetStatusBarColor(0.35, 0.37, 0.42)   -- neutral, bis echte Werte da sind
    b:SetMinMaxValues(0, 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    -- dunkle untere Hälfte, damit der flache Balken etwas Tiefe bekommt
    b.shade = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.shade:SetPoint("BOTTOMLEFT", b:GetStatusBarTexture(), "BOTTOMLEFT")
    b.shade:SetPoint("BOTTOMRIGHT", b:GetStatusBarTexture(), "BOTTOMRIGHT")
    b.shade:SetHeight(height / 2)
    b.shade:SetColorTexture(0, 0, 0, 0.22)
    return b
end

-- Neuere Clients geben manche Werte als "geheim" zurück: Balken dürfen sie anzeigen,
-- aber Rechnen und Vergleichen damit wirft einen Fehler.
local IsSecret = issecretvalue or function() return false end

-- Gibt nil zurück, wenn der Wert geheim ist (sonst den Wert selbst).
local function Clean(v)
    if IsSecret(v) then return nil end
    return v
end

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
end

local function UnitColor(unit, pct, p)
    if Clean(UnitIsPlayer(unit)) then
        if p.healthColor == "class" then
            local _, class = UnitClass(unit)
            class = Clean(class)
            local c = class and RAID_CLASS_COLORS[class]
            if c then return c.r, c.g, c.b end
        elseif p.healthColor == "custom" then
            local c = p.customColor
            return c.r, c.g, c.b
        end
        -- "health": grün → gelb → rot
        if not pct then return 0.25, 0.70, 0.35 end
        if pct > 0.5 then return (1 - pct) * 2, 0.75, 0.2 end
        return 0.85, pct * 2 * 0.75, 0.2
    end
    if UnitIsTapDenied and Clean(UnitIsTapDenied(unit)) then return unpack(REACTION.tapped) end
    local r = Clean(UnitReaction(unit, "player")) or 4
    if r <= 3 then return unpack(REACTION.hostile) end
    if r == 4 then return unpack(REACTION.neutral) end
    return unpack(REACTION.friendly)
end

local function LevelColor(level)
    if level < 0 then return 1, 0.3, 0.2 end
    local fn = GetCreatureDifficultyColor or GetQuestDifficultyColor
    if fn then
        local c = fn(level)
        return c.r, c.g, c.b
    end
    return 1, 0.82, 0.4
end

---------------------------------------------------------------------------
-- Frame-Objekt
---------------------------------------------------------------------------
local UF = {}

-- Heilung, die gerade auf die Einheit gewirkt wird (von allen Heilern).
-- Die Werte dürfen geheim sein: der Balken zeigt sie trotzdem an.
function UF:UpdateHealPrediction(max)
    local unit = self.unit
    if not UnitExists(unit) or not UnitGetIncomingHeals then
        self.heal:SetValue(0)
        return
    end
    max = max or UnitHealthMax(unit)
    local incoming = SafeCall(UnitGetIncomingHeals, unit)
    -- geheime Werte nicht auf nil prüfen (das wäre ein Vergleich), sondern direkt nutzen
    if not IsSecret(incoming) and not incoming then incoming = 0 end
    SafeCall(self.heal.SetMinMaxValues, self.heal, 0, max)
    SafeCall(self.heal.SetValue, self.heal, incoming)
end

function UF:UpdateHealth()
    local unit = self.unit
    if not UnitExists(unit) then
        self.hp:SetMinMaxValues(0, 1)
        self.hp:SetValue(1)
        self.hp:SetStatusBarColor(0.35, 0.37, 0.42)
        self.hpText:SetText("")
        self.heal:SetValue(0)
        return
    end

    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    self.hp:SetMinMaxValues(0, max)
    self.hp:SetValue(cur)
    self:UpdateHealPrediction(max)

    local secret = IsSecret(cur) or IsSecret(max)
    local pct
    if not secret then pct = (max > 0) and (cur / max) or 0 end
    local s = ns.profile[self.key]
    self.hp:SetStatusBarColor(UnitColor(unit, pct, s))

    local mode, txt = s.textMode, ""
    if Clean(UnitIsDeadOrGhost(unit)) then
        txt = Clean(UnitIsGhost(unit)) and L["Ghost"] or L["Dead"]
    elseif Clean(UnitIsPlayer(unit)) and Clean(UnitIsConnected(unit)) == false then
        txt = L["Offline"]
    elseif mode ~= "none" then
        local valStr, maxStr, pctStr
        if secret then
            valStr = SafeCall(AbbreviateLargeNumbers, cur)
            maxStr = SafeCall(AbbreviateLargeNumbers, max)
            if UnitHealthPercent then
                pctStr = SafeCall(function()
                    local curve = CurveConstants and CurveConstants.ScaleTo100
                    return format("%.0f%%", UnitHealthPercent(unit, true, curve))
                end)
            end
        else
            valStr, maxStr = Abbrev(cur), Abbrev(max)
            pctStr = math.floor(pct * 100 + 0.5) .. "%"
        end
        txt = SafeCall(function()
            if mode == "both" then
                if valStr and pctStr then return valStr .. " · " .. pctStr end
                return valStr or pctStr or ""
            elseif mode == "pct" then
                return pctStr or ""
            else
                if valStr and maxStr then return valStr .. " / " .. maxStr end
                return valStr or ""
            end
        end) or ""
    end
    SafeCall(self.hpText.SetText, self.hpText, txt)
end

function UF:UpdatePower()
    local unit = self.unit
    if not UnitExists(unit) then
        self.pw:SetMinMaxValues(0, 1); self.pw:SetValue(0)
        return
    end
    local ptype, token = UnitPowerType(unit)
    self.pw:SetMinMaxValues(0, UnitPowerMax(unit, ptype))
    self.pw:SetValue(UnitPower(unit, ptype))
    token, ptype = Clean(token), Clean(ptype)
    local c = (token and PowerBarColor[token]) or (ptype and PowerBarColor[ptype]) or { r = 0.2, g = 0.4, b = 0.85 }
    self.pw:SetStatusBarColor(c.r, c.g, c.b)
end

function UF:UpdateName()
    local unit = self.unit
    if UnitExists(unit) then
        self.nameText:SetText(UnitName(unit))
    else
        self.nameText:SetText(self.isTarget and FRAME_LABEL[self.key] or "")
    end
end

function UF:UpdateMeta()
    local unit = self.unit
    if not UnitExists(unit) then
        self.metaLeft:SetText(""); self.metaRight:SetText(""); self.levelText:SetText("")
        return
    end
    -- In Instanzen können Level, Klasse, Kreaturtyp usw. "geheim" sein:
    -- solche Werte lassen wir weg statt mit ihnen zu rechnen/zu verketten.
    local level = Clean(UnitLevel(unit))
    local lr, lg, lb
    local lvlStr
    if level then
        lr, lg, lb = LevelColor(level)
        lvlStr = level < 0 and "??" or tostring(level)
    else
        lr, lg, lb = 1, 0.82, 0.4
        lvlStr = "??"
    end
    local lvlHex = format("|cff%02x%02x%02x", lr * 255, lg * 255, lb * 255)

    local parts = {}
    if not self.portraitOn then parts[#parts + 1] = lvlHex .. lvlStr .. "|r" end
    local clsKey = Clean(UnitClassification(unit))
    local cls = clsKey and CLASSIFICATION[clsKey]
    if cls then parts[#parts + 1] = cls end
    if Clean(UnitIsPlayer(unit)) then
        local className = Clean((UnitClass(unit)))
        if className then parts[#parts + 1] = className end
    else
        local ctype = Clean(UnitCreatureType(unit))
        if ctype then parts[#parts + 1] = ctype end
    end
    self.metaLeft:SetText(table.concat(parts, " · "))

    self.levelText:SetText(lvlStr)
    self.levelText:SetTextColor(lr, lg, lb)

    if self.isTarget then
        if Clean(UnitIsDead(unit)) then
            self.metaRight:SetText("|cff999999" .. L["dead"] .. "|r")
        elseif Clean(UnitIsPlayer(unit)) and Clean(UnitIsFriend("player", unit)) then
            self.metaRight:SetText("")
        else
            local r = Clean(UnitReaction(unit, "player")) or 4
            if r <= 3 then self.metaRight:SetText("|cffc9302c" .. L["hostile"] .. "|r")
            elseif r == 4 then self.metaRight:SetText("|cffe3c23a" .. L["neutral"] .. "|r")
            else self.metaRight:SetText("|cff40b35a" .. L["friendly"] .. "|r") end
        end
    else
        self.metaRight:SetText(Clean(UnitAffectingCombat("player")) and "|cffe0675a" .. L["Combat"] .. "|r" or "")
    end
end

function UF:UpdatePortrait()
    if self.portraitOn and UnitExists(self.unit) then
        SetPortraitTexture(self.portrait, self.unit)
    end
end

function UF:UpdateMarker()
    local idx = UnitExists(self.unit) and Clean(GetRaidTargetIndex(self.unit))
    if idx then
        SetRaidTargetIconTexture(self.marker, idx)
        self.marker:Show()
    else
        self.marker:Hide()
    end
end

-- PvP-Symbol: Wappen der Fraktion bzw. FFA-Symbol
local PVP_ICON = {
    Alliance = { atlas = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", file = "Interface\\TargetingFrame\\UI-PVP-Alliance" },
    Horde    = { atlas = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",    file = "Interface\\TargetingFrame\\UI-PVP-Horde" },
    FFA      = { atlas = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",      file = "Interface\\TargetingFrame\\UI-PVP-FFA" },
}
local PVP_H = 28

function UF:SetPvPIcon(kind)
    local t, icon = self.pvp, kind and PVP_ICON[kind]
    if not icon or not ns.profile[self.key].showPvP then
        t:Hide()
        return
    end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon.atlas)
    if info and info.height and info.height > 0 then
        t:SetAtlas(icon.atlas, false)
        t:SetSize(PVP_H * info.width / info.height, PVP_H)
    else
        -- ältere Clients: alte Grafik, das Wappen sitzt oben links in der 64er-Textur
        t:SetTexture(icon.file)
        t:SetTexCoord(0, 0.62, 0, 0.62)
        t:SetSize(PVP_H, PVP_H)
    end
    t:Show()
end

function UF:UpdatePvP()
    local unit, kind = self.unit, nil
    if UnitExists(unit) then
        -- in Instanzen können diese Abfragen geheim sein: dann kein Symbol
        if Clean(UnitIsPVPFreeForAll(unit)) then
            kind = "FFA"
        elseif Clean(UnitIsPVP(unit)) then
            local faction = Clean(UnitFactionGroup(unit))
            if faction == "Alliance" or faction == "Horde" then kind = faction end
        end
    end
    self:SetPvPIcon(kind)
end

function UF:UpdateAuras()
    local s = ns.profile[self.key]
    local unitChanged = self.unitChanged
    self.unitChanged = nil
    -- Bevorzugt Blizzards AuraContainer (AuraContainers.lua): der darf Auren auch im Kampf
    -- zeigen. Die eigenen Icons bleiben nur als Rückfall, falls der Client ihn nicht kennt.
    local own = true
    if not self.preview and ns.EnsureAuraContainers then
        local fresh = not self.ac
        if ns:EnsureAuraContainers(self) then
            own = false
            if fresh and self.auraW then ns:LayoutAuraContainers(self, self.auraW) end
            ns:UpdateAuraContainers(self, unitChanged)
        end
    end
    self.auras:Update({ enabled = own and s.showDebuffs, onlyOwn = s.onlyOwnDebuffs, max = 16 })
    self.buffs:Update({
        enabled = own and s.showBuffs, filter = s.buffFilter, size = s.buffSize,
        max = s.buffMax, highlightSteal = s.buffSteal,
    })
end

-- Jeder Teil einzeln abgesichert, damit ein Fehler nicht den ganzen Frame lahmlegt
function UF:Run(method)
    ns.Try(self[method], self)
end

---------------------------------------------------------------------------
-- Vorschau in den Einstellungen: gleicher Frame, aber mit Beispieldaten
---------------------------------------------------------------------------
local ICON = "Interface\\Icons\\"
local SAMPLE = {
    player = {
        pct = 0.86, power = 0.64, powerToken = "MANA",   -- Name und Level kommen vom eigenen Charakter
        buffs = {
            { name = L["Mark of the Wild"], icon = ICON .. "Spell_Nature_Regeneration", own = true, duration = 1800, rem = 1500 },
            { name = L["Rejuvenation"], icon = ICON .. "Spell_Nature_Rejuvenation", own = true, duration = 12, rem = 8 },
            { name = L["Power Word: Fortitude"], icon = ICON .. "Spell_Holy_WordFortitude", own = false, duration = 1800, rem = 900 },
            { name = L["Power Word: Shield"], icon = ICON .. "Spell_Holy_PowerWordShield", own = false, duration = 30, rem = 21 },
        },
        debuffs = {
            { name = L["Curse of Weakness"], icon = ICON .. "Spell_Shadow_CurseOfMannoroth", dispelName = "Curse", duration = 120, rem = 74 },
            { name = L["Poison"], icon = ICON .. "Ability_Rogue_DualWeild", dispelName = "Poison", duration = 15, rem = 6, applications = 3 },
        },
    },
    target = {
        name = L["Warchief Grimhoof"], level = 62, pct = 0.72, power = 1, powerToken = "RAGE",
        classification = L["Elite"], ctype = L["Humanoid"], marker = 8,
        portraitIcon = ICON .. "INV_Misc_Head_Orc_01",
        buffs = {
            { name = L["Battle Shout"], icon = ICON .. "Ability_Warrior_BattleShout", own = false, duration = 120, rem = 95 },
            { name = L["Mage Armor"], icon = ICON .. "Spell_Frost_FrostArmor02", own = false, duration = 1800, rem = 1200, dispelName = "Magic", isStealable = true },
            { name = L["Enrage"], icon = ICON .. "Ability_Druid_ChallangingRoar", own = false, duration = 10, rem = 4 },
        },
        debuffs = {
            { name = L["Rake"], icon = ICON .. "Ability_Druid_Disembowel", own = true, duration = 9, rem = 6 },
            { name = L["Faerie Fire"], icon = ICON .. "Spell_Nature_FaerieFire", own = true, duration = 40, rem = 31, dispelName = "Magic" },
            { name = L["Sunder Armor"], icon = ICON .. "Ability_Warrior_Sunder", own = false, duration = 30, rem = 22, applications = 5 },
            { name = L["Shadow Word: Pain"], icon = ICON .. "Spell_Shadow_ShadowWordPain", own = false, duration = 18, rem = 11, dispelName = "Magic" },
        },
    },
    -- Ziel des Ziels: der Gegner hat dich im Visier (Name und Level vom eigenen Charakter)
    targettarget = {
        pct = 0.54, power = 0.40, powerToken = "MANA", friendly = true,
        buffs = {
            { name = L["Power Word: Fortitude"], icon = ICON .. "Spell_Holy_WordFortitude", own = false, duration = 1800, rem = 900 },
            { name = L["Rejuvenation"], icon = ICON .. "Spell_Nature_Rejuvenation", own = true, duration = 12, rem = 8 },
        },
        debuffs = {
            { name = L["Curse of Weakness"], icon = ICON .. "Spell_Shadow_CurseOfMannoroth", own = false, dispelName = "Curse", duration = 120, rem = 74 },
            { name = L["Sunder Armor"], icon = ICON .. "Ability_Warrior_Sunder", own = false, duration = 30, rem = 22, applications = 2 },
        },
    },
}

function UF:PreviewUpdate()
    local s, d = ns.profile[self.key], SAMPLE[self.key]

    -- Leben
    self.hp:SetMinMaxValues(0, 1)
    self.hp:SetValue(d.pct)
    self.heal:SetMinMaxValues(0, 1)
    self.heal:SetValue(self.isTarget and 0 or 0.15)   -- Beispiel: Heilung unterwegs
    local hostile = self.isTarget and not d.friendly
    if hostile then
        self.hp:SetStatusBarColor(unpack(REACTION.hostile))
    else
        self.hp:SetStatusBarColor(UnitColor("player", d.pct, s))
    end
    local pct = math.floor(d.pct * 100 + 0.5) .. "%"
    local cur, max = Abbrev(math.floor(d.pct * 18400)), Abbrev(18400)
    local mode = s.textMode
    self.hpText:SetText(mode == "both" and (cur .. " · " .. pct) or mode == "pct" and pct
        or mode == "val" and (cur .. " / " .. max) or "")

    -- Ressource
    self.pw:SetMinMaxValues(0, 1)
    self.pw:SetValue(d.power)
    local c = PowerBarColor[d.powerToken] or { r = 0.2, g = 0.4, b = 0.85 }
    self.pw:SetStatusBarColor(c.r, c.g, c.b)

    -- Name, Level, Zeile darunter
    local name = d.name or UnitName("player")
    local level = d.level or UnitLevel("player")
    self.nameText:SetText(name)
    local lr, lg, lb = LevelColor(level)
    self.levelText:SetText(level)
    self.levelText:SetTextColor(lr, lg, lb)
    local parts = {}
    if not self.portraitOn then parts[#parts + 1] = format("|cff%02x%02x%02x%d|r", lr * 255, lg * 255, lb * 255, level) end
    if d.classification then parts[#parts + 1] = d.classification end
    parts[#parts + 1] = d.ctype or (UnitClass("player"))
    self.metaLeft:SetText(table.concat(parts, " · "))
    self.metaRight:SetText(hostile and ("|cffc9302c" .. L["hostile"] .. "|r") or "")

    -- Portrait: eigenes Bild bzw. echtes Ziel, sonst Beispielbild
    if self.portraitOn then
        if not self.isTarget then
            SetPortraitTexture(self.portrait, "player")
        elseif UnitExists(self.unit) then
            SetPortraitTexture(self.portrait, self.unit)
        elseif d.portraitIcon then
            self.portrait:SetTexture(d.portraitIcon)
            self.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            SetPortraitTexture(self.portrait, "player")
        end
    end

    -- Marker
    if d.marker then
        SetRaidTargetIconTexture(self.marker, d.marker)
        self.marker:Show()
    else
        self.marker:Hide()
    end

    -- PvP: eigene Fraktion, beim Ziel die andere
    local faction = UnitFactionGroup("player")
    if hostile then
        faction = (faction == "Horde") and "Alliance" or (faction == "Alliance") and "Horde" or "FFA"
    end
    self:SetPvPIcon(PVP_ICON[faction] and faction or "FFA")

    -- Auren mit Beispieldaten
    self.auras:Update({ enabled = s.showDebuffs, onlyOwn = s.onlyOwnDebuffs, max = 16, sample = d.debuffs })
    self.buffs:Update({
        enabled = s.showBuffs, filter = s.buffFilter, size = s.buffSize, max = s.buffMax,
        highlightSteal = s.buffSteal, sample = d.buffs, sampleHostile = self.isTarget,
    })
end

---------------------------------------------------------------------------
-- Drachen-Ornament (originale Blizzard-Grafiken)
---------------------------------------------------------------------------
-- Mögliche Atlas-Namen je Art, der erste vorhandene wird genommen
local ORN_ATLAS = {
    elite     = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold" },
    worldboss = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold" },
    rareelite = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver" },
    -- "rare" bewusst nicht: Blizzard zeigt dafür nur einen kleinen Stern
}
local BLIZZ_PORTRAIT = 60     -- ungefähre Portraitgröße, für die Blizzard die Drachen gezeichnet hat
local ornCache, ornWarned = {}, false

local function OrnamentInfo(kind)
    if not ORN_ATLAS[kind] then return nil end   -- z. B. alte Einstellung "rare": einfach nichts zeigen
    if ornCache[kind] ~= nil then return ornCache[kind] or nil end
    local found = false
    if C_Texture and C_Texture.GetAtlasInfo then
        for _, name in ipairs(ORN_ATLAS[kind] or {}) do
            local info = C_Texture.GetAtlasInfo(name)
            if info and info.file then found = info break end
        end
    end
    ornCache[kind] = found
    if not found and not ornWarned then
        ornWarned = true
        print("|cffd8a64aForeverUnitFrames:|r " .. format(L["Dragon artwork not found (%s). Please report."], kind))
    end
    return found or nil
end

local CLASS_TO_ORN = { elite = "elite", worldboss = "worldboss", rareelite = "rareelite" }

function UF:UpdateOrnament()
    local s = ns.profile[self.key]
    local kind = s.ornament
    if kind == "auto" then
        if self.preview then
            kind = "elite"
        else
            local cls = UnitExists(self.unit) and Clean(UnitClassification(self.unit))
            kind = cls and CLASS_TO_ORN[cls] or nil
        end
    end
    local info = kind and kind ~= "none" and OrnamentInfo(kind)
    if not info then
        self.ornament:Hide()
        return
    end

    local t = self.ornament
    t:SetTexture(info.file)
    -- Blizzard zeichnet die Drachen für ein Portrait rechts; links (Spieler) wird gespiegelt
    if self.portraitRight then
        t:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
    else
        t:SetTexCoord(info.rightTexCoord, info.leftTexCoord, info.topTexCoord, info.bottomTexCoord)
    end

    -- Größe folgt allein dem Portrait. Auch der Versatz wird mitskaliert,
    -- damit der Drache bei jeder Portraitgröße an derselben Stelle sitzt.
    local size = s.portrait and (s.portraitSize or PORTRAIT) or BLIZZ_PORTRAIT
    local f = size / BLIZZ_PORTRAIT
    t:SetSize(info.width * f, info.height * f)

    -- Mitte auf das Portrait (bzw. ohne Portrait auf die Außenkante); X positiv = nach außen
    local ox = (s.ornX or 0) * f * (self.portraitRight and 1 or -1)
    local oy = (s.ornY or 0) * f
    t:ClearAllPoints()
    if s.portrait then
        t:SetPoint("CENTER", self.portraitFrame, "CENTER", ox, oy)
    else
        t:SetPoint("CENTER", self.box, self.portraitRight and "RIGHT" or "LEFT", ox, oy)
    end
    t:Show()
end

function UF:UpdateAll()
    if self.preview then
        ns.Try(self.PreviewUpdate, self)
        ns.Try(self.UpdateOrnament, self)
        return
    end
    self:Run("UpdateHealth")
    self:Run("UpdatePower")
    self:Run("UpdateName")
    self:Run("UpdateMeta")
    self:Run("UpdatePortrait")
    self:Run("UpdateMarker")
    self:Run("UpdatePvP")
    self:Run("UpdateAuras")
    self:Run("UpdateOrnament")
end

function UF:SetPortraitShape(shape)
    local path = MEDIA .. "mask_" .. (shape or "round")
    for _, m in ipairs(self.pMasks) do
        m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
end

function UF:LayoutPortrait(size)
    self.portraitFrame:SetSize(size + 6, size + 6)
    self.pShadow:SetSize(size + 6, size + 6)
    self.pRing:SetSize(size + 3, size + 3)
    self.pInner:SetSize(size, size)
    self.portrait:SetSize(size - 2, size - 2)
end

-- Nur außerhalb des Kampfes aufrufen (Größe, Position, Sichtbarkeit)
function UF:ApplySettings()
    local s = ns.profile[self.key]
    self.portraitOn = s.portrait

    local scale = s.scale or 1
    self:SetScale(scale * (BASE_SCALE[self.key] or 1))
    if not self.preview then
        self:ClearAllPoints()
        self:SetPoint(s.point, UIParent, s.point, s.x, s.y)
    end

    -- Balkengröße: Prozentwert wird zur Skalierung addiert (1,2 und -20 % = 1,0).
    -- Der Frame ist schon mit der Skalierung vergrößert, daher hier durch sie teilen.
    -- Der Kasten passt sich dem breiteren Balken an, der schmalere sitzt mittig.
    local function Pct(v) return math.max(0.1, scale + (v or 0) / 100) / scale end
    local barW = W - 2 * PAD_X
    local hpW = math.floor(barW * Pct(s.hpWidth) + 0.5)
    local pwW = math.floor(barW * Pct(s.pwWidth) + 0.5)
    local hpH = math.max(6, math.floor(HP_H * Pct(s.hpHeight) + 0.5))
    local pwH = math.max(2, math.floor(PW_H * Pct(s.pwHeight) + 0.5))
    local w = math.max(hpW, pwW) + 2 * PAD_X
    local h = PAD + hpH + PAD + pwH + PAD
    self.box:SetSize(w, h)
    self.hp:SetSize(hpW, hpH)
    self.pw:SetSize(pwW, pwH)
    -- Schrift im Lebensbalken wächst mit dessen Höhe (Standardhöhe = 12)
    local fontSize = math.max(8, math.min(20, math.floor(12 * hpH / HP_H + 0.5)))
    self.nameText:SetFont(FONT, fontSize, "")
    self.hpText:SetFont(FONT, fontSize, "")

    -- Portrait: Größe und Versatz (X positiv = weiter nach außen, Y positiv = nach oben)
    local size = s.portraitSize or PORTRAIT
    local offX, offY = s.portraitX or 0, s.portraitY or 0
    local overlap = s.portrait and math.max(0, P_OVER - offX) or 0
    local extra = s.portrait and math.max(0, size + 6 - overlap) or 0
    self:SetSize(w + extra, h)
    self:LayoutPortrait(size)
    self:SetPortraitShape(s.portraitShape)

    -- Kasten liegt auf der dem Portrait abgewandten Seite
    self.box:ClearAllPoints()
    if self.portraitRight then
        self.box:SetPoint("TOPLEFT")
    else
        self.box:SetPoint("TOPRIGHT")
    end

    -- Textur und Schattierung
    local tex = ns:GetBarTexturePath(s.barTexture)
    for _, bar in ipairs({ self.hp, self.pw }) do
        bar:SetStatusBarTexture(tex)
        local fill = bar:GetStatusBarTexture()
        fill:SetHorizTile(false); fill:SetVertTile(false)
        bar.shade:ClearAllPoints()
        bar.shade:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
        bar.shade:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
        bar.shade:SetHeight(bar:GetHeight() / 2)
        bar.shade:SetShown(s.barShade)
    end
    self.heal:SetStatusBarTexture(tex)
    self.heal:GetStatusBarTexture():SetHorizTile(false)
    self.heal:SetShown(s.showHealPrediction ~= false)
    -- Anker neu setzen, falls SetStatusBarTexture ein neues Füllobjekt erzeugt hat
    local hpFill = self.hp:GetStatusBarTexture()
    self.heal:ClearAllPoints()
    self.heal:SetPoint("TOPLEFT", hpFill, "TOPRIGHT")
    self.heal:SetPoint("BOTTOMLEFT", hpFill, "BOTTOMRIGHT")

    -- Balken laufen bis an den Rand, das Portrait liegt leicht darüber
    -- Balken an der Portrait-Seite ausrichten: Ein schmalerer Balken endet dann außen,
    -- statt eine Lücke zwischen Portrait und Balken zu lassen
    local barSide = self.portraitRight and "RIGHT" or "LEFT"
    local sx = self.portraitRight and -PAD_X or PAD_X
    self.hp:ClearAllPoints()
    self.hp:SetPoint("TOP" .. barSide, self.box, "TOP" .. barSide, sx, -PAD)
    self.pw:ClearAllPoints()
    self.pw:SetPoint("BOTTOM" .. barSide, self.box, "BOTTOM" .. barSide, sx, PAD)

    -- nur die Texte rücken auf der Portrait-Seite ein
    local leftIn  = self.portraitRight and 0 or overlap
    local rightIn = self.portraitRight and overlap or 0
    self.hpText:ClearAllPoints()
    self.hpText:SetPoint("RIGHT", self.hp, "RIGHT", -(TEXT_PAD + rightIn), 0)
    self.nameText:ClearAllPoints()
    self.nameText:SetPoint("LEFT", self.hp, "LEFT", TEXT_PAD + leftIn, 0)
    self.nameText:SetPoint("RIGHT", self.hpText, "LEFT", -8, 0)
    self.metaLeft:ClearAllPoints()
    -- am Kasten statt am Ressourcenbalken, damit die Zeile auch bei schmalem Balken bündig bleibt
    self.metaLeft:SetPoint("TOPLEFT", self.box, "BOTTOMLEFT", PAD_X + leftIn, PAD - 6)
    self.metaRight:ClearAllPoints()
    self.metaRight:SetPoint("TOPRIGHT", self.box, "BOTTOMRIGHT", -(PAD_X + rightIn), PAD - 6)

    -- Debuffs unter dem Frame, auf der Portrait-Seite eingerückt
    local auraW = math.max(40, w - overlap)
    self.auraW = auraW
    self.auras:ClearAllPoints()
    self.auras:SetWidthPx(auraW)
    self.auras:SetPoint("TOPLEFT", self.box, "BOTTOMLEFT", leftIn, -22)

    -- Buffs: über dem Frame, unter den Debuffs oder neben dem Frame (zur Bildschirmmitte hin)
    local b = self.buffs
    b:ClearAllPoints()
    if s.buffPos == "side" then
        b:SetWidthPx(4 * ((s.buffSize or 22) + 4))
        b:SetGrowth(self.portraitRight, false)
        if self.portraitRight then
            b:SetPoint("TOPRIGHT", self.box, "TOPLEFT", -8, 0)
        else
            b:SetPoint("TOPLEFT", self.box, "TOPRIGHT", 8, 0)
        end
    elseif s.buffPos == "bottom" then
        b:SetWidthPx(auraW)
        b:SetGrowth(false, false)
        b:SetPoint("TOPLEFT", self.auras, "BOTTOMLEFT", 0, -6)
    else -- "top"
        b:SetWidthPx(auraW)
        b:SetGrowth(false, true)
        -- Unterkante des Containers = Oberkante des Kastens; die unterste Reihe sitzt
        -- darüber mit Platz für die Restzeit
        b:SetPoint("BOTTOMLEFT", self.box, "TOPLEFT", leftIn, 0)
    end

    self.portraitFrame:SetShown(s.portrait)
    self.portraitFrame:ClearAllPoints()
    if self.portraitRight then
        self.portraitFrame:SetPoint("LEFT", self.box, "RIGHT", -P_OVER + offX, offY)
    else
        self.portraitFrame:SetPoint("RIGHT", self.box, "LEFT", P_OVER - offX, offY)
    end

    -- PvP-Symbol: obere Außenecke des Portraits, ohne Portrait an der Außenkante des Kastens
    self.pvp:ClearAllPoints()
    local side = self.portraitRight and "TOPRIGHT" or "TOPLEFT"
    if s.portrait then
        self.pvp:SetPoint("CENTER", self.portraitFrame, side, self.portraitRight and -6 or 6, -6)
    else
        self.pvp:SetPoint("CENTER", self.box, side, self.portraitRight and 4 or -4, 0)
    end

    -- Sichtbarkeit / Verschieben
    local locked = not ns:IsUnlocked()
    self.moveOverlay:SetShown(not locked and not self.preview)
    if self.isTarget and not self.preview then
        if locked then
            RegisterUnitWatch(self)
        else
            UnregisterUnitWatch(self)
            self:Show()
        end
    end
    -- Blizzards AuraContainer an dieselben Stellen wie die eigenen Icons legen
    if not self.preview and ns.EnsureAuraContainers and ns:EnsureAuraContainers(self) then
        ns:LayoutAuraContainers(self, self.auraW)
    end
    self:UpdateAll()
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------
local function OnEvent(self, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH_FREQUENT" then
        self:Run("UpdateHealth")
    elseif event == "UNIT_HEAL_PREDICTION" then
        self:Run("UpdateHealPrediction")
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        self:Run("UpdatePower")
    elseif event == "UNIT_AURA" then
        self:Run("UpdateAuras")
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
        self:Run("UpdatePortrait")
    elseif event == "UNIT_NAME_UPDATE" then
        self:Run("UpdateName")
    elseif event == "RAID_TARGET_UPDATE" then
        self:Run("UpdateMarker")
    elseif event == "PLAYER_FLAGS_CHANGED" then
        self:Run("UpdatePvP")
    elseif event == "UNIT_LEVEL" or event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        self:Run("UpdateMeta")
        if event == "UNIT_FACTION" then self:Run("UpdateHealth"); self:Run("UpdatePvP") end
        if event == "UNIT_CLASSIFICATION_CHANGED" then self:Run("UpdateOrnament") end
        if event == "PLAYER_REGEN_ENABLED" then
            -- nach dem Kampf wieder lesbar; kurz danach noch einmal, falls die Sperre nachläuft
            self:Run("UpdateAuras")
            C_Timer.After(1, function() self:Run("UpdateAuras") end)
        end
    else -- PLAYER_TARGET_CHANGED, PLAYER_ENTERING_WORLD
        -- andere Einheit: alte Auren nie stehen lassen
        self.unitChanged = true
        if self.auras then self.auras:Invalidate() end
        if self.buffs then self.buffs:Invalidate() end
        self:UpdateAll()
    end
end

local function SafeRegisterUnit(f, event, unit)
    -- Manche Events gibt es nicht in jeder Client-Version
    pcall(f.RegisterUnitEvent, f, event, unit)
end

local function BuildVisuals(f, unit) end   -- wird unten definiert

local function CreateUnitFrame(key, unit, name, previewParent)
    if previewParent then
        -- Vorschau: normaler Frame ohne Klicks, Events und Kampfsperre
        local f = CreateFrame("Frame", nil, previewParent)
        for k, v in pairs(UF) do f[k] = v end
        f.key, f.unit, f.isTarget, f.preview = key, unit, (unit ~= "player"), true
        f.portraitRight = (unit == "target")   -- nur das Ziel hat das Portrait rechts
        BuildVisuals(f, unit)
        return f
    end

    local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    for k, v in pairs(UF) do f[k] = v end
    f.key, f.unit, f.isTarget = key, unit, (unit ~= "player")
    f.portraitRight = (unit == "target")   -- Ziel des Ziels ist angeordnet wie der Spieler

    f:SetAttribute("unit", unit)
    f:SetAttribute("type1", "target")
    f:SetAttribute("type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ns:IsUnlocked() and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        ns.Try(ns.SnapAndSave, ns, self)
    end)
    f:SetScript("OnEnter", function(self)
        if not UnitExists(self.unit) then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    BuildVisuals(f, unit)

    -- Events
    for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
        "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_AURA", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
        "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_FLAGS_CHANGED" }) do
        SafeRegisterUnit(f, ev, unit)
    end
    f:RegisterEvent("RAID_TARGET_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")   -- nach dem Kampf Auren neu lesen
    if f.isTarget then
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
    if unit == "targettarget" then
        -- Das Ziel wechselt sein Ziel: neue Einheit hinter "targettarget"
        SafeRegisterUnit(f, "UNIT_TARGET", "target")
        -- Für "targettarget" schickt der Client keine UNIT_*-Events (Leben, Ressource, Auren):
        -- wie Blizzards eigener Frame regelmäßig nachfragen, solange er sichtbar ist.
        f.pollElapsed, f.auraElapsed = 0, 0
        f:SetScript("OnUpdate", function(self, el)
            self.pollElapsed = self.pollElapsed + el
            if self.pollElapsed < 0.2 then return end
            self.auraElapsed = self.auraElapsed + self.pollElapsed
            self.pollElapsed = 0
            if not UnitExists(self.unit) then return end
            -- andere Einheit (falls die GUID lesbar ist): alles neu, wie bei einem Zielwechsel
            local guid = UnitGUID(self.unit)
            if not IsSecret(guid) and guid ~= self.lastGUID then
                self.lastGUID = guid
                OnEvent(self, "UNIT_TARGET", "target")
                return
            end
            self:Run("UpdateHealth")
            self:Run("UpdatePower")
            self:Run("UpdateName")
            self:Run("UpdateMeta")
            self:Run("UpdateMarker")
            self:Run("UpdatePvP")
            if self.auraElapsed >= 1 then
                self.auraElapsed = 0
                -- Auren-Container neu verbinden, damit er die Auren frisch einliest
                self.unitChanged = true
                self:Run("UpdateAuras")
            end
        end)
    end
    f:SetScript("OnEvent", OnEvent)
    return f
end

-- Alles Sichtbare eines Frames (für echte Frames und die Vorschau)
BuildVisuals = function(f, unit)
    -- Kasten mit 1px-Kante
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(W, BOX_H)
    f.box = box
    f.hp = Bar(box, HP_H)
    f.pw = Bar(box, PW_H)

    -- Hintergrund mit 1px-Kante je Balken: Sind die Balken verschieden breit, ergibt das
    -- eine gestufte Form statt einer schwarzen Lücke. Alle Kanten liegen unter allen
    -- schwarzen Flächen, sodass innen keine Kantenlinie zwischen den Balken sichtbar ist.
    -- (Bei gleicher Breite sieht das genauso aus wie der frühere einzelne Kasten.)
    local function Backing(bar, top, bottom)
        local edge = box:CreateTexture(nil, "BACKGROUND", nil, -2)
        edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -PAD_X - 1, top + 1)
        edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", PAD_X + 1, -bottom - 1)
        edge:SetColorTexture(0.23, 0.25, 0.30, 1)
        local bg = box:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -PAD_X, top)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", PAD_X, -bottom)
        bg:SetColorTexture(0, 0, 0, 1)
    end
    Backing(f.hp, PAD, PAD)   -- deckt auch den Spalt zwischen den Balken ab
    Backing(f.pw, 0, PAD)

    -- Eingehende Heilung: eigener Balken, der direkt an der Kante der Lebensfüllung
    -- beginnt und so breit ist wie der ganze Lebensbalken. Mit denselben Min/Max-Werten
    -- entspricht seine Füllung genau der Heilmenge. So kommt man ohne Rechnen aus,
    -- was mit geheimen Werten wichtig ist. Was über das Maximum hinausgeht, wird abgeschnitten.
    f.hp:SetClipsChildren(true)
    local heal = CreateFrame("StatusBar", nil, f.hp)
    heal:SetFrameLevel(f.hp:GetFrameLevel() + 1)
    heal:SetStatusBarTexture(FLAT)
    heal:SetStatusBarColor(0.35, 0.95, 0.45, 0.45)
    heal:SetMinMaxValues(0, 1)
    heal:SetValue(0)
    local hpFill = f.hp:GetStatusBarTexture()
    heal:SetPoint("TOPLEFT", hpFill, "TOPRIGHT")
    heal:SetPoint("BOTTOMLEFT", hpFill, "BOTTOMRIGHT")
    heal:SetWidth(W)
    f.hp:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then heal:SetWidth(w) end end)
    f.heal = heal

    local textLayer = CreateFrame("Frame", nil, f.hp)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(f.hp:GetFrameLevel() + 2)
    f.nameText = Text(textLayer, 12, "LEFT")
    f.nameText:SetPoint("LEFT", 7, 0)
    f.hpText = Text(textLayer, 12, "RIGHT")
    f.hpText:SetPoint("RIGHT", -7, 0)
    f.nameText:SetPoint("RIGHT", f.hpText, "LEFT", -8, 0)

    -- Zeile unter dem Kasten
    f.metaLeft = Text(f, 11, "LEFT")
    -- an den Balken ausgerichtet, damit die Zeile mit dem Portrait mitrückt
    f.metaLeft:SetPoint("TOPLEFT", f.pw, "BOTTOMLEFT", 0, -6)
    f.metaLeft:SetTextColor(0.75, 0.77, 0.82)
    f.metaRight = Text(f, 11, "RIGHT")
    f.metaRight:SetPoint("TOPRIGHT", f.pw, "BOTTOMRIGHT", 0, -6)
    f.metaRight:SetTextColor(0.75, 0.77, 0.82)

    -- Portrait (Form wählbar) mit Ring und Levelplakette
    local pf = CreateFrame("Frame", nil, f)
    pf:SetSize(PORTRAIT + 6, PORTRAIT + 6)
    pf:SetFrameLevel(box:GetFrameLevel() + 5)
    f.portraitFrame = pf
    f.pMasks = {}
    f.pShadow = Shaped(pf, "BACKGROUND", 0, PORTRAIT + 6, f.pMasks)
    f.pShadow:SetPoint("CENTER"); f.pShadow:SetColorTexture(0, 0, 0, 1)
    f.pRing = Shaped(pf, "BORDER", 0, PORTRAIT + 3, f.pMasks)
    f.pRing:SetPoint("CENTER"); f.pRing:SetColorTexture(0.35, 0.37, 0.42, 1)
    f.pInner = Shaped(pf, "BORDER", 1, PORTRAIT, f.pMasks)
    f.pInner:SetPoint("CENTER"); f.pInner:SetColorTexture(0, 0, 0, 1)
    f.portrait = Shaped(pf, "ARTWORK", 0, PORTRAIT - 2, f.pMasks)
    f.portrait:SetPoint("CENTER")

    -- Drachen-Ornament über dem Portrait (eigene Ebene, auch ohne Portrait sichtbar)
    local orn = CreateFrame("Frame", nil, f)
    orn:SetAllPoints(f)
    orn:SetFrameLevel(pf:GetFrameLevel() + 1)
    f.ornament = orn:CreateTexture(nil, "OVERLAY")
    f.ornament:Hide()

    -- Levelplakette liegt über dem Ornament
    local bf = CreateFrame("Frame", nil, pf)
    bf:SetAllPoints(pf)
    bf:SetFrameLevel(orn:GetFrameLevel() + 1)
    local lvlBg = Circle(bf, "OVERLAY", 0, 24)
    lvlBg:SetColorTexture(0.35, 0.37, 0.42, 1)
    local lvlIn = Circle(bf, "OVERLAY", 1, 20)
    lvlIn:SetColorTexture(0.05, 0.04, 0.03, 1)
    if f.portraitRight then
        lvlBg:SetPoint("CENTER", pf, "BOTTOMRIGHT", -8, 8)
    else
        lvlBg:SetPoint("CENTER", pf, "BOTTOMLEFT", 8, 8)
    end
    lvlIn:SetPoint("CENTER", lvlBg)
    f.levelText = bf:CreateFontString(nil, "OVERLAY", nil, 2)
    f.levelText:SetFont(FONT, 10, "OUTLINE")
    f.levelText:SetPoint("CENTER", lvlBg, "CENTER", 0, 0)

    -- Schlachtzugsmarker mittig über dem Kasten
    local mk = CreateFrame("Frame", nil, f)
    mk:SetAllPoints(box)
    mk:SetFrameLevel(pf:GetFrameLevel() + 2)
    f.marker = mk:CreateTexture(nil, "OVERLAY")
    f.marker:SetSize(26, 26)
    f.marker:SetPoint("CENTER", box, "TOP", 0, 2)
    f.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.marker:Hide()

    -- PvP-Symbol (Position folgt in ApplySettings)
    f.pvp = mk:CreateTexture(nil, "OVERLAY", nil, 1)
    f.pvp:SetSize(PVP_H, PVP_H)
    f.pvp:Hide()

    -- Debuffs
    f.auras = ns:CreateAuraContainer(f, unit, W, f.isTarget and "target" or "player")
    f.auras:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -22)
    f.buffs = ns:CreateAuraContainer(f, unit, W, "buff")

    -- Markierung beim Verschieben, im Stil des Blizzard-Bearbeitungsmodus (blau)
    local mo = CreateFrame("Frame", nil, f)
    mo:SetAllPoints(f)
    mo:SetFrameLevel(mk:GetFrameLevel() + 2)
    local hl = mo:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints()
    hl:SetColorTexture(0.25, 0.55, 1.0, 0.30)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = mo:CreateTexture(nil, "OVERLAY", nil, 1)
        e:SetColorTexture(0.35, 0.65, 1.0, 1)
        e:SetPoint(side[1]); e:SetPoint(side[2])
        if side[1] == "TOPLEFT" and side[2] == "TOPRIGHT" or side[1] == "BOTTOMLEFT" then e:SetHeight(2) else e:SetWidth(2) end
    end
    local lbl = Text(mo, 12, "CENTER")
    lbl:SetPoint("CENTER")
    lbl:SetText(MOVE_LABEL[f.key] or f.key)
    mo:Hide()
    f.moveOverlay = mo
end

---------------------------------------------------------------------------
-- Einrasten nach dem Verschieben
---------------------------------------------------------------------------
local SNAP_DIST = 12   -- Abstand in UI-Pixeln, ab dem am anderen Frame eingerastet wird

-- Mitte, halbe Breite und halbe Höhe eines Frames in UIParent-Einheiten, relativ zur Bildschirmmitte
local function Geometry(frame)
    local cx, cy = frame:GetCenter()
    if not cx then return nil end
    local s = frame:GetScale()
    return cx * s - UIParent:GetWidth() / 2, cy * s - UIParent:GetHeight() / 2,
        frame:GetWidth() * s / 2, frame:GetHeight() * s / 2
end

-- Rasterabstand des Bearbeitungsmodus, falls "Einrasten" an ist
local function GridSpacing()
    local em = EditModeManagerFrame
    if not em then return nil end
    local ok, snap = pcall(function() return em:IsSnapEnabled() end)
    if not ok or not snap then return nil end
    local grid = em.Grid
    return grid and grid.gridSpacing
end

local function Nearest(value, candidates)
    local best, bestD
    for _, c in ipairs(candidates) do
        local d = math.abs(value - c)
        if d <= SNAP_DIST and (not bestD or d < bestD) then best, bestD = c, d end
    end
    return best
end

function ns:SnapAndSave(frame)
    local x, y, hw, hh = Geometry(frame)
    if not x then return end
    -- Einrastpunkte an allen anderen sichtbaren Frames
    local xs, ys = {}, {}
    for _, other in pairs(ns.frames) do
        if other ~= frame and other:IsShown() then
            local ox, oy, ohw, ohh = Geometry(other)
            if ox then
                -- X: gleiche Mitte, gleiche linke/rechte Kante oder spiegelbildlich zur Bildschirmmitte
                xs[#xs + 1] = ox
                xs[#xs + 1] = (ox - ohw) + hw
                xs[#xs + 1] = (ox + ohw) - hw
                xs[#xs + 1] = -ox
                -- Y: gleiche Mitte, gleiche Ober- oder Unterkante
                ys[#ys + 1] = oy
                ys[#ys + 1] = (oy + ohh) - hh
                ys[#ys + 1] = (oy - ohh) + hh
            end
        end
    end
    local snappedX, snappedY = Nearest(x, xs), Nearest(y, ys)

    local g = GridSpacing()
    if g and g > 0 then
        if not snappedX then snappedX = math.floor(x / g + 0.5) * g end
        if not snappedY then snappedY = math.floor(y / g + 0.5) * g end
    end
    x, y = snappedX or x, snappedY or y

    -- Position als Versatz zur Bildschirmmitte speichern (in Frame-Einheiten)
    local s = frame:GetScale()
    local px, py = math.floor(x / s + 0.5), math.floor(y / s + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", px, py)
    local prof = ns.profile[frame.key]
    prof.point, prof.x, prof.y = "CENTER", px, py
end

function ns:CreateFrames()
    ns.frames.player = CreateUnitFrame("player", "player", "ForeverUnitFramesPlayer")
    ns.frames.target = CreateUnitFrame("target", "target", "ForeverUnitFramesTarget")
    ns.frames.targettarget = CreateUnitFrame("targettarget", "targettarget", "ForeverUnitFramesTargetTarget")
end

-- Vorschau-Frame für die Einstellungen
ns.previews = {}
function ns:CreatePreview(key, parent)
    local f = CreateUnitFrame(key, key, nil, parent)
    ns.previews[key] = f
    return f
end
