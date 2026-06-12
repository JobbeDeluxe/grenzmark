class_name BuildingCatalog
extends RefCounted

## Daten-getriebene Gebäudedefinitionen. Eine Definition beschreibt Größe,
## Baukosten, Eingangs-/Ausgangswaren, Arbeitsdauer, benötigte Ressourcen und
## (für Militärgebäude) den Einflussradius. Neue Gebäude = nur hier ergänzen.
##
## Felder eines Defs:
##   id, name, size (WorldState.BQ_*), cost {good:n}, inputs {good:n},
##   output (Goods.* oder -1), work (Ticks), resource ("","tree","plant_tree",
##   "stone","ore","water"), influence (0 = nicht militärisch), category

static func defs() -> Dictionary:
	var H := WorldState.BQ_HUT
	var M := WorldState.BQ_HOUSE
	var C := WorldState.BQ_CASTLE
	var MINE := WorldState.BQ_MINE
	return {
		"hq": {
			id = "hq", name = "Hauptquartier", size = C, cost = {},
			inputs = {}, output = -1, work = 0, resource = "",
			influence = 9, category = "lager",
		},
		# Baubares zweites Lager (#31): zusätzlicher Lager- und Verteilknoten, um Waren
		# näher an die Verbraucher zu bringen. Kein Einfluss (rein logistisch), eigener
		# Tür↔Flagge-Träger; das Mehr-Lager-Routing in [Economy] beliefert das nächste Lager.
		"storehouse": {
			id = "storehouse", name = "Lagerhaus", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 3 },
			inputs = {}, output = -1, work = 0, resource = "",
			influence = 0, category = "lager",
		},
		"woodcutter": {
			id = "woodcutter", name = "Holzfäller", size = H,
			cost = { Goods.BOARDS: 2 }, inputs = {}, output = Goods.WOOD,
			work = 100, resource = "tree", influence = 0, category = "holz",
		},
		"forester": {
			id = "forester", name = "Förster", size = H,
			cost = { Goods.BOARDS: 2 }, inputs = {}, output = -1,
			work = 160, resource = "plant_tree", influence = 0, category = "holz",
		},
		"sawmill": {
			id = "sawmill", name = "Sägewerk", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 2 },
			inputs = { Goods.WOOD: 1 }, output = Goods.BOARDS,
			work = 110, resource = "", influence = 0, category = "holz",
		},
		"quarry": {
			id = "quarry", name = "Steinbruch", size = H,
			cost = { Goods.BOARDS: 2 }, inputs = {}, output = Goods.STONE,
			work = 130, resource = "stone", influence = 0, category = "bau",
		},
		"well": {
			id = "well", name = "Brunnen", size = H,
			cost = { Goods.BOARDS: 2 }, inputs = {}, output = Goods.WATER,
			work = 110, resource = "", influence = 0, category = "nahrung",
		},
		"farm": {
			id = "farm", name = "Bauernhof", size = C,
			cost = { Goods.BOARDS: 3, Goods.STONE: 3 }, inputs = {},
			output = Goods.GRAIN, work = 200, resource = "field", influence = 0,
			category = "nahrung",
		},
		"mill": {
			id = "mill", name = "Mühle", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 1 },
			inputs = { Goods.GRAIN: 1 }, output = Goods.FLOUR,
			work = 110, resource = "", influence = 0, category = "nahrung",
		},
		"bakery": {
			id = "bakery", name = "Bäckerei", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 3 },
			inputs = { Goods.FLOUR: 1, Goods.WATER: 1 }, output = Goods.BREAD,
			work = 130, resource = "", influence = 0, category = "nahrung",
		},
		"fishery": {
			id = "fishery", name = "Fischerhütte", size = H,
			cost = { Goods.BOARDS: 2 }, inputs = {}, output = Goods.FISH,
			work = 120, resource = "water", influence = 0, category = "nahrung",
		},
		"hunter": {
			id = "hunter", name = "Jägerhütte", size = H,
			cost = { Goods.BOARDS: 2 }, inputs = {}, output = Goods.MEAT,
			work = 140, resource = "", influence = 0, category = "nahrung",
		},
		"pigfarm": {
			id = "pigfarm", name = "Schweinefarm", size = C,
			cost = { Goods.BOARDS: 3, Goods.STONE: 3 },
			inputs = { Goods.GRAIN: 1, Goods.WATER: 1 }, output = Goods.PIG,
			work = 200, resource = "", influence = 0, category = "nahrung",
		},
		"slaughterhouse": {
			id = "slaughterhouse", name = "Schlachterei", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 2 },
			inputs = { Goods.PIG: 1 }, output = Goods.MEAT,
			work = 120, resource = "", influence = 0, category = "nahrung",
		},
		"toolmaker": {
			id = "toolmaker", name = "Werkzeugmacher", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 2 },
			inputs = { Goods.BOARDS: 1, Goods.IRON: 1 }, output = Goods.TOOLS,
			work = 150, resource = "", influence = 0, category = "metall",
		},
		"coalmine": {
			id = "coalmine", name = "Kohlemine", size = MINE,
			cost = { Goods.BOARDS: 2 }, inputs = { Goods.BREAD: 1 },
			output = Goods.COAL, work = 150, resource = "ore",
			mineral = MapData.ORE_COAL, influence = 0, category = "bergbau",
		},
		"ironmine": {
			id = "ironmine", name = "Eisenmine", size = MINE,
			cost = { Goods.BOARDS: 2 }, inputs = { Goods.BREAD: 1 },
			output = Goods.IRON_ORE, work = 150, resource = "ore",
			mineral = MapData.ORE_IRON, influence = 0, category = "bergbau",
		},
		"goldmine": {
			id = "goldmine", name = "Goldmine", size = MINE,
			cost = { Goods.BOARDS: 2 }, inputs = { Goods.BREAD: 1 },
			output = Goods.GOLD_ORE, work = 170, resource = "ore",
			mineral = MapData.ORE_GOLD, influence = 0, category = "bergbau",
		},
		"granitemine": {
			id = "granitemine", name = "Granitmine", size = MINE,
			cost = { Goods.BOARDS: 2 }, inputs = { Goods.BREAD: 1 },
			output = Goods.STONE, work = 160, resource = "ore",
			mineral = MapData.ORE_GRANITE, influence = 0, category = "bergbau",
		},
		"smelter": {
			id = "smelter", name = "Eisenschmelze", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 3 },
			inputs = { Goods.IRON_ORE: 1, Goods.COAL: 1 }, output = Goods.IRON,
			work = 140, resource = "", influence = 0, category = "metall",
		},
		"mint": {
			id = "mint", name = "Münzprägerei", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 3 },
			inputs = { Goods.GOLD_ORE: 1, Goods.COAL: 1 }, output = Goods.COINS,
			work = 160, resource = "", influence = 0, category = "metall",
		},
		"brewery": {
			id = "brewery", name = "Brauerei", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 2 },
			inputs = { Goods.GRAIN: 1, Goods.WATER: 1 }, output = Goods.BEER,
			work = 150, resource = "", influence = 0, category = "nahrung",
		},
		"smithy": {
			id = "smithy", name = "Schmiede", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 2 },
			inputs = { Goods.IRON: 1, Goods.COAL: 1 }, output = Goods.SWORD,
			work = 160, resource = "", influence = 0, category = "metall",
		},
		"guardhouse": {
			id = "guardhouse", name = "Wachhaus", size = H,
			cost = { Goods.BOARDS: 2, Goods.STONE: 2 }, inputs = {},
			output = -1, work = 0, resource = "", influence = 5,
			category = "militaer",
		},
		"watchtower": {
			id = "watchtower", name = "Wachturm", size = M,
			cost = { Goods.BOARDS: 3, Goods.STONE: 5 }, inputs = {},
			output = -1, work = 0, resource = "", influence = 7,
			category = "militaer",
		},
		"fortress": {
			id = "fortress", name = "Festung", size = C,
			cost = { Goods.BOARDS: 5, Goods.STONE: 9 }, inputs = {},
			output = -1, work = 0, resource = "", influence = 10,
			category = "militaer",
		},
		"catapult": {
			id = "catapult", name = "Katapult", size = M,
			cost = { Goods.BOARDS: 4, Goods.STONE: 6 }, inputs = {},
			output = -1, work = 0, resource = "", influence = 4,
			category = "militaer",
		},
	}


