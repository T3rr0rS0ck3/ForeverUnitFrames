-- ForeverUnitFrames: Debuffs und Buffs für Spieler und Ziel
local _, ns = ...
local L = ns.L

local MAX_AURAS   = 24
local SIZE_BIG    = 26
local SIZE_SMALL  = 18
local GAP         = 4
local ROW_GAP     = 16   -- Platz für die Restzeit unter dem Icon

-- Rahmenfarben nach Debuff-Typ
local TYPE_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    none    = { 0.70, 0.15, 0.15 },
}
local function TypeColor(dispelName)
    if dispelName and DebuffTypeColor and DebuffTypeColor[dispelName] then
        local c = DebuffTypeColor[dispelName]
        return c.r, c.g, c.b
    end
    local c = TYPE_COLORS[dispelName or "none"] or TYPE_COLORS.none
    return c[1], c[2], c[3]
end

local GOLD_BORDER = { 0.90, 0.70, 0.30 }
local DARK_BORDER = { 0.11, 0.11, 0.13 }
local STEAL_COLOR = { 0.40, 0.70, 1.00 }

-- Was die eigene Klasse von Verbündeten entfernen kann (Classic-Stand; bei Bedarf anpassen)
local DISPELS = {
    MAGE    = { Curse = true },
    DRUID   = { Curse = true, Poison = true },
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN  = { Poison = true, Disease = true },
}
-- Klassen, die Magie-Buffs von Gegnern entfernen oder stehlen können
local PURGERS = { PRIEST = true, SHAMAN = true, MAGE = true, HUNTER = true, WARLOCK = true }
local playerDispels, playerPurges = {}, false

---------------------------------------------------------------------------
-- Aura-Daten lesen (neue API mit Rückfall auf die alte)
---------------------------------------------------------------------------
local GetAuraByIndex
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    GetAuraByIndex = function(unit, i, filter)
        return C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
    end
else
    GetAuraByIndex = function(unit, i, filter)
        local name, icon, count, dispelType, duration, expirationTime, source, isStealable = UnitAura(unit, i, filter)
        if not name then return nil end
        return {
            name = name, icon = icon, applications = count, dispelName = dispelType,
            duration = duration, expirationTime = expirationTime, sourceUnit = source,
            isStealable = isStealable,
        }
    end
end

-- Neuere Clients geben Aura-Daten teilweise als "geheim" zurück (z. B. in Instanzen,
-- im Kampf oder bei fremden Auren). Geheime Werte dürfen nicht verglichen oder
-- verrechnet werden, Blizzards Anzeige-Funktionen (SetTexture, SetText, Cooldown)
-- nehmen sie aber an. Deshalb: Aura immer anzeigen, geheime Felder über diese
-- Funktionen darstellen und nur lesbare Werte für Logik (Sortierung, Filter) nutzen.
local IsSecret = issecretvalue or function() return false end
local function Clean(v)
    if IsSecret(v) then return nil end
    return v
end

local AuraAPI = C_UnitAuras or {}
local GetDurationObject = AuraAPI.GetAuraDuration
local GetCountText      = AuraAPI.GetAuraApplicationDisplayCount
local IsFilteredOut     = AuraAPI.IsAuraFilteredOutByInstanceID

-- Passt die Aura zu einem Filter (z. B. "HARMFUL|PLAYER")? true/false, nil = unbekannt
local function MatchesFilter(unit, id, hasId, filter)
    if not (IsFilteredOut and hasId) then return nil end
    local ok, out = pcall(IsFilteredOut, unit, id, filter)
    if not ok or IsSecret(out) then return nil end
    return not out
end

