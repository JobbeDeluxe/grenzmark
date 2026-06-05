class_name AIBase
extends RefCounted

## Schnittstelle für austauschbare Gegner-KIs.
##
## Eine eigene KI: dieses Skript erweitern, `ai_name()` und `think()` überschreiben,
## als .gd-Datei in `res://ai/` ablegen. Die KI taucht dann automatisch in der
## Auswahl auf (Taste J im Spiel). Details: ai/README.md.
##
## `think()` wird in jedem Simulations-Tick aufgerufen (30/s). Die KI verwaltet
## ihre eigenen Timer/Zustände als Member-Variablen. Sie steuert die Gebäude des
## Besitzers [param owner] (Spieler = 0, Standard-Gegner = 1) und hat über
## [param eco] vollen Zugriff auf den Spielzustand.

func ai_name() -> String:
	return "Basis"


## Ein Denkschritt. eco = Economy, owner = von dieser KI gesteuerter Besitzer.
func think(_eco: Economy, _owner: int) -> void:
	pass
