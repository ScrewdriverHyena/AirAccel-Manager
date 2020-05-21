
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

Handle g_hProcessMovement;
Handle g_hProcessMovementPost;
Handle g_hTryPlayerMove;
Handle g_hGetBaseEntity;

ConVar g_cvarEnable;
ConVar g_cvarAirAcceleration;

int g_iProcessMovement = -1;

float g_flAirAccel[MAXPLAYERS + 1] = {10.0, 10.0, ...};
float g_flStockAirAccel;

bool g_bGotMovement;
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
	RegPluginLibrary("airaccel");
}

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_TF2)
		SetFailState("[AIRACCEL] ERROR: This plugin is currently only compatible with Team Fortress 2.");
	
	g_cvarAirAcceleration = FindConVar("sv_airaccelerate");
	g_cvarAirAcceleration.AddChangeHook(OnChangeAirAccel);
	
	// Set the default air accelerate values to match those of the cvar
	g_flStockAirAccel = g_cvarAirAcceleration.FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAirAccel[i] = g_flStockAirAccel;
	
	CreateConVar("airaccel_version", PLUGIN_VERSION, "Plugin Version", FCVAR_ARCHIVE);
	g_cvarEnable = CreateConVar("airaccel_enable", "1", "Enable indexing airaccelerate values", _, true, _, true, 1.0);
	
	RegAdminCmd("sm_setairaccel", Command_SetAirAcceleration, ADMFLAG_ROOT, "Set a player's air acceleration");
	
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

public void OnMapStart()
{
	float flStockAirAccel = g_cvarAirAcceleration.FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAirAccel[i] = flStockAirAccel;
}

public void OnClientDisconnect(int iClient)
{
	SetPlayerAirAccel(iClient, g_cvarAirAcceleration.FloatValue);
}

public void OnClientPostAdminCheck(int iClient)
{
	SetPlayerAirAccel(iClient, g_cvarAirAcceleration.FloatValue);
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
	
	g_iProcessMovement = GameConfGetOffset(g_hGamedata, "CTFGameMovement::ProcessMovement");
	if (g_iProcessMovement == -1)
		ThrowError("Can't find offset for function CTFGameMovement::ProcessMovement");
	
	g_hProcessMovement = DHookCreate(g_iProcessMovement, HookType_Raw, ReturnType_Void, ThisPointer_Address, ProcessMovement);
	DHookAddParam(g_hProcessMovement, HookParamType_CBaseEntity);
	DHookAddParam(g_hProcessMovement, HookParamType_ObjectPtr);
	
	g_hProcessMovementPost = DHookCreate(g_iProcessMovement, HookType_Raw, ReturnType_Void, ThisPointer_Address, ProcessMovementPost);
	DHookAddParam(g_hProcessMovementPost, HookParamType_CBaseEntity);
	DHookAddParam(g_hProcessMovementPost, HookParamType_ObjectPtr);
	
	g_hTryPlayerMove = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Int, ThisPointer_Address);
	DHookSetFromConf(g_hTryPlayerMove, g_hGamedata, SDKConf_Signature, "CGameMovement::TryPlayerMove");
	DHookAddParam(g_hTryPlayerMove, HookParamType_Int);
	DHookAddParam(g_hTryPlayerMove, HookParamType_Int);
	DHookEnableDetour(g_hTryPlayerMove, false, TryPlayerMove);
	
	//PrintToChatAll("Enabled Detour");
}

public MRESReturn TryPlayerMove(Address pThis, Handle hReturn, Handle hParams)
{
	//PrintToChatAll("TryPlayerMove");
	
	if (!g_bGotMovement)
	{
		//PrintToChatAll("Attempting AA");
		g_bGotMovement = true;
		DHookRaw(g_hProcessMovement, false, pThis);
		DHookRaw(g_hProcessMovementPost, false, pThis);
		
		//PrintToChatAll("Hooked AA %d", g_iOffsAirAccelerate);
		RequestFrame(TryPlayerMovePost);
	}
	
	return MRES_Ignored;
}

public void TryPlayerMovePost(any aData)
{
	DHookDisableDetour(g_hTryPlayerMove, false, TryPlayerMove);
}

public MRESReturn ProcessMovement(Address pThis, Handle hParams)
{
	if (!g_cvarEnable.IntValue)
		return MRES_Ignored;
	
	if (g_flAirAccel[view_as<CGameMovement>(pThis).player] != g_flStockAirAccel)
	{
		g_bInProcessMovement = true;
		g_cvarAirAcceleration.SetFloat(g_flAirAccel[view_as<CGameMovement>(pThis).player]);
	}
	
	return MRES_ChangedHandled;
}

public MRESReturn ProcessMovementPost(Address pThis, Handle hParams)
{
	if (!g_cvarEnable.IntValue)
		return MRES_Ignored;
	
	g_cvarAirAcceleration.SetFloat(g_flStockAirAccel);
	g_bInProcessMovement = false;
	return MRES_ChangedHandled;
}

public Action Command_SetAirAcceleration(int iClient, int iArgs)
{
	if (iArgs < 2)
	{
		ReplyToCommand(iClient, "Usage: sm_setairaccel <target> <value>");
		return Plugin_Handled;
	}
	
	char strName[32], strValue[8];
	int iTarget = -1;
	float flValue;
	GetCmdArg(1, strName, sizeof(strName));
	GetCmdArg(2, strValue, sizeof(strValue));
	flValue = StringToFloat(strValue);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i))
			continue;
		
		char strOther[32];
		GetClientName(i, strOther, sizeof(strOther));
		
		if (StrEqual(strName, strOther))
			iTarget = i;
	}
	
	if (iTarget == -1)
	{
		ReplyToCommand(iClient, "Could not find specified user.");
		return Plugin_Handled;
	}
	
	if (flValue <= 0.0)
	{
		ReplyToCommand(iClient, "Invalid air acceleration value.");
		return Plugin_Handled;
	}
	
	SetPlayerAirAccel(iTarget, flValue);
	ReplyToCommand(iClient, "Set %N's airaccelerate to %.2f.", iTarget, flValue);
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

void SetPlayerAirAccel(int iClient, float flValue)
{
	g_flAirAccel[iClient] = flValue;
}

float GetPlayerAirAccel(int iClient)
{
	return g_flAirAccel[iClient];
}

public Action Event_ServerCvar(Event hEvent, const char[] strName, bool bDontBroadcast)
{
	char strConVarName[64];
	GetEventString(hEvent, "cvarname", strConVarName, sizeof(strConVarName));
	return (StrEqual(strConVarName, "sv_airaccelerate")) ? Plugin_Handled : Plugin_Continue;
}