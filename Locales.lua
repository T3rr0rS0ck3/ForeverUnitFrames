-- ForeverUnitFrames: Lokalisierung
-- Schlüssel sind die englischen Texte. Englisch ist der Standard und Fallback für
-- alle Clients; nur deDE bekommt deutsche Übersetzungen.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

if GetLocale() ~= "deDE" then return end

local T = {
    -- Allgemein / Chat
    ["Change will be applied after combat."] = "Änderung wird nach dem Kampf übernommen.",
    ["Not possible in combat."] = "Im Kampf nicht möglich.",
    ["Frames locked."] = "Rahmen gesperrt.",
    ["Frames unlocked. Drag them with the mouse, then /ff lock."] = "Rahmen entsperrt. Mit der Maus verschieben, danach /ff lock.",
    ["Name missing or already taken."] = "Name fehlt oder ist schon vergeben.",
    ["Dragon artwork not found (%s). Please report."] = "Drachen-Grafik nicht gefunden (%s). Bitte melden.",
    ["Saved. Use /reload to write it to disk."] = "Gespeichert. Mit /reload wird es auf die Festplatte geschrieben.",
    ["Default"] = "Standard",

    -- Frames
    ["Round"] = "Rund",
    ["Square"] = "Eckig",
    ["Rounded"] = "Abgerundet",
    ["Hexagon"] = "Sechseck",
    ["Octagon"] = "Achteck",
    ["Diamond"] = "Raute",
    ["Elite"] = "Elite",
    ["Rare"] = "Rar",
    ["Rare Elite"] = "Rar-Elite",
    ["Boss"] = "Boss",
    ["Flat"] = "Flach",
    ["Gloss"] = "Glanz",
    ["Ghost"] = "Geist",
    ["Dead"] = "Tot",
    ["Offline"] = "Offline",
    ["Target"] = "Ziel",
    ["Player"] = "Spieler",
    ["dead"] = "tot",
    ["hostile"] = "feindlich",
    ["neutral"] = "neutral",
    ["friendly"] = "freundlich",
    ["Combat"] = "Kampf",
    ["Sample"] = "Beispiel",
    ["ForeverUnitFrames: Target"] = "ForeverUnitFrames: Ziel",
    ["ForeverUnitFrames: Player"] = "ForeverUnitFrames: Spieler",
    ["Target of Target"] = "Ziel des Ziels",
    ["ForeverUnitFrames: Target of Target"] = "ForeverUnitFrames: Ziel des Ziels",

    -- Beispieldaten der Vorschau
    ["Mark of the Wild"] = "Mal der Wildnis",
    ["Rejuvenation"] = "Verjüngung",
    ["Power Word: Fortitude"] = "Machtwort: Seelenstärke",
    ["Power Word: Shield"] = "Machtwort: Schild",
    ["Curse of Weakness"] = "Fluch der Schwäche",
    ["Poison"] = "Gift",
    ["Warchief Grimhoof"] = "Kriegshäuptling Grimmhuf",
    ["Humanoid"] = "Humanoid",
    ["Battle Shout"] = "Schlachtruf",
    ["Mage Armor"] = "Magierüstung",
    ["Enrage"] = "Wutanfall",
    ["Rake"] = "Krallenhieb",
    ["Faerie Fire"] = "Feenfeuer",
    ["Sunder Armor"] = "Rüstung zerreißen",
    ["Shadow Word: Pain"] = "Schattenwort: Schmerz",

    -- Optionen: Bausteine
    ["Sure? Click again"] = "Sicher? Nochmal klicken",

    -- Optionen: Startseite
    ["Flat player and target frames with debuffs"] = "Flache Spieler- und Ziel-Frames mit Debuffs",
    ["Version"] = "Version",
    ["Settings"] = "Einstellungen",
    ["On the left under ForeverUnitFrames you will find the pages Player, Target, Target of Target and Profiles. Each frame has its own size, color, texture and portrait there."] =
        "Links unter ForeverUnitFrames findest du die Seiten Spieler, Ziel, Ziel des Ziels und Profile. Jeder Frame hat dort seine eigene Größe, Farbe, Textur und sein eigenes Portrait.",
    ["Moving"] = "Verschieben",
    ["Open Edit Mode via Esc and drag the frames highlighted in blue. When released they snap to the other frame (same height, stacked or mirrored) and, if enabled, to the grid."] =
        "Über Esc den Bearbeitungsmodus öffnen und die blau markierten Frames ziehen. Beim Loslassen rasten sie am anderen Frame ein (gleiche Höhe, untereinander oder spiegelbildlich) und, falls aktiviert, am Raster.",
    ["Buffs"] = "Buffs",
    ["Shown above the frame by default. Gold border: cast by you. Glowing blue: on an enemy and removable by you."] =
        "Stehen standardmäßig über dem Frame. Goldrahmen: von dir. Blau leuchtend: auf einem Gegner und von dir entfernbar.",
    ["Debuffs"] = "Debuffs",
    ["Large icons: cast by you. Small, faded icons: cast by others. The border color shows the type: %s, %s, %s, %s. Anything you can remove yourself glows on your frame."] =
        "Große Symbole: von dir. Kleine, blasse Symbole: von anderen. Die Rahmenfarbe zeigt den Typ: %s, %s, %s, %s. Was du selbst entfernen kannst, leuchtet auf deinem Frame.",
    ["Magic"] = "Magie",
    ["Curse"] = "Fluch",
    ["Disease"] = "Krankheit",
    ["Controls"] = "Bedienung",
    ["Left-click a frame to target the unit, right-click opens its menu."] =
        "Linksklick auf einen Frame wählt die Einheit aus, Rechtsklick öffnet ihr Menü.",
    ["Commands"] = "Befehle",
    ["opens these settings"] = "öffnet diese Einstellungen",
    ["opens Edit Mode for moving frames"] = "öffnet den Bearbeitungsmodus zum Verschieben",
    ["same as /ff"] = "gleich wie /ff",
    ["Hide Blizzard player and target frames"] = "Blizzard-Spieler- und Zielrahmen ausblenden",
    ["Showing them again only takes effect after /reload."] = "Wieder einblenden wirkt erst nach /reload.",
    ["Hide Blizzard's buff bar (top right)"] = "Blizzards Buffleiste oben rechts ausblenden",
    ["Hide Blizzard's debuff bar (top right)"] = "Blizzards Debuffleiste oben rechts ausblenden",
    ["Cancelling buffs with right-click only works via Blizzard's buff bar."] =
        "Buffs abbrechen per Rechtsklick geht nur über Blizzards Buffleiste.",
    ["Frames locked (uncheck to move them)"] = "Rahmen gesperrt (Haken entfernen zum Verschieben)",

    -- Optionen: Spieler / Ziel
    ["Preview (sample data)"] = "Vorschau (Beispieldaten)",
    ["General"] = "Allgemein",
    ["Scale"] = "Skalierung",
    ["Scale enlarges the whole frame. Bar sizes are added to it: 1.2 and -20% = 1.0."] =
        "Skalierung vergrößert den ganzen Frame. Die Balkengröße wird dazugerechnet: 1,2 und -20 % = 1,0.",
    ["Health bar"] = "Lebensbalken",
    ["Power bar"] = "Ressourcenbalken",
    ["Width"] = "Breite",
    ["Height"] = "Höhe",
    ["Keep proportions"] = "Seitenverhältnis halten",
    ["Show your debuffs"] = "Deine Debuffs anzeigen",
    ["Show debuffs"] = "Debuffs anzeigen",
    ["Show only own debuffs"] = "Nur eigene Debuffs zeigen",
    ["Show PvP icon"] = "PvP-Symbol anzeigen",
    ["Bars"] = "Balken",
    ["Color"] = "Farbe",
    ["Class color (default)"] = "Klassenfarbe (Standard)",
    ["By health"] = "Nach Lebenspunkten",
    ["Custom color"] = "Eigene Farbe",
    ["NPCs always use the reaction color."] = "NPCs nutzen immer die Reaktionsfarbe.",
    ["Bar text"] = "Text im Balken",
    ["Value + percent"] = "Wert + Prozent",
    ["Percent only"] = "Nur Prozent",
    ["Value / maximum"] = "Wert / Maximum",
    ["No text"] = "Kein Text",
    ["Texture"] = "Textur",
    ["Shading (dark lower half)"] = "Schattierung (dunkle untere Hälfte)",
    ["Show incoming heals"] = "Eingehende Heilung anzeigen",
    ["Show 5-second rule and mana ticks"] = "5-Sekunden-Regel und Mana-Ticks anzeigen",
    ["Ornament (Blizzard dragon)"] = "Ornament (Blizzard-Drache)",
    ["Automatic (by enemy)"] = "Automatisch (nach Gegner)",
    ["None"] = "Keins",
    ["Elite (gold)"] = "Elite (Gold)",
    ["Rare Elite (silver)"] = "Rar-Elite (Silber)",
    ["Style (looks only)"] = "Optik (nur Aussehen)",
    ["Display"] = "Anzeige",
    ["The size follows the portrait size automatically."] = "Die Größe richtet sich automatisch nach der Portrait-Größe.",
    ["Offset X (+ = outward)"] = "Versatz X (+ = nach außen)",
    ["Offset Y (+ = upward)"] = "Versatz Y (+ = nach oben)",
    ["Portrait"] = "Portrait",
    ["Show portrait"] = "Portrait anzeigen",
    ["Shape"] = "Form",
    ["Size"] = "Größe",
    ["Show buffs"] = "Buffs anzeigen",
    ["Position"] = "Position",
    ["Above the frame (default)"] = "Über dem Frame (Standard)",
    ["Below the debuffs"] = "Unter den Debuffs",
    ["Beside the frame (inside)"] = "Neben dem Frame (innen)",
    ["Filter"] = "Filter",
    ["All"] = "Alle",
    ["Own only"] = "Nur eigene",
    ["Short only (under 1 minute)"] = "Nur kurze (unter 1 Minute)",
    ["Dispellable / stealable only"] = "Nur bannbare / stehlbare",
    ["Icon size"] = "Symbolgröße",
    ["Maximum count"] = "Maximale Anzahl",

    -- Optionen: Profile
    ["Profiles"] = "Profile",
    ["Character"] = "Charakter",
    ["Active profile"] = "Aktives Profil",
    ["New profile"] = "Neues Profil",
    ["Create"] = "Anlegen",
    ["Copy settings from"] = "Einstellungen kopieren von",
    ["Copy"] = "Kopieren",
    ["Reset profile"] = "Profil zurücksetzen",
    ["Delete profile"] = "Profil löschen",
    ["Position, size and colors belong to the profile.\nEach character remembers its own profile."] =
        "Position, Größe und Farben gehören zum Profil.\nJeder Charakter merkt sich sein eigenes Profil.",
}

for k, v in pairs(T) do L[k] = v end
