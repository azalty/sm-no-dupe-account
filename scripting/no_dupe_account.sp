#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <colorvariables>
#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#include <steamworks>
#include <discord>

#define PLUGIN_VERSION "1.4.2b"

int g_iChecks; // amount of checks
int g_iClientChecksDone[MAXPLAYERS + 1];
int g_iVACBans[MAXPLAYERS + 1];
int g_iGameBans[MAXPLAYERS + 1];
int g_iLastBan[MAXPLAYERS + 1];

int g_iClientDatabaseStatus[MAXPLAYERS + 1]; // 0 = awaiting check | 1 = checked | 2 = checked and should be updated | 3 = checked and doesn't exist
int g_iClientDatabasePlaytime[MAXPLAYERS + 1] = -1;
int g_iClientDatabaseSteamLevel[MAXPLAYERS + 1] = -1;
int g_iClientDatabaseSteamAge[MAXPLAYERS + 1] = -1;
int g_iClientDatabaseCSGOLevel[MAXPLAYERS + 1] = -1;
int g_iClientDatabaseCSGOCoin[MAXPLAYERS + 1];
int g_iClientLastCheck[MAXPLAYERS + 1];

bool g_bClientPassedCheck[MAXPLAYERS + 1];
bool g_bClientPrivatePlaytime[MAXPLAYERS + 1];
bool g_bClientPrivateProfile[MAXPLAYERS + 1];
bool g_bVPN[MAXPLAYERS + 1];
bool g_bCommunityBanned[MAXPLAYERS + 1];
bool g_bPrime[MAXPLAYERS + 1];

bool g_bSteamAPIKeyAvailable;
bool g_bDiscordAvailable;
bool g_bSteamworksExists;
bool g_bDiscordExists;

bool g_bSteamAgeEnabled;

// bool g_bMySQL;		NOT USED AS OF NOW
bool g_bDatabaseReady;

char g_sSteamAPIKey[33]; // 32+null terminator
char g_sDiscordWebhook[200]; // idk what size it can go up to, so this should be fine
char g_sSteamAge[16];
char g_sHostname[128];
char g_sRequestURLBuffer[512];
char g_sSQLBuffer[3096]; // all queries will go into this buffer, to prevent high CPU usage due to the creation of this variable. Higher RAM consumption (but still negligible), lower CPU usage, that's the goal of global buffers.

Handle g_hResourceTimer[MAXPLAYERS + 1];
Handle g_hDB;

// Cvars

ConVar cvarSteamAPIKey;
ConVar cvarDiscord;
ConVar cvarDatabase;
ConVar cvarDatabaseRefresh;
ConVar cvarDatabaseExpire;
ConVar cvarVPN;
ConVar cvarLevel;
ConVar cvarPrime;
ConVar cvarPlaytime;
ConVar cvarSteamLevel;
ConVar cvarSteamAge;
ConVar cvarCoin;
ConVar cvarBansVAC;
ConVar cvarBansGame;
ConVar cvarBansCommunity;
ConVar cvarBansTotal;
ConVar cvarBansRecent;
ConVar cvarLog;

ConVar cvarHostname;

public Plugin myinfo = 
{
	name = "No Dupe Account",
	author = "azalty/rlevet",
	description = "Prevents duplicated or new accounts from accessing the server",
	version = PLUGIN_VERSION,
	url = "github.com/azalty/sm-no-dupe-account"
}

