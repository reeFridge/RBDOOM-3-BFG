pub const ScreenRect = extern struct {
    // Inclusive pixel bounds inside viewport
    x1: c_short,
    y1: c_short,
    x2: c_short,
    y2: c_short,

    // for depth bounds test
    zmin: f32,
    zmax: f32,

    pub fn isEmpty(rect: ScreenRect) bool {
        return rect.x1 > rect.x2 or rect.y1 > rect.y2;
    }

    pub fn unionWith(a: *ScreenRect, b: ScreenRect) void {
        if (b.x1 < a.x1) a.x1 = b.x1;
        if (b.x2 > a.x2) a.x2 = b.x2;
        if (b.y1 < a.y1) a.y1 = b.y1;
        if (b.y2 > a.y2) a.y2 = b.y2;
    }

    pub fn intersect(a: *ScreenRect, b: ScreenRect) void {
        if (b.x1 > a.x1) a.x1 = b.x1;
        if (b.x2 < a.x2) a.x2 = b.x2;
        if (b.y1 > a.y1) a.y1 = b.y1;
        if (b.y2 < a.y2) a.y2 = b.y2;
    }

    pub fn clear(rect: *ScreenRect) void {
        rect.y1 = 32000;
        rect.x1 = rect.y1;
        rect.y2 = -32000;
        rect.x2 = rect.y2;
        rect.zmin = 0.0;
        rect.zmax = 1.0;
    }

    pub fn addPoint(rect: *ScreenRect, x: f32, y: f32) void {
        const ix: c_short = @intFromFloat(x);
        const iy: c_short = @intFromFloat(y);

        if (ix < rect.x1) rect.x1 = ix;
        if (ix > rect.x2) rect.x2 = ix;
        if (iy < rect.y1) rect.y1 = iy;
        if (iy > rect.y2) rect.y2 = iy;
    }
};
