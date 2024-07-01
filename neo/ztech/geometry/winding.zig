pub const CWinding = struct {
    numPoints: c_int,
    p: ?*anyopaque, // idVec5*
    allocedSize: c_int,
};