public void OnPluginStart()
{
	// Cvars
	
	AutoExecConfig_SetFile("no_dupe_account");
	AutoExecConfig_SetCreateFile(true);
	
	cvarSteamAPIKey = AutoExecConfig_CreateConVar("nda_steamapi_key", "", "(Requires SteamWorks)\nA SteamAPI key that will be used to check playtime\nGet your own at: https://steamcommunity.com/dev/apikey\nThis is a sensitive key, don't share it!\nNeeded to get the playtime or prime status", FCVAR_PROTECTED);
	cvarDiscord = AutoExecConfig_CreateConVar("nda_discord", "", "(Requires Discord API and SteamWorks)\nDiscord integration with a webhook\nempty = disabled\nwebhook url = enable", FCVAR_PROTECTED);
	cvarDatabase = AutoExecConfig_CreateConVar("nda_database", "1", "Enable saving player values in a database.\nWill act as a cache, if a player doesn't want to keep is profile public, he can join once while it's public and it won't deny him in the future.\n1 = enabled\n0 = disabled\nDatabase config name: 'no_dupe_account'");
	cvarDatabaseRefresh = AutoExecConfig_CreateConVar("nda_database_refresh", "1440", "(Requires Database)\nany integer = refresh players values if older than X minutes\n0 = never refresh (recommended if you don't plan on using the DB for other reasons)\nNOTE: Player values will ALWAYS refresh if they are denied, but this will NOT count as a true full refresh");
	cvarDatabaseExpire = AutoExecConfig_CreateConVar("nda_database_expire", "365", "(Requires Database)\nany integer = players values are deleted if older than X days (using refresh as well is recommended)\n0 = keep player values forever\nNOTE: Deleting really old values of players that don't play anymore is recommended");
	cvarVPN = AutoExecConfig_CreateConVar("nda_vpn", "1", "(Requires SteamWorks)\n0 = disabled\n1 = check for VPNs or proxies, and send an in-game alert to admins if someone is potentially using one (and a discord message if setup)\n2 = is a user check that fails is user has a VPN\n3 = kick user");
	cvarLevel = AutoExecConfig_CreateConVar("nda_level", "2", "0 = disabled\nany integer = is a user check that fails if his level is under this value. Keep in mind if someone gets his service medal he will go back to level 1");
	cvarPrime = AutoExecConfig_CreateConVar("nda_prime", "1", "(Requires SteamWorks)\n0 = disabled\n1 = is a user check that fails if user is not prime (will only work if user paid the game) + nda menu\n2 = only add an !nda menu displaying non-prime players");
	cvarPlaytime = AutoExecConfig_CreateConVar("nda_playtime", "120", "(Requires SteamAPI Key)\n0 = disabled\nany integer = is a user check that fails if he has less mins in playtime than asked or has private hours\nany negative integer = same as positive, but is not a check and will kick user");
	cvarSteamLevel = AutoExecConfig_CreateConVar("nda_steam_level", "5", "(Requires SteamAPI Key)\n0 = disabled\nany integer = is a user check that fails if his steam level is under this value or his profile is private\nany negative integer = same as positive, but is not a check and will kick user");
	cvarSteamAge = AutoExecConfig_CreateConVar("nda_steam_age", "1576800", "(Requires SteamAPI Key)\n0 = disabled\nany integer = is a user check that fails if his steam account age is newer than this value in minutes or his profile is private\nany negative integer = same as positive, but is not a check and will kick user\n&integer (ex: &60) = same as negative, but will not kick user if his profile is private");
	cvarCoin = AutoExecConfig_CreateConVar("nda_coin", "1", "0 = disabled\n1 = is a user check that fails if he doesn't have any CS:GO coin/badge equipped\n2 = kick user if he doesn't have any CS:GO coin/badge equipped (this is not recommended as a lot of players don't have a coin)");
	cvarBansVAC = AutoExecConfig_CreateConVar("nda_bans_vac", "0", "(Requires SteamAPI Key)\n0 = disabled\nany integer = kick player if he has been VAC banned at least X times");
	cvarBansGame = AutoExecConfig_CreateConVar("nda_bans_game", "0", "(Requires SteamAPI Key)\n0 = disabled\nany integer = kick player if he has been Game banned at least X times");
	cvarBansCommunity = AutoExecConfig_CreateConVar("nda_bans_community", "2", "(Requires SteamAPI Key)\n0 = disabled\n1 = kick player if he is community banned (spam, phishing, nudity...)\nThese people will have private profiles and are unable to add friends or comment.\n2 = send an in-game alert to admins if player is community banned (and a discord message if setup)");
	cvarBansTotal = AutoExecConfig_CreateConVar("nda_bans_total", "0", "(Requires SteamAPI Key)\n0 = disabled\nany integer = kick player if he has been banned at least X times (VAC+Game bans)");
	cvarBansRecent = AutoExecConfig_CreateConVar("nda_bans_recent", "5", "(Requires SteamAPI Key)\n0 = disabled\nany positive integer = send an in-game alert to admins (and a discord message if setup) if player has been VAC or Game banned X days ago or less\nany negative integer = same as positive integer, but instead of sending an alert, it will kick the player");
	cvarLog = AutoExecConfig_CreateConVar("nda_log", "1", "0 = don't log\n1 = log check approvals & refusals to server's console\n2 = log check refusals to server's console");
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	cvarHostname = FindConVar("hostname");
	cvarHostname.GetString(g_sHostname, sizeof(g_sHostname));
	
	// Cvars hooks
	
	cvarSteamAPIKey.AddChangeHook(OnSteamAPIKeyChange);
	cvarDiscord.AddChangeHook(OnDiscordChange);
	cvarSteamAge.AddChangeHook(OnSteamAgeChange);
	cvarHostname.AddChangeHook(OnHostnameChange);
	
	// Translations
	LoadTranslations("no_dupe_account.phrases");
	
	// Cmds
	
	RegAdminCmd("sm_checkmepls", Command_CheckMePls, ADMFLAG_ROOT, "Runs every check on you again and apply punishment if needed");
	//RegAdminCmd("sm_vpn", Command_VPN, ADMFLAG_BAN, "Opens a menu to see if someone is potentially using a VPN");
	RegAdminCmd("sm_nda", Command_NDA, ADMFLAG_BAN, "Opens the NDA menu with useful infos");
}

