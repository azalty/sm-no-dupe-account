#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <colorvariables>
#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#include <steamworks>
#include <discord>

#define PLUGIN_VERSION "1.1.0"

int g_iChecks; // amount of checks
int g_iClientChecksDone[MAXPLAYERS + 1];

bool g_bClientPassedCheck[MAXPLAYERS + 1];
bool g_bClientPrivatePlaytime[MAXPLAYERS + 1];
bool g_bClientPrivateLevel[MAXPLAYERS + 1];
bool g_bVPN[MAXPLAYERS + 1];

bool g_bSteamAPIKeyAvailable;
bool g_bDiscordAvailable;
bool g_bSteamworksExists;
bool g_bDiscordExists;

char g_sSteamAPIKey[33]; // 32+null terminator
char g_sDiscordWebhook[200]; // idk what size it can go up to, so this should be fine
char g_sHostname[128];

Handle g_hLevelTimer[MAXPLAYERS + 1];

// Cvars

ConVar cvarSteamAPIKey;
ConVar cvarDiscord;
ConVar cvarVPN;
ConVar cvarLevel;
ConVar cvarPrime;
ConVar cvarPlaytime;
ConVar cvarSteamLevel;

ConVar cvarHostname;

public Plugin myinfo = 
{
	name = "No Dupe Account",
	author = "azalty/rlevet",
	description = "Prevents duplicated or new accounts from accessing the server",
	version = PLUGIN_VERSION,
	url = "github.com/rlevet/sm-no-dupe-account"
}

public void OnPluginStart()
{
	// Cvars
	
	AutoExecConfig_SetFile("no_dupe_account");
	AutoExecConfig_SetCreateFile(true);
	
	cvarSteamAPIKey = AutoExecConfig_CreateConVar("nda_steamapi_key", "", "(Requires SteamWorks) A SteamAPI key that will be used to check playtime\nGet your own at: https://steamcommunity.com/dev/apikey\nThis is a sensitive key, don't share it!\nNeeded to get the playtime or prime status", FCVAR_PROTECTED);
	cvarDiscord = AutoExecConfig_CreateConVar("nda_discord", "", "(Requires Discord API and SteamWorks) Discord integration with a webhook\nempty = disabled\nwebhook url = enable", FCVAR_PROTECTED);
	cvarVPN = AutoExecConfig_CreateConVar("nda_vpn", "1", "(Requires SteamWorks) 0 = disabled\n1 = check for VPNs or proxies, and send an in-game alert to admins if someone is potentially using one (and a discord message if setup)\n2 = is a user check that fails is user has a VPN\n3 = kick user");
	cvarLevel = AutoExecConfig_CreateConVar("nda_level", "2", "0 = disabled\nany integer = is a user check that fails if his level is under this value. Keep in mind if someone gets his service medal he will go back to level 1");
	cvarPrime = AutoExecConfig_CreateConVar("nda_prime", "1", "(Requires SteamWorks) 0 = disabled\n1 = is a user check that fails if user is not prime (will only work if user paid the game)");
	cvarPlaytime = AutoExecConfig_CreateConVar("nda_playtime", "120", "(Requires SteamAPI Key) 0 = disabled\nany integer = is a user check that fails if he has less mins in playtime than asked or has private hours\nany negative integer = same as positive, but is not a check and will kick user");
	cvarSteamLevel = AutoExecConfig_CreateConVar("nda_steam_level", "5", "(Requires SteamAPI Key) 0 = disabled\nany integer = is a user check that fails if his steam level is under this value or his profile is private\nany negative integer = same as positive, but is not a check and will kick user");
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	cvarHostname = FindConVar("hostname");
	cvarHostname.GetString(g_sHostname, sizeof(g_sHostname));
	
	// Cvars hooks
	
	cvarSteamAPIKey.AddChangeHook(OnSteamAPIKeyChange);
	cvarDiscord.AddChangeHook(OnDiscordChange);
	cvarHostname.AddChangeHook(OnHostnameChange);
	
	// Translations
	LoadTranslations("no_dupe_account.phrases");
	
	// Cmds
	
	RegAdminCmd("sm_checkmepls", Command_CheckMePls, ADMFLAG_ROOT, "Runs every check on you again and apply punishment if needed");
	RegAdminCmd("sm_vpn", Command_VPN, ADMFLAG_CHANGEMAP, "Opens a menu to see if someone is potentially using a VPN");
}

