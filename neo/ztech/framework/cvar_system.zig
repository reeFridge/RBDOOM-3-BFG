const std = @import("std");
const idlib = @import("../idlib.zig");
const cmd = @import("cmd_system.zig");
const bit = @import("../math/math.zig").bit;
const global = @import("../global.zig");
const Allocator = std.mem.Allocator;

pub const CVarFlags = struct {
    pub const CVAR_ALL: c_int = -1; // all flags
    pub const CVAR_BOOL: c_int = bit(0); // variable is a boolean
    pub const CVAR_INTEGER: c_int = bit(1); // variable is an integer
    pub const CVAR_FLOAT: c_int = bit(2); // variable is a float
    pub const CVAR_SYSTEM: c_int = bit(3); // system variable
    pub const CVAR_RENDERER: c_int = bit(4); // renderer variable
    pub const CVAR_SOUND: c_int = bit(5); // sound variable
    pub const CVAR_GUI: c_int = bit(6); // gui variable
    pub const CVAR_GAME: c_int = bit(7); // game variable
    pub const CVAR_TOOL: c_int = bit(8); // tool variable
    // original doom3 used to have CVAR_USERINFO ("sent to servers; available to menu") here
    pub const CVAR_SERVERINFO: c_int = bit(10); // sent from servers; available to menu
    pub const CVAR_NETWORKSYNC: c_int = bit(11); // cvar is synced from the server to clients
    pub const CVAR_STATIC: c_int = bit(12); // statically declared; not user created
    pub const CVAR_CHEAT: c_int = bit(13); // variable is considered a cheat
    pub const CVAR_NOCHEAT: c_int = bit(14); // variable is not considered a cheat
    pub const CVAR_INIT: c_int = bit(15); // can only be set from the command-line
    pub const CVAR_ROM: c_int = bit(16); // display only; cannot be set by user at all
    pub const CVAR_ARCHIVE: c_int = bit(17); // set to cause it to be saved to a config file
    pub const CVAR_MODIFIED: c_int = bit(18); // set when the variable is modified
    pub const CVAR_NEW: c_int = bit(19); // added for RBDoom
};

fn is_numeric(str: []const u8) bool {
    var dot = false;
    for (str) |char| {
        if (char == '-') continue;

        if (!std.ascii.isDigit(char)) {
            if ((char == '.') and !dot) {
                dot = true;
                continue;
            }

            return false;
        }
    }

    return true;
}