public void OnConfigsExecuted()
{
	cvarSteamAPIKey.GetString(g_sSteamAPIKey, sizeof(g_sSteamAPIKey));
	cvarDiscord.GetString(g_sDiscordWebhook, sizeof(g_sDiscordWebhook));
	cvarSteamAge.GetString(g_sSteamAge, sizeof(g_sSteamAge));
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
	if (cvarPrime.IntValue == 1)
	{
		g_iChecks++;
	}
	if (cvarPlaytime.BoolValue)
	{
		if (g_bSteamAPIKeyAvailable)
		{
			if (cvarPlaytime.IntValue > 0)
			{
				g_iChecks++;
			}
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
	if (!StrEqual(g_sSteamAge, "0"))
	{
		g_bSteamAgeEnabled = true;
		if (g_bSteamAPIKeyAvailable)
		{
			if ((StrContains(g_sSteamAge, "~") == -1) && cvarSteamAge.IntValue > 0)
			{
				g_iChecks++;
			}
		}
		else
		{
			LogMessage("WARNING: No SteamAPI Key is configured, but Steam Age method is enabled! Steam Age requests will NOT work.");
		}
	}
	else
	{
		g_bSteamAgeEnabled = false;
	}
	if (cvarCoin.IntValue == 1)
	{
		g_iChecks++;
	}
	if (!g_bSteamAPIKeyAvailable && (cvarBansVAC.BoolValue || cvarBansGame.BoolValue || cvarBansCommunity.BoolValue || cvarBansTotal.BoolValue || cvarBansRecent.BoolValue))
	{
		LogMessage("WARNING: No SteamAPI Key is configured, but Steam Bans method is enabled! Steam Bans requests will NOT work.");
	}
	
	// Database
	if (cvarDatabase.BoolValue)
	{
		if (!SQL_CheckConfig("no_dupe_account"))
		{
			LogError("WARNING: Database config 'no_dupe_account' doesn't exist in databases.cfg - Database will be automatically disabled.");
			cvarDatabase.IntValue = 0;
		}
		else
			SQL_TConnect(OnSQLConnect, "no_dupe_account");
	}
}

public void OnAllPluginsLoaded()
{
	g_bSteamworksExists = LibraryExists("SteamWorks");
	g_bDiscordExists = LibraryExists("discord-api");
	
	if (!g_bSteamworksExists && (cvarVPN.BoolValue || cvarPrime.BoolValue || cvarPlaytime.BoolValue || cvarSteamLevel.BoolValue || g_bDiscordAvailable || g_bSteamAgeEnabled || cvarBansVAC.BoolValue || cvarBansGame.BoolValue || cvarBansCommunity.BoolValue || cvarBansTotal.BoolValue || cvarBansRecent.BoolValue))
	{
		LogMessage("WARNING: Your current config requires the SteamWorks extension, and it is not installed. VPN, Prime, Playtime, Steam Level and Steam Bans modules will NOT work.");
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
	strcopy(g_sSteamAPIKey, sizeof(g_sSteamAPIKey), newValue);
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
	strcopy(g_sDiscordWebhook, sizeof(g_sDiscordWebhook), newValue);
	if (StrEqual(g_sDiscordWebhook, ""))
	{
		g_bDiscordAvailable = false;
	}
	else
	{
		g_bDiscordAvailable = true;
	}
}

public void OnSteamAgeChange(ConVar convar, char[] oldValue, char[] newValue)
{
	strcopy(g_sSteamAge, sizeof(g_sSteamAge), newValue);
	if (StrEqual(g_sSteamAge, "0"))
	{
		g_bSteamAgeEnabled = false;
	}
	else
	{
		g_bSteamAgeEnabled = true;
	}
}

public void OnHostnameChange(ConVar convar, char[] oldValue, char[] newValue)
{
	strcopy(g_sHostname, sizeof(g_sHostname), newValue);
}

public Action Command_NDA(int client, int args)
{
	Menu menu = new Menu(NDAMenu);
	menu.SetTitle("No Dupe Account");
	
	bool bMenu;
	char buffer[64];
	if (cvarVPN.BoolValue)
	{
		bMenu = true;
		menu.AddItem("vpn", "VPNs");
	}
	if (g_bSteamworksExists)
	{
		if (cvarPrime.BoolValue)
		{
			bMenu = true;
			Format(buffer, sizeof(buffer), "%T", "Command_NDA_NonPrime", client);
			menu.AddItem("prime", buffer);
		}
		if (g_bSteamAPIKeyAvailable)
		{
			if (cvarBansCommunity.IntValue == 2)
			{
				bMenu = true;
				Format(buffer, sizeof(buffer), "%T", "Command_NDA_CommunityBans", client);
				menu.AddItem("communitybans", buffer);
			}
			if (cvarBansRecent.IntValue > 0)
			{
				bMenu = true;
				Format(buffer, sizeof(buffer), "%T", "Command_NDA_RecentBans", client);
				menu.AddItem("recentbans", buffer);
			}
		}
	}
	if (!bMenu)
	{
		Format(buffer, sizeof(buffer), "%T", "Command_NDA_NoMenu", client);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int NDAMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[16];
			GetMenuItem(menu, itemNum, info, sizeof(info));
			
			if (StrEqual(info, "vpn"))
			{
				InitVPNMenu(client);
			}
			else if (StrEqual(info, "prime"))
			{
				InitPrimeMenu(client);
			}
			else if (StrEqual(info, "communitybans"))
			{
				InitCommunityBansMenu(client);
			}
			else
			{
				InitRecentBansMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

void InitVPNMenu(int client)
{
	Menu menu = new Menu(VPNMenu);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%T", "Command_VPN_Title", client);
	menu.SetTitle(buffer);
	char sName[MAX_NAME_LENGTH];
	bool bMenu;
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
			bMenu = true;
		}
	}
	if (!bMenu)
	{
		Format(buffer, sizeof(buffer), "%T", "Command_VPN_NoVPN", client);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
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
				CPrintToChat(client, "%t", "Command_NDA_PlayerDisconnected");
				return 0;
			}
			
			char ip[20];
			GetClientIP(i, ip, sizeof(ip));
			char playername[MAX_NAME_LENGTH];
			GetClientName(i, playername, sizeof(playername));
			CPrintToChat(client, "%t", "SeemsUsingVPN", playername, ip);
		}
		case MenuAction_Cancel: 
		{
			if (itemNum == MenuCancel_ExitBack)
			{
				Command_NDA(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void InitPrimeMenu(int client)
{
	Menu menu = new Menu(PrimeMenu);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%T", "Command_Prime_Title", client);
	menu.SetTitle(buffer);
	char sName[MAX_NAME_LENGTH];
	bool bMenu;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !g_bPrime[i])
		{
			IntToString(GetClientUserId(i), buffer, sizeof(buffer));
			GetClientName(i, sName, sizeof(sName));
			menu.AddItem(buffer, sName);
			bMenu = true;
		}
	}
	if (!bMenu)
	{
		Format(buffer, sizeof(buffer), "%T", "Command_Prime_NoNonPrime", client);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PrimeMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[16];
			GetMenuItem(menu, itemNum, info, sizeof(info));
						
			int i = GetClientOfUserId(StringToInt(info));
			if (!i)
			{
				CPrintToChat(client, "%t", "Command_NDA_PlayerDisconnected");
				return 0;
			}
			
			char playername[MAX_NAME_LENGTH];
			GetClientName(i, playername, sizeof(playername));
			CPrintToChat(client, "%t", "IsNonPrime", playername);
		}
		case MenuAction_Cancel: 
		{
			if (itemNum == MenuCancel_ExitBack)
			{
				Command_NDA(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void InitCommunityBansMenu(int client)
{
	Menu menu = new Menu(CommunityBansMenu);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%T", "Command_Bans_Community_Title", client);
	menu.SetTitle(buffer);
	char sName[MAX_NAME_LENGTH];
	bool bMenu;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && g_bCommunityBanned[i])
		{
			IntToString(GetClientUserId(i), buffer, sizeof(buffer));
			GetClientName(i, sName, sizeof(sName));
			menu.AddItem(buffer, sName);
			bMenu = true;
		}
	}
	if (!bMenu)
	{
		Format(buffer, sizeof(buffer), "%T", "Command_Bans_Community_NoBan", client);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int CommunityBansMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[16];
			GetMenuItem(menu, itemNum, info, sizeof(info));
						
			int i = GetClientOfUserId(StringToInt(info));
			if (!i)
			{
				CPrintToChat(client, "%t", "Command_NDA_PlayerDisconnected");
				return 0;
			}
			
			char playername[MAX_NAME_LENGTH];
			GetClientName(i, playername, sizeof(playername));
			CPrintToChat(client, "%t", "IsCommunityBanned", playername);
		}
		case MenuAction_Cancel: 
		{
			if (itemNum == MenuCancel_ExitBack)
			{
				Command_NDA(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void InitRecentBansMenu(int client)
{
	Menu menu = new Menu(RecentBansMenu);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%T", "Command_Bans_Recent_Title", client);
	menu.SetTitle(buffer);
	char sName[MAX_NAME_LENGTH];
	bool bMenu;
	int days = cvarBansRecent.IntValue;
	if (days < 0)
	{
		days = -days;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && ((g_iVACBans[client] + g_iGameBans[client]) > 0) && (g_iLastBan[i] <= days))
		{
			IntToString(GetClientUserId(i), buffer, sizeof(buffer));
			GetClientName(i, sName, sizeof(sName));
			menu.AddItem(buffer, sName);
			bMenu = true;
		}
	}
	if (!bMenu)
	{
		Format(buffer, sizeof(buffer), "%T", "Command_Bans_Recent_NoBan", client);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int RecentBansMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[16];
			GetMenuItem(menu, itemNum, info, sizeof(info));
						
			int i = GetClientOfUserId(StringToInt(info));
			if (!i)
			{
				CPrintToChat(client, "%t", "Command_NDA_PlayerDisconnected");
				return 0;
			}
			
			char playername[MAX_NAME_LENGTH];
			GetClientName(i, playername, sizeof(playername));
			CPrintToChat(client, "%t", "RecentlyBanned", playername, g_iLastBan[i]);
		}
		case MenuAction_Cancel: 
		{
			if (itemNum == MenuCancel_ExitBack)
			{
				Command_NDA(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void ResetClientVars(int client)
{
	g_iClientChecksDone[client] = 0;
	g_iVACBans[client] = 0
	g_iGameBans[client] = 0;
	g_iLastBan[client] = 0;
	g_bClientPassedCheck[client] = false;
	g_bClientPrivatePlaytime[client] = false;
	g_bClientPrivateProfile[client] = false;
	g_bVPN[client] = false;
	g_bCommunityBanned[client] = false;
	g_bPrime[client] = false;
	delete g_hResourceTimer[client];
	
	// DB
	g_iClientDatabaseStatus[client] = 0; // 0 = awaiting check | 1 = checked | 2 = checked and should be updated | 3 = checked and doesn't exist
	g_iClientDatabasePlaytime[client] = -1;
	g_iClientDatabaseSteamLevel[client] = -1;
	g_iClientDatabaseSteamAge[client] = -1;
	g_iClientDatabaseCSGOLevel[client] = -1;
	g_iClientDatabaseCSGOCoin[client] = 0;
	g_iClientLastCheck[client] = 0;
}

public Action Command_CheckMePls(int client, int args)
{
	if (client)
	{
		ResetClientVars(client);
		OnClientPostAdminCheck(client);
	}
	return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
	if (g_iClientDatabaseStatus[client])
	{
		InsertUpdatePlayer(client, g_iClientDatabaseCSGOLevel[client], g_iClientDatabaseCSGOCoin[client], g_bPrime[client], g_iClientDatabasePlaytime[client], g_iClientDatabaseSteamLevel[client], g_iClientDatabaseSteamAge[client]);
	}
	ResetClientVars(client);
}

//public void OnClientAuthorized(int client)
public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client)) // exclude bots
	{
		return;
	}
	
	if (cvarDatabase.BoolValue && !g_iClientDatabaseStatus[client] && g_bDatabaseReady)
	{
		CheckSQLPlayer(client);
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
		
		if (cvarPrime.IntValue == 1)
		{
			g_iClientChecksDone[client]++;
			// NOTE: This will only consider them as Prime if they bought the game. If they got it by going to Level 21, it won't work
			if (g_bPrime[client] || (SteamWorks_HasLicenseForApp(client, 624820) == k_EUserHasLicenseResultHasLicense)) // if player is paid prime
			{
				if (!g_bClientPassedCheck[client])
					PassedCheck(client, "Is Prime");
				g_bClientPassedCheck[client] = true;
				g_bPrime[client] = true; // this will set Prime again if got through DB, but we don't care
			}
			else
				ProcessChecks(client);
		}
		else if ((cvarPrime.IntValue == 2) && !g_bPrime[client] && (SteamWorks_HasLicenseForApp(client, 624820) == k_EUserHasLicenseResultHasLicense))
			g_bPrime[client] = true;
		
		if (g_bSteamAPIKeyAvailable)
		{
			if (cvarPlaytime.BoolValue)
			{
				if ((g_iClientDatabaseStatus[client] == 1) && (g_iClientDatabasePlaytime[client] != -1))
					VerifPlaytime(client, g_iClientDatabasePlaytime[client], true);
				else
					CheckPlaytime(client);
			}
			
			if (cvarSteamLevel.BoolValue)
			{
				if ((g_iClientDatabaseStatus[client] == 1) && (g_iClientDatabaseSteamLevel[client] != -1))
					VerifSteamLevel(client, g_iClientDatabaseSteamLevel[client], true);
				else
					CheckSteamLevel(client);
			}
			
			if (g_bSteamAgeEnabled)
			{
				if ((g_iClientDatabaseStatus[client] == 1) && (g_iClientDatabaseSteamAge[client] != -1))
					VerifSteamAge(client, g_iClientDatabaseSteamAge[client], true);
				else
					CheckSteamAge(client);
			}
			
			if (cvarBansVAC.BoolValue || cvarBansGame.BoolValue || cvarBansCommunity.BoolValue || cvarBansTotal.BoolValue || cvarBansRecent.BoolValue)
			{
				CheckSteamBans(client);
			}
		}
	}
	
	if (cvarLevel.BoolValue || cvarCoin.BoolValue)
	{
		// NOTE: It was a pain in the ass to make the DB system effective here, so I just made this
		// Player resource is never available immediately
		g_hResourceTimer[client] = CreateTimer(3.0, Timer_GetResource, client, TIMER_REPEAT); // no need to pass userid since OnClientDisconnect() stops the timer
	}
}

public Action Timer_GetResource(Handle timer, int client)
{
	int resourceEnt = GetPlayerResourceEntity();
	int level = GetEntProp(resourceEnt, Prop_Send, "m_nPersonaDataPublicLevel", _, client);
	if (level == -1) // client level is still not available, recheck in 3s
	{
		return Plugin_Continue;
	}
	
	// Resource is available
	
	if (cvarLevel.BoolValue)
	{
		if (level > g_iClientDatabaseCSGOLevel[client])
			g_iClientDatabaseCSGOLevel[client] = level;
		
		g_iClientChecksDone[client]++;
		if (g_iClientDatabaseCSGOLevel[client] >= cvarLevel.IntValue)
		{
			if (!g_bClientPassedCheck[client])
				PassedCheck(client, "Enough CS:GO Level");
			g_bClientPassedCheck[client] = true;
		}
		else
		{
			ProcessChecks(client);
		}
	}
	
	if (cvarCoin.BoolValue)
	{
		int activeCoin = GetEntProp(resourceEnt, Prop_Send, "m_nActiveCoinRank", _, client);
		if (activeCoin)
			g_iClientDatabaseCSGOCoin[client] = activeCoin;
		if (g_iClientDatabaseCSGOCoin[client])
		{
			if (cvarCoin.IntValue == 1)
			{
				if (!g_bClientPassedCheck[client])
					PassedCheck(client, "Has a Coin on his cs:go profile");
				g_iClientChecksDone[client]++;
				g_bClientPassedCheck[client] = true;
			}
		}
		else
		{
			if (cvarCoin.IntValue == 1)
			{
				g_iClientChecksDone[client]++;
				ProcessChecks(client);
			}
			else
			{
				KickClient(client, "%t", "Kicked_NoCoin");
			}
		}
	}
	
	g_hResourceTimer[client] = null;
	return Plugin_Stop;
}

void CheckIP(int client, char[] ip, bool dontNotify = false)
{
	Format(g_sRequestURLBuffer, sizeof(g_sRequestURLBuffer), "http://blackbox.ipinfo.app/lookup/%s", ip);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, g_sRequestURLBuffer);
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client), dontNotify);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckIPResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public void OnCheckIPResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid, bool dontNotify)
{
	int client = GetClientOfUserId(userid);
	
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("Check IP request failed!");
		if ((cvarVPN.IntValue == 2) && client)
		{
			if (!g_bClientPassedCheck[client])
			{
				PassedCheck(client, "Check IP request failed");
				g_bClientPassedCheck[client] = true;
			}
			g_iClientChecksDone[client]++;
		}
		delete hRequest;
		return;
	}
	
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
						if (IsClientInGame(i) && CheckCommandAccess(i, "sm_nda", ADMFLAG_BAN))
						{
							CPrintToChat(i, "%t", "SeemsUsingVPN", playername, ip);
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
				if (!g_bClientPassedCheck[client])
					PassedCheck(client, "No VPN");
				g_bClientPassedCheck[client] = true;
				g_iClientChecksDone[client]++;
			}
			case 3:
			{
				KickClient(client, "%t", "Kicked_VPN");
			}
		}
	}
	else if (cvarVPN.IntValue == 2)
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
			if (cvarLog.BoolValue)
				LogMessage("Refused %L (no check passed - private playtime)", client);
			
			KickClient(client, "%t", "Kicked_PrivatePlaytime");
		}
		else if (g_bClientPrivateProfile[client])
		{
			if (cvarLog.BoolValue)
				LogMessage("Refused %L (no check passed - private profile)", client);
			
			KickClient(client, "%t", "Kicked_PrivateProfile");
		}
		else
		{
			if (cvarLog.BoolValue)
				LogMessage("Refused %L (no check passed)", client);
			
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
	Format(g_sRequestURLBuffer, sizeof(g_sRequestURLBuffer), "http://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=%s&include_played_free_games=1&appids_filter[0]=730&steamid=%s", g_sSteamAPIKey, steamid);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, g_sRequestURLBuffer);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckPlaytimeResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public void OnCheckPlaytimeResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("Playtime request failed!");
		if ((cvarPlaytime.IntValue > 0) && client)
		{
			if (!g_bClientPassedCheck[client])
			{
				PassedCheck(client, "Playtime request failed");
				g_bClientPassedCheck[client] = true;
			}
			g_iClientChecksDone[client]++;
		}
		delete hRequest;
		return;
	}
	
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
	
	if (g_iClientDatabaseStatus[client])
	{
		if (g_iClientDatabasePlaytime[client] < iPlayTime)
			g_iClientDatabasePlaytime[client] = iPlayTime;
		else
			iPlayTime = g_iClientDatabasePlaytime[client];
	}
	
	VerifPlaytime(client, iPlayTime, false);
}

void VerifPlaytime(int client, int iPlayTime, bool database)
{
	int requiredTime = cvarPlaytime.IntValue;
	bool kick;
	if (requiredTime < 0)
	{
		kick = true;
		requiredTime = -requiredTime;
	}
	
	if (iPlayTime <= 0) // 0 could also be that the player just started playing, but it will also appear if games are visible but not playtime
	{
		if (database)
		{
			CheckPlaytime(client);
			return;
		}
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
		if (database)
		{
			CheckPlaytime(client);
			return;
		}
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
	else if (!kick)
	{
		if (!g_bClientPassedCheck[client])
			PassedCheck(client, "Enough playtime");
		g_bClientPassedCheck[client] = true;
		g_iClientChecksDone[client]++;
	}
}

void CheckSteamLevel(int client)
{
	char steamid[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	Format(g_sRequestURLBuffer, sizeof(g_sRequestURLBuffer), "http://api.steampowered.com/IPlayerService/GetSteamLevel/v1/?key=%s&steamid=%s", g_sSteamAPIKey, steamid);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, g_sRequestURLBuffer);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckSteamLevelResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public void OnCheckSteamLevelResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("Steam Level request failed!");
		if ((cvarSteamLevel.IntValue > 0) && client)
		{
			if (!g_bClientPassedCheck[client])
			{
				PassedCheck(client, "Steam Level request failed");
				g_bClientPassedCheck[client] = true;
			}
			g_iClientChecksDone[client]++;
		}
		delete hRequest;
		return;
	}
	
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
	
	if (g_iClientDatabaseStatus[client])
	{
		if (g_iClientDatabaseSteamLevel[client] < iSteamLevel)
			g_iClientDatabaseSteamLevel[client] = iSteamLevel;
		else
			iSteamLevel = g_iClientDatabaseSteamLevel[client];
	}
	
	VerifSteamLevel(client, iSteamLevel, false);
}

void VerifSteamLevel(int client, int iSteamLevel, bool database)
{
	int requiredLevel = cvarSteamLevel.IntValue;
	bool kick;
	if (requiredLevel < 0)
	{
		kick = true;
		requiredLevel = -requiredLevel;
	}
	
	if (iSteamLevel == -1)
	{
		if (database)
		{
			CheckSteamLevel(client);
			return;
		}
		if (kick)
		{
			KickClient(client, "%t", "Kicked_PrivateProfile");
		}
		else
		{
			g_bClientPrivateProfile[client] = true;
			g_iClientChecksDone[client]++;
			ProcessChecks(client);
		}
	}
	else if (iSteamLevel < requiredLevel)
	{
		if (database)
		{
			CheckSteamLevel(client);
			return;
		}
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
	else if (!kick)
	{
		if (!g_bClientPassedCheck[client])
			PassedCheck(client, "Enough Steam Level");
		g_bClientPassedCheck[client] = true;
		g_iClientChecksDone[client]++;
	}
}

void CheckSteamAge(int client)
{
	char steamid[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	Format(g_sRequestURLBuffer, sizeof(g_sRequestURLBuffer), "http://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=%s&steamids=%s", g_sSteamAPIKey, steamid);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, g_sRequestURLBuffer);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckSteamAgeResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

// sets iMode to the correct mode: 0 = positive, 1 = negative, 2 = '~'
// sets iRequiredAge to the required age
void RetrieveSteamAgeMode(int& iMode, int& iRequiredAge)
{	
	if (StrContains(g_sSteamAge, "~") != -1)
	{
		iMode = 2;
		iRequiredAge = StringToInt(g_sSteamAge[1]);
	}
	else
	{
		iRequiredAge = StringToInt(g_sSteamAge);
		if (iRequiredAge < 0)
		{
			iMode = 1;
			iRequiredAge = -iRequiredAge;
		}
	}
}

public void OnCheckSteamAgeResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("Steam Age request failed!");
		int iMode, iRequiredAge;
		RetrieveSteamAgeMode(iMode, iRequiredAge);
		if (!iMode && client)
		{
			if (!g_bClientPassedCheck[client])
			{
				PassedCheck(client, "Steam Age request failed");
				g_bClientPassedCheck[client] = true;
			}
			g_iClientChecksDone[client]++;
		}
		delete hRequest;
		return;
	}
	
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
	
	int iSteamAge = -1;
	int iStartPosition = StrContains(sBody, "timecreated");
	if (iStartPosition != -1)
	{
		strcopy(sBody, iBodySize, sBody[iStartPosition]); // keep: timecreated":XXXXXXX,"personastateflags":X,"loccountrycode":"XX"}]}}
		char sArray[1][32]; // we only need the first part
		ExplodeString(sBody, ",", sArray, sizeof(sArray), sizeof(sArray[])); // keep: timecreated":XXXXXXX
		iSteamAge = StringToInt(sArray[0][13]); // get everything after ':', aka the integer
		iSteamAge = GetTime() - iSteamAge; // returns age in seconds
		iSteamAge /= 60; // returns age in minutes, rounds to zero (iSteamAge is an integer)
	}
	
	if (g_iClientDatabaseStatus[client])
	{
		if (g_iClientDatabaseSteamAge[client] < iSteamAge)
			g_iClientDatabaseSteamAge[client] = iSteamAge;
		else
			iSteamAge = g_iClientDatabaseSteamAge[client];
	}
	
	VerifSteamAge(client, iSteamAge, false);
}

void VerifSteamAge(int client, int iSteamAge, bool database)
{
	int iMode, iRequiredAge;
	RetrieveSteamAgeMode(iMode, iRequiredAge);
	
	if (iSteamAge == -1)
	{
		if (database)
		{
			CheckSteamAge(client);
			return;
		}
		switch (iMode)
		{
			case 0:
			{
				g_iClientChecksDone[client]++;
				ProcessChecks(client);
			}
			case 1:
			{
				KickClient(client, "%t", "Kicked_PrivateProfile");
			}
		}
	}
	else if (iSteamAge < iRequiredAge)
	{
		if (database)
		{
			CheckSteamAge(client);
			return;
		}
		if (!iMode)
		{
			g_iClientChecksDone[client]++;
			ProcessChecks(client);
		}
		else
		{
			KickClient(client, "%t", "Kicked_SteamAccountTooRecent");
		}
	}
	else if (!iMode)
	{
		if (!g_bClientPassedCheck[client])
			PassedCheck(client, "Enough Steam Age");
		g_bClientPassedCheck[client] = true;
		g_iClientChecksDone[client]++;
	}
}

void CheckSteamBans(int client)
{
	char steamid[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	Format(g_sRequestURLBuffer, sizeof(g_sRequestURLBuffer), "http://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=%s&steamids=%s", g_sSteamAPIKey, steamid);
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, g_sRequestURLBuffer);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hRequest, 5);
	SteamWorks_SetHTTPCallbacks(hRequest, OnCheckSteamBansResponse);
	SteamWorks_SendHTTPRequest(hRequest);
}

public void OnCheckSteamBansResponse(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int userid)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("Steam Bans request failed!");
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
	
	char sArray[6][64]; // cut the last one
	ExplodeString(sBody, ",", sArray, sizeof(sArray), sizeof(sArray[]));
	if (StrContains(sArray[1], "false") == -1) // doesn't contain 'false'
	{
		g_bCommunityBanned[client] = true;
	}
	g_iVACBans[client] = StringToInt(sArray[3][18]) // get everything after ':', aka the integer
	g_iLastBan[client] = StringToInt(sArray[4][19]) // get everything after ':', aka the integer, days since last ban
	g_iGameBans[client] = StringToInt(sArray[5][19]) // get everything after ':', aka the integer
	
	if (cvarBansVAC.BoolValue && (g_iVACBans[client] >= cvarBansVAC.IntValue))
	{
		if (g_iVACBans[client] == 1)
			KickClient(client, "%t", "Kicked_Bans_VAC");
		else
			KickClient(client, "%t", "Kicked_Bans_VAC_multiple");
	}
	else if (cvarBansGame.BoolValue && (g_iGameBans[client] >= cvarBansGame.IntValue))
	{
		if (g_iGameBans[client] == 1)
			KickClient(client, "%t", "Kicked_Bans_Game");
		else
			KickClient(client, "%t", "Kicked_Bans_Game_multiple");
	}
	else if (g_bCommunityBanned[client] && cvarBansCommunity.BoolValue)
	{
		if (cvarBansCommunity.IntValue == 1)
		{
			KickClient(client, "%t", "Kicked_Bans_Community");
		}
		else
		{
			char playername[MAX_NAME_LENGTH];
			GetClientName(client, playername, sizeof(playername));
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientInGame(i) && CheckCommandAccess(i, "sm_nda", ADMFLAG_BAN))
				{
					CPrintToChat(i, "%t", "IsCommunityBanned", playername);
				}
			}
			if (g_bDiscordAvailable && g_bDiscordExists)
			{
				char message[128];
				Format(message, sizeof(message), "%T", "Discord_IsCommunityBanned", LANG_SERVER);
				SendDiscordMessage("Community Ban", message, client);
			}
		}
	}
	else if (cvarBansTotal.BoolValue && ((g_iVACBans[client] + g_iGameBans[client]) >= cvarBansTotal.IntValue))
	{
		KickClient(client, "%t", "Kicked_Bans_Total");
	}
	else // having else if here is not a problem in itself for now, but it might be in the future due to how the BansRecent method is done
	{
		if (cvarBansRecent.BoolValue)
		{
			if ((cvarBansRecent.IntValue < 0) && ((g_iVACBans[client] + g_iGameBans[client]) > 0) && (g_iLastBan[client] <= -cvarBansRecent.IntValue))
			{
				KickClient(client, "%t", "Kicked_Bans_Recent");
			}
			else if ((cvarBansRecent.IntValue > 0) && ((g_iVACBans[client] + g_iGameBans[client]) > 0) && (g_iLastBan[client] <= cvarBansRecent.IntValue))
			{
				char playername[MAX_NAME_LENGTH];
				GetClientName(client, playername, sizeof(playername));
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i) && CheckCommandAccess(i, "sm_nda", ADMFLAG_BAN))
					{
						CPrintToChat(i, "%t", "RecentlyBanned", playername, g_iLastBan[client]);
					}
				}
				if (g_bDiscordAvailable && g_bDiscordExists)
				{
					char message[128];
					Format(message, sizeof(message), "%T", "Discord_RecentlyBanned", LANG_SERVER, g_iLastBan[client]);
					SendDiscordMessage("Recently Banned", message, client);
				}
			}
		}
	}
}

