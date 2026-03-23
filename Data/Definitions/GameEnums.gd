extends RefCounted
class_name GameEnums

enum MatchState {
	BOOT,
	MAIN_MENU,
	MATCH_INTRO,
	KICKOFF,
	PLAYING,
	GOAL_SCORED,
	PAUSED,
	MATCH_ENDED
}

enum TeamId {
	NEUTRAL = -1,
	RED = 0,
	BLUE = 1
}
