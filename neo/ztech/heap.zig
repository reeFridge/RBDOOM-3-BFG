pub fn BlockAllocator(ElementType: type) type {
    return struct {
        pub const T = ElementType;
    };
}