void PassedCheck(int client, char[] reason)
{
	if (cvarLog.IntValue == 1)
	{
		LogMessage("Approved %L (%s)", client, reason);
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

public void OnSQLConnect(Handle owner, Handle hndl, char[] error, any data)
{
	if (!hndl)
	{
		LogError("ERROR: The database doesn't work: Database failure: %s", error);
		cvarDatabase.IntValue = 0;
	}
	else
	{
		g_hDB = hndl;
		
		/* NOT USED AS OF NOW
		DBDriver driver = view_as<DBDriver>(SQL_ReadDriver(g_hDB));
		driver.GetIdentifier(g_sSQLBuffer, sizeof(g_sSQLBuffer)); // returns "mysql" or "sqlite"
		if (StrEqual(g_sSQLBuffer, "mysql"))
			g_bMySQL = true;
		*/
		
		UpdateDatabase();
	}
}

// Create tables, fix older syntaxes (if any)...
// Meant for upgrading from the very first version to the latest one seemlessly
// Going the other way around will NOT work and might break the DB (although unlikely), proceed with caution.
void UpdateDatabase()
{
	// SQLite syntax, but seems valid for MySQL too
	Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "CREATE TABLE IF NOT EXISTS players("
												... "steamid varchar(32) PRIMARY KEY NOT NULL, "
												... "csgo_level INTEGER NOT NULL, "
												... "csgo_coin INTEGER NOT NULL, "
												... "prime INTEGER NOT NULL, "
												... "csgo_playtime INTEGER NOT NULL, "
												... "steam_level INTEGER NOT NULL, "
												... "steam_age INTEGER NOT NULL, "
												... "last_check INTEGER NOT NULL)");
	SQL_TQuery(g_hDB, OnDatabaseUpdated, g_sSQLBuffer);
	
	/* THIS PART OF THE CODE IS LEFT UNTOUCHED, SINCE WE DON'T NEED IT AS OF NOW.
	Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "PRAGMA table_info(players)");
	SQL_TQuery(g_hDB, OnGetColumnsResponse, g_sSQLBuffer);
	*/
}

public void OnDatabaseUpdated(Handle owner, Handle hndl, char[] error, any data)
{
	if (!hndl)
	{
		LogError("'UpdateDatabase' Query failure: %s", error);
		SetFailState("'UpdateDatabase' Query failure, check your logs");
	}
	
	if (cvarDatabaseExpire.BoolValue)
	{
		Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "DELETE FROM players WHERE last_check < %i", GetTime() - (cvarDatabaseExpire.IntValue * 60 * 60 * 24));
		SQL_TQuery(g_hDB, SQL_NullCallback, g_sSQLBuffer);
	}
	
	g_bDatabaseReady = true;
}

