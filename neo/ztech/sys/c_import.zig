pub const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("sys/sdl/sdl2_scancode_mappings.h");
    @cInclude("SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("vk_mem_alloc.h");
    @cInclude("AL/alc.h");
});
