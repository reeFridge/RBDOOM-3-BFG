pub const ScreenRect = extern struct {
    // Inclusive pixel bounds inside viewport
    x1: c_short,
    y1: c_short,
    x2: c_short,
    y2: c_short,

    // for depth bounds test
    zmin: f32,
    zmax: f32,
};
