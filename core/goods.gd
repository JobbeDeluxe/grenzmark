class_name Goods
extends RefCounted

## Alle Warentypen des Spiels. Reihenfolge = Enum-Wert (für Serialisierung).

enum {
	WOOD,      # Holz (Baumstamm)
	BOARDS,    # Bretter
	STONE,     # Steine
	GRAIN,     # Getreide
	FLOUR,     # Mehl
	WATER,     # Wasser
	BREAD,     # Brot
	FISH,      # Fisch
	MEAT,      # Fleisch
	COAL,      # Kohle
	IRON_ORE,  # Eisenerz
	IRON,      # Eisen
	GOLD_ORE,  # Golderz
	COINS,     # Münzen
	BEER,      # Bier
	TOOLS,     # Werkzeug
	SWORD,     # Schwert
	SHIELD,    # Schild
	PIG,       # Schwein (Schweinefarm -> Schlachterei -> Fleisch)
}

const COUNT := 19


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
		GOLD_ORE: return "Golderz"
		COINS: return "Münzen"
		BEER: return "Bier"
		TOOLS: return "Werkzeug"
		SWORD: return "Schwert"
		SHIELD: return "Schild"
		PIG: return "Schwein"
	return "?"