public void OnConfigsExecuted()
{
	cvarSteamAPIKey.GetString(g_sSteamAPIKey, sizeof(g_sSteamAPIKey));
	cvarDiscord.GetString(g_sDiscordWebhook, sizeof(g_sDiscordWebhook));
	if (StrEqual(g_sSteamAPIKey, "")) // if none
	{
		g_bSteamAPIKeyAvailable = false;
	}
	else
	{
		g_bSteamAPIKeyAvailable = true;
	}
	if (StrEqual(g_sDiscordWebhook, "")) // if none
	{
		g_bDiscordAvailable = false;
	}
	else
	{
		g_bDiscordAvailable = true;
	}
	
	if (cvarVPN.IntValue == 2)
	{
		g_iChecks++;
	}
	if (cvarLevel.BoolValue)
	{
		g_iChecks++;
	}
	if (cvarPrime.BoolValue)
	{
		if (g_bSteamAPIKeyAvailable)
		{
			g_iChecks++;
		}
		else
		{
			LogMessage("WARNING: No SteamAPI Key is configured, but Prime status checking is enabled! Prime checks will NOT work.");
		}
	}
	if (cvarPlaytime.IntValue > 0)
	{
		if (g_bSteamAPIKeyAvailable)
		{
			g_iChecks++;
		}
		else
		{
			LogMessage("WARNING: No SteamAPI Key is configured, but Playtime method is enabled! Playtime requests will NOT work.");
		}
	}
	if (cvarSteamLevel.IntValue > 0)
	{
		if (g_bSteamAPIKeyAvailable)
		{
			g_iChecks++;
		}
		else
		{
			LogMessage("WARNING: No SteamAPI Key is configured, but Steam Level method is enabled! Steam Level requests will NOT work.");
		}
	}
}

public void OnAllPluginsLoaded()
{
	g_bSteamworksExists = LibraryExists("SteamWorks");
	g_bDiscordExists = LibraryExists("discord-api");
	
	if (!g_bSteamworksExists && (cvarVPN.BoolValue || cvarPrime.BoolValue || cvarPlaytime.BoolValue || cvarSteamLevel.BoolValue || g_bDiscordAvailable))
	{
		LogMessage("WARNING: Your current config requires the SteamWorks extension, and it is not installed. VPN, Prime, Playtime and Steam Level modules will NOT work.");
	}
	if (!g_bDiscordExists && g_bDiscordAvailable)
	{
		LogMessage("WARNING: Your current config requires the Discord API extension, and it is not installed. Discord notifications will NOT work.");
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "SteamWorks"))
	{
		g_bSteamworksExists = true;
	}
	else if (StrEqual(name, "discord-api"))
	{
		g_bDiscordExists = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "SteamWorks"))
	{
		g_bSteamworksExists = false;
	}
	else if (StrEqual(name, "discord-api"))
	{
		g_bDiscordExists = false;
	}
}

public void OnSteamAPIKeyChange(ConVar convar, char[] oldValue, char[] newValue)
{
	cvarSteamAPIKey.GetString(g_sSteamAPIKey, sizeof(g_sSteamAPIKey));
	if (StrEqual(g_sSteamAPIKey, ""))
	{
		g_bSteamAPIKeyAvailable = false;
	}
	else
	{
		g_bSteamAPIKeyAvailable = true;
	}
}

public void OnDiscordChange(ConVar convar, char[] oldValue, char[] newValue)
{
	cvarDiscord.GetString(g_sDiscordWebhook, sizeof(g_sDiscordWebhook));
	if (StrEqual(g_sDiscordWebhook, ""))
	{
		g_bDiscordAvailable = false;
	}
	else
	{
		g_bDiscordAvailable = true;
	}
}

public void OnHostnameChange(ConVar convar, char[] oldValue, char[] newValue)
{
	strcopy(g_sHostname, sizeof(g_sHostname), newValue);
}