## Reihenfolge der Bau-Menü-Einträge (ohne HQ, das wird automatisch gesetzt).
static func menu_order() -> Array:
	return [
		"storehouse",
		"woodcutter", "forester", "sawmill", "quarry",
		"well", "farm", "mill", "bakery", "fishery", "hunter",
		"pigfarm", "slaughterhouse",
		"coalmine", "ironmine", "goldmine", "granitemine",
		"smelter", "mint", "brewery", "smithy", "toolmaker",
		"guardhouse", "watchtower", "fortress", "catapult",
	]


static func get_def(id: String) -> Dictionary:
	return defs().get(id, {})


## Beruf (Jobs.*), der dieses Gebäude betreibt, oder -1 (Lager/Militär haben keinen
## Produktionsarbeiter). Grundlage für das S2-Personalmodell: ein Gebäude wird vom
## passenden Spezialisten besetzt; fehlt er, rekrutiert das Lager ihn aus einem
## Träger + dem Werkzeug aus [Jobs.tool_for]. Quelle: RTTR Gebäude→Beruf-Zuordnung.
static func job_of(def_id: String) -> int:
	match def_id:
		"woodcutter": return Jobs.WOODCUTTER
		"forester": return Jobs.FORESTER
		"sawmill": return Jobs.CARPENTER
		"quarry": return Jobs.STONEMASON
		"well": return Jobs.HELPER          # Brunnen: einfacher Träger, kein Werkzeug
		"farm": return Jobs.FARMER
		"mill": return Jobs.MILLER
		"bakery": return Jobs.BAKER
		"fishery": return Jobs.FISHER
		"hunter": return Jobs.HUNTER
		"pigfarm": return Jobs.PIGBREEDER
		"slaughterhouse": return Jobs.BUTCHER
		"toolmaker": return Jobs.METALWORKER
		"coalmine", "ironmine", "goldmine", "granitemine": return Jobs.MINER
		"smelter": return Jobs.IRONFOUNDER
		"mint": return Jobs.MINTER
		"brewery": return Jobs.BREWER
		"smithy": return Jobs.ARMORER
	return -1
