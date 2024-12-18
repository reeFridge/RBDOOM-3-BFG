const std = @import("std");
const Decl = @import("decl_manager.zig").Decl;
const idlib = @import("../idlib.zig");
const Material = @import("../renderer/material.zig").Material;
const SoundShader = @import("../sound/sound.zig").SoundShader;

pub const DeclAudio = extern struct {
    base: Decl = .{},
    audio: ?*const SoundShader = null,
    audioName: idlib.Str = .{},
    info: idlib.Str = .{},

    pub fn init(self: *DeclAudio) void {
        self.* = .{};
    }
};

pub const DeclVideo = extern struct {
    base: Decl = .{},
    preview: ?*const Material = null,
    video: ?*const Material = null,
    videoName: idlib.Str = .{},
    info: idlib.Str = .{},
    audio: ?*const SoundShader = null,

    pub fn init(self: *DeclVideo) void {
        self.* = .{};
    }
};

pub const DeclEmail = extern struct {
    base: Decl = .{},
    text: idlib.Str = .{},
    subject: idlib.Str = .{},
    date: idlib.Str = .{},
    to: idlib.Str = .{},
    from: idlib.Str = .{},

    pub fn init(self: *DeclEmail) void {
        self.* = .{};
    }
};

pub const DeclPDA = extern struct {
    base: Decl = .{},
    videos: idlib.List(*const DeclVideo) = .{},
    audios: idlib.List(*const DeclAudio) = .{},
    emails: idlib.List(*const DeclEmail) = .{},
    pdaName: idlib.Str = .{},
    fullName: idlib.Str = .{},
    icon: idlib.Str = .{},
    id: idlib.Str = .{},
    post: idlib.Str = .{},
    title: idlib.Str = .{},
    security: idlib.Str = .{},
    originalEmails: u32 = 0,
    originalVideos: u32 = 0,

    pub fn init(self: *DeclPDA) void {
        self.* = .{};
    }
};
