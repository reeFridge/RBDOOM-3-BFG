// This is a row-major matrix and transforms are applied with left-multiplication.
pub const RenderMatrix = extern struct {
    m: [16]f32,
};
