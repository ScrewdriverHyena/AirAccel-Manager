
#define DEBUG

#define PLUGIN_NAME           "Air-Accel Manager"
#define PLUGIN_AUTHOR         "Screwdriver (Jon S.)"
#define PLUGIN_DESCRIPTION    "Add the ability to set air acceleration per player"
#define PLUGIN_VERSION        "3.0"
#define PLUGIN_URL            "parkour.tf"

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <airaccel>

#pragma newdecls required
#pragma semicolon 1

GameData g_hGamedata;

Handle g_hGetBaseEntity;
Handle g_hAirAccelerate;
Handle g_hAccelerate;

ConVar g_cvarEnable;
ConVar g_cvarAirAcceleration;
ConVar g_cvarAcceleration;

float g_flAirAccel[MAXPLAYERS + 1] = {10.0, 10.0, ...};
float g_flStockAirAccel;

float g_flAccel[MAXPLAYERS + 1] = {10.0, 10.0, ...};
float g_flStockAccel;

bool g_bInProcessMovement;

enum struct CTFGameMovementOffsets
{
	int player;
}

CTFGameMovementOffsets offsets;

methodmap CGameMovement
{
	public CGameMovement(Address pGameMovement)
	{
		return view_as<CGameMovement>(pGameMovement);
	}
	
	property int player
	{
		public get() { return SDKCall(g_hGetBaseEntity, LoadFromAddress(view_as<Address>(this) + view_as<Address>(offsets.player), NumberType_Int32)); }
	}
}

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public APLRes AskPluginLoad2()
{
	CreateNative("SetClientAirAcceleration", Native_SetAirAccel);
	CreateNative("GetClientAirAcceleration", Native_GetAirAccel);
	CreateNative("SetClientAcceleration", Native_SetAccel);
	CreateNative("GetClientAcceleration", Native_GetAccel);
	RegPluginLibrary("airaccel");
}

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_TF2)
		SetFailState("[AIRACCEL] ERROR: This plugin is currently only compatible with Team Fortress 2.");
	
	g_cvarAirAcceleration = FindConVar("sv_airaccelerate");
	g_cvarAirAcceleration.AddChangeHook(OnChangeAirAccel);
	
	g_cvarAcceleration = FindConVar("sv_accelerate");
	g_cvarAcceleration.AddChangeHook(OnChangeAccel);
	
	// Set the default air accelerate values to match those of the cvar
	g_flStockAirAccel = g_cvarAirAcceleration.FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAirAccel[i] = g_flStockAirAccel;
	
	g_flStockAccel = g_cvarAcceleration.FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAccel[i] = g_flStockAccel;
	
	CreateConVar("airaccel_version", PLUGIN_VERSION, "Plugin Version", FCVAR_ARCHIVE);
	g_cvarEnable = CreateConVar("airaccel_enable", "1", "Enable indexing airaccelerate values", _, true, _, true, 1.0);
	HookEvent("server_cvar", Event_ServerCvar, EventHookMode_Pre);
	
	RegAdminCmd("sm_setairaccel", Command_SetAirAcceleration, ADMFLAG_ROOT, "Set a player's air acceleration");
	RegAdminCmd("sm_getairaccel", Command_GetAirAcceleration, ADMFLAG_ROOT, "Get a player's air acceleration");
	
	RegAdminCmd("sm_setaccel", Command_SetAcceleration, ADMFLAG_ROOT, "Set a player's acceleration");
	RegAdminCmd("sm_getaccel", Command_GetAcceleration, ADMFLAG_ROOT, "Get a player's acceleration");

	SDK_Init();
}

public void OnChangeAirAccel(ConVar cvarAirAccel, const char[] strOldValue, const char[] strNewValue)
{
	if (g_bInProcessMovement)
		return;
	
	g_flStockAirAccel = StringToFloat(strNewValue);
	float flOldValue = StringToFloat(strOldValue);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (g_flAirAccel[i] == flOldValue)
			g_flAirAccel[i] = g_flStockAirAccel;
	}
}

public void OnChangeAccel(ConVar cvarAccel, const char[] strOldValue, const char[] strNewValue)
{
	if (g_bInProcessMovement)
		return;
	
	g_flStockAccel = StringToFloat(strNewValue);
	float flOldValue = StringToFloat(strOldValue);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (g_flAccel[i] == flOldValue)
			g_flAccel[i] = g_flStockAccel;
	}
}

