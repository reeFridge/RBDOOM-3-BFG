const std = @import("std");

pub const EntityId = u32;
pub const SpawnArgs = std.StringHashMap([]const u8);

pub inline fn assertFields(comptime Required: type, comptime T: type) bool {
    inline for (std.meta.fields(Required)) |field_info| {
        if (std.meta.fieldIndex(T, field_info.name)) |field_index| {
            if (@typeInfo(T).Struct.fields[field_index].type != field_info.type)
                return false;
        } else return false;
    }

    return true;
}

pub fn TypedEntities(comptime Archetype: type) type {
    return struct {
        allocator: std.mem.Allocator,
        storage: std.MultiArrayList(Archetype),

        pub const Type = Archetype;

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .storage = std.MultiArrayList(Archetype){},
            };
        }

        pub fn add(self: *@This(), instance: Archetype) error{OutOfMemory}!EntityId {
            try self.storage.append(self.allocator, instance);

            const index = self.storage.len - 1;
            self.initFieldsAtIndex(index);

            return @intCast(index);
        }

        pub fn deinit(self: *@This()) void {
            self.deinitFields();
            self.storage.deinit(self.allocator);
        }

        fn initFieldsAtIndex(self: *@This(), index: usize) void {
            const slices = self.storage.slice();
            const fields = std.meta.fields(Type);

            inline for (fields, 0..) |field_info, field_index| {
                if (std.meta.hasMethod(field_info.type, "component_init")) {
                    const StorageType = @TypeOf(self.storage);
                    const field_slice = slices.items(@as(StorageType.Field, @enumFromInt(field_index)));
                    field_slice[index].component_init();
                }
            }
        }

        fn deinitFields(self: *@This()) void {
            const slices = self.storage.slice();
            const fields = std.meta.fields(Type);

            inline for (fields, 0..) |field_info, field_index| {
                if (std.meta.hasMethod(field_info.type, "component_deinit")) {
                    const StorageType = @TypeOf(self.storage);
                    const field_slice = slices.items(@as(StorageType.Field, @enumFromInt(field_index)));
                    for (field_slice) |*item| {
                        item.component_deinit();
                    }
                }
            }
        }
    };
}

pub const EntityError = error{
    UnknownEntityType,
};

pub fn Entities(comptime archetypes: anytype) type {
    comptime var fields: []const std.builtin.Type.StructField = &.{};
    inline for (archetypes) |Archetype| {
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .name = @typeName(Archetype),
            .type = TypedEntities(Archetype),
            .is_comptime = false,
            .default_value = null,
            .alignment = 0,
        }};
    }

    const ComptimeEntities = @Type(.{
        .Struct = .{
            .layout = .auto,
            .is_tuple = false,
            .decls = &.{},
            .fields = fields,
        },
    });

    return struct {
        allocator: std.mem.Allocator,
        comptime_entities: ComptimeEntities,

        pub fn init(allocator: std.mem.Allocator) @This() {
            var comptime_entities: ComptimeEntities = undefined;
            inline for (archetypes) |Archetype| {
                @field(comptime_entities, @typeName(Archetype)) = TypedEntities(Archetype).init(allocator);
                std.debug.print("register type_name: {s}\n", .{@typeName(Archetype)});
            }

            return .{
                .allocator = allocator,
                .comptime_entities = comptime_entities,
            };
        }

        pub fn getByType(self: *@This(), comptime Archetype: type) *TypedEntities(Archetype) {
            if (!@hasField(ComptimeEntities, @typeName(Archetype))) {
                @compileError("Unknown Archetype " ++ @typeName(Archetype));
            }

            return &@field(self.comptime_entities, @typeName(Archetype));
        }

        pub fn spawn(self: *@This(), type_name: []const u8, spawn_args: *const SpawnArgs, c_dict_ptr: ?*anyopaque) !EntityId {
            inline for (std.meta.fields(ComptimeEntities)) |field_info| {
                if (std.mem.eql(u8, type_name, field_info.name)) {
                    const Archetype = field_info.type.Type;
                    const entities = &@field(self.comptime_entities, field_info.name);

                    return try entities.add(try Archetype.spawn(spawn_args, c_dict_ptr));
                }
            }

            return EntityError.UnknownEntityType;
        }

        pub fn size(self: @This()) usize {
            var count = @as(usize, 0);

            inline for (std.meta.fields(ComptimeEntities)) |info| {
                const field = &@field(self.comptime_entities, info.name);
                count += field.storage.len;
            }

            return count;
        }

        pub fn process(self: *@This(), f: *const fn (type, anytype) void) void {
            inline for (std.meta.fields(ComptimeEntities)) |info| {
                const field = &@field(self.comptime_entities, info.name);
                f(info.type.Type, &field.storage);
            }
        }

        pub fn deinit(self: *@This()) void {
            inline for (archetypes) |Archetype| {
                @field(self.comptime_entities, @typeName(Archetype)).deinit();
            }
        }
    };
}