pub const CVar = extern struct {
    name: [*:0]const u8,
    value: [*:0]const u8,
    description: [*:0]const u8,
    flags: c_int,
    value_min: f32,
    value_max: f32,
    valueStrings: ?[*]?[*:0]const u8,
    valueCompletion: ?*const cmd.ArgCompletionFn,
    integer_value: i32,
    float_value: f32,
    internalVar: ?*CVar,
    next: ?*CVar,
    nameString: idlib.Str,
    resetString: idlib.Str,
    valueString: idlib.Str,
    descriptionString: idlib.Str,

    pub fn init(
        name: [:0]const u8,
        value: [:0]const u8,
        flags: c_int,
        desc: [:0]const u8,
    ) CVar {
        return .{
            .name = name.ptr,
            .value = value.ptr,
            .flags = flags,
            .description = desc.ptr,
            .value_min = 0,
            .value_max = 0,
            .valueCompletion = null,
            .valueStrings = null,
            .integer_value = 0,
            .float_value = 0,
            .internalVar = null,
            .next = null,
            .nameString = idlib.Str{},
            .resetString = idlib.Str{},
            .valueString = idlib.Str{},
            .descriptionString = idlib.Str{},
        };
    }

    pub fn initMinMax(
        name: [:0]const u8,
        value: [:0]const u8,
        flags: c_int,
        desc: [:0]const u8,
        min: f32,
        max: f32,
    ) CVar {
        var c = init(name, value, flags, desc);
        c.value_min = min;
        c.value_max = max;

        return c;
    }

    pub fn getString(cvar: *const CVar) [:0]const u8 {
        return std.mem.span(cvar.value);
    }

    pub fn setup(cvar: *CVar, allocator: Allocator) Allocator.Error!void {
        try cvar.nameString.assignSliceZ(std.mem.span(cvar.name), allocator);
        cvar.name = cvar.nameString.constSliceZ();
        try cvar.valueString.assignSliceZ(std.mem.span(cvar.value), allocator);
        cvar.value = cvar.valueString.constSliceZ();
        try cvar.resetString.assignSliceZ(cvar.nameString.constSlice(), allocator);
        try cvar.descriptionString.assignSliceZ(std.mem.span(cvar.description), allocator);
        cvar.flags |= CVarFlags.CVAR_MODIFIED;
        try cvar.updateValue(allocator);
        cvar.updateCheat();

        // TODO: remove
        cvar.internalVar = cvar;
    }

    pub fn setString(cvar: *CVar, value: []const u8, allocator: Allocator) Allocator.Error!void {
        try cvar.set(value, true, allocator);
    }

    pub fn setInteger(cvar: *CVar, value: i32, allocator: Allocator) Allocator.Error!void {
        var buffer: [256]u8 = undefined;
        const pos = std.fmt.formatIntBuf(&buffer, value, 10, .lower, .{});
        const str = buffer[0..pos];
        try cvar.set(str, true, allocator);
    }

    pub fn set(cvar: *CVar, value: ?[]const u8, force: bool, allocator: Allocator) Allocator.Error!void {
        const new_value = value orelse cvar.resetString.constSlice();
        if (!force) {
            if ((cvar.flags & CVarFlags.CVAR_ROM) != 0) return;
            if ((cvar.flags & CVarFlags.CVAR_INIT) != 0) return;
        }

        if (std.mem.eql(u8, cvar.valueString.constSlice(), new_value)) return;

        try cvar.valueString.assignSliceZ(new_value, allocator);
        cvar.value = cvar.valueString.constSliceZ();
        try cvar.updateValue(allocator);
        cvar.flags |= CVarFlags.CVAR_MODIFIED;
        instance.modifiedFlags |= cvar.flags;
    }

    fn updateValue(cvar: *CVar, allocator: Allocator) Allocator.Error!void {
        var clamped = false;

        const value_str = std.mem.span(cvar.value);
        if ((cvar.flags & CVarFlags.CVAR_BOOL) != 0) {
            const int = std.fmt.parseInt(i32, value_str, 10) catch |err| {
                std.debug.print("[CVAR] Parse value error: {s}\n", .{@errorName(err)});
                return;
            };
            cvar.integer_value = if (int != 0) 1 else 0;
            cvar.float_value = @floatFromInt(cvar.integer_value);

            if (!std.mem.eql(u8, "0", value_str) and !std.mem.eql(u8, "1", value_str)) {
                try cvar.valueString.assignSliceZ(if (int != 0) "1" else "0", allocator);
                cvar.value = cvar.valueString.constSliceZ();
            }
        } else if ((cvar.flags & CVarFlags.CVAR_INTEGER) != 0) {
            const int = std.fmt.parseInt(i32, value_str, 10) catch |err| {
                std.debug.print("[CVAR] Parse value error: {s}\n", .{@errorName(err)});
                return;
            };
            cvar.integer_value = @intCast(int);
            if (cvar.value_min < cvar.value_max) {
                const min_int: c_int = @intFromFloat(cvar.value_min);
                const max_int: c_int = @intFromFloat(cvar.value_max);
                if (cvar.integer_value < min_int) {
                    cvar.integer_value = min_int;
                    clamped = true;
                } else if (cvar.integer_value > max_int) {
                    cvar.integer_value = max_int;
                    clamped = true;
                }
            }

            if (clamped or
                !is_numeric(value_str) or
                std.mem.indexOfScalar(u8, value_str, '.') != null)
            {
                try cvar.valueString.assignSlice(value_str, allocator);
                cvar.value = cvar.valueString.constSliceZ();
            }
            cvar.float_value = @floatFromInt(int);
        } else if ((cvar.flags & CVarFlags.CVAR_FLOAT) != 0) {
            const float = std.fmt.parseFloat(f32, value_str) catch |err| {
                std.debug.print("[CVAR] Parse value error: {s}\n", .{@errorName(err)});
                return;
            };

            cvar.float_value = float;
            if (cvar.value_min < cvar.value_max) {
                if (cvar.float_value < cvar.value_min) {
                    cvar.float_value = cvar.value_min;
                    clamped = true;
                } else if (cvar.float_value > cvar.value_max) {
                    cvar.float_value = cvar.value_max;
                    clamped = true;
                }
            }

            if (clamped or !is_numeric(value_str)) {
                try cvar.valueString.assignSliceZ(value_str, allocator);
                cvar.value = cvar.valueString.constSliceZ();
            }
            cvar.integer_value = @intFromFloat(float);
        } else {
            const has_value_strings = if (cvar.valueStrings) |value_strings|
                value_strings[0] != null
            else
                false;

            if (has_value_strings) {
                const value_strings = cvar.valueStrings orelse unreachable;
                cvar.integer_value = 0;
                var i: usize = 0;
                var opt_variant_ptr = value_strings[i];
                while (opt_variant_ptr) |variant_ptr| : ({
                    i += 1;
                    opt_variant_ptr = value_strings[i];
                }) {
                    if (std.mem.eql(
                        u8,
                        cvar.valueString.constSlice(),
                        std.mem.span(variant_ptr),
                    )) {
                        cvar.integer_value = @intCast(i);
                        break;
                    }
                }

                const variant_ptr = value_strings[@intCast(cvar.integer_value)] orelse unreachable;
                try cvar.valueString.assignSliceZ(std.mem.span(variant_ptr), allocator);
                cvar.value = cvar.valueString.constSliceZ();
                cvar.float_value = @floatFromInt(cvar.integer_value);
            } else if (cvar.valueString.len < 32) {
                const float = std.fmt.parseFloat(f32, value_str) catch 0;

                cvar.float_value = float;
                cvar.integer_value = @intFromFloat(float);
            } else {
                cvar.float_value = 0;
                cvar.integer_value = 0;
            }
        }
    }

    pub fn updateCheat(cvar: *CVar) void {
        const cheat_mask =
            CVarFlags.CVAR_NOCHEAT |
            CVarFlags.CVAR_INIT |
            CVarFlags.CVAR_ROM |
            CVarFlags.CVAR_ARCHIVE |
            CVarFlags.CVAR_SERVERINFO |
            CVarFlags.CVAR_NETWORKSYNC;

        if ((cvar.flags & cheat_mask) != 0) {
            cvar.flags &= ~CVarFlags.CVAR_CHEAT;
        } else {
            cvar.flags |= CVarFlags.CVAR_CHEAT;
        }
    }
};