public void OnMapStart()
{
	g_cvarAirAcceleration = FindConVar("sv_airaccelerate");
	float flStockAirAccel = g_cvarAirAcceleration.FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAirAccel[i] = flStockAirAccel;
		
	g_cvarAcceleration = FindConVar("sv_accelerate");
	float flStockAccel = g_cvarAcceleration.FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAccel[i] = flStockAccel;
}

public void OnClientDisconnect(int iClient)
{
	SetPlayerAirAccel(iClient, g_cvarAirAcceleration.FloatValue);
	SetPlayerAccel(iClient, g_cvarAcceleration.FloatValue);
}

public void OnClientPostAdminCheck(int iClient)
{
	SetPlayerAirAccel(iClient, g_cvarAirAcceleration.FloatValue);
	SetPlayerAccel(iClient, g_cvarAcceleration.FloatValue);
}

void SDK_Init()
{
	g_hGamedata = LoadGameConfigFile("airaccel");
	if (g_hGamedata == null)
		ThrowError("[AIRACCEL] Can't find gamedata file airaccel.txt");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(g_hGamedata, SDKConf_Virtual, "CBaseEntity::GetBaseEntity");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hGetBaseEntity = EndPrepSDKCall();
	
	char strBuf[4];
	g_hGamedata.GetKeyValue("CGameMovement::player", strBuf, sizeof(strBuf));
	offsets.player = StringToInt(strBuf);
	
	g_hAirAccelerate = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address);
	DHookSetFromConf(g_hAirAccelerate, g_hGamedata, SDKConf_Signature, "CGameMovement::AirAccelerate");
	DHookAddParam(g_hAirAccelerate, HookParamType_VectorPtr);
	DHookAddParam(g_hAirAccelerate, HookParamType_Float);
	DHookAddParam(g_hAirAccelerate, HookParamType_Float);
	DHookEnableDetour(g_hAirAccelerate, false, AirAccelerate);
	
	g_hAccelerate = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address);
	DHookSetFromConf(g_hAccelerate, g_hGamedata, SDKConf_Signature, "CGameMovement::Accelerate");
	DHookAddParam(g_hAccelerate, HookParamType_VectorPtr);
	DHookAddParam(g_hAccelerate, HookParamType_Float);
	DHookAddParam(g_hAccelerate, HookParamType_Float);
	DHookEnableDetour(g_hAccelerate, false, Accelerate);
}

public MRESReturn AirAccelerate(Address pThis, Handle hParams)
{
	if (!g_cvarEnable.BoolValue)
		return MRES_Ignored;
	
	DHookSetParam(hParams, 3, g_flAirAccel[view_as<CGameMovement>(pThis).player]);
	return MRES_ChangedOverride;
}

public MRESReturn Accelerate(Address pThis, Handle hParams)
{
	if (!g_cvarEnable.BoolValue || DHookGetParam(hParams, 3) != g_cvarAcceleration.FloatValue)
		return MRES_Ignored;
	
	DHookSetParam(hParams, 3, g_flAccel[view_as<CGameMovement>(pThis).player]);
	return MRES_ChangedOverride;
}

public Action Command_SetAirAcceleration(int iClient, int iArgs)
{
	if (iArgs < 2)
	{
		ReplyToCommand(iClient, "Usage: sm_setairaccel <target> <value>");
		return Plugin_Handled;
	}
	
	char strTarget[32], strTargetName[MAX_TARGET_LENGTH], strValue[8];
	float flValue;
	bool bTN_is_ml;
	int iTargets[MAXPLAYERS], iTargetCount;
	GetCmdArg(1, strTarget, sizeof(strTarget));
	GetCmdArg(2, strValue, sizeof(strValue));
	flValue = StringToFloat(strValue);
	if (flValue <= 0.0)
	{
		ReplyToCommand(iClient, "Invalid air acceleration value.");
		return Plugin_Handled;
	}
	
	iTargetCount = ProcessTargetString(strTarget, iClient, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, strTargetName, MAX_TARGET_LENGTH, bTN_is_ml);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		if (!IsValidClient(iTargets[i]))
			continue;
		
		SetPlayerAirAccel(iTargets[i], flValue);
		ReplyToCommand(iClient, "Set %N's airaccelerate to %.2f.", iTargets[i], flValue);
	}
	
	return Plugin_Handled;
}

