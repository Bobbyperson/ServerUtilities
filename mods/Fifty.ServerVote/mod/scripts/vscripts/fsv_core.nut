globalize_all_functions


table <entity, string> mapVoteTable = {}

/**
 * Gets called after the map is loaded
*/
void function FSV_Init() {
	FSV_Localization_Init()
	array<string> rotationMaps
	foreach( string map in FSV_GetMapArrayFromConVar( "FSV_MAP_ROTATION" ) ) {
		if( !rotationMaps.contains( map ) )
			rotationMaps.append( map )
	}
	int maxReplayLimit = int( max( 0, rotationMaps.len() - 1 ) )
	if( FSU_GetSettingIntFromConVar("FSV_MAP_REPLAY_LIMIT") > maxReplayLimit ){
		array<string> playedMaps = FSU_GetArrayFromConVar( "FSV_MAP_REPLAY_LIMIT" )
		while( playedMaps.len() > maxReplayLimit )
			playedMaps.remove( 0 )
		SetConVarInt("FSV_MAP_REPLAY_LIMIT", maxReplayLimit )
		FSU_SaveArrayToConVar( "FSV_MAP_REPLAY_LIMIT", playedMaps )
		FSU_Error("Map replay limit is set too high! There are not enough maps in rotation to block that many recent maps.")
	}

	if (FSU_GetSettingIntFromConVar("FSV_MAP_REPLAY_LIMIT") > 0)
		FSV_UpdatePlayedMaps()

	if( GetConVarBool( "FSV_CUSTOM_MAP_ROTATION" ) )
		AddCallback_GameStateEnter( eGameState.Postmatch, FSV_EndOfMatchMatch_Threaded )

	FSCC_CommandStruct command
	command.m_UsageUser = "nextmap <map>"
	command.m_UsageAdmin = "nextmap <map> force"
	command.m_Description = "Allows you to vote for the next map, or view map rotation information."
	command.m_Group = "VOTE"
	command.m_Abbreviations = [ "nm", "maps", "map" ]
	command.Callback = FSV_CommandCallback_NextMap
	if( !GetConVarBool( "FSV_ENABLE_MAP_VOTING" ) )
		command.PlayerCanUse = FSU_IsAdmin
	FSCC_RegisterCommand( "nextmap", command )
	command.PlayerCanUse = null

	command.m_UsageUser = "skip"
	command.m_UsageAdmin = "skip force"
	command.m_Description = "Allows you to vote to skip the current map."
	command.m_Group = "VOTE"
	command.m_Abbreviations = []
	command.Callback = FSV_CommandCallback_Skip
	if( !GetConVarBool( "FSV_ENABLE_MAP_SKIPPING" ) )
		command.PlayerCanUse = FSU_IsAdmin
	FSCC_RegisterCommand( "skip", command )
	command.PlayerCanUse = null

	command.m_UsageUser = "extend"
	command.m_UsageAdmin = "extend <minutes>"
	command.m_Description = "Allows you to vote to extend the current match."
	command.m_Group = "VOTE"
	command.m_Abbreviations = [ "ex" ]
	command.Callback = FSV_CommandCallback_Extend
	if( !GetConVarBool( "FSV_ENABLE_MAP_EXTENDING" ) )
		command.PlayerCanUse = FSU_IsAdmin
	FSCC_RegisterCommand( "extend", command )
	command.PlayerCanUse = null

// 	command.m_UsageUser = "testvote"
// 	command.m_Description = "Test MentalEdge's style of votes."
// 	command.m_Group = "VOTE"
// 	command.m_Abbreviations = ["tv"]
// 	command.Callback = FSV_CommandCallback_TestVote
// 	FSCC_RegisterCommand( "testvote", command)

	command.m_UsageUser = "kick <partial/full-name>"
	command.m_UsageAdmin = "kick <partial/full-name> force"
	command.m_Description = "Starts a vote to kick a player."
	command.m_Group = "VOTE"
	command.m_Abbreviations = []
	command.Callback = FSV_CommandCallback_Kick
	if( !GetConVarBool( "FSV_ENABLE_KICK_VOTING" ) )
		command.PlayerCanUse = FSU_IsAdmin
	FSCC_RegisterCommand( "kick", command)

	if( FSU_GetSettingIntFromConVar( "FSV_KICK_BLOCK" ) > 0 ){
		FSV_UpdateKicked()
		AddCallback_OnClientConnected(FSV_JoiningPlayerKickCheck)
	}
}

/**
 * Updates last played (vote blocked) maps
*/
void function FSV_UpdatePlayedMaps(){
	if(GetMapName() != "mp_lobby"){
		array <string> playedMaps = FSU_GetArrayFromConVar("FSV_MAP_REPLAY_LIMIT")
		playedMaps.append(GetMapName())
		while (playedMaps.len() > FSU_GetSettingIntFromConVar("FSV_MAP_REPLAY_LIMIT")){
			playedMaps.remove(0)
		}

		FSU_SaveArrayToConVar("FSV_MAP_REPLAY_LIMIT", playedMaps)
	}
}

/**
 * Convert seconds to minutes and seconds
*/
string function FSV_TimerToMinutesAndSeconds(int timer){
	int minutes = int(floor(timer / 60))
	string seconds = string(timer - (minutes * 60))
	if (timer - (minutes * 60) < 10){
		seconds = "0"+seconds
	}
	return minutes + ":" + seconds
}