public Action Command_VPN(int client, int args)
{
	if (!g_bSteamworksExists)
	{
		CPrintToChat(client, "{darkred}Sorry, but it seems that {darkblue}SteamWorks{darkred}, a needed extension, is not loaded.");
		return Plugin_Handled;
	}
	
	Menu menu = new Menu(VPNMenu);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%T", "Command_VPN_Title", client);
	menu.SetTitle(buffer);
	char sName[MAX_NAME_LENGTH];
	int iAmount;
	Format(buffer, sizeof(buffer), "%T", "Command_VPN_Recheck", client);
	menu.AddItem("verify", buffer);
	menu.AddItem("", "-", ITEMDRAW_DISABLED);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && g_bVPN[i])
		{
			IntToString(GetClientUserId(i), buffer, sizeof(buffer));
			GetClientName(i, sName, sizeof(sName));
			menu.AddItem(buffer, sName);
			iAmount++;
		}
	}
	if (!iAmount)
	{
		Format(buffer, sizeof(buffer), "%T", "Command_VPN_NoVPN", client);
		menu.AddItem("", "No player appears to be using a VPN.", ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int VPNMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[16];
			GetMenuItem(menu, itemNum, info, sizeof(info));
			
			if (StrEqual(info, "verify"))
			{
				if (!g_bSteamworksExists)
				{
					CPrintToChat(client, "{darkred}Sorry, but it seems that {darkblue}SteamWorks{darkred}, a needed extension, is not loaded.");
					return 0;
				}
				char ip[20];
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i) && !IsFakeClient(i))
					{
						g_bVPN[i] = false;
						GetClientIP(i, ip, sizeof(ip));
						CheckIP(i, ip, true);
					}
				}
				return 0;
			}
			
			int i = GetClientOfUserId(StringToInt(info));
			if (!i)
			{
				CPrintToChat(client, "%t", "Command_VPN_PlayerDisconnected");
				return 0;
			}
			
			char ip[20];
			GetClientIP(i, ip, sizeof(ip));
			char playername[MAX_NAME_LENGTH];
			GetClientName(i, playername, sizeof(playername));
			CPrintToChat(client, "%t", "SeemsUsingVPN", playername, ip);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public Action Command_CheckMePls(int client, int args)
{
	if (client)
	{
		g_iClientChecksDone[client] = 0;
		g_bClientPassedCheck[client] = false;
		g_bClientPrivatePlaytime[client] = false;
		g_bClientPrivateLevel[client] = false;
		g_bVPN[client] = false;
		OnClientPostAdminCheck(client);
	}
	return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
	g_iClientChecksDone[client] = 0;
	g_bClientPassedCheck[client] = false;
	g_bClientPrivatePlaytime[client] = false;
	g_bClientPrivateLevel[client] = false;
	g_bVPN[client] = false;
	delete g_hLevelTimer[client];
}

//public void OnClientAuthorized(int client)
public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client)) // exclude bots
	{
		return;
	}
	
	// sources:
	// https://forums.alliedmods.net/showthread.php?t=314780
	// https://forums.alliedmods.net/showthread.php?p=2617618
	
	if (g_bSteamworksExists)
	{
		if (cvarVPN.BoolValue)
		{
			char ip[20];
			GetClientIP(client, ip, sizeof(ip));
			
			CheckIP(client, ip);
		}
		
		if (g_bSteamAPIKeyAvailable)
		{
			if (cvarPrime.BoolValue)
			{
				g_iClientChecksDone[client]++;
				// NOTE: This will only consider them as Prime if they bought the game. If they got it by going to Level 21, it won't work
				if (SteamWorks_HasLicenseForApp(client, 624820) == k_EUserHasLicenseResultHasLicense) // if player is paid prime
				{
					g_bClientPassedCheck[client] = true;
					
				}
				else
				{
					ProcessChecks(client);
				}
			}
			
			if (cvarPlaytime.BoolValue)
			{
				CheckPlaytime(client);
			}
			
			if (cvarSteamLevel.BoolValue)
			{
				CheckSteamLevel(client);
			}
		}
	}
	
	if (cvarLevel.BoolValue)
	{
		// Player level is never available immediately
		g_hLevelTimer[client] = CreateTimer(3.0, Timer_GetLevel, client, TIMER_REPEAT); // no need to pass userid since OnClientDisconnect() stops the timer
	}
}

public Action Timer_GetLevel(Handle timer, int client)
{
	int level = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_nPersonaDataPublicLevel", _, client);
	if (level == -1) // client level is still not available, recheck in 3s
	{
		return Plugin_Continue;
	}
	
	g_iClientChecksDone[client]++;
	if (level >= cvarLevel.IntValue)
	{
		g_bClientPassedCheck[client] = true;
	}
	else
	{
		ProcessChecks(client);
	}
	
	g_hLevelTimer[client] = null;
	return Plugin_Stop;
}

