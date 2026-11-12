-- ForeverFrames: Einstellungen unter Optionen → AddOns
-- Hauptseite "ForeverFrames" (Optik) mit Unterseiten Spieler, Ziel, Profile
local _, ns = ...

local refreshers = {}

local function Refresh()
    for _, fn in ipairs(refreshers) do fn() end
end
ns.RefreshOptions = Refresh

local function Get(path)
    local t = ns.profile
    for i = 1, #path - 1 do t = t[path[i]] end
    return t[path[#path]]
end

local function Set(path, v)
    local t = ns.profile
    for i = 1, #path - 1 do t = t[path[i]] end
    t[path[#path]] = v
end

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------
local GOLD = { 0.95, 0.85, 0.6 }

local function Label(parent, text, x, y, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 11, "")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    local c = color or { 0.65, 0.67, 0.72 }
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function Checkbox(parent, text, path, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self)
        Set(path, self:GetChecked() and true or false)
        ns:ApplyAll()
        Refresh()
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(Get(path)) end
    return cb
end

local function Slider(parent, text, path, minV, maxV, step, x, y, fmt)
    fmt = fmt or "%.2f×"
    Label(parent, text, x, y)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(220, 16)
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouse(true)
    s:EnableMouseWheel(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    track:SetColorTexture(0.25, 0.27, 0.32, 1)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local val = s:CreateFontString(nil, "OVERLAY")
    val:SetFont(STANDARD_TEXT_FONT, 12, "")
    val:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        val:SetText(format(fmt, v))
        if self.updating then return end
        Set(path, v)
        ns:ApplyAll()
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    refreshers[#refreshers + 1] = function()
        s.updating = true
        s:SetValue(Get(path))
        val:SetText(format(fmt, Get(path)))
        s.updating = false
    end
    return s
end

-- Dropdown: neues Menüsystem, falls vorhanden, sonst das alte UIDropDownMenu
-- getOptions() liefert { {wert, anzeigetext}, ... }
local function Dropdown(parent, text, x, y, width, getOptions, getValue, setValue)
    Label(parent, text, x, y)
    local function onSelect(v)
        setValue(v)
        Refresh()
    end

    if MenuUtil and CreateFrame then
        local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and dd then
            dd:SetWidth(width)
            dd:SetPoint("TOPLEFT", x, y - 16)
            dd:SetupMenu(function(_, root)
                local opts = getOptions()
                if #opts > 20 and root.SetScrollMode then root:SetScrollMode(400) end
                for _, o in ipairs(opts) do
                    root:CreateRadio(o[2],
                        function() return getValue() == o[1] end,
                        function() onSelect(o[1]) end)
                end
            end)
            refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
            return dd
        end
    end

    -- älterer Client
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y - 12)
    UIDropDownMenu_SetWidth(dd, width - 20)
    UIDropDownMenu_Initialize(dd, function()
        for _, o in ipairs(getOptions()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = o[2]
            info.checked = (getValue() == o[1])
            info.func = function() onSelect(o[1]) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    refreshers[#refreshers + 1] = function()
        local cur = getValue()
        for _, o in ipairs(getOptions()) do
            if o[1] == cur then UIDropDownMenu_SetText(dd, o[2]) return end
        end
        UIDropDownMenu_SetText(dd, "–")
    end
    return dd
end

local function OptionDropdown(parent, text, path, options, x, y)
    return Dropdown(parent, text, x, y, 220,
        function() return options end,
        function() return Get(path) end,
        function(v) Set(path, v); ns:ApplyAll() end)
end

-- Aktionsknopf mit Sicherheitsabfrage: erster Klick fragt, zweiter Klick führt aus
local function ConfirmButton(parent, text, width, x, y, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", function(self)
        if self.armed and GetTime() - self.armed < 4 then
            self.armed = nil
            self:SetText(text)
            action()
            Refresh()
        else
            self.armed = GetTime()
            self:SetText("Sicher? Nochmal klicken")
            C_Timer.After(4, function()
                if self.armed and GetTime() - self.armed >= 4 then
                    self.armed = nil; self:SetText(text)
                end
            end)
        end
    end)
    return b
end

local function OpenColorPicker(c, onChange)
    local prev = { r = c.r, g = c.g, b = c.b }
    local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        c.r, c.g, c.b = r, g, b
        onChange()
    end
    local function cancel()
        c.r, c.g, c.b = prev.r, prev.g, prev.b
        onChange()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c.r, g = c.g, b = c.b, hasOpacity = false,
            swatchFunc = apply, cancelFunc = cancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame.previousValues = prev
        ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

-- Scrollbarer Inhaltsbereich, damit lange Seiten nicht über den Fensterrand laufen
local function MakeScroll(page, top, height)
    local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, page, "ScrollFrameTemplate")
    if not ok or not sf then
        sf = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    end
    sf:SetPoint("TOPLEFT", 0, top)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(600, height)
    sf:SetScrollChild(child)
    sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
    return child
end

-- Eine Seite im Optionsfenster
local function NewPage(title, height)
    local page = CreateFrame("Frame")
    page:Hide()
    page:SetScript("OnShow", Refresh)
    Label(page, title, 14, -12, 16, GOLD)
    return page, MakeScroll(page, -40, height or 600)
end

local function Section(parent, text, x, y)
    local fs = Label(parent, text, x, y, 13, GOLD)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.85, 0.65, 0.29, 0.35)
    line:SetSize(260, 1)
    line:SetPoint("TOPLEFT", x, y - 18)
    return fs
end

---------------------------------------------------------------------------
-- Startseite: Logo, Anleitung, Befehle
---------------------------------------------------------------------------
local ADDON = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local function BuildMain(page)
    -- Kopf mit Logo
    local logo = page:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(MEDIA .. "logo")
    logo:SetSize(96, 96)
    logo:SetPoint("TOPLEFT", 10, -8)

    local title = page:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 26, "")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -18)
    title:SetText("ForeverFrames")

    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = meta and meta(ADDON, "Version") or ""
    local sub = Label(page, "", 0, 0, 12)
    sub:ClearAllPoints()
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Flache Spieler- und Ziel-Frames mit Debuffs   ·   Version " .. version)

    -- Anleitung
    local H = "|cffd8a64a"
    local guide = page:CreateFontString(nil, "OVERLAY")
    guide:SetFont(STANDARD_TEXT_FONT, 12, "")
    guide:SetTextColor(0.85, 0.86, 0.9)
    guide:SetJustifyH("LEFT")
    guide:SetJustifyV("TOP")
    guide:SetSpacing(3)
    -- Breite folgt der Seite, WoW bricht die Absätze selbst um
    guide:SetPoint("TOPLEFT", 16, -120)
    guide:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    guide:SetWordWrap(true)
    guide:SetText(table.concat({
        H .. "Einstellungen|r",
        "Links unter ForeverFrames findest du die Seiten Spieler, Ziel und Profile. Jeder Frame hat dort seine eigene Größe, Farbe, Textur und sein eigenes Portrait.",
        "",
        H .. "Verschieben|r",
        "Über Esc den Bearbeitungsmodus öffnen und die blau markierten Frames ziehen. Beim Loslassen rasten sie am anderen Frame ein (gleiche Höhe, untereinander oder spiegelbildlich) und, falls aktiviert, am Raster.",
        "",
        H .. "Buffs|r",
        "Stehen standardmäßig über dem Frame. Goldrahmen: von dir. Blau leuchtend: auf einem Gegner und von dir entfernbar.",
        "",
        H .. "Debuffs|r",
        "Große Symbole: von dir. Kleine, blasse Symbole: von anderen. Die Rahmenfarbe zeigt den Typ: |cff3399ffMagie|r, |cff9900ffFluch|r, |cff996600Krankheit|r, |cff009900Gift|r. Was du selbst entfernen kannst, leuchtet auf deinem Frame.",
        "",
        H .. "Bedienung|r",
        "Linksklick auf einen Frame wählt die Einheit aus, Rechtsklick öffnet ihr Menü.",
        "",
        H .. "Befehle|r",
        "|cffffffff/ff|r  –  öffnet diese Einstellungen",
        "|cffffffff/ff unlock|r  –  öffnet den Bearbeitungsmodus zum Verschieben",
        "|cffffffff/foreverframes|r  –  gleich wie /ff",
    }, "\n"))

    -- Optionen direkt unter dem Textende, egal wie lang er umbricht
    local cb = Checkbox(page, "Blizzard-Spieler- und Zielrahmen ausblenden", { "hideBlizzard" }, 14, 0)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", -2, -18)
    local hint = Label(page, "Wieder einblenden wirkt erst nach /reload.", 0, 0, 10)
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 30, -2)
    local cbBuffs = Checkbox(page, "Blizzards Buffleiste oben rechts ausblenden", { "hideBlizzBuffs" }, 14, 0)
    cbBuffs:ClearAllPoints()
    cbBuffs:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -30, -10)
    local cbDebuffs = Checkbox(page, "Blizzards Debuffleiste oben rechts ausblenden", { "hideBlizzDebuffs" }, 14, 0)
    cbDebuffs:ClearAllPoints()
    cbDebuffs:SetPoint("TOPLEFT", cbBuffs, "BOTTOMLEFT", 0, -4)
    local hint2 = Label(page, "Buffs abbrechen per Rechtsklick geht nur über Blizzards Buffleiste.", 0, 0, 10)
    hint2:ClearAllPoints()
    hint2:SetPoint("TOPLEFT", cbDebuffs, "BOTTOMLEFT", 30, -2)
    if not ns.hasEditMode then
        local lock = Checkbox(page, "Rahmen gesperrt (Haken entfernen zum Verschieben)", { "locked" }, 14, 0)
        lock:ClearAllPoints()
        lock:SetPoint("TOPLEFT", hint2, "BOTTOMLEFT", -30, -8)
    end
end

---------------------------------------------------------------------------
-- Spieler / Ziel: links Balken und Debuffs, rechts Portrait
---------------------------------------------------------------------------
local PREVIEW_H = 230   -- Höhe des Vorschaubereichs oben auf der Seite

local function BuildPreview(content, key)
    local stage = CreateFrame("Frame", nil, content)
    stage:SetPoint("TOPLEFT", 8, -4)
    stage:SetPoint("TOPRIGHT", -8, -4)
    stage:SetHeight(PREVIEW_H - 16)
    local bg = stage:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    local edge = stage:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetHeight(1)
    edge:SetColorTexture(0.85, 0.65, 0.29, 0.35)
    local cap = Label(stage, "Vorschau (Beispieldaten)", 8, -6, 10)

    local pv = ns:CreatePreview(key, stage)
    -- Kastenoberkante etwa im oberen Drittel, damit Buffs darüber Platz haben
    pv:SetPoint("TOP", stage, "TOP", 0, -78)
    stage:SetScript("OnShow", function() ns.Try(pv.ApplySettings, pv) end)
    refreshers[#refreshers + 1] = function() ns.Try(pv.ApplySettings, pv) end
end

local function BuildUnit(content, key)
    BuildPreview(content, key)
    -- Einstellungen beginnen unter der Vorschau
    local p = CreateFrame("Frame", nil, content)
    p:SetPoint("TOPLEFT", 0, -PREVIEW_H)
    p:SetPoint("BOTTOMRIGHT")
    local L, R = 16, 320

    -- linke Spalte
    Section(p, "Allgemein", L, -4)
    Slider(p, "Skalierung", { key, "scale" }, 0.5, 2.0, 0.05, L, -30)
    Checkbox(p, key == "player" and "Deine Debuffs anzeigen" or "Debuffs anzeigen", { key, "showDebuffs" }, L - 2, -76)
    local y = -104
    if key == "target" then
        Checkbox(p, "Nur eigene Debuffs zeigen", { key, "onlyOwnDebuffs" }, L - 2, -104)
        y = -132
    end

    Section(p, "Balken", L, y - 10)
    y = y - 36
    OptionDropdown(p, "Farbe", { key, "healthColor" }, {
        { "class", "Klassenfarbe (Standard)" },
        { "health", "Nach Lebenspunkten" },
        { "custom", "Eigene Farbe" },
    }, L, y)
    local swatch = CreateFrame("Button", nil, p)
    swatch:SetSize(22, 22)
    swatch:SetPoint("TOPLEFT", L + 230, y - 18)
    local swEdge = swatch:CreateTexture(nil, "BACKGROUND")
    swEdge:SetAllPoints(); swEdge:SetColorTexture(0, 0, 0, 1)
    local swTex = swatch:CreateTexture(nil, "ARTWORK")
    swTex:SetPoint("TOPLEFT", 2, -2); swTex:SetPoint("BOTTOMRIGHT", -2, 2)
    swatch:SetScript("OnClick", function()
        OpenColorPicker(ns.profile[key].customColor, function() ns:ApplyAll(); Refresh() end)
    end)
    refreshers[#refreshers + 1] = function()
        local c = ns.profile[key].customColor
        swTex:SetColorTexture(c.r, c.g, c.b, 1)
        swatch:SetShown(ns.profile[key].healthColor == "custom")
    end
    if key == "target" then
        Label(p, "NPCs nutzen immer die Reaktionsfarbe.", L, y - 46, 10)
    end

    y = y - 62
    OptionDropdown(p, "Text im Balken", { key, "textMode" }, {
        { "both", "Wert + Prozent" }, { "pct", "Nur Prozent" },
        { "val", "Wert / Maximum" }, { "none", "Kein Text" },
    }, L, y)

    y = y - 54
    Dropdown(p, "Textur", L, y, 220,
        function()
            -- Wert = Name, Anzeige = Name ohne Pfad (nur der letzte Teil)
            local o = {}
            for _, t in ipairs(ns:GetBarTextures()) do
                o[#o + 1] = { t[1], t[1]:match("([^\\/]+)$") or t[1] }
            end
            return o
        end,
        function() return ns.profile[key].barTexture end,
        function(v) ns.profile[key].barTexture = v; ns:ApplyAll() end)
    Checkbox(p, "Schattierung (dunkle untere Hälfte)", { key, "barShade" }, L - 2, y - 50)

    -- Drachen-Ornament (linke Spalte unten)
    y = y - 92
    Section(p, "Ornament (Blizzard-Drache)", L, y)
    local ornOpts = {}
    if key == "target" then ornOpts[#ornOpts + 1] = { "auto", "Automatisch (nach Gegner)" } end
    for _, o in ipairs({
        { "none", "Keins" }, { "elite", "Elite (Gold)" },
        { "rareelite", "Rar-Elite (Silber)" }, { "worldboss", "Boss" },
    }) do ornOpts[#ornOpts + 1] = o end
    OptionDropdown(p, key == "player" and "Optik (nur Aussehen)" or "Anzeige", { key, "ornament" }, ornOpts, L, y - 26)
    Label(p, "Die Größe richtet sich automatisch nach der Portrait-Größe.", L, y - 76, 10)
    Slider(p, "Versatz X (+ = nach außen)", { key, "ornX" }, -60, 60, 1, L, y - 96, "%d")
    Slider(p, "Versatz Y (+ = nach oben)", { key, "ornY" }, -60, 60, 1, L, y - 144, "%d")

    -- rechte Spalte
    Section(p, "Portrait", R, -4)
    Checkbox(p, "Portrait anzeigen", { key, "portrait" }, R - 2, -28)
    local shapes = {}
    for _, s in ipairs(ns.PORTRAIT_SHAPES) do shapes[#shapes + 1] = s end
    OptionDropdown(p, "Form", { key, "portraitShape" }, shapes, R, -60)
    Slider(p, "Größe", { key, "portraitSize" }, 40, 110, 1, R, -114, "%d px")
    Slider(p, "Versatz X (+ = nach außen)", { key, "portraitX" }, -40, 40, 1, R, -162, "%d")
    Slider(p, "Versatz Y (+ = nach oben)", { key, "portraitY" }, -40, 40, 1, R, -210, "%d")

    -- Buffs (rechte Spalte unter dem Portrait)
    Section(p, "Buffs", R, -258)
    Checkbox(p, "Buffs anzeigen", { key, "showBuffs" }, R - 2, -282)
    OptionDropdown(p, "Position", { key, "buffPos" }, {
        { "top", "Über dem Frame (Standard)" },
        { "bottom", "Unter den Debuffs" },
        { "side", "Neben dem Frame (innen)" },
    }, R, -312)
    OptionDropdown(p, "Filter", { key, "buffFilter" }, {
        { "all", "Alle" },
        { "own", "Nur eigene" },
        { "short", "Nur kurze (unter 1 Minute)" },
        { "steal", "Nur bannbare / stehlbare" },
    }, R, -364)
    Slider(p, "Symbolgröße", { key, "buffSize" }, 16, 32, 1, R, -418, "%d px")
    Slider(p, "Maximale Anzahl", { key, "buffMax" }, 4, 24, 1, R, -464, "%d")
    if key == "target" then
        Checkbox(p, "Bannbare Buffs auf Gegnern hervorheben", { key, "buffSteal" }, R - 2, -508)
    end
end

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
local function BuildProfiles(p)
    Label(p, "Charakter", 16, -6)
    local charLbl = Label(p, "", 16, -22, 12, { 1, 1, 1 })
    refreshers[#refreshers + 1] = function() charLbl:SetText(ns.charKey) end

    local function AllProfiles()
        local o = {}
        for _, n in ipairs(ns:GetProfileNames()) do o[#o + 1] = { n, n } end
        return o
    end
    Dropdown(p, "Aktives Profil", 16, -46, 220, AllProfiles,
        function() return ns:GetProfileName() end,
        function(v) ns:SetProfile(v) end)

    Label(p, "Neues Profil", 16, -100)
    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(150, 20)
    eb:SetPoint("TOPLEFT", 22, -116)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(32)
    local newBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    newBtn:SetSize(80, 22)
    newBtn:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    newBtn:SetText("Anlegen")
    local function CreateNew()
        if ns:NewProfile(eb:GetText()) then
            eb:SetText(""); eb:ClearFocus(); Refresh()
        else
            print("|cffd8a64aForeverFrames:|r Name fehlt oder ist schon vergeben.")
        end
    end
    newBtn:SetScript("OnClick", CreateNew)
    eb:SetScript("OnEnterPressed", CreateNew)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)

    local copySource
    local function OtherProfiles()
        local o = {}
        for _, n in ipairs(ns:GetProfileNames()) do
            if n ~= ns:GetProfileName() then o[#o + 1] = { n, n } end
        end
        return o
    end
    Dropdown(p, "Einstellungen kopieren von", 16, -150, 220, OtherProfiles,
        function()
            if copySource == ns:GetProfileName() or (copySource and not ns.db.profiles[copySource]) then
                copySource = nil
            end
            return copySource
        end,
        function(v) copySource = v end)
    ConfirmButton(p, "Kopieren", 120, 248, -166, function()
        if copySource then ns:CopyProfileFrom(copySource) end
    end)

    ConfirmButton(p, "Profil zurücksetzen", 170, 16, -214, function() ns:ResetProfile() end)
    local del = ConfirmButton(p, "Profil löschen", 150, 192, -214, function() ns:DeleteProfile() end)
    refreshers[#refreshers + 1] = function() del:SetEnabled(ns:GetProfileName() ~= "Standard") end
    Label(p, "Position, Größe und Farben gehören zum Profil.\nJeder Charakter merkt sich sein eigenes Profil.", 16, -248, 10)
end

---------------------------------------------------------------------------
function ns:CreateOptions()
    local main = CreateFrame("Frame")
    main:Hide()
    main:SetScript("OnShow", Refresh)
    BuildMain(MakeScroll(main, 0, 820))
    local player, playerC = NewPage("Spieler", 620 + PREVIEW_H)
    BuildUnit(playerC, "player")
    local target, targetC = NewPage("Ziel", 650 + PREVIEW_H)
    BuildUnit(targetC, "target")
    local prof, profC = NewPage("Profile")
    BuildProfiles(profC)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(main, "ForeverFrames")
        Settings.RegisterCanvasLayoutSubcategory(cat, player, "Spieler")
        Settings.RegisterCanvasLayoutSubcategory(cat, target, "Ziel")
        Settings.RegisterCanvasLayoutSubcategory(cat, prof, "Profile")
        Settings.RegisterAddOnCategory(cat)
        ns.settingsCategory = cat
    elseif InterfaceOptions_AddCategory then
        main.name = "ForeverFrames"
        player.name, player.parent = "Spieler", "ForeverFrames"
        target.name, target.parent = "Ziel", "ForeverFrames"
        prof.name, prof.parent = "Profile", "ForeverFrames"
        for _, pg in ipairs({ main, player, target, prof }) do InterfaceOptions_AddCategory(pg) end
        ns.legacyPanel = main
    end
end

-- /ff öffnet die Einstellungen
function ns:ToggleOptions()
    if ns.settingsCategory and Settings.OpenToCategory then
        local cat = ns.settingsCategory
        Settings.OpenToCategory(cat.GetID and cat:GetID() or cat.ID)
    elseif ns.legacyPanel and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(ns.legacyPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.legacyPanel)
    end
end
