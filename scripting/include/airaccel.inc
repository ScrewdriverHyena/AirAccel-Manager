//
// Air-Accel Manager Include by Screwdriver (Jon S.)
//

#if defined _my_library_included
	#endinput
#endif
#define _my_library_included

native void SetClientAirAcceleration(int iClient, float flValue);

native float GetClientAirAcceleration(int iClient);

native void SetClientAcceleration(int iClient, float flValue);

native float GetClientAcceleration(int iClient);

public SharedPlugin __pl_airaccel =
{
	name = "airaccel",
	file = "airaccel.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};