public void SQL_NullCallback(Handle owner, Handle hndl, char[] error, any data)
{
	if (!hndl)
	{
		LogError("Query failure: %s", error);
	}
}

void CheckSQLPlayer(int client)
{
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "SELECT last_check FROM players WHERE steamid = '%s'", steamid);
	SQL_TQuery(g_hDB, OnCheckSQLPlayer, g_sSQLBuffer, GetClientUserId(client));
}

public void OnCheckSQLPlayer(Handle owner, Handle hndl, char [] error, any data)
{
	int client = GetClientOfUserId(data);
	
	/* Make sure the client didn't disconnect while the thread was running */
	
	if (!client)
		return;
	
	if (!hndl)
	{
		LogError("'CheckSQLPlayer' Query failure: %s", error);
		return;
	}
	
	if (!SQL_GetRowCount(hndl) || !SQL_FetchRow(hndl)) 
	{
		g_iClientDatabaseStatus[client] = 3; // doesn't exist
		OnClientPostAdminCheck(client);
		return;
	}
	
	g_iClientLastCheck[client] = SQL_FetchInt(hndl, 0);
	
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	if (cvarDatabaseExpire.BoolValue && (g_iClientLastCheck[client] < (GetTime() - (cvarDatabaseExpire.IntValue * 60 * 60 * 24))))
	{
		Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "DELETE FROM players WHERE steamid = '%s'", steamid);
		SQL_TQuery(g_hDB, SQL_NullCallback, g_sSQLBuffer);
		g_iClientDatabaseStatus[client] = 3; // doesn't exist
		OnClientPostAdminCheck(client);
		return;
	}
	
	Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "SELECT csgo_level, "
												... "csgo_coin, "
												... "prime, "
												... "csgo_playtime, "
												... "steam_level, "
												... "steam_age "
												... "FROM players WHERE steamid = '%s'", steamid);
	SQL_TQuery(g_hDB, OnCheckSQLPlayer2, g_sSQLBuffer, GetClientUserId(client));
}

