const Decl = @import("decl_manager.zig").Decl;
const idlib = @import("../idlib.zig");
const Material = @import("../renderer/material.zig").Material;
const SoundShader = @import("../sound/sound.zig").SoundShader;

pub const DeclAudio = extern struct {
    base: Decl,
    audio: ?*const SoundShader,
    audioName: idlib.idStr,
    info: idlib.idStr,
};

pub const DeclVideo = extern struct {
    base: Decl,
    preview: ?*const Material,
    video: ?*const Material,
    videoName: idlib.idStr,
    info: idlib.idStr,
    audio: ?*const SoundShader,
};

pub const DeclEmail = extern struct {
    base: Decl,
    text: idlib.idStr,
    subject: idlib.idStr,
    date: idlib.idStr,
    to: idlib.idStr,
    from: idlib.idStr,
};

pub const DeclPDA = extern struct {
    base: Decl,
    videos: idlib.idList(*const DeclVideo),
    audios: idlib.idList(*const DeclAudio),
    emails: idlib.idList(*const DeclEmail),
    pdaName: idlib.idStr,
    fullName: idlib.idStr,
    icon: idlib.idStr,
    id: idlib.idStr,
    post: idlib.idStr,
    title: idlib.idStr,
    security: idlib.idStr,
    originalEmails: c_int,
    originalVideos: c_int,
};
