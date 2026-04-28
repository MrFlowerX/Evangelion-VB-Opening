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

#include <Singleton.h>

#include <Camera.h>
#include <CameraEffectManager.h>
#include <HardwareManager.h>
#include <VisualComponent.h>
#include <VideoPlayerState.h>
#include <VUEngine.h>
#include <VirtualList.h>
#include <VirtualNode.h>

//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
// DECLARATIONS
//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————

extern StageROMSpec VideoStage;
extern AnimationFunctionROMSpec VideoAnimation;

#define VIDEO_PLAYER_EXTERNAL_SYNC_ADDRESS			((volatile uint16*)0x04000000)
#define VIDEO_PLAYER_EXTERNAL_SYNC_START			((uint16)0x0101)
#define VIDEO_PLAYER_EXTERNAL_SYNC_END				((uint16)0x0100)
#define VIDEO_PLAYER_WCR_EXPANSION_WAIT_BIT			((uint8)0x02)

static int16 VideoPlayerState_getCurrentFrame(Actor actor)
{
	VirtualList sprites = Entity::getComponents(Entity::safeCast(actor), kSpriteComponent);
	VirtualNode firstSprite = isDeleted(sprites) ? NULL : VirtualList::begin(sprites);

	if(NULL == firstSprite)
	{
		return 0;
	}

	return VisualComponent::getActualFrame(VisualComponent::safeCast(VirtualNode::getData(firstSprite)));
}

static void VideoPlayerState_configureExpansionWaitState()
{
	// Keep ROM timing untouched and force the expansion bus (/ES) to the slowest setting.
	_hardwareRegisters[__WCR] &= (uint8)~VIDEO_PLAYER_WCR_EXPANSION_WAIT_BIT;
}

static void VideoPlayerState_writeExternalSync(uint16 value)
{
	*VIDEO_PLAYER_EXTERNAL_SYNC_ADDRESS = value;
}

static void VideoPlayerState_updateExternalSync(Actor videoActor, int16 numberOfFrames, int16* previousVideoFrame)
{
	if(isDeleted(videoActor) || NULL == previousVideoFrame || 0 >= numberOfFrames)
	{
		return;
	}

	int16 currentFrame = VideoPlayerState_getCurrentFrame(videoActor);

	if(0 > *previousVideoFrame)
	{
		*previousVideoFrame = currentFrame;
		return;
	}

	if(*previousVideoFrame == currentFrame)
	{
		return;
	}

	if(0 == currentFrame && 0 < *previousVideoFrame)
	{
		VideoPlayerState_writeExternalSync(VIDEO_PLAYER_EXTERNAL_SYNC_START);
	}

	*previousVideoFrame = currentFrame;
}

//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
// CLASS'S METHODS
//——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————

void VideoPlayerState::constructor()
{
	// Always explicitly call the base's constructor 
	Base::constructor();

	// Init members
	this->videoActor = NULL;
	this->numberOfFrames = 0;
	this->previousVideoFrame = -1;
}

void VideoPlayerState::destructor()
{
	// Always explicitly call the base's destructor 
	Base::destructor();
}

void VideoPlayerState::enter(void* owner __attribute__ ((unused)))
{
	Camera camera = Camera::getInstance();

	Base::enter(this, owner);

	// Load stage
	GameState::configureStage(GameState::safeCast(this), (StageSpec*)&VideoStage, NULL);

	// Get actors from stage
	this->videoActor = Actor::safeCast(Container::getChildByName
	(
		Container::safeCast(this->stage),
		"VideoEnt",
		false
	));

	this->numberOfFrames = VideoAnimation.numberOfFrames;
	this->previousVideoFrame = -1;

	VideoPlayerState_configureExpansionWaitState();
	VideoPlayerState_writeExternalSync(VIDEO_PLAYER_EXTERNAL_SYNC_START);

	// Start clocks to start animations
	GameState::startClocks(GameState::safeCast(this));

	Camera::startEffect(camera, kHide);
	Camera::startEffect
	(
		camera,
		kFadeTo,
		0,
		NULL,
		__FADE_DELAY,
		Object::safeCast(this)
	);
}

void VideoPlayerState::execute(void* owner)
{
    Base::execute(this, owner);

	if(!isDeleted(this->videoActor))
	{
		VideoPlayerState_updateExternalSync(this->videoActor, this->numberOfFrames, &this->previousVideoFrame);
	}
}
