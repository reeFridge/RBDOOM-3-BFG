const idlib = @import("../idlib.zig");
const Material = @import("material.zig").Material;

const ScaledGlyphInfo = extern struct {
    top: f32,
    left: f32,
    x_skip: f32,
    s1: f32,
    t1: f32,
    s2: f32,
    t2: f32,
    material: ?*const Material,
};

const FontInfo = extern struct {
    const GlyphInfo = extern struct {
        width: u8,
        height: u8,
        top: i8,
        left: i8,
        x_skip: u8,
        s: u16,
        t: u16,
    };

    const InfoLegacy = extern struct {
        max_width: f32,
        max_height: f32,
    };

    info_legacy: [3]InfoLegacy,
    ascender: i16,
    descender: i16,
    num_glyphs: u16,
    glyph_data: ?*GlyphInfo,
    char_index: ?*u32,
    ascii: [128]u8,
};

pub const Font = extern struct {
    name: idlib.Str,
    alias: ?*Font,
    info: *FontInfo,
};