---------------------------------------------------------------------------
-- Alle Auren einer Einheit holen
-- Manche Clients verweigern Addons den Zugriff per Index komplett, sobald die
-- Auren geheim sind ("Auras cannot be accessed when secret while tainted").
-- Deshalb mehrere Wege nacheinander probieren; der zuletzt erfolgreiche zuerst.
---------------------------------------------------------------------------
local MAX_READ = 64
local STRATEGIES = {}
if AuraAPI.GetUnitAuras then
    STRATEGIES[#STRATEGIES + 1] = { name = "GetUnitAuras", fn = function(unit, filter)
        local t = AuraAPI.GetUnitAuras(unit, filter, MAX_READ)
        return type(t) == "table" and t or {}
    end }
end
if AuraAPI.GetUnitAuraInstanceIDs and AuraAPI.GetAuraDataByAuraInstanceID then
    STRATEGIES[#STRATEGIES + 1] = { name = "GetUnitAuraInstanceIDs", fn = function(unit, filter)
        local t, ids = {}, AuraAPI.GetUnitAuraInstanceIDs(unit, filter, MAX_READ)
        if type(ids) == "table" then
            for _, id in ipairs(ids) do
                local a = AuraAPI.GetAuraDataByAuraInstanceID(unit, id)
                if type(a) == "table" then t[#t + 1] = a end
            end
        end
        return t
    end }
end
if AuraAPI.GetAuraSlots and AuraAPI.GetAuraDataBySlot then
    STRATEGIES[#STRATEGIES + 1] = { name = "GetAuraSlots", fn = function(unit, filter)
        local t, token = {}, nil
        for _ = 1, 10 do   -- Fortsetzungs-Token, sicherheitshalber begrenzt
            local res = { AuraAPI.GetAuraSlots(unit, filter, MAX_READ, token) }
            token = res[1]
            for k = 2, #res do
                local a = AuraAPI.GetAuraDataBySlot(unit, res[k])
                if type(a) == "table" then t[#t + 1] = a end
            end
            if not token then break end
        end
        return t
    end }
end
STRATEGIES[#STRATEGIES + 1] = { name = "Index", fn = function(unit, filter)
    local t = {}
    for i = 1, MAX_READ do
        local a = GetAuraByIndex(unit, i, filter)
        if type(a) ~= "table" then break end
        t[#t + 1] = a
    end
    return t
end }

local preferred = 1
local seenSpells = {}   -- spellId -> Name, für den Test in /ff auras

-- Sperrt der Client gerade alle Auren dieser Einheit? (im Kampf: ja)
local function AurasLocked(unit)
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local ok, locked = pcall(C_Secrets.ShouldAurasBeSecret, unit)
    return ok and not IsSecret(locked) and locked == true
end

-- Liefert die rohen Aura-Tabellen oder nil, wenn der Client den Zugriff verweigert
local function GetAuraList(unit, filter)
    if AurasLocked(unit) then return nil end
    local order = { preferred }
    for k = 1, #STRATEGIES do if k ~= preferred then order[#order + 1] = k end end
    for _, k in ipairs(order) do
        local ok, list = pcall(STRATEGIES[k].fn, unit, filter)
        if ok and list then
            preferred = k
            for _, raw in ipairs(list) do
                local id = Clean(raw.spellId)
                if id then seenSpells[id] = Clean(raw.name) or "?" end
            end
            return list
        end
    end
    return nil
end

-- Bereitet eine rohe Aura auf (geheime Felder bleiben für die Anzeige erhalten)
local function ReadAura(unit, raw, i, filter)
    local a = { raw = raw, index = i }
    -- Die ID darf geheim sein: Blizzards Funktionen nehmen sie trotzdem an
    a.id = raw.auraInstanceID
    a.hasId = IsSecret(a.id) or a.id ~= nil
    a.icon = raw.icon                                   -- darf geheim sein (nur SetTexture)
    a.duration = Clean(raw.duration)
    a.expirationTime = Clean(raw.expirationTime)
    a.timeSecret = IsSecret(raw.duration) or IsSecret(raw.expirationTime)
    a.applications = Clean(raw.applications)
    a.countSecret = IsSecret(raw.applications)
    a.dispelName = Clean(raw.dispelName)
    a.isStealable = Clean(raw.isStealable)

    -- eigene Aura? Erst die direkten Felder, dann über den PLAYER-Filter fragen
    local own = Clean(raw.isFromPlayerOrPlayerPet)
    if own == nil then
        local src = Clean(raw.sourceUnit)
        if src ~= nil then own = (src == "player" or src == "pet" or src == "vehicle") end
    end
    if own == nil then own = MatchesFilter(unit, a.id, a.hasId, filter .. "|PLAYER") end
    a.own = own and true or false
    return a
end

local function Remaining(aura, now)
    if aura.expirationTime and aura.expirationTime > 0 then return aura.expirationTime - now end
    return math.huge   -- ohne Ablauf oder unbekannt (Aura, Gestalt …) ganz nach hinten
end

local function FormatTime(t)
    if t >= 3600 then return format("%dh", math.ceil(t / 3600)) end
    if t >= 60 then return format("%dm", math.ceil(t / 60)) end
    if t >= 3 then return format("%d", math.ceil(t)) end
    return format("%.1f", t)
end

---------------------------------------------------------------------------
-- Ein Icon
---------------------------------------------------------------------------
local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if self.sampleName then
        GameTooltip:SetText(self.sampleName .. " |cff999999(" .. L["Sample"] .. ")|r")
        GameTooltip:Show()
        return
    end
    local helpful = (self.filter == "HELPFUL")
    if self.hasId and helpful and GameTooltip.SetUnitBuffByAuraInstanceID then
        GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID)
    elseif self.hasId and not helpful and GameTooltip.SetUnitDebuffByAuraInstanceID then
        GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID)
    elseif helpful then
        pcall(GameTooltip.SetUnitBuff, GameTooltip, self.unit, self.index)
    else
        pcall(GameTooltip.SetUnitDebuff, GameTooltip, self.unit, self.index)
    end
    GameTooltip:Show()
end

local function CreateIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:EnableMouse(true)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)

    -- leuchtender Rand (bannbar)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.glow:SetPoint("TOPLEFT", -3, 3)
    b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.glow:SetColorTexture(1, 1, 1, 1)
    b.glowAnim = b.glow:CreateAnimationGroup()
    b.glowAnim:SetLooping("BOUNCE")
    local a = b.glowAnim:CreateAnimation("Alpha")
    a:SetFromAlpha(0.25); a:SetToAlpha(0.9); a:SetDuration(0.7)

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0, 0, 0, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetReverse(true)
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.cd.noCooldownCount = true   -- OmniCC und ähnliche Addons ignorieren das

    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.count = over:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 1, 0)

    b.time = b:CreateFontString(nil, "OVERLAY")
    b.time:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -2)
    return b
