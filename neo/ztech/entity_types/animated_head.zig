const std = @import("std");
const Transform = @import("../physics/physics.zig").Transform;
const Animator = @import("../anim/animator.zig");
const JointMat = @import("../anim/animator.zig").JointMat;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const common = @import("common.zig");
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

transform: Transform,
local_transform: Transform,
animator: Animator,
model_def_handle: c_int = -1,
render_entity: RenderEntity,
bind_joint_ptr: ?*const JointMat,
parent_link: ?EntityHandle,

const AnimatedHead = @This();