/**
 * Runs on player connected, preventing any previously kicked players from re-joining
*/
void function FSV_JoiningPlayerKickCheck(entity player) {
	if (FSU_GetSelectedArrayFromConVar("FSV_KICK_BLOCK", 0).contains(player.GetUID())) {
		FSU_Print("previously kicked " + player.GetPlayerName() + " tried to rejoin")
		ServerCommand("kick " + player.GetPlayerName())
	}
}

/**
 * Updates the kicked player re-join block list, removing any expired blocks and incrementing existing ones
*/
void function FSV_UpdateKicked(){
	array <string> kicked = FSU_GetSelectedArrayFromConVar("FSV_KICK_BLOCK", 0)
	array <string> kickedfor = FSU_GetSelectedArrayFromConVar	("FSV_KICK_BLOCK", 1)
	int kickDuration = FSU_GetSettingIntFromConVar("FSV_KICK_BLOCK")

	for(int i = kickedfor.len()-1; i > -1; i--){
		kickedfor.insert(i, (kickedfor[i].tointeger()+1).tostring())
		kickedfor.remove(i+1)
		if(kickedfor[i].tointeger() > kickDuration){
			kickedfor.remove(i)
			kicked.remove(i)
		}
	}

	array <array <string> > newKickedArray = [kicked, kickedfor]
	FSU_SaveArrayArrayToConVar("FSV_KICK_BLOCK", newKickedArray)
}

/**
 * Adds a vote to a map
 * @param player The player who voted
 * @param map The map to vote for
*/
void function FSV_VoteForNextMap( entity player, string map ) {
	mapVoteTable[player] <- map;
}

/**
 * Grab a reference to the mvt
*/
table <entity, string> function FSV_GetMapVoteTable() {
	return mapVoteTable
}

/**
 * Get a string containing maps that currently have votes, and how many votes they have
*/
string function FSV_GetMapVotesMessage() {
	table <string, float> votedMaps
	foreach(entity player, string map in mapVoteTable){
		if((map in votedMaps))
			votedMaps[map] += 1
		else
			votedMaps[map] <- 1
	}
	string message = ""
	foreach(string map, float votes in votedMaps){
		if (message == "")
			message += FSV_Localize(map) + ": %T" + votes + " votes"
		else
			message += ", %H" + FSV_Localize(map) + ": %T" + votes + " votes"
	}
	return message
}

/**
 * Gets the map to be played next
*/
string function FSV_GetNextMap() {
	table< string, int > mapVotes

	// If there have been votes, choose a random one from the vote-pool
	if( mapVoteTable.len() > 0 ) {
		int mostVotes = 0

		foreach( entity player, string map in mapVoteTable ) {
			if( map in mapVotes )
				mapVotes[map]++
			else
				mapVotes[map] <- 1

			if( mapVotes[map] > mostVotes )
				mostVotes = mapVotes[map]
		}

		array<string> winners
		foreach( string map, int votes in mapVotes ){
			if( votes == mostVotes ){
				winners.append( map )
			}
		}

		if(winners.len() > 1)
			return winners[RandomInt(winners.len())]

		return winners[0]
	}

	// Set up the arrays needed
	array<string> allMaps = FSV_GetMapArrayFromConVar( "FSV_MAP_ROTATION" )
	array<string> validMaps = FSV_GetMapArrayFromConVar( "FSV_MAP_ROTATION" )
	array<string> blockedMaps = FSU_GetArrayFromConVar( "FSV_MAP_REPLAY_LIMIT" )
	foreach( string blockedMap in blockedMaps ) {
		int index = validMaps.find(blockedMap)
		if( index != -1 ){
			validMaps.remove( index )
		}
	}

	if( validMaps.len() == 0 ) {
		FSU_Error( "No eligible maps remain in the rotation!" )
		return "mp_lobby"
	}

	// Return a random map if set
	if( GetConVarInt( "FSV_RANDOM_MAP_ROTATION" ) ) {
		return validMaps[RandomInt(validMaps.len())]
	}

	// Return the next map
	int index = allMaps.find( GetMapName() )
	if( index != -1 ) {
		int nextMap = index + 1
		if( nextMap >= allMaps.len() )
			nextMap = 0

		int loop = 0
		while( validMaps.find(allMaps[nextMap]) == -1 && loop < blockedMaps.len()){
			nextMap++
			loop++
			if ( nextMap >= allMaps.len() )
				nextMap = 0
		}

		return allMaps[nextMap]
	}

	FSU_Error( "Couldn't get the next map!" );

	// If there is no valid next map, pick a random one
	return validMaps[RandomInt(validMaps.len())]
}

/**
 * Gets called when the game enters Postmatch
*/
void function FSV_EndOfMatchMatch_Threaded() {
	wait GAME_POSTMATCH_LENGTH - 1

	GameRules_ChangeMap( FSV_GetNextMap(), GAMETYPE )
}


/**
 * Skips the current map
*/
void function FSV_SkipMatch() {
	SetServerVar( "gameEndTime", Time()+4 )
}

/**
 * Extends the match
 * @param minutes The amount by which to extend the match
*/
void function FSV_ExtendMatch( float minutes ) {
	// Credit:
	// https://github.com/CTalvio/MentalEdge.FSU-fvnk/blob/main/mod/scripts/vscripts/fm.nut#L386-L394
	float currentEndTime = expect float( GetServerVar( "gameEndTime" ) )
	float newEndTime = currentEndTime + ( 60 * minutes )
	SetServerVar( "gameEndTime", newEndTime )
}
