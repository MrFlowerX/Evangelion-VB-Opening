/*
 * Minimal stage for autoplay-only video playback.
 */

#include <Stage.h>

extern ActorSpec VideoActor;

PositionedActorROMSpec VideoStageChildren[] =
{
	{&VideoActor, {0, 0, 0}, {0, 0, 0}, {1, 1, 1}, 1, "VideoEnt", NULL, NULL, true},
	{NULL, {0, 0, 0}, {0, 0, 0}, {1, 1, 1}, 0, NULL, NULL, NULL, false},
};

StageROMSpec VideoStage =
{
	__TYPE(Stage),

	{
		__TIMER_100US,
		10,
		kMS,
	},

	{
		__DEFAULT_PCM_HZ,
	},

	{
		{
			__SCREEN_WIDTH,
			__SCREEN_HEIGHT,
			__SCREEN_DEPTH,
		},

		{
			0,
			0,
			0,
			0,
		},

		{
			0,
			0,
			-10,
			__SCREEN_WIDTH,
			__SCREEN_HEIGHT,
			__SCREEN_WIDTH * 5,
		}
	},

	{
		40,
		16,
		24,
		false,
	},

	{
		64,
		16,

		{
			__COLOR_BLACK,
			{
				__BRIGHTNESS_DARK_RED,
				__BRIGHTNESS_MEDIUM_RED,
				__BRIGHTNESS_BRIGHT_RED,
			},
			(BrightnessRepeatSpec*)NULL,
		},

		{
			{
				__BGMAP_PALETTE_0,
				__BGMAP_PALETTE_1,
				__BGMAP_PALETTE_2,
				__BGMAP_PALETTE_3,
			},
			{
				__OBJECT_PALETTE_0,
				__OBJECT_PALETTE_1,
				__OBJECT_PALETTE_2,
				__OBJECT_PALETTE_3,
			},
		},

		0,

		{
			0,
			0,
			0,
			0,
		},

		{
			0,
			0,
			0,
			0,
		},

		{
			__MAXIMUM_X_VIEW_DISTANCE,
			__MAXIMUM_Y_VIEW_DISTANCE,
			__CAMERA_NEAR_PLANE,
			__BASE_FACTOR,
			__HORIZONTAL_VIEW_POINT_CENTER,
			__VERTICAL_VIEW_POINT_CENTER,
			__SCALING_MODIFIER_FACTOR,
		},
	},

	{
		{
			__I_TO_FIXED(0),
			__F_TO_FIXED(0),
			__I_TO_FIXED(0),
		},

		__F_TO_FIXED(0),
	},

	{
		(FontSpec**)NULL,
		(CharSetSpec**)NULL,
		(TextureSpec**)NULL,
		NULL,
	},

	{
		{
			NULL,
			__TYPE(UIContainer),
		},

		(PositionedActor*)VideoStageChildren,
	},

	(PostProcessingEffect*)NULL,
};
