#pragma semicolon 1

#define PLUGIN_AUTHOR "Wesker"
#define PLUGIN_VERSION "0.01"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

StringMap g_smButtonMap;
float g_fCmdTime[MAXPLAYERS+1];
bool g_bInUse[MAXPLAYERS+1];
bool g_bEquipping[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "Button Tracer",
	author = PLUGIN_AUTHOR,
	description = "Finds buttons blocked by other players in your line of sight.",
	version = PLUGIN_VERSION,
	url = "https://steam-gamers.net/"
};

public void OnPluginStart()
{
	HookEvent("round_end", RoundEnd);
	g_smButtonMap = new StringMap();
	
	for(int i = 1; i <= MaxClients; i++)
    {
    	if (IsClientInGame(i))
    	{
			OnClientPostAdminCheck(i);
		}
    }
    HookEntityOutput("func_button", "OnPressed", Button_Pressed);
}

public void OnClientPostAdminCheck(int client)
{
	g_bEquipping[client] = false;
	SDKHook(client, SDKHook_WeaponEquip, WeaponEquip);
}

public void Button_Pressed(const char[] output, int caller, int activator, float delay)
{
	if (!IsValidClient(activator))
		return;
		
	if (!IsPlayerAlive(activator)) 
		return;
		
	g_fCmdTime[activator] = GetGameTime() + 1.0;
}

