const std = @import("std");
const Decl = @import("decl_manager.zig").Decl;
const idlib = @import("../idlib.zig");
const Material = @import("../renderer/material.zig").Material;
const SoundShader = @import("../sound/sound.zig").SoundShader;

pub const DeclAudio = extern struct {
    base: Decl = .{},
    audio: ?*const SoundShader = null,
    audioName: idlib.idStr = .{},
    info: idlib.idStr = .{},

    pub fn init(self: *DeclAudio) void {
        self.* = .{};
        self.audioName.initEmptyBuffer();
        self.info.initEmptyBuffer();
    }
};

pub const DeclVideo = extern struct {
    base: Decl = .{},
    preview: ?*const Material = null,
    video: ?*const Material = null,
    videoName: idlib.idStr = .{},
    info: idlib.idStr = .{},
    audio: ?*const SoundShader = null,

    pub fn init(self: *DeclVideo) void {
        self.* = .{};
        self.videoName.initEmptyBuffer();
        self.info.initEmptyBuffer();
    }
};

pub const DeclEmail = extern struct {
    base: Decl = .{},
    text: idlib.idStr = .{},
    subject: idlib.idStr = .{},
    date: idlib.idStr = .{},
    to: idlib.idStr = .{},
    from: idlib.idStr = .{},

    pub fn init(self: *DeclEmail) void {
        self.* = .{};
        self.text.initEmptyBuffer();
        self.subject.initEmptyBuffer();
        self.date.initEmptyBuffer();
        self.to.initEmptyBuffer();
        self.from.initEmptyBuffer();
    }
};

pub const DeclPDA = extern struct {
    base: Decl = .{},
    videos: idlib.idList(*const DeclVideo) = .{},
    audios: idlib.idList(*const DeclAudio) = .{},
    emails: idlib.idList(*const DeclEmail) = .{},
    pdaName: idlib.idStr = .{},
    fullName: idlib.idStr = .{},
    icon: idlib.idStr = .{},
    id: idlib.idStr = .{},
    post: idlib.idStr = .{},
    title: idlib.idStr = .{},
    security: idlib.idStr = .{},
    originalEmails: u32 = 0,
    originalVideos: u32 = 0,

    pub fn init(self: *DeclPDA) void {
        self.* = .{};
        self.pdaName.initEmptyBuffer();
        self.fullName.initEmptyBuffer();
        self.icon.initEmptyBuffer();
        self.id.initEmptyBuffer();
        self.post.initEmptyBuffer();
        self.title.initEmptyBuffer();
        self.security.initEmptyBuffer();
    }
};