void CheckIP(int client, char[] ip, bool dontNotify = false)
{
	char sRequestURL[64];
	Format(sRequestURL, sizeof(sRequestURL), "http://blackbox.ipinfo.app/lookup/%s", ip);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sRequestURL);
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client), dontNotify);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckIPResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnCheckIPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid, bool dontNotify)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		delete hRequest;
		return;
	}
	
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		delete hRequest;
		return;
	}
	
	int iBodySize;
	SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize);
	
	char[] sBody = new char[iBodySize];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, iBodySize);
	
	delete hRequest;
	
	if (StrEqual(sBody, "Y")) // API returned 'Y' -> IP is a VPN/Proxy
	{
		g_bVPN[client] = true;
		switch (cvarVPN.IntValue)
		{
			case 1:
			{
				if (!dontNotify)
				{
					char playername[MAX_NAME_LENGTH];
					char ip[20];
					GetClientName(client, playername, sizeof(playername));
					GetClientIP(client, ip, sizeof(ip));
					for (int i = 1; i <= MaxClients; i++)
					{
						if (IsClientInGame(i) && CheckCommandAccess(i, "sm_vpn", ADMFLAG_BAN))
						{
							CPrintToChat(client, "%t", "SeemsUsingVPN", playername, ip);
						}
					}
					if (g_bDiscordAvailable && g_bDiscordExists)
					{
						char message[128];
						Format(message, sizeof(message), "%T", "Discord_SeemsUsingVPN", LANG_SERVER, ip);
						SendDiscordMessage("VPN", message, client);
					}
				}
			}
			case 2:
			{
				g_bClientPassedCheck[client] = true;
				g_iClientChecksDone[client]++;
			}
			case 3:
			{
				KickClient(client, "%t", "Kicked_VPN");
			}
		}
	}
	else
	{
		g_iClientChecksDone[client]++;
		ProcessChecks(client);
	}
}

void ProcessChecks(int client)
{
	if (!g_iChecks || g_bClientPassedCheck[client])
	{
		return;
	}
	if (g_iClientChecksDone[client] == g_iChecks)
	{
		if (g_bClientPrivatePlaytime[client])
		{
			KickClient(client, "%t", "Kicked_PrivatePlaytime");
		}
		else if (g_bClientPrivateLevel[client])
		{
			KickClient(client, "%t", "Kicked_PrivateProfile");
		}
		else
		{
			KickClient(client, "%t", "Kicked_FailedChecks");
		}
	}
}

void CheckPlaytime(int client)
{
	// Request playtime
	// Source: https://forums.alliedmods.net/showthread.php?t=323407
	
	char steamid[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	char sRequestURL[512];
	Format(sRequestURL, sizeof(sRequestURL), "http://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=%s&include_played_free_games=1&appids_filter[0]=730&steamid=%s", g_sSteamAPIKey, steamid);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sRequestURL);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckPlaytimeResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnCheckPlaytimeResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		delete hRequest;
		return;
	}
	
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		delete hRequest;
		return;
	}
	
	int iBodySize;
	SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize);
	
	char[] sBody = new char[iBodySize];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, iBodySize);
	
	delete hRequest;
	
	int iPlayTime = -1;
	char sArray[8][64];
	ExplodeString(sBody, ",", sArray, sizeof(sArray), sizeof(sArray[]));
	
	for (int i; i < 8; i++)
	{
		if (StrContains(sArray[i], "playtime_forever") != -1)
		{
			char sArray2[2][32];
			ExplodeString(sArray[i], ":", sArray2, sizeof(sArray2), sizeof(sArray2[]));
			
			iPlayTime = StringToInt(sArray2[1]); // playtime in minutes
			break;
		}
	}
	
	int requiredTime = cvarPlaytime.IntValue;
	bool kick;
	if (requiredTime < 0)
	{
		kick = true;
		requiredTime = -requiredTime;
	}
	
	if (iPlayTime <= 0) // 0 could also be that the player just started playing, but it will also appear if games are visible but not playtime
	{
		if (kick)
		{
			KickClient(client, "%t", "Kicked_PrivatePlaytime");
		}
		else
		{
			g_bClientPrivatePlaytime[client] = true;
			g_iClientChecksDone[client]++;
			ProcessChecks(client);
		}
	}
	else if (iPlayTime < requiredTime)
	{
		if (kick)
		{
			int hours = requiredTime / 60;
			int minutes = requiredTime - (hours * 60);
			if (hours > 1)
			{
				if (minutes)
				{
					KickClient(client, "%t", "Kicked_NotEnoughPlaytime", "Time_HoursAndMins", hours, minutes);
				}
				else
				{
					KickClient(client, "%t", "Kicked_NotEnoughPlaytime", "Time_Hours", hours);
				}
			}
			else if (hours)
			{
				KickClient(client, "%t", "Kicked_NotEnoughPlaytime", "Time_Hour");
			}
			else // minutes only
			{
				KickClient(client, "%t", "Kicked_NotEnoughPlaytime", "Time_Mins", minutes);
			}
		}
		else
		{
			g_iClientChecksDone[client]++;
			ProcessChecks(client);
		}
	}
	else
	{
		g_bClientPassedCheck[client] = true;
		g_iClientChecksDone[client]++;
	}
}

