const std = @import("std");

pub const EntityId = u32;
pub const SpawnArgs = std.StringHashMap([]const u8);

pub fn findEntryMatchedPrefix(
    spawn_args: *const SpawnArgs,
    prefix: []const u8,
    last_index: *?usize,
) ?SpawnArgs.Entry {
    var iterator = spawn_args.iterator();

    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        if (last_index.*) |last| {
            if (index <= last) continue;
        }

        if (entry.key_ptr.*.len < prefix.len) continue;

        if (std.mem.eql(u8, entry.key_ptr.*[0..prefix.len], prefix)) {
            last_index.* = index;
            return entry;
        }
    }

    return null;
}

pub inline fn assertFields(comptime Required: type, comptime T: type) bool {
    inline for (std.meta.fields(Required)) |field_info| {
        if (std.meta.fieldIndex(T, field_info.name)) |field_index| {
            if (@typeInfo(T).Struct.fields[field_index].type != field_info.type)
                return false;
        } else return false;
    }

    return true;
}

pub const Capture = struct {
    pub const Type = enum { ByValue, ByReference };
    const ByValue = struct {};
    const ByReference = struct {};

    pub fn capturePayload(capture: type) type {
        return std.meta.FieldType(capture, .payload);
    }

    pub fn captureType(capture: type) Type {
        if (std.meta.FieldType(capture, .type) == ByValue) return .ByValue;
        if (std.meta.FieldType(capture, .type) == ByReference) return .ByReference;

        unreachable;
    }

    pub fn value(T: type) type {
        return struct { type: ByValue, payload: T };
    }

    pub fn ref(T: type) type {
        return struct { type: ByReference, payload: T };
    }
};

pub const QueryField = struct {
    name: [:0]const u8,
    type: type,
    capture_type: Capture.Type,
};

fn Query(query: anytype) []const QueryField {
    comptime var query_fields: []const QueryField = &.{};

    inline for (std.meta.fields(query)) |field_info| {
        query_fields = query_fields ++ [_]QueryField{.{
            .name = field_info.name,
            .capture_type = Capture.captureType(field_info.type),
            .type = Capture.capturePayload(field_info.type),
        }};
    }

    return query_fields;
}

