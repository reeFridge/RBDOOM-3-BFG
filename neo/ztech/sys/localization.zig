//! @exportCVars
const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;

pub var sys_lang: CVar = CVar.init(
    "sys_lang",
    lang_english,
    cvar.CVarFlags.CVAR_SYSTEM | cvar.CVarFlags.CVAR_INIT | cvar.CVarFlags.CVAR_ARCHIVE,
    "",
);

pub const lang_english = "english";

pub fn getDefaultLang() []const u8 {
    // TODO support other languages
    // TODO support .strings files
    return lang_english;
}

pub fn setDefaultLang() !void {
    try sys_lang.setString(getDefaultLang());
}
