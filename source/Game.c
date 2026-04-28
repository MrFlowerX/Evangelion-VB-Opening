/*
 * VUEngine Video Player
 *
 * © Christian Radke and Marten Reiß
 *
 * For the full copyright and license information, please view the LICENSE file
 * that was distributed with this source code.
 */

//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
// INCLUDES
//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————

#include <VideoPlayerState.h>
#include <VUEngine.h>

#define GAME_EXTERNAL_SYNC_ADDRESS		((volatile uint16*)0x04000000)
#define GAME_EXTERNAL_SYNC_BOOT			((uint16)0xFFFF)

//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
// GAME'S MAIN LOOP
//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————

GameState game(void)
{
	*GAME_EXTERNAL_SYNC_ADDRESS = GAME_EXTERNAL_SYNC_BOOT;

	// Start the game
	return GameState::safeCast(VideoPlayerState::getInstance());
}
