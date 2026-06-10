class_name Goods
extends RefCounted

## Alle Warentypen des Spiels. Reihenfolge = Enum-Wert (für Serialisierung).
##
## ORIGINAL-ABGLEICH (Die Siedler 2 / RTTR `gameTypes/GoodTypes.h`): Im Original
## sind die zwölf WERKZEUGE eigene Waren (Zange..Bogen) — ein Träger wird durch
## „Träger + passendes Werkzeug" zum Spezialisten (siehe [Jobs.tool_for]). Die
## generische Ware TOOLS bleibt vorerst als Alt-Eintrag bestehen (bisher inert,
## nur Ausgang des Werkzeugmachers) und wird in einer späteren Stufe durch die
## einzelnen Werkzeuge ersetzt. NEUE Waren werden ANGEHÄNGT, damit bestehende
## Spielstände gültig bleiben (Enum-Werte 0..18 unverändert).

enum {
	WOOD,        # 0  Holz (Baumstamm)
	BOARDS,      # 1  Bretter
	STONE,       # 2  Steine
	GRAIN,       # 3  Getreide
	FLOUR,       # 4  Mehl
	WATER,       # 5  Wasser
	BREAD,       # 6  Brot
	FISH,        # 7  Fisch
	MEAT,        # 8  Fleisch
	COAL,        # 9  Kohle
	IRON_ORE,    # 10 Eisenerz
	IRON,        # 11 Eisen
	GOLD_ORE,    # 12 Gold(erz) — im Original „Gold", wandert in die Münzprägerei
	COINS,       # 13 Münzen
	BEER,        # 14 Bier
	TOOLS,       # 15 (Alt) generisches Werkzeug — wird durch die Einzelwerkzeuge ersetzt
	SWORD,       # 16 Schwert
	SHIELD,      # 17 Schild
	PIG,         # 18 Schwein (im Original „Ham": Schweinefarm -> Schlachterei -> Fleisch)
	# --- Einzelwerkzeuge (Original S2), angehängt ab 19 ---
	TONGS,       # 19 Zange       -> Werkzeugmacher
	HAMMER,      # 20 Hammer      -> Bauarbeiter/Waffenschmied/Geologe/Schiffsbauer
	AXE,         # 21 Axt         -> Holzfäller
	SAW,         # 22 Säge        -> Zimmermann (Sägewerk)
	PICKAXE,     # 23 Spitzhacke  -> Steinmetz/Bergarbeiter
	SHOVEL,      # 24 Schaufel    -> Förster/Planierer
	CRUCIBLE,    # 25 Schmelztiegel -> Schmelzer/Münzer
	ROD_AND_LINE,# 26 Angel       -> Fischer
	SCYTHE,      # 27 Sense       -> Bauer
	CLEAVER,     # 28 Beil        -> Schlachter
	ROLLING_PIN, # 29 Nudelholz   -> Bäcker
	BOW,         # 30 Bogen       -> Jäger/Späher
}

const COUNT := 31

## Erste/letzte ID des zusammenhängenden Werkzeug-Blocks (für [method is_tool_good]).
const FIRST_TOOL := TONGS
const LAST_TOOL := BOW

## Stabile String-IDs (Index = Enum-Wert) — für tuning.json und Debug/UI.
const KEYS := [
	"wood", "boards", "stone", "grain", "flour", "water", "bread", "fish",
	"meat", "coal", "iron_ore", "iron", "gold_ore", "coins", "beer", "tools",
	"sword", "shield", "pig",
	"tongs", "hammer", "axe", "saw", "pickaxe", "shovel", "crucible",
	"rod_and_line", "scythe", "cleaver", "rolling_pin", "bow",
]


static func name_of(g: int) -> String:
	match g:
		WOOD: return "Holz"
		BOARDS: return "Bretter"
		STONE: return "Steine"
		GRAIN: return "Getreide"
		FLOUR: return "Mehl"
		WATER: return "Wasser"
		BREAD: return "Brot"
		FISH: return "Fisch"
		MEAT: return "Fleisch"
		COAL: return "Kohle"
		IRON_ORE: return "Eisenerz"
		IRON: return "Eisen"
		GOLD_ORE: return "Gold"
		COINS: return "Münzen"
		BEER: return "Bier"
		TOOLS: return "Werkzeug"
		SWORD: return "Schwert"
		SHIELD: return "Schild"
		PIG: return "Schwein"
		TONGS: return "Zange"
		HAMMER: return "Hammer"
		AXE: return "Axt"
		SAW: return "Säge"
		PICKAXE: return "Spitzhacke"
		SHOVEL: return "Schaufel"
		CRUCIBLE: return "Schmelztiegel"
		ROD_AND_LINE: return "Angel"
		SCYTHE: return "Sense"
		CLEAVER: return "Beil"
		ROLLING_PIN: return "Nudelholz"
		BOW: return "Bogen"
	return "?"


## Stabile String-ID einer Ware (für tuning.json / Save-Debug). "" wenn unbekannt.
static func key_of(g: int) -> String:
	return KEYS[g] if g >= 0 and g < KEYS.size() else ""


## Enum-Wert zu einer String-ID, oder -1 wenn unbekannt.
static func id_of(key: String) -> int:
	return KEYS.find(key)


## Ist diese Ware eines der zwölf Spezialwerkzeuge (Träger + Werkzeug -> Beruf)?
## Hinweis: NICHT `is_tool` nennen — das kollidiert mit der eingebauten
## `Script.is_tool()` und würde beim Aufruf über den Klassennamen verdeckt.
static func is_tool_good(g: int) -> bool:
	return g >= FIRST_TOOL and g <= LAST_TOOL
