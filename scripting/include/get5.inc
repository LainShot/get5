#if defined _OpenPug_included_
#endinput
#endif
#define _OpenPug_included_

enum OpenPugState {
  OpenPugState_None,                          // no setup has taken place
  OpenPugState_PreVeto,                       // warmup, waiting for the veto
  OpenPugState_Veto,                          // warmup, doing the veto
  OpenPugState_Warmup,                        // setup done, waiting for players to ready up
  OpenPugState_KnifeRound,                    // in the knife round
  OpenPugState_WaitingForKnifeRoundDecision,  // waiting for a .stay/.swap command after the knife
  OpenPugState_GoingLive,                     // in the lo3 process
  OpenPugState_Live,                          // the match is live
  OpenPugState_PostGame,                      // postgame screen + waiting for GOTV to finish broadcast
};

#define MATCHTEAM_COUNT 4

enum MatchTeam {
  MatchTeam_Team1,
  MatchTeam_Team2,
  MatchTeam_TeamSpec,
  MatchTeam_TeamNone,
  MatchTeam_Count,
};

enum MatchSideType {
  MatchSideType_Standard,     // Team that doesn't pick map gets side choice, leftovers go to knife
                              // rounds
  MatchSideType_AlwaysKnife,  // All maps use a knife round to pick sides
  MatchSideType_NeverKnife,   // Team 1 always starts CT
};

enum SideChoice {
  SideChoice_Team1CT,     // Team 1 will start on CT
  SideChoice_Team1T,      // Team 2 will start on T
  SideChoice_KnifeRound,  // There will be a knife round to choose sides
};

// Called each OpenPug-event with JSON formatted event text.
forward void OpenPug_OnEvent(const char[] eventJson);

// Called when a series is first setup.
// Note: do not rely on the state of any cvars at this point.
forward void OpenPug_OnSeriesInit();

// Called each time in a match when a map is going live.
// The mapNumber parameter starts at 0.
forward void OpenPug_OnGoingLive(int mapNumber);

// Called whenever the gamestate phase is changed.
forward void OpenPug_OnGameStateChanged(OpenPugState oldState, OpenPugState newState);

// Called when the stats for the last round have been updated.
forward void OpenPug_OnRoundStatsUpdated();

// Called at the end of a map in a series.
forward void OpenPug_OnMapResult(const char[] map, MatchTeam mapWinner, int team1Score, int team2Score,
                              int mapNumber);

// Called at the end of a full match.
// Note: both OpenPug_OnMapResult and OpenPug_OnSeriesResult are called on the last map of a series.
forward void OpenPug_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore);

forward void OpenPug_OnPreLoadMatchConfig(const char[] filePath);

// Called when a match config fails to load.
forward void OpenPug_OnLoadMatchConfigFailed(const char[] reason);

// Called when a team vetoes a map.
forward void OpenPug_OnMapVetoed(MatchTeam team, const char[] map);

// Called when a team selects a map.
// The team parameter will be MatchTeam_TeamNone if the map was selected as the last remaining map
// and not by one of the teams specifically.
forward void OpenPug_OnMapPicked(MatchTeam team, const char[] map);

// Called when a team selects a side.
forward void OpenPug_OnSidePicked(MatchTeam team, const char[] map, int side);

// Called when a demo finishes recording.
forward void OpenPug_OnDemoFinished(const char[] filename);

// Called when a match backup is restored.
forward void OpenPug_OnBackupRestore();

// Returns the current pug gamestate.
native OpenPugState OpenPug_GetGameState();

// Prints a plugin-formatted message to a client.
native void OpenPug_Message(int client, const char[] format, any:...);

// Prints a plugin-formatted message to a team.
native void OpenPug_MessageToTeam(MatchTeam team, const char[] format, any:...);

// Prints a plugin-formatted message to all clients.
native void OpenPug_MessageToAll(const char[] format, any:...);

// Loads a match config (keyvalues or JSON) from a local file.
// Returns true if the config was successfully loaded.
native bool OpenPug_LoadMatchConfig(const char[] filename);

// Loads a match config by downloading a remote config via a HTTP GET request.
// Request parameters should be left out of the url and put into the optional ArrayLists parameters.
native bool OpenPug_LoadMatchConfigFromURL(const char[] url, ArrayList paramNames = null,
                                        ArrayList paramValues = null);

// Adds a player to a match team. You can optionally force set a player name here as well.
// Returns if they were successfully added.
native bool OpenPug_AddPlayerToTeam(const char[] steamId, MatchTeam team,
                                 const char[] playerName = "");

// Force sets a steam64 to map to a specified playername
native bool OpenPug_SetPlayerName(const char[] steamId, const char[] playerName);

// Removes a player from all match teams.
// Returns if they were successfully removed (false if not round).
native bool OpenPug_RemovePlayerFromTeam(const char[] steamId);

// Returns the current match team a auth is mapped to.
native MatchTeam OpenPug_GetPlayerTeam(const char[] steamId);

