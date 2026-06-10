class_name Jobs
extends RefCounted

## Berufe (Personen) — wie im Original (Die Siedler 2 / RTTR `gameTypes/JobTypes.h`
## und `gameData/JobConsts.cpp`). Ein Lager (HQ/Lagerhaus) hält von JEDEM Beruf
## einen Bestand, analog zu [Goods] für Waren — das ist das S2-Lagermodell
## (RTTR `Inventory` = goods[] + people[]).
##
## Kernmechanik: ein generischer Träger (HELPER) wird zusammen mit dem passenden
## WERKZEUG zum Spezialisten ([method tool_for]). Berufe ohne Werkzeug entstehen
## direkt aus einem Träger (z. B. Müller/Brauer); Soldaten entstehen aus
## Schwert + Bier und sind nicht über ein Werkzeug rekrutierbar.
##
## Es ist bewusst NICHT die volle RTTR-Liste (kein Schiffsbauer/Esel/Köhler/
## Addon-Berufe), sondern genau die Berufe, die Grenzmarks Gebäude einsetzen,
## plus die Soldatenränge und die Erkundungsberufe (Geologe/Späher, Issue #21).
## Reihenfolge = Enum-Wert (Serialisierung); NEUE Berufe nur ANHÄNGEN.

enum {
	HELPER,         # 0  Träger / Siedler (Basis, kein Werkzeug)
	WOODCUTTER,     # 1  Holzfäller
	FISHER,         # 2  Fischer
	FORESTER,       # 3  Förster
	CARPENTER,      # 4  Zimmermann (Sägewerk)
	STONEMASON,     # 5  Steinmetz (Steinbruch)
	HUNTER,         # 6  Jäger
	FARMER,         # 7  Bauer
	MILLER,         # 8  Müller
	BAKER,          # 9  Bäcker
	BUTCHER,        # 10 Schlachter
	MINER,          # 11 Bergarbeiter (alle Minen)
	BREWER,         # 12 Brauer
	PIGBREEDER,     # 13 Schweinezüchter
	IRONFOUNDER,    # 14 Schmelzer (Eisenschmelze)
	MINTER,         # 15 Münzer (Münzprägerei)
	METALWORKER,    # 16 Werkzeugmacher (Schlosser)
	ARMORER,        # 17 Waffenschmied (Schmiede)
	BUILDER,        # 18 Bauarbeiter
	PLANER,         # 19 Planierer (Geländeplanierung)
	GEOLOGIST,      # 20 Geologe (Issue #21)
	SCOUT,          # 21 Späher/Pionier (Issue #21)
	# --- Soldatenränge (schwächster zuerst), Sprites/Stufenleiter: Issue #28 ---
	PRIVATE,        # 22 Gehilfe
	PRIVATE_FIRST,  # 23 Gefreiter
	SERGEANT,       # 24 Unteroffizier
	OFFICER,        # 25 Offizier
	GENERAL,        # 26 General
}

const COUNT := 27

const FIRST_SOLDIER := PRIVATE
const LAST_SOLDIER := GENERAL

## Stabile String-IDs (Index = Enum-Wert) — für tuning.json und Debug/UI.
const KEYS := [
	"helper", "woodcutter", "fisher", "forester", "carpenter", "stonemason",
	"hunter", "farmer", "miller", "baker", "butcher", "miner", "brewer",
	"pigbreeder", "ironfounder", "minter", "metalworker", "armorer",
	"builder", "planer", "geologist", "scout",
	"private", "private_first", "sergeant", "officer", "general",
]


static func name_of(j: int) -> String:
	match j:
		HELPER: return "Träger"
		WOODCUTTER: return "Holzfäller"
		FISHER: return "Fischer"
		FORESTER: return "Förster"
		CARPENTER: return "Zimmermann"
		STONEMASON: return "Steinmetz"
		HUNTER: return "Jäger"
		FARMER: return "Bauer"
		MILLER: return "Müller"
		BAKER: return "Bäcker"
		BUTCHER: return "Schlachter"
		MINER: return "Bergarbeiter"
		BREWER: return "Brauer"
		PIGBREEDER: return "Schweinezüchter"
		IRONFOUNDER: return "Schmelzer"
		MINTER: return "Münzer"
		METALWORKER: return "Werkzeugmacher"
		ARMORER: return "Waffenschmied"
		BUILDER: return "Bauarbeiter"
		PLANER: return "Planierer"
		GEOLOGIST: return "Geologe"
		SCOUT: return "Späher"
		PRIVATE: return "Gehilfe"
		PRIVATE_FIRST: return "Gefreiter"
		SERGEANT: return "Unteroffizier"
		OFFICER: return "Offizier"
		GENERAL: return "General"
	return "?"


static func key_of(j: int) -> String:
	return KEYS[j] if j >= 0 and j < KEYS.size() else ""


static func id_of(key: String) -> int:
	return KEYS.find(key)


## Werkzeug (Goods.*), das ein Träger braucht, um diesen Beruf zu werden.
## -1 = kein Werkzeug nötig (Helper/Müller/Brauer/Schweinezüchter) bzw. nicht
## über Werkzeug rekrutierbar (Soldaten). Quelle: RTTR JobConsts.cpp.
static func tool_for(j: int) -> int:
	match j:
		WOODCUTTER: return Goods.AXE
		FISHER: return Goods.ROD_AND_LINE
		FORESTER: return Goods.SHOVEL
		CARPENTER: return Goods.SAW
		STONEMASON: return Goods.PICKAXE
		HUNTER: return Goods.BOW
		FARMER: return Goods.SCYTHE
		BAKER: return Goods.ROLLING_PIN
		BUTCHER: return Goods.CLEAVER
		MINER: return Goods.PICKAXE
		IRONFOUNDER: return Goods.CRUCIBLE
		MINTER: return Goods.CRUCIBLE
		METALWORKER: return Goods.TONGS
		ARMORER: return Goods.HAMMER
		BUILDER: return Goods.HAMMER
		PLANER: return Goods.SHOVEL
		GEOLOGIST: return Goods.HAMMER
		SCOUT: return Goods.BOW
	return -1


static func is_soldier(j: int) -> bool:
	return j >= FIRST_SOLDIER and j <= LAST_SOLDIER
