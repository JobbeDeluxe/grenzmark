class_name Terrain
extends RefCounted

## Terrain-Typen und ihre Eigenschaften.
## Terrain sitzt auf den Dreiecken, nicht auf den Knoten.

enum {
	WATER,    # Wasser — nicht begehbar, nicht bebaubar
	MEADOW,   # Wiese/Gras — bebaubar
	MOUNTAIN, # Berg — Minen, sonst nicht bebaubar
	SAND,     # Sand/Wüste — begehbar, nicht bebaubar
	SWAMP,    # Sumpf — begehbar, nicht bebaubar
	SNOW,     # Schnee/Fels — gesperrt
}

const COUNT := 6


static func is_water(t: int) -> bool:
	return t == WATER


static func is_mountain(t: int) -> bool:
	return t == MOUNTAIN


## Bebaubar = normales Gebäude (Hütte/Haus/Burg) möglich.
static func is_buildable(t: int) -> bool:
	return t == MEADOW


## Begehbar = Träger/Straßen erlaubt.
static func is_walkable(t: int) -> bool:
	return t == MEADOW or t == MOUNTAIN or t == SAND or t == SWAMP


## Gesperrt = blockiert auch Flaggen.
static func is_blocking(t: int) -> bool:
	return t == WATER or t == SNOW


static func color(t: int) -> Color:
	match t:
		WATER:    return Color(0.12, 0.35, 0.62)
		MEADOW:   return Color(0.32, 0.55, 0.20)
		MOUNTAIN: return Color(0.45, 0.40, 0.38)
		SAND:     return Color(0.78, 0.71, 0.45)
		SWAMP:    return Color(0.30, 0.38, 0.28)
		SNOW:     return Color(0.90, 0.92, 0.96)
	return Color.MAGENTA


static func name_of(t: int) -> String:
	match t:
		WATER:    return "Wasser"
		MEADOW:   return "Wiese"
		MOUNTAIN: return "Berg"
		SAND:     return "Sand"
		SWAMP:    return "Sumpf"
		SNOW:     return "Schnee"
	return "?"
