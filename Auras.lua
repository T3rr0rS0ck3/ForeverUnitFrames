-- ForeverUnitFrames: Debuffs und Buffs für Spieler und Ziel
local _, ns = ...

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

-- Neuere Clients sperren Aura-Daten in bestimmten Situationen (z. B. im Kampf)
-- für Addons ("secret values"). Dann liefern wir "gesperrt" statt eines Fehlers.
local IsSecret = issecretvalue or function() return false end
local ShouldIndexBeSecret = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret

local function ReadAura(unit, i, filter)
    if ShouldIndexBeSecret then
        local ok, secret = pcall(ShouldIndexBeSecret, unit, i, filter)
        if ok and secret and not IsSecret(secret) then return nil, true end
    end
    local ok, aura = pcall(GetAuraByIndex, unit, i, filter)
    if not ok then return nil, true end
    if aura and (IsSecret(aura.name) or IsSecret(aura.icon) or IsSecret(aura.duration)
        or IsSecret(aura.expirationTime) or IsSecret(aura.applications)
        or IsSecret(aura.dispelName) or IsSecret(aura.isStealable)
        or IsSecret(aura.isFromPlayerOrPlayerPet) or IsSecret(aura.sourceUnit)) then
        return nil, true
    end
    return aura
end

local function IsOwn(aura)
    if aura.isFromPlayerOrPlayerPet ~= nil then return aura.isFromPlayerOrPlayerPet end
    local s = aura.sourceUnit
    return s == "player" or s == "pet" or s == "vehicle"
end

local function Remaining(aura, now)
    if aura.expirationTime and aura.expirationTime > 0 then return aura.expirationTime - now end
    return math.huge   -- ohne Ablauf (Aura, Gestalt …) ganz nach hinten
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
        GameTooltip:SetText(self.sampleName .. " |cff999999(Beispiel)|r")
        GameTooltip:Show()
        return
    end
    local helpful = (self.filter == "HELPFUL")
    if self.auraInstanceID and helpful and GameTooltip.SetUnitBuffByAuraInstanceID then
        GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID)
    elseif self.auraInstanceID and not helpful and GameTooltip.SetUnitDebuffByAuraInstanceID then
        GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID)
    elseif helpful then
        GameTooltip:SetUnitBuff(self.unit, self.index)
    else
        GameTooltip:SetUnitDebuff(self.unit, self.index)
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
function Container:Update(opts)
    local list, unit = self.list, self.unit
    wipe(list)
    local isBuff = (self.mode == "buff")
    local canSteal
    if opts.sample then
        canSteal = isBuff and opts.highlightSteal and opts.sampleHostile
    else
        canSteal = isBuff and opts.highlightSteal and UnitExists(unit) and UnitCanAttack("player", unit)
    end

    if opts.enabled and (opts.sample or UnitExists(unit)) then
        local now = GetTime()
        local i = 1
        while true do
            local aura
            if opts.sample then
                -- Beispieldaten für die Vorschau in den Einstellungen
                local src = opts.sample[i]
                if src then
                    aura = {
                        name = src.name, icon = src.icon, applications = src.applications,
                        dispelName = src.dispelName, duration = src.duration,
                        expirationTime = (src.duration and src.duration > 0) and (now + src.rem) or 0,
                        isFromPlayerOrPlayerPet = src.own and true or false,
                        isStealable = src.isStealable, isSample = true,
                    }
                end
            else
                local blocked
                aura, blocked = ReadAura(unit, i, self.filter)
                if blocked then
                    -- Daten gerade gesperrt: letzte Anzeige stehen lassen,
                    -- aktualisiert wird beim nächsten erlaubten UNIT_AURA bzw. nach dem Kampf
                    return
                end
            end
            if not aura or not aura.name then break end
            aura.index = i
            aura.own = IsOwn(aura)
            if isBuff then
                aura.steal = canSteal and (aura.isStealable or (playerPurges and aura.dispelName == "Magic")) and true or false
                local keep = true
                local f = opts.filter
                if f == "own" then keep = aura.own
                elseif f == "short" then keep = aura.duration and aura.duration > 0 and aura.duration <= 60
                elseif f == "steal" then keep = aura.steal end
                if keep then list[#list + 1] = aura end
            else
                aura.dispellable = (self.mode == "player" and playerDispels[aura.dispelName or ""]) and true or false
                if not (opts.onlyOwn and not aura.own) then list[#list + 1] = aura end
            end
            i = i + 1
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

            b.unit, b.index, b.auraInstanceID, b.filter = unit, aura.index, aura.auraInstanceID, self.filter
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

            local stacks = aura.applications or 0
            b.count:SetText(stacks > 1 and stacks or "")

            b.expiration = aura.expirationTime or 0
            if aura.duration and aura.duration > 0 and b.expiration > 0 then
                b.cd:SetCooldown(b.expiration - aura.duration, aura.duration)
                b.cd:Show()
            else
                b.cd:Hide()
                b.time:SetText("")
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
            end
        end
    end
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
