-- ForeverUnitFrames: Kern (Datenbank, Profile, Events, Slash-Befehl)
local ADDON, ns = ...

ns.frames = {}

---------------------------------------------------------------------------
-- Standardwerte eines Profils
---------------------------------------------------------------------------
-- Optik-Einstellungen, die Spieler und Ziel jeweils einzeln haben
local function UnitDefaults(x, ornament)
    return {
        scale = 1.0,
        healthColor = "class",               -- class | health | custom
        customColor = { r = 0.25, g = 0.70, b = 0.35 },
        textMode = "both",                   -- both | pct | val | none
        barTexture = "Flach",
        barShade = true,                     -- dunkle untere Hälfte für etwas Tiefe
        portrait = false, portraitShape = "round",
        portraitSize = 70, portraitX = 0, portraitY = 0,
        showDebuffs = true, onlyOwnDebuffs = false,
        showBuffs = true, buffPos = "top",          -- top | bottom | side
        buffFilter = "all",                          -- all | own | short | steal
        buffSize = 22, buffMax = 12, buffSteal = true,
        ornament = ornament,                         -- none | auto | elite | rare | rareelite | worldboss
        ornX = 0, ornY = 0,                          -- Versatz, wächst mit der Portraitgröße mit
        point = "CENTER", x = x, y = -180,
    }
end

ns.defaults = {
    hideBlizzard = true,
    hideBlizzBuffs   = false,   -- Blizzards Buffleiste oben rechts
    hideBlizzDebuffs = false,   -- Blizzards Debuffleiste oben rechts
    locked       = true,    -- nur ohne Blizzard-Bearbeitungsmodus genutzt
    player = UnitDefaults(-280, "none"),
    target = UnitDefaults(280, "auto"),
}

-- Ältere Profile hatten Farbe/Text/Textur für beide Frames gemeinsam: auf beide verteilen
local MOVED_KEYS = { "healthColor", "customColor", "textMode", "barTexture", "barShade" }
local function Migrate(p)
    for _, k in ipairs(MOVED_KEYS) do
        if p[k] ~= nil then
            for _, unit in ipairs({ "player", "target" }) do
                p[unit] = p[unit] or {}
                if p[unit][k] == nil then
                    p[unit][k] = (type(p[k]) == "table") and ns.CopyTable(p[k]) or p[k]
                end
            end
            p[k] = nil
        end
    end
end

local function CopyTable(src)
    local t = {}
    for k, v in pairs(src) do
        t[k] = (type(v) == "table") and CopyTable(v) or v
    end
    return t
end
ns.CopyTable = CopyTable

-- Fehlende Schlüssel aus den Standardwerten ergänzen (für neue Optionen in späteren Versionen)
local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            FillDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
local function CharKey()
    return UnitName("player") .. " - " .. GetRealmName()
end

function ns:InitDB()
    ForeverUnitFramesDB = ForeverUnitFramesDB or {}
    local db = ForeverUnitFramesDB
    db.profiles = db.profiles or {}
    db.chars = db.chars or {}
    if not db.profiles["Standard"] then
        db.profiles["Standard"] = CopyTable(ns.defaults)
    end
    for _, p in pairs(db.profiles) do
        Migrate(p)
        FillDefaults(p, ns.defaults)
    end

    local key = CharKey()
    if not db.chars[key] or not db.profiles[db.chars[key]] then
        db.chars[key] = "Standard"
    end
    ns.db = db
    ns.charKey = key
    ns.profile = db.profiles[db.chars[key]]
end

function ns:GetProfileName()
    return ns.db.chars[ns.charKey]
end

function ns:GetProfileNames()
    local names = {}
    for name in pairs(ns.db.profiles) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == "Standard" then return true elseif b == "Standard" then return false end
        return a < b
    end)
    return names
end

function ns:SetProfile(name)
    if not ns.db.profiles[name] then return end
    ns.db.chars[ns.charKey] = name
    ns.profile = ns.db.profiles[name]
    ns:ApplyAll()
end

function ns:NewProfile(name)
    name = name and strtrim(name) or ""
    if name == "" or ns.db.profiles[name] then return false end
    ns.db.profiles[name] = CopyTable(ns.defaults)
    ns:SetProfile(name)
    return true
end

function ns:CopyProfileFrom(source)
    local src = ns.db.profiles[source]
    if not src or src == ns.profile then return end
    local name = ns:GetProfileName()
    ns.db.profiles[name] = CopyTable(src)
    ns:SetProfile(name)
