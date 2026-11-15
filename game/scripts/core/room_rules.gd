class_name RoomRules
extends RefCounted

const MAX_TEAM := 4
const MAX_HUMANS := MAX_TEAM * 2
const BOT_SIDE := MAX_HUMANS
const SIDES := MAX_HUMANS + 1
const ZONES := ["Вся карта", "Центральная зона", "Компактная зона"]

static func normalized(map: String, source: Dictionary) -> Dictionary:
	var mask := int(source.get("tools", (1 << PlayerTools.NAMES.size()) - 1))
	# У пустой панели инструментов нет активной ячейки. Оставляем кувалду.
	var tools := mask & ((1 << PlayerTools.NAMES.size()) - 1)
	if (tools & ((1 << PlayerTools.POSSESSOR) - 1)) == 0:
		tools |= 1 << PlayerTools.HAMMER
	return {
		"map": map, "hiders": clampi(int(source.get("hiders", 1)), 1, MAX_TEAM),
		"seekers": clampi(int(source.get("seekers", 1)), 1, MAX_TEAM),
		"bot": map == "school" and bool(source.get("bot", false)),
		"host_seeks": bool(source.get("host_seeks", true)),
		"switch_roles": bool(source.get("switch_roles", true)),
		"hide": clampi(int(source.get("hide", 22)), 10, 120),
		"seek": clampi(int(source.get("seek", 180)), 30, 900),
		"zone": clampi(int(source.get("zone", 0)), 0, 2),
		"tools": tools, "gadgets": bool(source.get("gadgets", true)),
		"bot_clues": bool(source.get("bot_clues", true)),
		"free_spectate": bool(source.get("free_spectate", false)),
	}

static func human_count(rules: Dictionary) -> int:
	return int(rules.hiders) + int(rules.seekers) - int(bool(rules.bot))

static func host_seeks(rules: Dictionary) -> bool:
	return bool(rules.host_seeks) or int(rules.hiders) == int(bool(rules.bot))

static func half(map: String, zone: int) -> float:
	match map:
		"school": return [79.4, 59.0, 45.0][zone]
		"district": return [DistrictLevel.HALF - 0.6, 69.0, 49.0][zone]
		"hide": return HideLevel.HALF - 0.6
		_: return [39.4, 33.0, 28.0][zone]

static func contains(at: Vector3, half_size: float) -> bool:
	return at.is_finite() and absf(at.x) <= half_size and absf(at.z) <= half_size
