# Zig使用LCM（Lightweight Communications and Marshalling）协议通信

# 目标
使用Zig作为开发语言，通过LCM进行实时的数据交换。展示Zig的开发能力，以及LCM的使用。为实现基于Zig的LCM协议的开发提供基础。

# 前提

1. 安装了LCM，包括C语言头文件和库文件，以及lcm-gen工具；
2. 安装Zig编译器；
3. 有手。


# 步骤

## 创建一个Zig项目

```bash
mkdir zig-lcm-tutor
cd zig-lcm-tutor
zig init-exe
```

## 创建一个LCM类型

根据[LCM类型定义](https://blog.csdn.net/withstand/article/details/130249738)创建一个LCM类型定义文件`lcm_tutorial_t.lcm`，内容如下：

```lcm
package exlcm;

struct example_t
{
    int64_t  timestamp;
    double   position[3];
    double   orientation[4];
    int32_t  num_ranges;
    int16_t  ranges[num_ranges];
    string   name;
    boolean  enabled;
}

```

```bash
lcm-gen -c lcm_tutorial_t.lcm
```

这就在当前目录下生成了一个`exlcm_example_t.h`头文件，以及一个`exlcm_example_t.c`源文件。从头文件里面可以看到，我们的数据结构，`exlcm.example_t`变成一个C结构体`exlcm_example_t`。这是因为C语言没有包结构，所以用这么一个名字前缀的方式来模拟。编码解码的代码在C源文件中，这里不再赘述。值得注意的是，我们暂时（或者永远）无需关心这两个文件的内容。我刚才还在犹豫到底要不要把这两个文件贴出来，因为实在有点无聊。

## 修改`build.zig`文件

修改这个文件主要是为了在Zig中能够引用相应的头文件，编译时包含相应的库文件和刚才生成的C语言源文件。

在自动生成的`build.zig`文件中，增加如下内容：

```zig
// added for LCM
exe.addIncludePath("src/");
exe.addCSourceFile("src/exlcm_tutorial_t.c", &[_][]const u8{});

exe.addIncludePath("/usr/local/include/");
exe.addLibPath("/usr/local/lib/");
exe.linkSystemLibrary("lcm");
exe.linkSystemLibrary("glib-2.0");
exe.linkSystemLibrary("m");
exe.linkSystemLibrary("pthread");
exe.linkLibC();
```

## 实现`main.zig`文件

```zig
const std = @import("std");

const l = @cImport({
    @cInclude("lcm/lcm.h");
    @cInclude("exlcm_example_t.h");
});

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    const lcm = l.lcm_create(null);
    defer l.lcm_destroy(lcm);

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
}
```

## 测试运行过程
前面这个Zig的版本，与C语言、Python、Java、C++的版本，都可以实现相互通信，前提条件就是LCM数据类型的定义完全一致，这就是为什么前面定义的名字是`exlcm.example_t`，这是为了与LCM的例子一致。

首先测试Python的Listenr。

```bash
python ~/lcm/examples/python/listener.py &
zig build run
```

后台的输出很快就出现了：

```
 Received message on channel "EXAMPLE"
   timestamp   = 1681904615426
   position    = (19.0, 2.0, 3.0)
   orientation = (19.0, 0.0, 0.0, 0.0)
   ranges: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18)
   name        = 'publish batch:        +18 th.'
   enabled     = True
```

与Zig程序中的逻辑一致。

# 进一步的改进：增加一个LCM的Zig语言的Listener
考虑一下，利用原来的Python语言的Listener还不够好，我们增加一个ZIG语言的Listener。


1. 增加一个处理exlcm.example_t的函数
2. 增加一个线程执行LCM的监听函数
3. 在主程序启动线程
4. 增加最终发送“SHUTDOWN”消息的逻辑


```zig
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
```

这里面最值得注意的几行代码是：

```zig
    // 值得注意的地方之一
    std.debug.print("  ranges      = {any}\n", .{msg.ranges[0..@intCast(usize, msg.num_ranges)]});

    // 值得注意的地方之二
    if (std.mem.startsWith(u8, std.mem.sliceTo(msg.name, 0), "SHUTDOWN")) {
        std.debug.print("Shutting down...\n", .{});
        std.os.exit(0);
    }
```

前者是从C语言的数组转换到Zig语言的数组，后者是从Zig语言的字符串转换到C语言的字符串。可以看到这里的逻辑都是从一个不同类型的array转换到一个slice。前者是按照长度来构造slice，后者是按照字符串的结束符`0:u8`来构造slice。

其他代码都非常直观，运行`zig build run`就可以看到效果了。

```
Received message on channel EXAMPLE
  timestamp   = 1681934219972
  position    = { 1.9e+01, 2.0e+00, 3.0e+00 }
  orientation = { 1.9e+01, 0.0e+00, 0.0e+00, 0.0e+00 }
  ranges      = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
  name        = 'publish batch:        +18 th.'
  enabled     = 1

Received message on channel EXAMPLE
  timestamp   = 1681934219972
  position    = { 1.9e+01, 2.0e+00, 3.0e+00 }
  orientation = { 1.9e+01, 0.0e+00, 0.0e+00, 0.0e+00 }
  ranges      = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
  name        = 'SHUTDOWN'
  enabled     = 1

Shutting down...
```

如果运行`zig build run & zig build run`，也就是同时运行两个，结果就很fun，因为两个都相互发，相互收……好乱。

# 结论

1. Zig使用C语言的库，相对来说非常简单。LCM的整个实现也比较干净。具体的数据编码都采用移植性非常好的C语言实现，并且通过头文件和源代码的方式复用。
2. 数据类型必须完全对应，这对于Zig来说并不是问题，仅仅是需要一一对照C语言的源代码来确定选择什么数据类型。字符串那个地方有一点点问题，就是要把Zig的常量字符串做一个`@constCast`变成变量字符串。
3. Zig的构建系统几乎无痛，赞！