pub const CVarSystem = extern struct {
    vptr: *anyopaque,
    initialized: bool,
    cvars: idlib.List(*CVar),
    cvarHash: idlib.HashIndex,
    modifiedFlags: c_int,

    const RegisterError = error{
        AlreadyRegistered,
        OutOfMemory,
    };

    pub fn init(cvar_system: *CVarSystem, allocator: Allocator) Allocator.Error!void {
        // override hash_index
        // TODO: init CVarSystem instance on the Zig side
        cvar_system.cvarHash = .{};

        cvar_system.modifiedFlags = 0;

        // TODO addCommand toggle
        // TODO addCommand set
        // TODO addCommand reset
        // TODO addCommand listCvars
        // TODO addCommand cvar_restart
        // TODO addCommand cvarAdd
        cvar_system.registerStaticCVars(allocator);

        cvar_system.initialized = true;
    }

    fn registerStaticCVars(cvar_system: *CVarSystem, allocator: Allocator) void {
        const cvar_decls = comptime blk: {
            var count: usize = 0;
            const tree = @import("../static_cvars.zig").root;

            for (tree) |mod| {
                for (@typeInfo(mod).Struct.decls) |decl| {
                    if (@TypeOf(@field(mod, decl.name)) == CVar) {
                        count += 1;
                    }
                }
            }

            var array: [count]*CVar = undefined;
            var i: usize = 0;
            for (tree) |mod| {
                for (@typeInfo(mod).Struct.decls) |decl| {
                    if (@TypeOf(@field(mod, decl.name)) == CVar) {
                        array[i] = &@field(mod, decl.name);
                        i += 1;
                    }
                }
            }

            break :blk array;
        };

        inline for (cvar_decls) |cvar| {
            cvar_system.register(cvar, allocator) catch |err| {
                std.debug.print(
                    "[CVAR][WARN] {s} err: {s}\n",
                    .{ cvar.name, @errorName(err) },
                );
            };
        }
    }

    fn register(
        cvar_system: *CVarSystem,
        cvar: *CVar,
        allocator: Allocator,
    ) RegisterError!void {
        std.debug.print("[CVAR] register: {s}\n", .{cvar.name});

        if (cvar_system.findByName(std.mem.span(cvar.name)) != null)
            return error.AlreadyRegistered;

        const hash = cvar_system.cvarHash.generateKey(std.mem.span(cvar.name), false);
        const index = try cvar_system.cvars.append(cvar, allocator);
        try cvar_system.cvarHash.add(hash, @intCast(index), allocator);

        try cvar.setup(allocator);
    }

    fn setCVarValue(
        cvar_system: *CVarSystem,
        name: [:0]const u8,
        value: [:0]const u8,
        flags: c_int,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (cvar_system.findByName(name)) |cvar| {
            try cvar.set(value, true, allocator);
            cvar.flags |= flags & ~CVarFlags.CVAR_STATIC;
            cvar.updateCheat();
        } else {
            const cvar = try allocator.create(CVar);
            cvar.* = CVar.init(name, value, flags, "");

            const hash = cvar_system.cvarHash.generateKey(name, false);
            const index = try cvar_system.cvars.append(cvar, allocator);
            try cvar_system.cvarHash.add(hash, @intCast(index), allocator);
        }
    }

    fn findByName(cvar_system: *CVarSystem, name: [:0]const u8) ?*CVar {
        const hash = cvar_system.cvarHash.generateKey(name, false);
        var i = cvar_system.cvarHash.first(hash);
        while (i != -1) : (i = cvar_system.cvarHash.next(@intCast(i))) {
            const cvars = cvar_system.cvars.slice();
            const cvar_ptr = if (i < cvars.len) cvars[@intCast(i)] else continue;
            if (std.mem.eql(u8, name, cvar_ptr.nameString.constSlice())) {
                return cvar_ptr;
            }
        }

        return null;
    }
};

pub const instance = @extern(*CVarSystem, .{ .name = "localCVarSystem" });

const console_lines = @import("common.zig").console_lines;
const num_console_lines = @import("common.zig").num_console_lines;

pub fn setCVarsFromArgs(
    opt_match: ?[]const u8,
    allocator: Allocator,
) Allocator.Error!void {
    for (0..@intCast(num_console_lines.*)) |i| {
        const arg = &console_lines[i];
        if (!std.mem.eql(u8, "set", std.mem.span(arg.argv[0]))) continue;
        if (arg.argc < 3) continue;

        const var_name = std.mem.span(arg.argv[1]);
        const var_value = std.mem.span(arg.argv[2]);

        const should_override = if (opt_match) |match|
            std.mem.eql(u8, var_name, match)
        else
            true;

        if (should_override) {
            try instance.setCVarValue(var_name, var_value, 0, allocator);

            std.debug.print(
                "[CVAR] Command-line override [{s}]='{s}'\n",
                .{
                    var_name,
                    var_value,
                },
            );
        }
    }
}