void CheckSteamLevel(int client)
{
	char steamid[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	char sRequestURL[512];
	Format(sRequestURL, sizeof(sRequestURL), "http://api.steampowered.com/IPlayerService/GetSteamLevel/v1/?key=%s&steamid=%s", g_sSteamAPIKey, steamid);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sRequestURL);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckSteamLevelResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnCheckSteamLevelResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		delete hRequest;
		return;
	}
	
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		delete hRequest;
		return;
	}
	
	int iBodySize;
	SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize);
	
	char[] sBody = new char[iBodySize];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, iBodySize);
	
	delete hRequest;
	
	int iSteamLevel = -1;
	if (ReplaceString(sBody, iBodySize, "\"player_level\":", "") != 0)
	{
		ReplaceString(sBody, iBodySize, "\"response\":", "");
		ReplaceString(sBody, iBodySize, "{", "");
		ReplaceString(sBody, iBodySize, "}", "");
		iSteamLevel = StringToInt(sBody);
	}
	
	int requiredLevel = cvarSteamLevel.IntValue;
	bool kick;
	if (requiredLevel < 0)
	{
		kick = true;
		requiredLevel = -requiredLevel;
	}
	
	if (requiredLevel == -1)
	{
		if (kick)
		{
			KickClient(client, "%t", "Kicked_PrivateProfile");
		}
		else
		{
			g_bClientPrivateLevel[client] = true;
			g_iClientChecksDone[client]++;
			ProcessChecks(client);
		}
	}
	else if (iSteamLevel < requiredLevel)
	{
		if (kick)
		{
			KickClient(client, "%t", "Kicked_NotEnoughSteamLevel", requiredLevel);
		}
		else
		{
			g_iClientChecksDone[client]++;
			ProcessChecks(client);
		}
	}
	else
	{
		g_bClientPassedCheck[client] = true;
		g_iClientChecksDone[client]++;
	}
}

void SendDiscordMessage(char[] title, char[] message, int client=0)
{
	DiscordWebHook hook = new DiscordWebHook(g_sDiscordWebhook);
	hook.SlackMode = true;
	hook.SetUsername("No Dupe Account (v" ... PLUGIN_VERSION ... ")"); // will work since PLUGIN_VERSION is NOT a variable, and will be defined when compiled
	
	MessageEmbed embed = new MessageEmbed();
	embed.SetColor("#ffb400");
	
	char buffer[512];
	char buffer2[256];
	
	// set title
	embed.SetTitle(title);
	
	// set fields/content
	strcopy(buffer, sizeof(buffer), message);
	if (client && (StrContains(buffer, "{client}") != -1))
	{
		GetClientAuthId(client, AuthId_SteamID64, buffer2, sizeof(buffer2));
		Format(buffer2, sizeof(buffer2), "[%N](http://www.steamcommunity.com/profiles/%s)", client, buffer2);
		ReplaceString(buffer, sizeof(buffer), "{client}", buffer2);
	}
	Format(buffer2, sizeof(buffer2), "%T", "Discord_Alert", LANG_SERVER);
	embed.AddField(buffer2, buffer, false);
	
	Format(buffer, sizeof(buffer), "%T %s", "Discord_Server", LANG_SERVER, g_sHostname);
	embed.SetFooter(buffer);
	
	hook.Embed(embed);
	hook.Send();
}