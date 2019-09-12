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
    version = "2.5",
    url = "https://github.com/Ilusion9/"
};

ArrayList g_List_Queue;
ConVar g_Cvar_RemoveWeapons;

int g_Terrorist;

public void OnPluginStart()
{
	g_List_Queue = new ArrayList();	
	
	LoadTranslations("common.phrases");
	LoadTranslations("deathrun.phrases");

	HookEvent("player_connect_full", Event_PlayerConnect);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("round_prestart", Event_RoundPreStart);
	
	AddCommandListener(Command_Jointeam, "jointeam");
	RegConsoleCmd("sm_queue", Command_Queue);
	
	g_Cvar_RemoveWeapons = CreateConVar("dr_remove_weapons_round_start", "1", "Remove all players weapons on round start.", 0, true, 0.0, true, 1.0);	
	AutoExecConfig(false, "gamemode_deathrun");
}

public void OnMapStart()
{
	g_Terrorist = 0;
}

public void OnMapEnd()
{	
	g_List_Queue.Clear();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	/* game_player_equip entities will be deactivated until players will trigger them */

	if (StrEqual(classname, "game_player_equip")) {
		SDKHook(entity, SDKHook_SpawnPost, OnGamePlayerEquipSpawn);
	}
}

public void OnGamePlayerEquipSpawn(int entity)
{
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");

	if (flags & 1) {
		return;
	}

	SetEntProp(entity, Prop_Data, "m_spawnflags", flags | 1);
}

public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) 
{
	RequestFrame(Frame_HandlePlayerConnect, event.GetInt("userid"));
}

public void Frame_HandlePlayerConnect(any data)
{
	int client = GetClientOfUserId(view_as<int>(data));
	
	if (client) {
		ChangeClientTeam(client, CS_TEAM_CT);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) 
{
	if (event.GetInt("team") != CS_TEAM_CT)
	{
		int index = g_List_Queue.FindValue(event.GetInt("userid"));

		if (index != -1) {
			g_List_Queue.Erase(index);
		}
	}
}

public void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{	
	if (GameRules_GetProp("m_bWarmupPeriod")) {
		return;
	}
		
	if (g_Terrorist)
	{
		int client = GetClientOfUserId(g_Terrorist);
		g_Terrorist = 0;
		
		if (client && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_T) {
			CS_SwitchTeam(client, CS_TEAM_CT);
		}
	}
	
	if (g_List_Queue.Length)
	{
		g_Terrorist = g_List_Queue.Get(0);
		int client = GetClientOfUserId(g_Terrorist);
		
		if (client && IsClientInGame(client)) {
			CS_SwitchTeam(client, CS_TEAM_T);
		}
	}
		
	if (g_Cvar_RemoveWeapons.BoolValue)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i)) {
				RemovePlayerWeapons(i);
			}
		}
	}
	
	PrintToChatAll(" \x04[DR]\x01 %t", "Type Command", "\x10!queue\x01");
}

public Action Command_Jointeam(int client, const char[] command, int args)
{	
	if (client)
	{
		char arg[3];
		GetCmdArg(1, arg, sizeof(arg));
		
		if (StrEqual(arg, "1") || StrEqual(arg, "3")) {
			return Plugin_Continue;
		}
	}
	
	return Plugin_Handled;
}

public Action Command_Queue(int client, int args)
{	
	if (!client)
	{
		ReplyToCommand(client, "[SM] %t", "Command is in-game only");
		return Plugin_Handled;
	}
	
	int userId = GetClientUserId(client);
	
	if (g_List_Queue.FindValue(userId) != -1)
	{
		ReplyToCommand(client, "%s%t", GetCmdReplySource() != SM_REPLY_TO_CONSOLE ? " \x04[DR]\x01 " : "", "Already In Queue");
		return Plugin_Handled;
	}
	
	g_List_Queue.Push(userId);
	ReplyToCommand(client, "%s%t", GetCmdReplySource() != SM_REPLY_TO_CONSOLE ? " \x04[DR]\x01 " : "", "Added To Queue");
	
	return Plugin_Handled;
}

stock void RemovePlayerWeapons(int client)
{   
	int length = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	
	for (int i= 0; i < length; i++) 
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