public void OnCheckSQLPlayer2(Handle owner, Handle hndl, char [] error, any data)
{
	int client = GetClientOfUserId(data);
	
	/* Make sure the client didn't disconnect while the thread was running */
	
	if (!client)
		return;
	
	if (!hndl)
	{
		LogError("'CheckSQLPlayer2' Query failure: %s", error);
		return;
	}
	
	g_iClientDatabaseCSGOLevel[client] = SQL_FetchInt(hndl, 0);
	g_iClientDatabaseCSGOCoin[client] = SQL_FetchInt(hndl, 1);
	g_bPrime[client] = !!SQL_FetchInt(hndl, 2); // !!int converts it to bool
	g_iClientDatabasePlaytime[client] = SQL_FetchInt(hndl, 3);
	g_iClientDatabaseSteamLevel[client] = SQL_FetchInt(hndl, 4);
	g_iClientDatabaseSteamAge[client] = SQL_FetchInt(hndl, 5);
	
	if (cvarDatabaseRefresh.BoolValue && (g_iClientLastCheck[client] < (GetTime() - (cvarDatabaseRefresh.IntValue * 60))))
		g_iClientDatabaseStatus[client] = 2;
	else
		g_iClientDatabaseStatus[client] = 1;
	
	OnClientPostAdminCheck(client);
}

