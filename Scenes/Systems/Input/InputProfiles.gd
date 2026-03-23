extends RefCounted
class_name InputProfiles

const PROFILES := {
	1: {
		"up": "p1_up",
		"down": "p1_down",
		"left": "p1_left",
		"right": "p1_right",
		"kick": "p1_kick",
		"dash": "p1_dash"
	},
	2: {
		"up": "p2_up",
		"down": "p2_down",
		"left": "p2_left",
		"right": "p2_right",
		"kick": "p2_kick",
		"dash": "p2_dash"
	}
}


static func get_profile(player_index: int) -> Dictionary:
	return PROFILES.get(player_index, PROFILES[1]).duplicate(true)
