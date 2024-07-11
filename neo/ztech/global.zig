const std = @import("std");
const entity = @import("entity.zig");
const Types = @import("types.zig").ExportedTypes;

pub const Entities = entity.Entities(Types);

pub var entities: Entities = undefined;

pub const gravity = 1066.0;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
