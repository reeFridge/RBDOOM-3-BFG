const Physics = @import("../../physics/physics.zig").Physics;
const ClipModel = @import("../../physics/clip_model.zig").ClipModel;
const Contacts = @import("../../entity_types/moveable_object.zig").Contacts;

pub const Query = struct {
    physics: Physics,
    clip_model: ClipModel,
    contacts: Contacts,
};

pub fn update(list: anytype) void {
    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.clip_model),
        list_slice.items(.contacts),
    ) |*physics, *clip_model, *contacts| {
        switch (physics.*) {
            Physics.rigid_body => |*rigid_body| {
                contacts.list.resize(0) catch unreachable;
                rigid_body.evaluateContacts(&contacts.list, clip_model) catch unreachable;

                if (rigid_body.testIfAtRest(contacts.list.items)) {
                    rigid_body.rest();
                } else {
                    rigid_body.contactFriction(contacts.list.items);
                }

                if (!rigid_body.atRest()) {
                    rigid_body.activateContactEntities();
                }
            },
            else => {},
        }
    }
}
