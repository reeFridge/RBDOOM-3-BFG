const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const net_if = @cImport(@cInclude("net/if.h"));
const ioctl = @cImport(@cInclude("sys/ioctl.h"));
const net_in = @cImport(@cInclude("netinet/in.h"));

const max_interfaces = 32;
const buffer_size = max_interfaces * @sizeOf(net_if.ifreq);

const netToHost = std.mem.bigToNative;
const hostToNet = std.mem.nativeToBig;

const NetInterface = extern struct {
    ip: u32,
    mask: u32,
    addr: [15:0]u8,

    pub fn print(iface: *const NetInterface) void {
        std.debug.print("[NET] interface(", .{});
        defer std.debug.print(")\n", .{});

        std.debug.print(".addr: {s}", .{std.mem.span(@as([*:0]const u8, &iface.addr))});
        const net_mask = hostToNet(u32, iface.mask);
        const mask_slice = &@as([4]u8, @bitCast(net_mask));
        std.debug.print(", .mask: {}.{}.{}.{}", .{
            mask_slice[0],
            mask_slice[1],
            mask_slice[2],
            mask_slice[3],
        });
    }
};

var num_interfaces: usize = 0;
var netint: [max_interfaces]NetInterface = undefined;

pub fn init() posix.SocketError!void {
    try detectInterfaces();
}

fn detectInterfaces() posix.SocketError!void {
    // TODO: support win
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
    var buf: [buffer_size]u8 = undefined;

    // const actually prevents change of the fields by ioctl call!!!
    var ifc = net_if.ifconf{
        .ifc_len = buffer_size,
        .ifc_ifcu = .{
            .ifcu_buf = &buf,
        },
    };

    if (std.c.ioctl(sock, ioctl.SIOCGIFCONF, &ifc) < 0) {
        @panic("[FATAL] SIOCGIFCONF error");
    }

    var if_index: usize = 0;
    while (if_index < ifc.ifc_len) : (if_index += @sizeOf(net_if.ifreq)) {
        const ifr: *net_if.ifreq = @ptrCast(@alignCast(ifc.ifc_ifcu.ifcu_buf + if_index));
        const if_name = std.mem.span(@as([*:0]u8, @ptrCast(&ifr.ifr_ifrn.ifrn_name)));

        if (std.c.ioctl(sock, ioctl.SIOCGIFADDR, ifr) < 0) {
            std.debug.print(
                "[NET][ERR] iface.name = {s}, SIOCGIFADDR error\n",
                .{if_name},
            );
            continue;
        }

        if (ifr.ifr_ifru.ifru_addr.sa_family != posix.AF.INET)
            continue;

        const ip = netToHost(
            u32,
            @as(*u32, @ptrCast(@alignCast(&ifr.ifr_ifru.ifru_addr.sa_data[2]))).*,
        );
        const addr_slice = ifr.ifr_ifru.ifru_addr.sa_data[2..6];

        // set netint.addr before getting the mask
        _ = std.fmt.bufPrintZ(&netint[num_interfaces].addr, "{}.{}.{}.{}", .{
            addr_slice[0],
            addr_slice[1],
            addr_slice[2],
            addr_slice[3],
        }) catch unreachable;

        if (std.c.ioctl(sock, ioctl.SIOCGIFNETMASK, ifr) < 0) {
            std.debug.print(
                "[NET][ERR] iface.name = {s}, SIOCGIFNETMASK error",
                .{if_name},
            );
            continue;
        }

        const mask = netToHost(
            u32,
            @as(*u32, @ptrCast(@alignCast(&ifr.ifr_ifru.ifru_addr.sa_data[2]))).*,
        );

        netint[num_interfaces].ip = ip;
        netint[num_interfaces].mask = mask;

        netint[num_interfaces].print();

        num_interfaces += 1;
    }
}
