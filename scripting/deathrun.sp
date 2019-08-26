#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
    name = "Deathrun Manager",
    author = "Ilusion9",
    description = "Deathrun gamemode with queue",
    version = "2.2",
    url = "https://github.com/Ilusion9/"
};

ArrayList g_List_Queue;

ConVar g_Cvar_BotQuota;
ConVar g_Cvar_BotTeam;

int g_iTerrorist;

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("deathrun.phrases");

	HookEvent("player_connect_full", Event_PlayerConnect);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("round_prestart", Event_RoundPreStart);
	
	AddCommandListener(Command_Jointeam, "jointeam");
	RegConsoleCmd("sm_t", Command_Terrorist);
	
	g_List_Queue = new ArrayList();
	
	g_Cvar_BotQuota = FindConVar("bot_quota");
	g_Cvar_BotTeam = FindConVar("bot_join_team");
	
	AutoExecConfig(false, "gamemode_deathrun");
}

public void OnMapStart()
{
	g_iTerrorist = 0;
}

public void OnMapEnd()
{	
	g_List_Queue.Clear();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	/* game_player_equip entities will not be activated until players will trigger them */
    if (StrEqual(classname, "game_player_equip"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnGamePlayerEquipSpawn);
	}
}

public void OnGamePlayerEquipSpawn(int entity)
{
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");

	if (flags & 1) // "Use Only" flag
	{
		return;
	}

	SetEntProp(entity, Prop_Data, "m_spawnflags", flags | 1);
}

public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) 
{
	/* Players will auto join CT */
	RequestFrame(Frame_PlayerConnect, event.GetInt("userid"));
}

public void Frame_PlayerConnect(any data)
{
	int client = GetClientOfUserId(view_as<int>(data));
	
	if (client)
	{
		ChangeClientTeam(client, CS_TEAM_CT);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) 
{
	if (event.GetInt("team") != CS_TEAM_CT)
	{
		int index = g_List_Queue.FindValue(event.GetInt("userid"));

		if (index != -1)
		{
			g_List_Queue.Erase(index);
		}
	}
}

public void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	g_Cvar_BotTeam.SetString("t");
	g_Cvar_BotQuota.SetString("1");

	if (GameRules_GetProp("m_bWarmupPeriod"))
	{
		return;
	}
	
	if (g_iTerrorist)
	{
		int client = GetClientOfUserId(g_iTerrorist);
		g_iTerrorist = 0;
		
		if (client && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_T)
		{
			CS_SwitchTeam(client, CS_TEAM_CT);
		}
	}

	if (g_List_Queue.Length)
	{
		g_iTerrorist = g_List_Queue.Get(0);
		int client = GetClientOfUserId(g_iTerrorist);
		
		if (client && IsClientInGame(client))
		{
			CS_SwitchTeam(client, CS_TEAM_T);
		}
	}
	
	PrintToChatAll("> %t", "Type Command", "sm_t");
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] %t", "Command is in-game only");
		return Plugin_Handled;
	}
	
	char arg[3];
	GetCmdArg(1, arg, sizeof(arg));
	
	/* Players will be able to join only CTs and Spectators */
	if (StrEqual(arg, "1") || StrEqual(arg, "3"))
	{
		return Plugin_Continue;
	}
	
	return Plugin_Handled;
}

public Action Command_Terrorist(int client, int args)
{	
	if (!client)
	{
		ReplyToCommand(client, "[SM] %t", "Command is in-game only");
		return Plugin_Handled;
	}
	
	int userId = GetClientUserId(client);
	
	if (g_List_Queue.FindValue(userId) != -1)
	{
		ReplyToCommand(client, "%t", "Queue At");
		return Plugin_Handled;
	}
	
	g_List_Queue.Push(userId);
	ReplyToCommand(client, "%t", "Queue In");

	return Plugin_Handled;
}