#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#include <colorlib>
#pragma newdecls required

public Plugin myinfo =
{
	name = "Deathrun Manager",
	author = "Ilusion9",
	description = "Deathrun gamemode with queue",
	version = "2.6",
	url = "https://github.com/Ilusion9/"
};

ArrayList g_List_Queue;

ConVar g_Cvar_BotQuota;
ConVar g_Cvar_RemoveWeapons;
ConVar g_Cvar_IgnoreDeaths;

int g_TerroristId;

public void OnPluginStart()
{
	g_List_Queue = new ArrayList();	
	LoadTranslations("deathrun.phrases");

	HookEvent("player_connect_full", Event_PlayerConnect);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_death", Event_PlayerDeath_Pre, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_prestart", Event_RoundPreStart);
	
	AddCommandListener(Command_JoinTeam, "jointeam");
	RegConsoleCmd("sm_t", Command_RequestTerrorist);
	RegConsoleCmd("sm_terro", Command_RequestTerrorist);
	RegConsoleCmd("sm_terrorist", Command_RequestTerrorist);

	g_Cvar_RemoveWeapons = CreateConVar("dr_remove_weapons_round_start", "1", "Remove all players weapons on round start?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_IgnoreDeaths = CreateConVar("dr_ignore_world_deaths_from_score", "0", "Ignore deaths made by world (traps) from players score?", FCVAR_NONE, true, 0.0, true, 1.0);

	g_Cvar_BotQuota = FindConVar("bot_quota");
	g_Cvar_BotQuota.AddChangeHook(ConVarChange_BotQuota);
	
	AutoExecConfig(true, "deathrun");
}

public void ConVarChange_BotQuota(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_Cvar_BotQuota.IntValue != 1)
	{
		g_Cvar_BotQuota.SetInt(1);
	}
}

public void OnMapStart()
{
	g_TerroristId = 0;
}

public void OnConfigsExecuted()
{
	g_Cvar_BotQuota.SetInt(1);
	ServerCommand("exec gamemode_deathrun");
	
	SetConVar("bot_quota_mode", "normal");
	SetConVar("bot_join_team", "t");
	SetConVar("bot_join_after_player", "0");
}

public void OnMapEnd()
{	
	g_List_Queue.Clear();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "game_player_equip"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnGamePlayerEquipSpawn);
	}
}

public void OnGamePlayerEquipSpawn(int entity)
{
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");
	if (flags & 1)
	{
		return;
	}

	SetEntProp(entity, Prop_Data, "m_spawnflags", flags | 1);
}

public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) 
{
	int userId = event.GetInt("userid");
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
	{
		return;
	}
	
	SetEntPropFloat(client, Prop_Send, "m_fForceTeam", 3600.0);
	CreateTimer(2.0, Timer_PlayerConnect, userId, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PlayerConnect(Handle timer, any data)
{
	int client = GetClientOfUserId(view_as<int>(data));
	if (!client || !IsClientInGame(client))
	{
		return Plugin_Stop;
	}
	
	if (GetClientTeam(client) != CS_TEAM_CT)
	{
		ChangeClientTeam(client, CS_TEAM_CT);
	}
	return Plugin_Stop;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) 
{
	int toTeam = event.GetInt("team");
	int userId = event.GetInt("userid");
	
	if (toTeam != CS_TEAM_CT)
	{
		int posQueue = g_List_Queue.FindValue(userId);
		if (posQueue != -1)
		{
			g_List_Queue.Erase(posQueue);
		}
	}
}

public void Event_PlayerDeath_Pre(Event event, const char[] name, bool dontBroadcast) 
{
	if (IsWarmupPeriod())
	{
		if (!event.GetInt("attacker"))
		{
			event.BroadcastDisabled = true;
		}
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) 
{
	if (!event.GetInt("attacker"))
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if (client)
		{
			int frags = GetClientFrags(client) + 1;
			SetEntProp(client, Prop_Data, "m_iFrags", frags);

			if (g_Cvar_IgnoreDeaths.BoolValue)
			{
				int deaths = GetClientDeaths(client) - 1;
				SetEntProp(client, Prop_Data, "m_iDeaths", deaths);
			}
		}
	}
}

public void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{	
	if (IsWarmupPeriod())
	{
		return;
	}
	
	if (g_TerroristId)
	{
		int client = GetClientOfUserId(g_TerroristId);
		g_TerroristId = 0;
		
		if (client && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_T)
		{
			CS_SwitchTeam(client, CS_TEAM_CT);
		}
	}
	
	if (g_List_Queue.Length)
	{
		g_TerroristId = g_List_Queue.Get(0);
		g_List_Queue.Erase(0);
		
		int client = GetClientOfUserId(g_TerroristId);
		if (client && IsClientInGame(client))
		{
			char clientName[MAX_NAME_LENGTH];
			GetClientName(client, clientName, sizeof(clientName));
			
			CS_SwitchTeam(client, CS_TEAM_T);
			CPrintToChatAll("{green}[DR]{default} %t", "New Terrorist", clientName);
		}
	}
	
	if (g_List_Queue.Length)
	{
		int client = GetClientOfUserId(g_List_Queue.Get(0));
		if (client)
		{
			CPrintToChat(client, "{green}[DR]{default} %t", "Terrorist in Next Round");
		}
		
		for (int i = 1; i < g_List_Queue.Length; i++)
		{
			client = GetClientOfUserId(g_List_Queue.Get(i));
			if (client)
			{
				CPrintToChat(client, "{green}[DR]{default} %t", "Terrorist in X Rounds", i + 1);
			}
		}
	}
	
	if (g_Cvar_RemoveWeapons.BoolValue)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				RemovePlayerWeapons(i);
			}
		}
	}	
}

public Action Command_JoinTeam(int client, const char[] command, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	char arg[3];
	GetCmdArg(1, arg, sizeof(arg));
	
	if (StrEqual(arg, "1") || StrEqual(arg, "3"))
	{
		return Plugin_Continue;
	}
	
	return Plugin_Handled;
}

public Action Command_RequestTerrorist(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	int userId = GetClientUserId(client);
	int posQueue = g_List_Queue.FindValue(userId);
	
	if (posQueue != -1)
	{
		CReplyToCommand(client, "{green}[DR]{default} %t", "Already Requested to be Terrorist");
	}
	else
	{
		posQueue = g_List_Queue.Push(userId);
	}
	
	if (posQueue)
	{
		CReplyToCommand(client, "{green}[DR]{default} %t", "Terrorist in X Rounds", posQueue + 1);
	}
	else
	{
		CReplyToCommand(client, "{green}[DR]{default} %t", "Terrorist in Next Round");
	}
	
	return Plugin_Handled;
}

void SetConVar(const char[] name, const char[] value)
{
	ConVar convar = FindConVar(name);
	if (convar)
	{
		convar.SetString(value);
	}
}

bool IsWarmupPeriod()
{
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

void RemovePlayerWeapons(int client)
{   
	int length = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < length; i++) 
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i); 
		if (weapon != -1)
		{
			RemovePlayerItem(client, weapon);
			AcceptEntityInput(weapon, "KillHierarchy");
		}
	}
	
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
}
