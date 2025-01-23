//! @exportCVars
const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;
const Allocator = @import("std").mem.Allocator;

pub var sys_lang: CVar = CVar.init(
    "sys_lang",
    lang_english,
    cvar.CVarFlags.system | cvar.CVarFlags.init | cvar.CVarFlags.archive,
    "",
);

pub const lang_english = "english";

pub fn getDefaultLang() []const u8 {
    // TODO support other languages
    // TODO support .strings files
    return lang_english;
}

pub fn setDefaultLang(allocator: Allocator) Allocator.Error!void {
    try sys_lang.setString(getDefaultLang(), allocator);
}