fn QueryMeta(comptime query_fields: []const QueryField) type {
    const StructField = std.builtin.Type.StructField;
    comptime var required_fields: []const StructField = &.{};
    comptime var out_fields: []const StructField = &.{};

    inline for (query_fields) |field| {
        required_fields = required_fields ++ [_]StructField{.{
            .name = field.name,
            .type = field.type,
            .is_comptime = false,
            .alignment = 0,
            .default_value = null,
        }};

        out_fields = out_fields ++ [_]StructField{.{
            .name = field.name,
            .type = switch (field.capture_type) {
                .ByValue => field.type,
                .ByReference => *field.type,
            },
            .is_comptime = false,
            .alignment = 0,
            .default_value = null,
        }};
    }

    return struct {
        pub const Required = @Type(.{
            .Struct = .{
                .layout = .auto,
                .fields = required_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });

        pub const Out = @Type(.{
            .Struct = .{
                .layout = .auto,
                .fields = out_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    };
}

pub fn TypedEntities(comptime Archetype: type, comptime EntityHandle: type) type {
    return struct {
        allocator: std.mem.Allocator,
        field_storage: std.MultiArrayList(Archetype),

        pub const Type = Archetype;

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .field_storage = std.MultiArrayList(Archetype){},
            };
        }

        pub fn add(self: *@This(), instance: Archetype) error{OutOfMemory}!EntityId {
            try self.field_storage.append(self.allocator, instance);

            const index = self.field_storage.len - 1;

            return @intCast(index);
        }

        pub fn addUndefined(self: *@This()) error{OutOfMemory}!EntityId {
            const index = try self.field_storage.addOne(self.allocator);

            return @intCast(index);
        }

        pub fn clear(self: *@This()) void {
            self.deinitFields();
            self.field_storage.shrinkAndFree(self.allocator, 0);
        }

        pub fn deinit(self: *@This()) void {
            self.deinitFields();
            self.field_storage.deinit(self.allocator);
        }

        pub fn initFields(self: *@This(), handle: EntityHandle) void {
            const slices = self.field_storage.slice();
            const fields = std.meta.fields(Type);
            const StorageType = @TypeOf(self.field_storage);

            inline for (fields, 0..) |field_info, field_index| {
                if (std.meta.hasMethod(field_info.type, "component_init")) {
                    const field_slice = slices.items(@as(StorageType.Field, @enumFromInt(field_index)));
                    field_slice[handle.id].component_init();
                }
            }
        }

        fn deinitFields(self: *@This()) void {
            const slices = self.field_storage.slice();
            const fields = std.meta.fields(Type);

            inline for (fields, 0..) |field_info, field_index| {
                if (std.meta.hasMethod(field_info.type, "component_deinit")) {
                    const StorageType = @TypeOf(self.field_storage);
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
    NoSpawnMethod,
    UnknownEntityType,
};

pub fn Entities(comptime archetypes: anytype) type {
    comptime var enum_fields: []const std.builtin.Type.EnumField = &.{};

    inline for (archetypes, 0..) |Archetype, i| {
        enum_fields = enum_fields ++ [_]std.builtin.Type.EnumField{.{
            .name = @typeName(Archetype),
            .value = i,
        }};
    }

    const E = @Type(.{
        .Enum = .{
            .decls = &.{},
            .fields = enum_fields,
            .is_exhaustive = true,
            .tag_type = std.math.IntFittingRange(0, enum_fields.len - 1),
        },
    });

    const ExternHandle = extern struct { type: u8, id: EntityId };
    const Handle = struct {
        type: E,
        id: EntityId,

        pub inline fn fromType(Archetype: type, id: EntityId) @This() {
            return .{
                .id = id,
                .type = std.enums.nameCast(E, @typeName(Archetype)),
            };
        }

        pub inline fn fromExtern(e: ExternHandle) @This() {
            return .{
                .type = @enumFromInt(e.type),
                .id = e.id,
            };
        }
    };

    comptime var union_fields: []const std.builtin.Type.UnionField = &.{};

    inline for (archetypes) |Archetype| {
        union_fields = union_fields ++ [_]std.builtin.Type.UnionField{.{
            .name = @typeName(Archetype),
            .type = TypedEntities(Archetype, Handle),
            .alignment = 0,
        }};
    }

    const U = @Type(.{
        .Union = .{
            .layout = .auto,
            .decls = &.{},
            .fields = union_fields,
            .tag_type = E,
        },
    });

    return struct {
        pub const EntityHandle = Handle;
        pub const ExternEntityHandle = ExternHandle;
        const Storage = std.EnumArray(E, U);

        storage: Storage,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            var storage = Storage.initUndefined();
            inline for (archetypes) |Archetype| {
                storage.set(
                    std.enums.nameCast(E, @typeName(Archetype)),
                    @unionInit(
                        U,
                        @typeName(Archetype),
                        TypedEntities(Archetype, EntityHandle).init(allocator),
                    ),
                );

                std.debug.print("register type_name: {s}\n", .{@typeName(Archetype)});
            }

            return .{
                .allocator = allocator,
                .storage = storage,
            };
        }

        pub fn getByTag(self: *@This(), tag: E) *U {
            return self.storage.getPtr(tag);
        }

        pub fn queryByHandle(
            self: *@This(),
            handle: EntityHandle,
            query: type,
        ) ?QueryMeta(Query(query)).Out {
            const query_fields = Query(query);
            const Meta = QueryMeta(query_fields);

            return switch (self.getByTag(handle.type).*) {
                inline else => |*obj| {
                    const Archetype = @TypeOf(obj.*).Type;
                    if (comptime !assertFields(Meta.Required, Archetype))
                        return null;

                    if (obj.field_storage.len == 0 or handle.id > obj.field_storage.len - 1)
                        return null;

                    const Field = std.meta.FieldEnum(Archetype);
                    const slice = obj.field_storage.slice();

                    var result: Meta.Out = undefined;

                    inline for (query_fields) |field| {
                        @field(result, field.name) = switch (field.capture_type) {
                            .ByValue => slice.items(std.enums.nameCast(Field, field.name))[handle.id],
                            .ByReference => &slice.items(std.enums.nameCast(Field, field.name))[handle.id],
                        };
                    }

                    return result;
                },
            };
        }

        pub fn getByType(self: *@This(), comptime Archetype: type) *TypedEntities(Archetype, EntityHandle) {
            if (!@hasField(E, @typeName(Archetype))) {
                @compileError("Unknown Archetype " ++ @typeName(Archetype));
            }

            const tag = comptime std.enums.nameCast(E, @typeName(Archetype));
            const storage = self.storage.getPtr(tag);

            return switch (storage.*) {
                tag => |*u| u,
                else => unreachable,
            };
        }

        pub fn spawn(
            self: *@This(),
            type_name: []const u8,
            spawn_args: SpawnArgs,
            c_dict_ptr: ?*anyopaque,
        ) anyerror!EntityHandle {
            const info = @typeInfo(U).Union;

            inline for (info.fields) |field_info| {
                if (std.mem.eql(u8, type_name, field_info.name)) {
                    const Archetype = field_info.type.Type;
                    if (!std.meta.hasMethod(Archetype, "spawn")) return EntityError.NoSpawnMethod;

                    const entities = self.getByType(Archetype);
                    const id = try entities.addUndefined();
                    errdefer {
                        _ = entities.field_storage.pop();
                    }
                    const handle = EntityHandle.fromType(Archetype, id);

                    entities.field_storage.set(id, try Archetype.spawn(
                        handle,
                        self.allocator,
                        spawn_args,
                        c_dict_ptr,
                    ));

                    entities.initFields(handle);

                    return handle;
                }
            }

            return EntityError.UnknownEntityType;
        }

        pub fn register(self: *@This(), instance: anytype) !EntityHandle {
            const Archetype = @TypeOf(instance);

            const entities = self.getByType(Archetype);
            const id = try entities.add(instance);
            const handle = EntityHandle.fromType(Archetype, id);

            entities.initFields(handle);

            return handle;
        }

        pub fn spawnType(self: *@This(), Archetype: type, spawn_args: SpawnArgs) !EntityHandle {
            const entities = self.getByType(Archetype);
            const id = try entities.add(try Archetype.spawn(self.allocator, spawn_args, null));
            const handle = EntityHandle.fromType(Archetype, id);

            entities.initFields(handle);

            return handle;
        }

        pub fn size(self: *const @This()) usize {
            var count = @as(usize, 0);

            inline for (0..Storage.len) |i| {
                switch (self.storage.values[i]) {
                    inline else => |*storage| {
                        count += storage.field_storage.len;
                    },
                }
            }

            return count;
        }

        pub fn processWithQuery(self: *@This(), query: type, f: *const fn (anytype) void) void {
            @setEvalBranchQuota(2000);
            const info = @typeInfo(U).Union;

            inline for (info.fields) |field_info| {
                const Archetype = field_info.type.Type;

                if (comptime assertFields(query, Archetype)) {
                    f(&self.getByType(Archetype).field_storage);
                }
            }
        }

        pub fn process(self: *@This(), f: *const fn (type, anytype) void) void {
            @setEvalBranchQuota(2000);
            const info = @typeInfo(U).Union;

            inline for (info.fields) |field_info| {
                const Archetype = field_info.type.Type;
                f(Archetype, &self.getByType(Archetype).field_storage);
            }
        }

        pub fn clear(self: *@This()) void {
            const info = @typeInfo(U).Union;

            inline for (info.fields) |field_info| {
                const Archetype = field_info.type.Type;
                const entities = self.getByType(Archetype);
                entities.clear();
            }
        }

        pub fn deinit(self: *@This()) void {
            const info = @typeInfo(U).Union;

            inline for (info.fields) |field_info| {
                const Archetype = field_info.type.Type;
                const entities = self.getByType(Archetype);
                entities.deinit();
            }
        }
    };
}
