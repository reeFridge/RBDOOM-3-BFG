#pragma once

class idVec3;
class idEntity;
class idPhysics;
class idAAS;
class idClipModel;
class idCmdArgs;

// path prediction
typedef enum
{
	SE_BLOCKED			= BIT( 0 ),
	SE_ENTER_LEDGE_AREA	= BIT( 1 ),
	SE_ENTER_OBSTACLE	= BIT( 2 ),
	SE_FALL				= BIT( 3 ),
	SE_LAND				= BIT( 4 )
} stopEvent_t;

typedef struct predictedPath_s
{
	idVec3				endPos;						// final position
	idVec3				endVelocity;				// velocity at end position
	idVec3				endNormal;					// normal of blocking surface
	int					endTime;					// time predicted
	int					endEvent;					// event that stopped the prediction
	const idEntity* 	blockingEntity;				// entity that blocks the movement
} predictedPath_t;

// obstacle avoidance
typedef struct obstaclePath_s
{
	idVec3				seekPos;					// seek position avoiding obstacles
	idEntity* 			firstObstacle;				// if != NULL the first obstacle along the path
	idVec3				startPosOutsideObstacles;	// start position outside obstacles
	idEntity* 			startPosObstacle;			// if != NULL the obstacle containing the start position
	idVec3				seekPosOutsideObstacles;	// seek position outside obstacles
	idEntity* 			seekPosObstacle;			// if != NULL the obstacle containing the seek position
} obstaclePath_t;

class idCombatNode : public idEntity
{
public:
	CLASS_PROTOTYPE( idCombatNode );

	idCombatNode();

	void				Save( idSaveGame* savefile ) const;
	void				Restore( idRestoreGame* savefile );

	void				Spawn();
	bool				IsDisabled() const;
	bool				EntityInView( idActor* actor, const idVec3& pos );
	static void			DrawDebugInfo();

private:
	float				min_dist;
	float				max_dist;
	float				cone_dist;
	float				min_height;
	float				max_height;
	idVec3				cone_left;
	idVec3				cone_right;
	idVec3				offset;
	bool				disabled;

	void				Event_Activate( idEntity* activator );
	void				Event_MarkUsed();
};

namespace idAIUtil {

// Outputs a list of all monsters to the console.
void				List_f( const idCmdArgs& args );

}

namespace idAIPathing {

// Frees any nodes used for the dynamic obstacle avoidance.
void				FreeObstacleAvoidanceNodes();

// Predicts movement, returns true if a stop event was triggered.
bool				PredictPath( const idEntity* ent, const idAAS* aas, const idVec3& start, const idVec3& velocity, int totalTime, int frameTime, int stopEvent, predictedPath_t& path );

// Finds a path around dynamic obstacles.
bool				FindPathAroundObstacles( const idPhysics* physics, const idAAS* aas, const idEntity* ignore, const idVec3& startPos, const idVec3& seekPos, obstaclePath_t& path );

// Return true if the trajectory of the clip model is collision free.
bool				TestTrajectory( const idVec3& start, const idVec3& end, float zVel, float gravity, float time, float max_height, const idClipModel* clip, int clipmask, const idEntity* ignore, const idEntity* targetEntity, int drawtime );

// Finds the best collision free trajectory for a clip model.
bool				PredictTrajectory( const idVec3& firePos, const idVec3& target, float projectileSpeed, const idVec3& projGravity, const idClipModel* clip, int clipmask, float max_height, const idEntity* ignore, const idEntity* targetEntity, int drawtime, idVec3& aimDir );

}
