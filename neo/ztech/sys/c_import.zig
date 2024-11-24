pub const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vk_mem_alloc.h");
});
