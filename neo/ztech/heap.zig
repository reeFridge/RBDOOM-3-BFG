pub fn BlockAllocator(ElementType: type) type {
    return struct {
        T: ElementType,
    };
}