end

local function SetGlow(b, on, r, g, bl)
    if on then
        b.glow:SetVertexColor(r, g, bl)
        b.glow:Show()
        if not b.glowAnim:IsPlaying() then b.glowAnim:Play() end
    else
        b.glowAnim:Stop()
        b.glow:Hide()
    end
end

---------------------------------------------------------------------------
-- Container
-- mode: "player" (Debuffs auf dir), "target" (Debuffs auf dem Ziel), "buff" (Buffs)
---------------------------------------------------------------------------
local Container = {}

function ns:CreateAuraContainer(parent, unit, width, mode)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, 1)
    c.unit, c.width, c.mode = unit, width, mode
    c.filter = (mode == "buff") and "HELPFUL" or "HARMFUL"
    c.icons, c.list = {}, {}
    for k, v in pairs(Container) do c[k] = v end

    c.elapsed = 0
    c:SetScript("OnUpdate", function(self, el)
        self.elapsed = self.elapsed + el
        if self.elapsed < 0.1 then return end
        self.elapsed = 0
        self:UpdateTimers()
    end)
    return c
end

-- Ausrichtung: rechtsbündig und/oder nach oben wachsend
function Container:SetGrowth(alignRight, growUp)
    self.alignRight, self.growUp = alignRight, growUp