end

function ns:ResetProfile()
    local name = ns:GetProfileName()
    ns.db.profiles[name] = CopyTable(ns.defaults)
    ns:SetProfile(name)
end

function ns:DeleteProfile()
    local name = ns:GetProfileName()
    if name == "Standard" then return end
    ns.db.profiles[name] = nil
    -- Alle Charaktere, die dieses Profil nutzten, fallen auf Standard zurück
    for char, prof in pairs(ns.db.chars) do
        if prof == name then ns.db.chars[char] = "Standard" end
    end
    ns:SetProfile("Standard")
end

---------------------------------------------------------------------------
-- Änderungen, die im Kampf gesperrt sind, bis nach dem Kampf aufschieben
---------------------------------------------------------------------------
local pendingApply = false

-- Funktion aufrufen; Fehler melden statt abzubrechen
local reported = {}
function ns.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[err] then
        reported[err] = true
        geterrorhandler()(err)
    end
    return ok
end

function ns:ApplyAll()
    -- Vorschau in den Einstellungen ist kein geschützter Frame: geht immer, auch im Kampf
    for _, pv in pairs(ns.previews or {}) do
        if pv:IsVisible() then ns.Try(pv.ApplySettings, pv) end
    end
    if InCombatLockdown() then
        if not pendingApply then
            pendingApply = true
            print("|cffd8a64aForeverUnitFrames:|r Änderung wird nach dem Kampf übernommen.")
        end
        -- Farben und Texte gehen auch im Kampf
        for _, f in pairs(ns.frames) do ns.Try(f.UpdateAll, f) end
        return
    end
    pendingApply = false
    ns.Try(ns.HideBlizzardFrames, ns)
    ns.Try(ns.UpdateBlizzardAuras, ns)
    for _, f in pairs(ns.frames) do ns.Try(f.ApplySettings, f) end
end

---------------------------------------------------------------------------
-- Blizzard-Frames ausblenden
---------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local blizzHidden = false

function ns:HideBlizzardFrames()
    if blizzHidden or not ns.profile.hideBlizzard then return end
    for _, frame in ipairs({ PlayerFrame, TargetFrame }) do
        if frame then
            frame:UnregisterAllEvents()
            frame:Hide()
            frame:SetParent(hiddenParent)
        end
    end
    blizzHidden = true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns:InitDB()
    elseif event == "PLAYER_LOGIN" then
        -- Jeder Schritt einzeln abgesichert: ein Fehler soll nicht alles Weitere blockieren
        ns.Try(ns.CreateOptions, ns)
        ns.Try(ns.CreateFrames, ns)
        ns.Try(ns.ApplyAll, ns)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then ns:ApplyAll() end
    end
end)

---------------------------------------------------------------------------
-- Bearbeitungsmodus von Blizzard: solange er offen ist, lassen sich die Frames ziehen
---------------------------------------------------------------------------
ns.editMode = false
ns.hasEditMode = (EventRegistry ~= nil and EditModeManagerFrame ~= nil)

function ns:IsUnlocked()
    if ns.hasEditMode then return ns.editMode end
    return not ns.profile.locked
end

local function SetEditMode(on)
    ns.editMode = on
    if InCombatLockdown() then return end
    for _, f in pairs(ns.frames) do ns.Try(f.ApplySettings, f) end
end

if ns.hasEditMode then
    EventRegistry:RegisterCallback("EditMode.Enter", function() SetEditMode(true) end, ns)
    EventRegistry:RegisterCallback("EditMode.Exit", function() SetEditMode(false) end, ns)
end

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------
SLASH_FOREVERFRAMES1 = "/ff"
SLASH_FOREVERFRAMES2 = "/foreverframes"
SlashCmdList.FOREVERFRAMES = function(msg)
    msg = strlower(strtrim(msg or ""))
    if (msg == "unlock" or msg == "lock") and ns.hasEditMode then
        if not InCombatLockdown() then ShowUIPanel(EditModeManagerFrame) end
    elseif msg == "unlock" or msg == "lock" then
        if InCombatLockdown() then
            print("|cffd8a64aForeverUnitFrames:|r Im Kampf nicht möglich.")
            return
        end
        ns.profile.locked = (msg == "lock")
        ns:ApplyAll()
        print("|cffd8a64aForeverUnitFrames:|r Rahmen " .. (ns.profile.locked and "gesperrt." or "entsperrt. Mit der Maus verschieben, danach /ff lock."))
    else
        ns:ToggleOptions()
    end
end
