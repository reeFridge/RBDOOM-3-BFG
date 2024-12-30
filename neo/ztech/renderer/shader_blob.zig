const std = @import("std");

pub const blob_signature: []const u8 = "NVSP";

pub const ShaderConstant = struct {
    name: []const u8,
    value: []const u8,
};

pub const ShaderBlobEntry = extern struct {
    permutation_size: u32,
    data_size: u32,
};

pub fn findPermutationInBlob(
    raw_blob: []const u8,
    constants: []const ShaderConstant,
) ?[]const u8 {
    if (raw_blob.len < blob_signature.len) return null;

    if (!std.mem.eql(u8, raw_blob[0..blob_signature.len], blob_signature)) {
        return if (constants.len == 0)
            raw_blob
        else
            null;
    }

    const blob = raw_blob[blob_signature.len..];
    var constants_str = std.BoundedArray(u8, 256).init(0) catch unreachable;
    {
        var w = constants_str.writer();
        for (constants, 0..) |constant, i| {
            w.print(
                "{s}={s}",
                .{ constant.name, constant.value },
            ) catch @panic("Buffer overflow");
            if (i + 1 < constants.len) {
                w.print(" ", .{}) catch @panic("Buffer overflow");
            }
        }
    }
    const constants_str_slice = constants_str.constSlice();

    var blob_slice = blob[0..];
    while (blob_slice.len > @sizeOf(ShaderBlobEntry)) {
        const header: *align(1) const ShaderBlobEntry = @ptrCast(blob_slice.ptr);
        if (header.data_size == 0) return null;
        if (blob_slice.len < (@sizeOf(ShaderBlobEntry) + header.data_size + header.permutation_size)) return null;

        const entry_permutation_mem = blob_slice[@sizeOf(ShaderBlobEntry)..];
        if (header.permutation_size == constants_str_slice.len and
            ((constants_str_slice.len == 0) or
            (std.mem.eql(u8, entry_permutation_mem[0..constants_str_slice.len], constants_str_slice))))
        {
            return blob_slice[@sizeOf(ShaderBlobEntry) + header.permutation_size ..][0..header.data_size];
        }
        const offset: usize = @sizeOf(ShaderBlobEntry) + header.data_size + header.permutation_size;
        blob_slice = blob_slice[offset..];
    }

    return null;
}