void InsertUpdatePlayer(int client, int csgo_level, int csgo_coin, bool prime, int csgo_playtime, int steam_level, int steam_age)
{
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "REPLACE INTO players("
												... "steamid, "
												... "csgo_level, "
												... "csgo_coin, "
												... "prime, "
												... "csgo_playtime, "
												... "steam_level, "
												... "steam_age, "
												... "last_check) "
												... "VALUES("
												... "'%s', "
												... "'%i', "
												... "'%i', "
												... "'%i', "
												... "'%i', "
												... "'%i', "
												... "'%i', "
												... "'%i')", steamid, csgo_level, csgo_coin, prime, csgo_playtime, steam_level, steam_age, (g_iClientDatabaseStatus[client] == 1) ? g_iClientLastCheck[client] : GetTime()); // Keep old last_check, else update it. Only update it if status != 1
	SQL_TQuery(g_hDB, SQL_NullCallback, g_sSQLBuffer);
}

/* THIS PART OF THE CODE IS LEFT UNTOUCHED, SINCE WE DON'T NEED IT AS OF NOW.

// Checks if a table exists
stock void ColumnExists(char[] column)
{
	if (g_bMySQL)
	{
		
		
	}
	else
	{
		// table exists?: Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='%s')", table);
		Format(g_sSQLBuffer, sizeof(g_sSQLBuffer), "PRAGMA table_info('%s')", column);
	}
	SQL_TQuery(g_hDB, OnTableExistsResponse, g_sSQLBuffer, table);
}

public void OnGetColumnsResponse(Handle owner, Handle hndl, char[] error, any data)
{
	if (!hndl)
	{
		LogError("'GetColumns' Query failure: %s", error);
		SetFailState("'GetColumns' Query failure, check your logs");
	}
	if (g_bMySQL)
	{
		
		
	}
	else
	{
		char tableName[32];
		while (SQL_FetchRow(g_hDB))
		{
			SQL_FetchString(g_hDB, 1, tableName, sizeof(tableName));
			if (StrEqual())
		}
	}	
}
*/