/**
 * =============================================================================
 * OpenPug web API integration
 * Copyright (C) 2016. Sean Lewis.  All rights reserved.
 * =============================================================================
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "include/OpenPug.inc"
#include "include/logdebug.inc"
#include <cstrike>
#include <sourcemod>

#include "OpenPug/util.sp"
#include "OpenPug/version.sp"

#include <SteamWorks>
#include <json>  // github.com/clugg/sm-json

#include "OpenPug/jsonhelpers.sp"

#pragma semicolon 1
#pragma newdecls required

int g_MatchID = -1;
ConVar g_UseSVGCvar;
char g_LogoBasePath[128];
ConVar g_APIKeyCvar;
char g_APIKey[128];

ConVar g_APIURLCvar;
char g_APIURL[128];

#define LOGO_DIR "materials/panorama/images/tournaments/teams"
#define LEGACY_LOGO_DIR "resource/flash/econ/tournaments/teams"

// clang-format off
public Plugin myinfo = {
  name = "OpenPug Web API Integration",
  author = "splewis",
  description = "Records match stats to a OpenPug-web api",
  version = PLUGIN_VERSION,
  url = "https://github.com/splewis/OpenPug"
};
// clang-format on

public void OnPluginStart() {
  InitDebugLog("OpenPug_debug", "OpenPug_api");
  LogDebug("OnPluginStart version=%s", PLUGIN_VERSION);
  g_UseSVGCvar = CreateConVar("OpenPug_use_svg", "1", "support svg team logos");
  HookConVarChange(g_UseSVGCvar, LogoBasePathChanged);
  g_LogoBasePath = g_UseSVGCvar.BoolValue ? LOGO_DIR : LEGACY_LOGO_DIR;
  g_APIKeyCvar =
      CreateConVar("OpenPug_web_api_key", "", "Match API key, this is automatically set through rcon");
  HookConVarChange(g_APIKeyCvar, ApiInfoChanged);

  g_APIURLCvar = CreateConVar("OpenPug_web_api_url", "", "URL the OpenPug api is hosted at");

  HookConVarChange(g_APIURLCvar, ApiInfoChanged);

  RegConsoleCmd("OpenPug_web_avaliable",
                Command_Avaliable);  // legacy version since I'm bad at spelling
  RegConsoleCmd("OpenPug_web_available", Command_Avaliable);
}

public Action Command_Avaliable(int client, int args) {
  char versionString[64] = "unknown";
  ConVar versionCvar = FindConVar("OpenPug_version");
  if (versionCvar != null) {
    versionCvar.GetString(versionString, sizeof(versionString));
  }

  JSON_Object json = new JSON_Object();

  json.SetInt("gamestate", view_as<int>(OpenPug_GetGameState()));
  json.SetInt("avaliable", 1);  // legacy version since I'm bad at spelling
  json.SetInt("available", 1);
  json.SetString("plugin_version", versionString);

  char buffer[256];
  json.Encode(buffer, sizeof(buffer), true);
  ReplyToCommand(client, buffer);

  delete json;

  return Plugin_Handled;
}

public void LogoBasePathChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  g_LogoBasePath = g_UseSVGCvar.BoolValue ? LOGO_DIR : LEGACY_LOGO_DIR;
}

public void ApiInfoChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  g_APIKeyCvar.GetString(g_APIKey, sizeof(g_APIKey));
  g_APIURLCvar.GetString(g_APIURL, sizeof(g_APIURL));

  // Add a trailing backslash to the api url if one is missing.
  int len = strlen(g_APIURL);
  if (len > 0 && g_APIURL[len - 1] != '/') {
    StrCat(g_APIURL, sizeof(g_APIURL), "/");
  }

  LogDebug("OpenPug_web_api_url now set to %s", g_APIURL);
}

static Handle CreateRequest(EHTTPMethod httpMethod, const char[] apiMethod, any:...) {
  char url[1024];
  Format(url, sizeof(url), "%s%s", g_APIURL, apiMethod);

  char formattedUrl[1024];
  VFormat(formattedUrl, sizeof(formattedUrl), url, 3);

  LogDebug("Trying to create request to url %s", formattedUrl);

  Handle req = SteamWorks_CreateHTTPRequest(httpMethod, formattedUrl);
  if (StrEqual(g_APIKey, "")) {
    // Not using a web interface.
    return INVALID_HANDLE;

  } else if (req == INVALID_HANDLE) {
    LogError("Failed to create request to %s", formattedUrl);
    return INVALID_HANDLE;

  } else {
    SteamWorks_SetHTTPCallbacks(req, RequestCallback);
    AddStringParam(req, "key", g_APIKey);
    return req;
  }
}

public int RequestCallback(Handle request, bool failure, bool requestSuccessful,
                    EHTTPStatusCode statusCode) {
  if (failure || !requestSuccessful) {
    LogError("API request failed, HTTP status code = %d", statusCode);
    char response[1024];
    SteamWorks_GetHTTPResponseBodyData(request, response, sizeof(response));
    LogError(response);
    return;
  }
}

public void OpenPug_OnBackupRestore() {
  char matchid[64];
  OpenPug_GetMatchID(matchid, sizeof(matchid));
  g_MatchID = StringToInt(matchid);
}

public void OpenPug_OnSeriesInit() {
  char matchid[64];
  OpenPug_GetMatchID(matchid, sizeof(matchid));
  g_MatchID = StringToInt(matchid);

  // Handle new logos.
  if (!DirExists(g_LogoBasePath)) {
    if (!CreateDirectory(g_LogoBasePath, 755)) {
      LogError("Failed to create logo directory: %s", g_LogoBasePath);
    }
  }

  char logo1[32];
  char logo2[32];
  GetConVarStringSafe("mp_teamlogo_1", logo1, sizeof(logo1));
  GetConVarStringSafe("mp_teamlogo_2", logo2, sizeof(logo2));
  CheckForLogo(logo1);
  CheckForLogo(logo2);
}

public void CheckForLogo(const char[] logo) {
  if (StrEqual(logo, "")) {
    return;
  }

  char logoPath[PLATFORM_MAX_PATH + 1];
  // change png to svg because it's better supported
  if (g_UseSVGCvar.BoolValue) {
    Format(logoPath, sizeof(logoPath), "%s/%s.svg", g_LogoBasePath, logo);
  } else {
    Format(logoPath, sizeof(logoPath), "%s/%s.png", g_LogoBasePath, logo);
  }

  // Try to fetch the file if we don't have it.
  if (!FileExists(logoPath)) {
    LogDebug("Fetching logo for %s", logo);
    Handle req = g_UseSVGCvar.BoolValue
                     ? CreateRequest(k_EHTTPMethodGET, "/static/img/logos/%s.svg", logo)
                     : CreateRequest(k_EHTTPMethodGET, "/static/img/logos/%s.png", logo);

    if (req == INVALID_HANDLE) {
      return;
    }

    Handle pack = CreateDataPack();
    WritePackString(pack, logo);

    SteamWorks_SetHTTPRequestContextValue(req, view_as<int>(pack));
    SteamWorks_SetHTTPCallbacks(req, LogoCallback);
    SteamWorks_SendHTTPRequest(req);
  }
}

public int LogoCallback(Handle request, bool failure, bool successful, EHTTPStatusCode status, int data) {
  if (failure || !successful) {
    LogError("Logo request failed, status code = %d", status);
    return;
  }

  DataPack pack = view_as<DataPack>(data);
  pack.Reset();
  char logo[32];
  pack.ReadString(logo, sizeof(logo));

  char logoPath[PLATFORM_MAX_PATH + 1];
  if (g_UseSVGCvar.BoolValue) {
    Format(logoPath, sizeof(logoPath), "%s/%s.svg", g_LogoBasePath, logo);
  } else {
    Format(logoPath, sizeof(logoPath), "%s/%s.png", g_LogoBasePath, logo);
  }

  LogMessage("Saved logo for %s to %s", logo, logoPath);
  SteamWorks_WriteHTTPResponseBodyToFile(request, logoPath);
}

public void OpenPug_OnGoingLive(int mapNumber) {
  char mapName[64];
  GetCurrentMap(mapName, sizeof(mapName));
  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%d/map/%d/start", g_MatchID, mapNumber);
  if (req != INVALID_HANDLE) {
    AddStringParam(req, "mapname", mapName);
    SteamWorks_SendHTTPRequest(req);
  }

  OpenPug_AddLiveCvar("OpenPug_web_api_key", g_APIKey);
  OpenPug_AddLiveCvar("OpenPug_web_api_url", g_APIURL);
}

public void UpdateRoundStats(int mapNumber) {
  int t1score = CS_GetTeamScore(OpenPug_MatchTeamToCSTeam(MatchTeam_Team1));
  int t2score = CS_GetTeamScore(OpenPug_MatchTeamToCSTeam(MatchTeam_Team2));

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%d/map/%d/update", g_MatchID, mapNumber);
  if (req != INVALID_HANDLE) {
    AddIntParam(req, "team1score", t1score);
    AddIntParam(req, "team2score", t2score);
    SteamWorks_SendHTTPRequest(req);
  }

  KeyValues kv = new KeyValues("Stats");
  OpenPug_GetMatchStats(kv);
  char mapKey[32];
  Format(mapKey, sizeof(mapKey), "map%d", mapNumber);
  if (kv.JumpToKey(mapKey)) {
    if (kv.JumpToKey("team1")) {
      UpdatePlayerStats(kv, MatchTeam_Team1);
      kv.GoBack();
    }
    if (kv.JumpToKey("team2")) {
      UpdatePlayerStats(kv, MatchTeam_Team2);
      kv.GoBack();
    }
    kv.GoBack();
  }
  delete kv;
}

public void OpenPug_OnMapResult(const char[] map, MatchTeam mapWinner, int team1Score, int team2Score,
                      int mapNumber) {
  char winnerString[64];
  GetTeamString(mapWinner, winnerString, sizeof(winnerString));

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%d/map/%d/finish", g_MatchID, mapNumber);
  if (req != INVALID_HANDLE) {
    AddIntParam(req, "team1score", team1Score);
    AddIntParam(req, "team2score", team2Score);
    AddStringParam(req, "winner", winnerString);
    SteamWorks_SendHTTPRequest(req);
  }
}

static void AddIntStat(Handle req, KeyValues kv, const char[] field) {
  AddIntParam(req, field, kv.GetNum(field));
}

public void UpdatePlayerStats(KeyValues kv, MatchTeam team) {
  char name[MAX_NAME_LENGTH];
  char auth[AUTH_LENGTH];
  int mapNumber = MapNumber();

  if (kv.GotoFirstSubKey()) {
    do {
      kv.GetSectionName(auth, sizeof(auth));
      kv.GetString("name", name, sizeof(name));
      char teamString[16];
      GetTeamString(team, teamString, sizeof(teamString));

      Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%d/map/%d/player/%s/update", g_MatchID,
                                 mapNumber, auth);
      if (req != INVALID_HANDLE) {
        AddStringParam(req, "team", teamString);
        AddStringParam(req, "name", name);
        AddIntStat(req, kv, STAT_KILLS);
        AddIntStat(req, kv, STAT_DEATHS);
        AddIntStat(req, kv, STAT_ASSISTS);
        AddIntStat(req, kv, STAT_FLASHBANG_ASSISTS);
        AddIntStat(req, kv, STAT_TEAMKILLS);
        AddIntStat(req, kv, STAT_SUICIDES);
        AddIntStat(req, kv, STAT_DAMAGE);
        AddIntStat(req, kv, STAT_HEADSHOT_KILLS);
        AddIntStat(req, kv, STAT_ROUNDSPLAYED);
        AddIntStat(req, kv, STAT_BOMBPLANTS);
        AddIntStat(req, kv, STAT_BOMBDEFUSES);
        AddIntStat(req, kv, STAT_1K);
        AddIntStat(req, kv, STAT_2K);
        AddIntStat(req, kv, STAT_3K);
        AddIntStat(req, kv, STAT_4K);
        AddIntStat(req, kv, STAT_5K);
        AddIntStat(req, kv, STAT_V1);
        AddIntStat(req, kv, STAT_V2);
        AddIntStat(req, kv, STAT_V3);
        AddIntStat(req, kv, STAT_V4);
        AddIntStat(req, kv, STAT_V5);
        AddIntStat(req, kv, STAT_FIRSTKILL_T);
        AddIntStat(req, kv, STAT_FIRSTKILL_CT);
        AddIntStat(req, kv, STAT_FIRSTDEATH_T);
        AddIntStat(req, kv, STAT_FIRSTDEATH_CT);
        AddIntStat(req, kv, STAT_TRADEKILL);
        AddIntStat(req, kv, STAT_CONTRIBUTION_SCORE);
        SteamWorks_SendHTTPRequest(req);
      }

    } while (kv.GotoNextKey());
    kv.GoBack();
  }
}

static void AddStringParam(Handle request, const char[] key, const char[] value) {
  if (!SteamWorks_SetHTTPRequestGetOrPostParameter(request, key, value)) {
    LogError("Failed to add http param %s=%s", key, value);
  } else {
    LogDebug("Added param %s=%s to request", key, value);
  }
}

static void AddIntParam(Handle request, const char[] key, int value) {
  char buffer[32];
  IntToString(value, buffer, sizeof(buffer));
  AddStringParam(request, key, buffer);
}

public void OpenPug_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore) {
  char winnerString[64];
  GetTeamString(seriesWinner, winnerString, sizeof(winnerString));

  KeyValues kv = new KeyValues("Stats");
  OpenPug_GetMatchStats(kv);
  bool forfeit = kv.GetNum(STAT_SERIES_FORFEIT, 0) != 0;
  delete kv;

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%d/finish", g_MatchID);
  if (req != INVALID_HANDLE) {
    AddStringParam(req, "winner", winnerString);
    AddIntParam(req, "forfeit", forfeit);
    SteamWorks_SendHTTPRequest(req);
  }

  g_APIKeyCvar.SetString("");
}

public void OpenPug_OnRoundStatsUpdated() {
  if (OpenPug_GetGameState() == OpenPugState_Live) {
    UpdateRoundStats(MapNumber());
  }
}

static int MapNumber() {
  int t1, t2, n;
  int buf;
  OpenPug_GetTeamScores(MatchTeam_Team1, t1, buf);
  OpenPug_GetTeamScores(MatchTeam_Team2, t2, buf);
  OpenPug_GetTeamScores(MatchTeam_TeamNone, n, buf);
  return t1 + t2 + n;
}