end

function Container:SetWidthPx(w)
    self.width = w
    self:SetWidth(w)
end

-- opts: enabled, onlyOwn (Debuffs Ziel) | filter, size, max, highlightSteal (Buffs)
-- Nach einem Zielwechsel: alte Anzeige gehört nicht mehr zur Einheit
function Container:Invalidate()
    self.valid = false
end

function Container:Update(opts)
    local list, unit = self.list, self.unit

    -- Im Kampf verweigert der Client Addons jeden Zugriff auf Auren. Dann die letzte
    -- Anzeige derselben Einheit stehen lassen (Timer laufen weiter, Abgelaufenes
    -- verschwindet); nach dem Kampf wird sofort neu gelesen.
    local raws
    if not opts.sample and opts.enabled and UnitExists(unit) then
        raws = GetAuraList(unit, self.filter)
        if raws == nil and self.valid then
            self.frozen = true
            self:UpdateTimers()
            return
        end
    end
    self.frozen = false
    self.valid = (raws ~= nil)
    wipe(list)
    local isBuff = (self.mode == "buff")
    local canSteal
    if opts.sample then
        canSteal = isBuff and opts.highlightSteal and opts.sampleHostile
    else
        local canAttack = UnitExists(unit) and UnitCanAttack("player", unit)
        if IsSecret(canAttack) then canAttack = false end
        canSteal = isBuff and opts.highlightSteal and canAttack
    end

    if opts.enabled and (opts.sample or UnitExists(unit)) then
        local now = GetTime()
        for i = 1, MAX_READ do
            local aura
            if opts.sample then
                -- Beispieldaten für die Vorschau in den Einstellungen
                local src = opts.sample[i]
                if not src then break end
                aura = {
                    index = i, name = src.name, icon = src.icon, applications = src.applications,
                    dispelName = src.dispelName, duration = src.duration,
                    expirationTime = (src.duration and src.duration > 0) and (now + src.rem) or 0,
                    own = src.own and true or false,
                    isStealable = src.isStealable, isSample = true,
                }
            else
                local raw = raws and raws[i]
                if not raw then break end
                aura = ReadAura(unit, raw, i, self.filter)
            end

            if isBuff then
                aura.steal = canSteal and (aura.isStealable or (playerPurges and aura.dispelName == "Magic")) and true or false
                local keep = true
                local f = opts.filter
                if f == "own" then keep = aura.own
                elseif f == "short" then keep = aura.duration and aura.duration > 0 and aura.duration <= 60
                elseif f == "steal" then keep = aura.steal end
                if keep then list[#list + 1] = aura end
            else
                if self.mode == "player" then
                    -- bannbar? Am zuverlässigsten über den RAID-Filter, sonst eigene Tabelle
                    local d = (not aura.isSample) and MatchesFilter(unit, aura.id, aura.hasId, "HARMFUL|RAID")
                    if d == nil then d = playerDispels[aura.dispelName or ""] end
                    aura.dispellable = d and true or false
                else
                    aura.dispellable = false
                end
                if not (opts.onlyOwn and not aura.own) then list[#list + 1] = aura end
            end
        end

        if self.mode == "player" then
            table.sort(list, function(a, b)
                if a.dispellable ~= b.dispellable then return a.dispellable end
                local ra, rb = Remaining(a, now), Remaining(b, now)
                if ra ~= rb then return ra < rb end
                return a.index < b.index
            end)
        elseif self.mode == "target" then
            table.sort(list, function(a, b)
                if a.own ~= b.own then return a.own end
                return a.index < b.index
            end)
        else
            table.sort(list, function(a, b)
                if a.own ~= b.own then return a.own end
                local ra, rb = Remaining(a, now), Remaining(b, now)
                if ra ~= rb then return ra < rb end
                return a.index < b.index
            end)
        end
    end

    local maxN = math.min(opts.max or 16, MAX_AURAS)
    local x, y, rowH, shown = 0, 0, 0, 0
    for n = 1, MAX_AURAS do
        local b = self.icons[n]
        local aura = (n <= maxN) and list[n]
        if aura then
            if not b then b = CreateIcon(self); self.icons[n] = b end
            local size
            if isBuff then size = opts.size or 22
            elseif self.mode == "target" and not aura.own then size = SIZE_SMALL
            else size = SIZE_BIG end
            b:SetSize(size, size)
            if x > 0 and x + size > self.width then
                x = 0; y = y + rowH + ROW_GAP; rowH = 0
            end
            b:ClearAllPoints()
            local h = self.alignRight and "RIGHT" or "LEFT"
            local v = self.growUp and "BOTTOM" or "TOP"
            -- nach oben wachsend: Platz für die Restzeit unter der untersten Reihe lassen
            local oy = self.growUp and (ROW_GAP + y) or -y
            b:SetPoint(v .. h, self, v .. h, self.alignRight and -x or x, oy)
            x = x + size + GAP
            rowH = math.max(rowH, size)

            b.unit, b.index, b.filter = unit, aura.index, self.filter
            b.auraInstanceID, b.hasId = aura.id, aura.hasId
            b.sampleName = aura.isSample and aura.name or nil
            b.icon:SetTexture(aura.icon)

            local r, g, bl
            if isBuff then
                local c = aura.steal and STEAL_COLOR or (aura.own and GOLD_BORDER or DARK_BORDER)
                r, g, bl = c[1], c[2], c[3]
            else
                r, g, bl = TypeColor(aura.dispelName)
            end
            b.border:SetColorTexture(r, g, bl, 1)

            local dim = (self.mode == "target" and not aura.own)
            b.icon:SetDesaturated(dim)
            b.icon:SetAlpha(dim and 0.8 or 1)

            -- Stapel
            local stacks = aura.applications
            if stacks then
                b.count:SetText(stacks > 1 and stacks or "")
            elseif aura.countSecret and GetCountText and aura.hasId then
                -- geheim: Blizzard liefert den fertigen Text (leer bei 0/1 Stapeln)
                local ok, txt = pcall(GetCountText, unit, aura.id, 2)
                b.count:SetText(ok and txt or "")
            else
                b.count:SetText("")
            end

            -- Laufzeit
            b.expiration = 0
            b.time:SetText("")
            if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
            local exp, dur = aura.expirationTime or 0, aura.duration
            if dur and dur > 0 and exp > 0 then
                b.expiration = exp
                b.cd:SetCooldown(exp - dur, dur)
                b.cd:Show()
            elseif aura.timeSecret and GetDurationObject and aura.hasId and b.cd.SetCooldownFromDurationObject
                and pcall(function()
                    b.cd:SetCooldownFromDurationObject(GetDurationObject(unit, aura.id))
                end) then
                -- geheime Laufzeit: Spirale und Zahl zeichnet Blizzard selbst
                if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
                b.cd:Show()
            else
                b.cd:Hide()
            end

            SetGlow(b, aura.dispellable or aura.steal, r, g, bl)
            b:Show()
            shown = shown + 1
        elseif b then
            b:Hide()
            SetGlow(b, false)
        end
    end
    self:SetHeight(shown > 0 and (y + rowH + ROW_GAP) or 1)
    self:UpdateTimers()
end

function Container:UpdateTimers()
    local now = GetTime()
    for _, b in ipairs(self.icons) do
        if b:IsShown() and b.expiration and b.expiration > 0 then
            local left = b.expiration - now
            if left > 0 then
                b.time:SetText(FormatTime(left))
                if left < 3 then b.time:SetTextColor(1, 0.4, 0.35) else b.time:SetTextColor(1, 1, 1) end
            else
                b.time:SetText("")
                -- eingefroren (Kampf): abgelaufene Aura selbst ausblenden
                if self.frozen then b:Hide(); SetGlow(b, false) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- /ff auras: zeigt im Chat, was der Client für Spieler und Ziel liefert
---------------------------------------------------------------------------
-- Merkt sich, was UNIT_AURA zuletzt mitgeliefert hat (nur für /ff auras)
local lastPayload = {}
local payloadFrame = CreateFrame("Frame")
pcall(payloadFrame.RegisterUnitEvent, payloadFrame, "UNIT_AURA", "player", "target")
payloadFrame:SetScript("OnEvent", function(_, _, unit, info)
    -- Im Kampf sind die Tabellen selbst geheim: dann nicht einmal die Länge abfragen
    local function Count(t)
        if IsSecret(t) then return "secret" end
        if type(t) == "table" then return #t end
    end
    local r = { time = GetTime(), hasInfo = (not IsSecret(info)) and type(info) == "table" }
    if r.hasInfo then
        r.full = info.isFullUpdate
        r.added = Count(info.addedAuras)
        r.updated = Count(info.updatedAuraInstanceIDs)
        r.removed = Count(info.removedAuraInstanceIDs)
        if type(r.added) == "number" and r.added > 0 then r.sample = info.addedAuras[1] end
    end
    lastPayload[unit] = r
end)

function ns:DebugAuras()
    local lines = {}
    local function out(...)
        local parts = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            parts[#parts + 1] = IsSecret(v) and "<secret>" or tostring(v)
        end
        local line = table.concat(parts, " ")
        lines[#lines + 1] = line
        print("|cffd8a64aFUF:|r " .. line)
    end
    local function has(v) return v and "yes" or "no" end
    local function val(v) if IsSecret(v) then return "<secret>" end return tostring(v) end

    out("Client:", (GetBuildInfo()), select(4, GetBuildInfo()))
    out("API C_UnitAuras:", has(C_UnitAuras), "GetAuraDataByIndex", has(AuraAPI.GetAuraDataByIndex),
        "GetUnitAuras", has(AuraAPI.GetUnitAuras), "GetUnitAuraInstanceIDs", has(AuraAPI.GetUnitAuraInstanceIDs),
        "GetAuraDataByAuraInstanceID", has(AuraAPI.GetAuraDataByAuraInstanceID),
        "GetAuraSlots", has(AuraAPI.GetAuraSlots), "GetAuraDataBySlot", has(AuraAPI.GetAuraDataBySlot),
        "GetAuraDuration", has(GetDurationObject),
        "GetAuraApplicationDisplayCount", has(GetCountText), "IsAuraFilteredOutByInstanceID", has(IsFilteredOut))
    out("API alt: UnitAura", has(UnitAura), "UnitBuff", has(UnitBuff), "UnitDebuff", has(UnitDebuff),
        "C_Secrets", has(C_Secrets), "SetCooldownFromDurationObject", has(CreateFrame("Cooldown").SetCooldownFromDurationObject))
    local inInst, instType = IsInInstance()
    out("State: combat", val(InCombatLockdown()), "UnitAffectingCombat", val(UnitAffectingCombat("player")),
        "instance", val(inInst), val(instType))
    for _, tblName in ipairs({ "C_Secrets", "C_UnitAuras" }) do
        local t = _G[tblName]
        if type(t) == "table" then
            local keys = {}
            for k in pairs(t) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            out(tblName .. ":", table.concat(keys, ", "))
        end
    end

    local FIELDS = { "auraInstanceID", "name", "spellId", "icon", "duration", "expirationTime", "applications",
        "dispelName", "isStealable", "isFromPlayerOrPlayerPet", "sourceUnit" }
    for _, unit in ipairs({ "player", "target" }) do
        if not UnitExists(unit) then
            out(unit, "does not exist")
        else
            out("==", unit, val(UnitName(unit)), "attackable:", val(UnitCanAttack("player", unit)))
            -- einzelne Auren per Index, auch nach einem Fehler weiter probieren
            for _, filter in ipairs({ "HELPFUL", "HARMFUL", "HELPFUL|PLAYER", "HARMFUL|PLAYER", "HARMFUL|RAID", "HELPFUL|RAID" }) do
                local okN, errN, firstErr = 0, 0, nil
                local secInfo = {}
                for i = 1, 20 do
                    if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret and i <= 5 then
                        local ok2, sec = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, unit, i, filter)
                        secInfo[#secInfo + 1] = ok2 and val(sec) or "x"
                    end
                    local ok, a = pcall(AuraAPI.GetAuraDataByIndex, unit, i, filter)
                    if ok then
                        if type(a) ~= "table" then break end
                        okN = okN + 1
                    else
                        errN = errN + 1
                        firstErr = firstErr or i
                    end
                end
                out(unit, filter, "Index single: readable", okN, "denied", errN,
                    "| IndexSecret 1-5:", #secInfo > 0 and table.concat(secInfo, ",") or "-")
            end
            if C_Secrets then
                for _, fn in ipairs({ "ShouldAurasBeSecret", "ShouldUnitAurasBeSecret", "ShouldUnitAuraInstanceBeSecret" }) do
                    if C_Secrets[fn] then
                        local ok2, r = pcall(C_Secrets[fn], unit)
                        out("C_Secrets." .. fn .. "(" .. unit .. "):", ok2 and val(r) or ("error " .. tostring(r)))
                    end
                end
            end
            out(unit, "auras locked:", AurasLocked(unit))
            -- Weg über Spell-IDs (außerhalb des Kampfes gesehene Auren)
            local tested = 0
            for id, name in pairs(seenSpells) do
                if tested >= 8 then break end
                tested = tested + 1
                local info = {}
                if C_Secrets and C_Secrets.GetSpellAuraSecrecy then
                    local ok2, r = pcall(C_Secrets.GetSpellAuraSecrecy, id); info[#info + 1] = "Secrecy=" .. (ok2 and val(r) or "error")
                end
                if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
                    local ok2, r = pcall(C_Secrets.ShouldSpellAuraBeSecret, id); info[#info + 1] = "secret=" .. (ok2 and val(r) or "error")
                end
                if AuraAPI.GetUnitAuraBySpellID then
                    local ok2, r = pcall(AuraAPI.GetUnitAuraBySpellID, unit, id)
                    info[#info + 1] = "BySpellID=" .. (ok2 and (type(r) == "table" and "READABLE" or val(r)) or ("ERROR " .. tostring(r):match("^[^\n]*")))
                end
                if unit == "player" and AuraAPI.GetPlayerAuraBySpellID then
                    local ok2, r = pcall(AuraAPI.GetPlayerAuraBySpellID, id)
                    info[#info + 1] = "Player=" .. (ok2 and (type(r) == "table" and "READABLE" or val(r)) or ("ERROR " .. tostring(r):match("^[^\n]*")))
                end
                out(unit, "Spell", id, name, table.concat(info, " "))
            end
            if tested == 0 then out(unit, "no spell IDs seen yet (run /ff auras out of combat first)") end

            local pl = lastPayload[unit]
            if pl then
                out(unit, "last UNIT_AURA", format("%.0fs", GetTime() - pl.time), "ago, data:", pl.hasInfo,
                    "full:", val(pl.full), "added:", val(pl.added), "updated:", val(pl.updated), "removed:", val(pl.removed))
                if pl.sample then
                    local f = {}
                    for _, k in ipairs(FIELDS) do f[#f + 1] = k .. "=" .. val(pl.sample[k]) end
                    out(unit, "event aura:", table.concat(f, " "))
                    if AuraAPI.GetAuraDataByAuraInstanceID then
                        local ok2, a = pcall(AuraAPI.GetAuraDataByAuraInstanceID, unit, pl.sample.auraInstanceID)
                        out(unit, "GetAuraDataByAuraInstanceID(event ID):", ok2 and (type(a) == "table" and "readable" or tostring(a)) or ("ERROR " .. tostring(a)))
                    end
                end
            else
                out(unit, "no UNIT_AURA received yet")
            end

            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                -- jeden Lese-Weg einzeln testen
                local good
                for _, st in ipairs(STRATEGIES) do
                    local ok, list = pcall(st.fn, unit, filter)
                    if ok then
                        out(unit, filter, st.name .. ":", #list, "auras")
                        if not good and #list > 0 then good = list end
                    else
                        out(unit, filter, st.name .. ": ERROR", list)
                    end
                end
                for i, raw in ipairs(good or {}) do
                    local f = {}
                    for _, k in ipairs(FIELDS) do f[#f + 1] = k .. "=" .. val(raw[k]) end
                    local a = ReadAura(unit, raw, i, filter)
                    f[#f + 1] = "own=" .. tostring(a.own)
                    out(unit, filter, "#" .. i, table.concat(f, " "))
                end
            end

            -- Was zeigt unser Frame gerade an?
            local fr = ns.frames and ns.frames[unit]
            if fr then
                out("Frame", unit, "visible:", fr:IsVisible(), "alpha:", fr:GetEffectiveAlpha())
                for _, key in ipairs({ "auras", "buffs" }) do
                    local c = rawget(fr, key)
                    if type(c) == "table" and c.icons then
                        local shown = 0
                        for _, b in ipairs(c.icons) do if b:IsShown() then shown = shown + 1 end end
                        local pt, rel, rp, x, y = c:GetPoint(1)
                        out(" ", key, "list:", #c.list, "icons visible:", shown, "container visible:", c:IsVisible(),
                            "height:", c:GetHeight(), "anchor:", pt, rel and (rel.GetName and rel:GetName() or "frame"), rp, x, y)
                    else
                        out(" ", key, "missing")
                    end
                end
            else
                out("Frame", unit, "not found")
            end
        end
    end

    if ns.DebugAuraContainers then
        local ok, err = pcall(ns.DebugAuraContainers, ns, out)
        if not ok then out("AuraContainer debug error:", err) end
    end

    -- auch in den SavedVariables ablegen (nach /reload in WTF lesbar)
    ForeverUnitFramesDB = ForeverUnitFramesDB or {}
    ForeverUnitFramesDB.auraDebug = { time = date("%Y-%m-%d %H:%M:%S"), lines = lines }
    print("|cffd8a64aFUF:|r " .. L["Saved. Use /reload to write it to disk."])
end

---------------------------------------------------------------------------
-- Blizzards Buff- und Debuffleiste oben rechts ein-/ausblenden (ohne /reload)
---------------------------------------------------------------------------
local hidden = CreateFrame("Frame")
hidden:Hide()
local origParent = {}

local function SetBlizzShown(frame, show)
    if not frame then return end
    if show and not origParent[frame] then return end   -- nie versteckt: nichts anfassen
    if not origParent[frame] then origParent[frame] = frame:GetParent() end
    if show then
        frame:SetParent(origParent[frame])
        frame:Show()
    else
        frame:SetParent(hidden)
    end
end

function ns:UpdateBlizzardAuras()
    if InCombatLockdown() then return end
    local p = ns.profile
    if DebuffFrame then
        SetBlizzShown(BuffFrame, not p.hideBlizzBuffs)
        SetBlizzShown(DebuffFrame, not p.hideBlizzDebuffs)
    else
        -- ältere Clients: Buffs und Debuffs sitzen gemeinsam im BuffFrame
        SetBlizzShown(BuffFrame, not (p.hideBlizzBuffs and p.hideBlizzDebuffs))
    end
    SetBlizzShown(TemporaryEnchantFrame, not p.hideBlizzBuffs)
end

---------------------------------------------------------------------------
local classFrame = CreateFrame("Frame")
classFrame:RegisterEvent("PLAYER_LOGIN")
classFrame:SetScript("OnEvent", function()
    local _, class = UnitClass("player")
    playerDispels = DISPELS[class] or {}
    playerPurges = PURGERS[class] or false
end)
