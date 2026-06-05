class_name PassiveAI
extends AIBase

## Beispiel-KI: tut nichts (Gegner bleibt stehen). Dient als Vorlage und zum
## bequemen Testen ohne Gegnerdruck.

func ai_name() -> String:
	return "Passiv"


func think(_eco: Economy, _owner: int) -> void:
	pass