public Action WeaponEquip(int client, int weapon)
{
	if (!IsValidClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;
	
	if (!IsValidEdict(weapon))
		return Plugin_Continue;
	
	char TargetName[255];
	GetEntPropString(weapon, Prop_Data, "m_iName", TargetName, sizeof(TargetName));  
	if (TargetName[0] != '\0')
	{
		g_bEquipping[client] = true;
		CreateTimer(3.5, Timer_Equipping, client);
		return Plugin_Continue;
	}
				
	int child = GetEntPropEnt(weapon, Prop_Data, "m_hMoveChild");
	int worldmodel = GetEntPropEnt(weapon, Prop_Send, "m_hWeaponWorldModel");
	if (child != -1 && child != worldmodel)
	{
		g_bEquipping[client] = true;
		CreateTimer(3.5, Timer_Equipping, client);
		return Plugin_Continue;
	}
	
	return Plugin_Continue;
}

public Action Timer_Equipping(Handle timer, int client)
{
	g_bEquipping[client] = false;
}

public void RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_smButtonMap.Clear();
	
	for (int i = 1; i <= MAXPLAYERS; i++) {
		g_fCmdTime[i] = 0.0;
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!StrEqual(classname, "func_button"))
		return;
		
	int mParent = FindMasterParent(entity);
	if (IsValidEdict(mParent))
	{
		char buffer[128];
		GetEdictClassname(mParent, buffer, sizeof(buffer));
		
		if (StrContains(buffer, "weapon") != -1)
		{
			Format(buffer, sizeof(buffer), "%i", EntIndexToEntRef(mParent));
			g_smButtonMap.SetValue(buffer, EntIndexToEntRef(entity));
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!(buttons & IN_USE))
	{
		g_bInUse[client] = false;
		return Plugin_Continue;
	}
	
	if (g_fCmdTime[client] > GetGameTime()) {
		return Plugin_Continue;
	}
	
	if (g_bInUse[client] || g_bEquipping[client])
	{
		return Plugin_Continue;
	}
	
	if (!IsValidClient(client))
		return Plugin_Continue;
		
	if (!IsPlayerAlive(client))
	{
		//PrintToChat(client, "[ButtonTracer] You must be alive to +USE");
		return Plugin_Continue;
	}
		
	float cEyePos[3], cEyeAng[3], cDistant[3];
	GetClientEyePosition(client, cEyePos);
	GetClientEyeAngles(client, cEyeAng);
	
	//Get direction
	GetAngleVectors(cEyeAng, cEyeAng, NULL_VECTOR, NULL_VECTOR); //Transform into vector
	NormalizeVector(cEyeAng, cEyeAng); //Clamp vector
	ScaleVector(cEyeAng, 96.0); //How far ahead of player we go
	AddVectors(cEyePos, cEyeAng, cDistant); //Move origin along vector
	
	Handle ray = TR_TraceRayFilterEx(cEyePos, cDistant, MASK_ALL, RayType_EndPoint, TraceEntities, client);
	
	if (TR_DidHit(ray))
	{
		int entity = TR_GetEntityIndex(ray);
		if (IsValidEdict(entity))
		{
			char sClass[128];
			GetEdictClassname(entity, sClass, sizeof(sClass));
			PrintToConsole(client, "[ButtonTrace] First trace entity - %s", sClass);
			if (!StrEqual(sClass, "func_movelinear") && StrContains(sClass, "train") == -1 && StrContains(sClass, "weapon") == -1 && !StrEqual(sClass, "func_rotating")
			&& StrContains(sClass, "func_wall") == -1 && !StrEqual(sClass, "func_brush") && !StrEqual(sClass, "worldspawn") && !StrEqual(sClass, "func_breakable") 
			&& !StrEqual(sClass, "prop_door_rotating"))
			{
				if (StrEqual(sClass, "func_door_rotating")) {
					int isLocked = GetEntProp(entity, Prop_Data, "m_bLocked", 1);
					int flags = GetEntProp(entity, Prop_Data, "m_spawnflags", 4);
					if (isLocked || !(flags & 256)) {
						CloseHandle(ray);
						g_bInUse[client] = true;
						return Plugin_Continue;
					}
				}
				if (AcceptEntityInput(entity, "Use", client, client))
				{
					PrintToConsole(client, "[ButtonTrace] Sent +USE to %s", sClass);
					if (StrContains(sClass, "func_button") == -1)
					{
						LogMessage("%N sent +USE to %s", client, sClass);
					}
				}
				//If it's not a button see it it has a button as a sibling
				if (!StrEqual(sClass, "func_button"))
				{
					int mParent = FindMasterParent(entity);
					if (IsValidEdict(mParent))
					{
						char buffer[128];
						GetEdictClassname(mParent, buffer, sizeof(buffer));
						
						if (StrContains(buffer, "weapon") != -1)
						{
							Format(buffer, sizeof(buffer), "%i", EntIndexToEntRef(mParent));
							int sibling;
							if (g_smButtonMap.GetValue(buffer, sibling))
							{
								sibling = EntRefToEntIndex(sibling);
								if (sibling != INVALID_ENT_REFERENCE)
								{
									AcceptEntityInput(sibling, "Use", client, client);
									g_fCmdTime[client] = GetGameTime() + 0.5;
									PrintToConsole(client, "[ButtonTrace] Sent +USE to sibling button %i", sibling);
								}
							}
						}
					}
				}
			}
		}
	}
	CloseHandle(ray);
	g_bInUse[client] = true;
	return Plugin_Continue;
}

public bool TraceEntities(int entity, int contentsMask, any data)
{
	if (entity > MAXPLAYERS)
	{
		if (IsValidEdict(entity))
		{
			char sClass[128];
			GetEntityClassname(entity, sClass, sizeof(sClass));
			if (StrContains(sClass, "trigger") != -1)
			{
				//this entity is bugged - don't use it
				return false;
			}
			//Check if it has the parent property
			int mParent = FindMasterParent(entity);
			if (mParent != -1)
			{
				//if (IsValidClient(data))
				//	PrintToConsole(data, "[ButtonTrace] Has Move Parent %i", mParent);
				
				if (IsValidEdict(mParent))
				{
					//Check if parented to a knife
					GetEntityClassname(mParent, sClass, sizeof(sClass));
					if (IsValidClient(data))
						PrintToConsole(data, "[ButtonTrace] Traced parent object %s", sClass);
					
					if (StrContains(sClass, "knife") != -1)
					{
						//Don't collide with this parented entity
						return false;
					}
				}
			}
			mParent = FindMasterParent(entity, true);
			if (IsValidClient(mParent) && mParent != data)
			{
				PrintToConsole(data, "[ButtonTrace] Traced item belonging to %N", mParent);
				return false;
			}
			return true;
		}
	}
	return false;
}

//Recursive function :)
stock int FindMasterParent(int entity, bool findPlayers = false)
{
	if (!IsValidEdict(entity))
		return -1;
		
	if (FindDataMapInfo(entity, "m_hMoveParent") != -1)
	{
		int parent = GetEntPropEnt(entity, Prop_Data, "m_hMoveParent");
		if (parent != -1)
		{
			int master = FindMasterParent(parent);
			
			if (master != -1 && (master > MAXPLAYERS || findPlayers)) {
				return master;
			} else {
				return parent;
			}
		}
	}
	return -1;
}

stock bool IsValidClient(int client)
{
	if ((client <= 0) || (client > MaxClients)) {
		return false;
	}
	if (!IsClientInGame(client)) {
		return false;
	}
	return true;
}