public Action Command_GetAirAcceleration(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		ReplyToCommand(iClient, "Usage: sm_getairaccel <target>");
		return Plugin_Handled;
	}
	
	char strTarget[32], strTargetName[MAX_TARGET_LENGTH];
	bool bTN_is_ml;
	int iTargets[MAXPLAYERS], iTargetCount;
	GetCmdArg(1, strTarget, sizeof(strTarget));
	
	iTargetCount = ProcessTargetString(strTarget, iClient, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, strTargetName, MAX_TARGET_LENGTH, bTN_is_ml);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		if (!IsValidClient(iTargets[i]))
			continue;
		
		ReplyToCommand(iClient, "%N Airaccel: %.2f", iTargets[i], GetPlayerAirAccel(iTargets[i]));
	}
	
	return Plugin_Handled;
}

public Action Command_SetAcceleration(int iClient, int iArgs)
{
	if (iArgs < 2)
	{
		ReplyToCommand(iClient, "Usage: sm_setaccel <target> <value>");
		return Plugin_Handled;
	}
	
	char strTarget[32], strTargetName[MAX_TARGET_LENGTH], strValue[8];
	float flValue;
	bool bTN_is_ml;
	int iTargets[MAXPLAYERS], iTargetCount;
	GetCmdArg(1, strTarget, sizeof(strTarget));
	GetCmdArg(2, strValue, sizeof(strValue));
	flValue = StringToFloat(strValue);
	if (flValue <= 0.0)
	{
		ReplyToCommand(iClient, "Invalid acceleration value.");
		return Plugin_Handled;
	}
	
	iTargetCount = ProcessTargetString(strTarget, iClient, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, strTargetName, MAX_TARGET_LENGTH, bTN_is_ml);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		if (!IsValidClient(iTargets[i]))
			continue;
		
		SetPlayerAccel(iTargets[i], flValue);
		ReplyToCommand(iClient, "Set %N's accelerate to %.2f.", iTargets[i], flValue);
	}
	
	return Plugin_Handled;
}

public Action Command_GetAcceleration(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		ReplyToCommand(iClient, "Usage: sm_getaccel <target>");
		return Plugin_Handled;
	}
	
	char strTarget[32], strTargetName[MAX_TARGET_LENGTH];
	bool bTN_is_ml;
	int iTargets[MAXPLAYERS], iTargetCount;
	GetCmdArg(1, strTarget, sizeof(strTarget));
	
	iTargetCount = ProcessTargetString(strTarget, iClient, iTargets, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, strTargetName, MAX_TARGET_LENGTH, bTN_is_ml);
	
	for (int i = 0; i < iTargetCount; i++)
	{
		if (!IsValidClient(iTargets[i]))
			continue;
		
		ReplyToCommand(iClient, "%N Accel: %.2f", iTargets[i], GetPlayerAccel(iTargets[i]));
	}
	
	return Plugin_Handled;
}

public any Native_SetAirAccel(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	if (!IsClientInGame(iClient))
		return;
	
	SetPlayerAirAccel(iClient, GetNativeCell(2));
}

public any Native_GetAirAccel(Handle hPlugin, int iNumParams)
{
	return GetPlayerAirAccel(GetNativeCell(1));
}

public any Native_GetAccel(Handle hPlugin, int iNumParams)
{
	return GetPlayerAccel(GetNativeCell(1));
}

public any Native_SetAccel(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	if (!IsClientInGame(iClient))
		return;
	
	SetPlayerAccel(iClient, GetNativeCell(2));
}

void SetPlayerAirAccel(int iClient, float flValue)
{
	if (flValue > 0.0)
		g_flAirAccel[iClient] = flValue;
}

float GetPlayerAirAccel(int iClient)
{
	return g_flAirAccel[iClient];
}

void SetPlayerAccel(int iClient, float flValue)
{
	if (flValue > 0.0)
		g_flAccel[iClient] = flValue;
}

float GetPlayerAccel(int iClient)
{
	return g_flAccel[iClient];
}

public Action Event_ServerCvar(Event hEvent, const char[] strName, bool bDontBroadcast)
{
	hEvent.BroadcastDisabled = true;
	bDontBroadcast = true;
	return Plugin_Handled;
}

bool IsValidClient(int iClient, bool bAllowBots = false)
{
	return !(!(1 <= iClient <= MaxClients) 
			|| !IsClientInGame(iClient) 
			|| (IsFakeClient(iClient) && !bAllowBots) 
			|| IsClientSourceTV(iClient) 
			|| IsClientReplay(iClient));
}