// Translates a CS team (CS_TEAM_T, etc.) to a Match team.
native MatchTeam OpenPug_CSTeamToMatchTeam(int csTeam);

// Translate da MatchTeam to a CS team.
native int OpenPug_MatchTeamToCSTeam(MatchTeam team);

// Gets the scores for a match team.
native void OpenPug_GetTeamScores(MatchTeam team, int& seriesScore, int& currentMapScore);

// Gets the current matchid.
native void OpenPug_GetMatchID(char[] id, int length);

// Sets the current matchid.
native void OpenPug_SetMatchID(const char[] id);

// Adds a cvar to be set when going live. If the cvar is already in the cvars for the match, the new
// value will replace the old value if the override parameter is true.
// Note: this should only be used when a match config loaded.
native void OpenPug_AddLiveCvar(const char[] name, const char[] value, bool override = true);

// Copies the current series stats into the passed KeyValues structure.
// Below are the keys used for stats in the kv copied.
// The caller is responsible for creating and deleting a KeyValues
// object if using this method.
native bool OpenPug_GetMatchStats(KeyValues kv);

// Increases an (integer-typed) player statistic in the plugin's stats keyvalue structure.
native int OpenPug_IncreasePlayerStat(int client, const char[] statName, int amount = 1);

// Series stats (root section)
#define STAT_SERIESWINNER "winner"
#define STAT_SERIESTYPE "series_type"
#define STAT_SERIES_TEAM1NAME "team1_name"
#define STAT_SERIES_TEAM2NAME "team2_name"
#define STAT_SERIES_FORFEIT "forfeit"

// Map stats (under "map0", "map1", etc.)
#define STAT_MAPNAME "mapname"
#define STAT_MAPWINNER "winner"
#define STAT_DEMOFILENAME "demo_filename"

// Team stats (under map section, then "team1" or "team2")
#define STAT_TEAMSCORE "score"

// Player stats (under map section, then team section, then player's steam64)
#define STAT_NAME "name"
#define STAT_KILLS "kills"
#define STAT_DEATHS "deaths"
#define STAT_ASSISTS "assists"
#define STAT_FLASHBANG_ASSISTS "flashbang_assists"
#define STAT_TEAMKILLS "teamkills"
#define STAT_SUICIDES "suicides"
#define STAT_DAMAGE "damage"
#define STAT_HEADSHOT_KILLS "headshot_kills"
#define STAT_ROUNDSPLAYED "roundsplayed"
#define STAT_BOMBDEFUSES "bomb_defuses"
#define STAT_BOMBPLANTS "bomb_plants"
#define STAT_1K "1kill_rounds"
#define STAT_2K "2kill_rounds"
#define STAT_3K "3kill_rounds"
#define STAT_4K "4kill_rounds"
#define STAT_5K "5kill_rounds"
#define STAT_V1 "v1"
#define STAT_V2 "v2"
#define STAT_V3 "v3"
#define STAT_V4 "v4"
#define STAT_V5 "v5"
#define STAT_FIRSTKILL_T "firstkill_t"
#define STAT_FIRSTKILL_CT "firstkill_ct"
#define STAT_FIRSTDEATH_T "firstdeath_t"
#define STAT_FIRSTDEATH_CT "firstdeath_ct"
#define STAT_TRADEKILL "tradekill"
#define STAT_CONTRIBUTION_SCORE "contribution_score"

public SharedPlugin __pl_OpenPug = {
    name = "OpenPug", file = "OpenPug.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_OpenPug_SetNTVOptional() {
  MarkNativeAsOptional("OpenPug_GetGameState");
  MarkNativeAsOptional("OpenPug_Message");
  MarkNativeAsOptional("OpenPug_MessageToTeam");
  MarkNativeAsOptional("OpenPug_MessageToAll");
  MarkNativeAsOptional("OpenPug_LoadMatchConfig");
  MarkNativeAsOptional("OpenPug_LoadMatchConfigFromURL");
  MarkNativeAsOptional("OpenPug_AddPlayerToTeam");
  MarkNativeAsOptional("OpenPug_SetPlayerName");
  MarkNativeAsOptional("OpenPug_RemovePlayerFromTeam");
  MarkNativeAsOptional("OpenPug_GetPlayerTeam");
  MarkNativeAsOptional("OpenPug_CSTeamToMatchTeam");
  MarkNativeAsOptional("OpenPug_MatchTeamToCSTeam");
  MarkNativeAsOptional("OpenPug_GetTeamScores");
  MarkNativeAsOptional("OpenPug_GetMatchID");
  MarkNativeAsOptional("OpenPug_SetMatchID");
  MarkNativeAsOptional("OpenPug_AddLiveCvar");
  MarkNativeAsOptional("OpenPug_IncreasePlayerStat");
  MarkNativeAsOptional("OpenPug_GetMatchStats");
}
#endif
