
#define DEBUG

#define PLUGIN_NAME           "Air-Accel Manager"
#define PLUGIN_AUTHOR         "Screwdriver (Jon S.)"
#define PLUGIN_DESCRIPTION    "Add the ability to set air acceleration per player"
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            "parkour.tf"

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <airaccel>

#pragma newdecls required
#pragma semicolon 1

GameData g_hGamedata;

Handle g_hAirAccelerate;
Handle g_hTryPlayerMove;
Handle g_hGetBaseEntity;
//Handle g_hProcessMovement;
//Handle g_hProcessMovementPost;

ConVar g_cvarEnable;

//int g_iOffsProcessMovement = -1;
int g_iOffsAirAccelerate = -1;
//int g_iCurrentPlayer = -1;

float g_flAirAccel[MAXPLAYERS + 1] = {10.0, 10.0, ...};

bool g_bGotMovement = false;

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

CGameMovement g_pGameMovement;

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
	CreateNative("SetPlayerAirAcceleration", Native_SetAirAccel);
	CreateNative("GetPlayerAirAcceleration", Native_GetAirAccel);
	RegPluginLibrary("airaccel");
}

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_TF2)
		SetFailState("[AIRACCEL] ERROR: This plugin is currently only compatible with Team Fortress 2.");
	
	// Set the default air accelerate values to match those of the cvar
	float flStockAirAccel = FindConVar("sv_airaccelerate").FloatValue;
	for (int i = 1; i < MaxClients; i++)
		g_flAirAccel[i] = flStockAirAccel;
	
	g_cvarEnable = CreateConVar("sm_airaccel_enable", "1", "Enable indexing airaccelerate values", _, true, _, true, 1.0);
	
	RegAdminCmd("sm_setairaccel", Command_SetAirAcceleration, ADMFLAG_ROOT, "Set a player's air acceleration");
	
	SDK_Init();
}

void SDK_Init()
{
	g_hGamedata = LoadGameConfigFile("airaccel");
	if (g_hGamedata == null)
		ThrowError("[AIRACCEL] Can't find gamedata file airaccel.txt");
	
	g_iOffsAirAccelerate = g_hGamedata.GetOffset("CGameMovement::AirAccelerate");
	if (g_iOffsAirAccelerate == -1)
		ThrowError("[AIRACCEL] Can't find offset for function CGameMovement::AirAccelerate");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(g_hGamedata, SDKConf_Virtual, "CBaseEntity::GetBaseEntity");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hGetBaseEntity = EndPrepSDKCall();
	
	char strBuf[4];
	g_hGamedata.GetKeyValue("CGameMovement::player", strBuf, sizeof(strBuf));
	offsets.player = StringToInt(strBuf);

	g_hTryPlayerMove = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Int, ThisPointer_Address);
	
	DHookSetFromConf(g_hTryPlayerMove, g_hGamedata, SDKConf_Signature, "CGameMovement::TryPlayerMove");
	DHookAddParam(g_hTryPlayerMove, HookParamType_Int);
	DHookAddParam(g_hTryPlayerMove, HookParamType_Int);
	
	DHookEnableDetour(g_hTryPlayerMove, false, TryPlayerMove);
}

public MRESReturn TryPlayerMove(Address pThis, Handle hReturn, Handle hParams)
{
	if (g_bGotMovement)
		return MRES_Supercede;
	
	g_bGotMovement = true;
	g_pGameMovement = CGameMovement(pThis);
	
	g_hAirAccelerate = DHookCreate(g_iOffsAirAccelerate, HookType_Raw, ReturnType_Void, ThisPointer_Address, AirAccelerate);
	DHookAddParam(g_hAirAccelerate, HookParamType_VectorPtr);
	DHookAddParam(g_hAirAccelerate, HookParamType_Float);
	DHookAddParam(g_hAirAccelerate, HookParamType_Float);
	DHookRaw(g_hAirAccelerate, false, view_as<Address>(g_pGameMovement));
	return MRES_Supercede;
}

public MRESReturn AirAccelerate(Address pThis, Handle hParams)
{
	if (!g_cvarEnable.IntValue)
		return MRES_Supercede;
	
	DHookSetParam(hParams, 3, g_flAirAccel[g_pGameMovement.player]);
	return MRES_ChangedOverride;
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
	SetPlayerAirAccel(GetNativeCell(1), GetNativeCell(2));
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

