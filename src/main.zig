const std = @import("std");

const l = @cImport({
    @cInclude("lcm/lcm.h");
    @cInclude("exlcm_example_t.h");
});

// 一个简单的lcm接收函数
fn my_handler(rbuf: [*c]const l.lcm_recv_buf_t, channel: [*c]const u8, msg_: [*c]const l.exlcm_example_t, usr: ?*anyopaque) callconv(.C) void {
    _ = usr;
    _ = rbuf;

    const msg = msg_.*;
    std.debug.print("Received message on channel {s}\n", .{channel});
    std.debug.print("  timestamp   = {}\n", .{msg.timestamp});
    std.debug.print("  position    = {any}\n", .{msg.position});
    std.debug.print("  orientation = {any}\n", .{msg.orientation});
    std.debug.print("  ranges      = {any}\n", .{msg.ranges[0..@intCast(usize, msg.num_ranges)]});
    std.debug.print("  name        = '{s}'\n", .{msg.name});
    std.debug.print("  enabled     = {}\n\n", .{msg.enabled});

    // cast to [*c]u8 to []u8 and test msg.name start with "SHUTDOWN"
    if (std.mem.startsWith(u8, std.mem.sliceTo(msg.name, 0), "SHUTDOWN")) {
        std.debug.print("Shutting down...\n", .{});
        std.os.exit(0);
    }
}

// 一个简单的lcm接收线程
fn lcm_loop() void {
    var lcm = l.lcm_create(null);
    defer l.lcm_destroy(lcm);

    _ = l.exlcm_example_t_subscribe(lcm, "EXAMPLE", &my_handler, null);
    while (true) {
        _ = l.lcm_handle(lcm);
    }
}

// zig的main函数
pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    var lcm = l.lcm_create(null);
    defer l.lcm_destroy(lcm);

    // define a thread to handle lcm
    var lcm_thread = try std.Thread.spawn(.{}, lcm_loop, .{});
    defer lcm_thread.join();

    // 两种不同的定义方法
    // var ranges: [18]i16 = undefined;
    var ranges = [_]i16{0} ** 18;
    inline for (&ranges, 0..) |*r, i| {
        r.* = @intCast(i16, i + 1);
    }

    // 定义一个结构体：
    var data = l.exlcm_example_t{
        .timestamp = std.time.milliTimestamp(),
        .position = .{ 1, 2, 3 },
        .orientation = .{ 1, 0, 0, 0 },
        .num_ranges = ranges.len,
        .enabled = 1,
        .ranges = &ranges,
        .name = @constCast("message string from zig!"),
    };
    var allocator = std.heap.page_allocator;

    // 更新参数，持续发送，间隔时间100毫秒
    for (ranges) |r| {
        // std.debug.print("{}", .{r});
        data.timestamp = std.time.milliTimestamp();
        data.position[0] += 1;
        data.orientation[0] += 1;
        data.name = @constCast(std.fmt.allocPrintZ(allocator, "publish batch: {d:>10} th.", .{r}) catch "string allocation error.");

        _ = l.exlcm_example_t_publish(lcm, "EXAMPLE", &data);
        // std.debug.print("ziglcm_example_t_publish -> {}\n", .{ret});
        std.time.sleep(std.time.ns_per_ms * 100);
    }

    data.name = @constCast("SHUTDOWN");
    _ = l.exlcm_example_t_publish(lcm, "EXAMPLE", &data);
}
