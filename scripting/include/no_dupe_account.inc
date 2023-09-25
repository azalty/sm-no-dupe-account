/** Double-include prevention */
#if defined _no_dupe_account_included_
  #endinput
#endif
#define _no_dupe_account_included_

public SharedPlugin __pl_no_dupe_account = 
{
    name = "no_dupe_account",
    file = "no_dupe_account.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_no_dupe_account_SetNTVOptional()
{
	MarkNativeAsOptional("NDA_VerifyClient");
	MarkNativeAsOptional("NDA_IsClientVerified");
	MarkNativeAsOptional("NDA_IsClientInVerification");
}
#endif


// ----- NATIVES BELOW ----- //


/**
 * Asks NDA to verify a client. Will call NDA_OnClientVerificationAsked.
 * Will not verify if the client is already in a verification.
 * 
 * @param client	A client index. Must be in game.
 * @param mode		The mode to use.
 * 0 = only verify if the client isn't verified yet (default)
 * 1 = only verify if the client isn't verified yet, and ignore NDA_OnClientVerificationAsked's return value
 * 2 = verify the client, even if they're already verified
 * 3 = verify the client, even if they're already verified, and ignore NDA_OnClientVerificationAsked's return value
 */
native void NDA_VerifyClient(int client, int mode=0);


/**
 * Returns whether or not a client is verified.
 * 
 * @param client	A client index. Must be in game.
 * @return bool		true if the client is verified, false if not.
 */
native bool NDA_IsClientVerified(int client);


/**
 * Returns whether or not a client is being verified.
 * 
 * @param client	A client index. Must be in game.
 * @return bool		true if the client is in verification, false if not.
 */
native bool NDA_IsClientInVerification(int client);


// ----- FORWARDS BELOW ----- //


/**
 * Called when a verification is asked on a player, either by NDA itself or another plugin.
 * Return Plugin_Handled to prevent the verification, but don't stop this forward.
 * Return Plugin_Stop to prevent the verification, and stops this forward call from being sent to other plugins.
 * 
 * int client		The client index.
 * return Action	Plugin_Continue to allow, Plugin_Handled or Plugin_Stop to prevent verification.
 */
forward Action NDA_OnClientVerificationAsked(int client);


/**
 * Called when a verification is started on a player.
 * This is called after NDA_OnClientVerificationAsked, if no external plugin prevented the verification.
 * 
 * int client		The client index.
 */
forward void NDA_OnClientVerificationStart(int client);


/**
 * Called when a player's verification has just finished.
 * Will pass true in the verified parameter if the player was verified/accepted, false if not.
 * This is called right before NDA_OnClientRefused and NDA_OnClientVerified.
 * 
 * int client		The client index.
 * bool verified	true if verified/accepted, false if not.
 */
forward void NDA_OnClientVerificationDone(int client, bool verified);


/**
 * Called when a player's verification has just finished, and the player was rejected.
 * Will be called right after NDA_OnClientVerificationDone.
 * 
 * int client		The client index.
 */
forward void NDA_OnClientRefused(int client);


/**
 * Called when a player's verification has just finished, and the player was verified/accepted.
 * Will be called right after NDA_OnClientVerificationDone.
 * 
 * int client		The client index.
 */
forward void NDA_OnClientVerified(int client);
