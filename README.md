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

 >Received message on channel "EXAMPLE"
 >  timestamp   = 1681904615426
 >  position    = (19.0, 2.0, 3.0)
 >  orientation = (19.0, 0.0, 0.0, 0.0)
 >  ranges: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18)
 >  name        = 'publish batch:        +18 th.'
 >  enabled     = True

与Zig程序中的逻辑一致。

# 结论

1. Zig使用C语言的库，相对来说非常简单。LCM的整个实现也比较干净。具体的数据编码都采用移植性非常好的C语言实现，并且通过头文件和源代码的方式复用。
2. 数据类型必须完全对应，这对于Zig来说并不是问题，仅仅是需要一一对照C语言的源代码来确定选择什么数据类型。字符串那个地方有一点点问题，就是要把Zig的常量字符串做一个`@constCast`变成变量字符串。
3. Zig的构建系统几乎无痛，赞！