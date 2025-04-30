const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const mem = std.mem;
const io = std.io;
const fs = std.fs;
const ascii = std.ascii;
const time = std.time;

const Color = struct {
    const Reset = "\x1b[0m";
    const Bold = "\x1b[1m";
    const Red = "\x1b[31m";
    const Green = "\x1b[32m";
    const Yellow = "\x1b[33m";
    const Blue = "\x1b[34m";
    const Magenta = "\x1b[35m";
    const Cyan = "\x1b[36m";
    const White = "\x1b[37m";
};

const SystemInfo = struct {
    os_name: []const u8,
    kernel_version: []const u8,
    hostname: []const u8,
    uptime: u64,
    shell: []const u8,
    terminal: []const u8,
    cpu_model: []const u8,
    cpu_cores: usize,
    ram_total: u64,
    ram_used: u64,
};

pub fn main() !void {
    const start_time = time.milliTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    const info = try getSystemInfo(allocator);
    defer {
        allocator.free(info.os_name);
        allocator.free(info.kernel_version);
        allocator.free(info.hostname);
        allocator.free(info.shell);
        allocator.free(info.terminal);
        allocator.free(info.cpu_model);
    }

    // Display ASCII art logo based on OS
    try displayLogo(stdout, info.os_name);

    // Display system info with formatting
    try stdout.print("\n{s}{s}OS:{s} {s}{s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, info.os_name });
    try stdout.print("{s}{s}Kernel:{s} {s}{s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, info.kernel_version });
    try stdout.print("{s}{s}Hostname:{s} {s}{s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, info.hostname });

    const uptime_str = try formatUptime(allocator, info.uptime);
    defer allocator.free(uptime_str);
    try stdout.print("{s}{s}Uptime:{s} {s}{s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, uptime_str });

    try stdout.print("{s}{s}Shell:{s} {s}{s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, info.shell });
    try stdout.print("{s}{s}Terminal:{s} {s}{s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, info.terminal });
    try stdout.print("{s}{s}CPU:{s} {s}{s} ({d} cores)\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, info.cpu_model, info.cpu_cores });

    const ram_total_mb = info.ram_total / 1024 / 1024;
    const ram_used_mb = info.ram_used / 1024 / 1024;
    const ram_percent = @as(f32, @floatFromInt(info.ram_used)) / @as(f32, @floatFromInt(info.ram_total)) * 100.0;

    try stdout.print("{s}{s}Memory:{s} {s}{d} MB / {d} MB ({d:.1}%){s}\n", .{ Color.Bold, Color.Blue, Color.Reset, Color.White, ram_used_mb, ram_total_mb, ram_percent, Color.Reset });

    // Color blocks
    try stdout.writeAll("\n");
    try stdout.print("{s}███{s}{s}███{s}{s}███{s}{s}███{s}{s}███{s}{s}███{s}{s}███{s}{s}███{s}\n", .{
        Color.Red,     Color.Reset,
        Color.Green,   Color.Reset,
        Color.Yellow,  Color.Reset,
        Color.Blue,    Color.Reset,
        Color.Magenta, Color.Reset,
        Color.Cyan,    Color.Reset,
        Color.White,   Color.Reset,
        Color.Bold,    Color.Reset,
    });

    const end_time = time.milliTimestamp();
    const elapsed = end_time - start_time;

    try stdout.print("\n{s}zfetch completed in {d} ms{s}\n", .{ Color.Bold, elapsed, Color.Reset });
}

fn getSystemInfo(allocator: mem.Allocator) !SystemInfo {
    var info: SystemInfo = undefined;

    // OS Name
    switch (builtin.os.tag) {
        .linux => {
            var buffer: [fs.max_path_bytes]u8 = undefined;
            const os_release_path = "/etc/os-release";

            const file = try fs.openFileAbsolute(os_release_path, .{});
            defer file.close();

            const reader = file.reader();
            var os_name_found = false;

            while (true) {
                const line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch break;
                if (line == null) break;

                if (mem.startsWith(u8, line.?, "NAME=")) {
                    const name_start = mem.indexOf(u8, line.?, "\"");
                    if (name_start) |start| {
                        const name_end = mem.indexOfPos(u8, line.?, start + 1, "\"");
                        if (name_end) |end| {
                            info.os_name = try allocator.dupe(u8, line.?[start + 1 .. end]);
                            os_name_found = true;
                            break;
                        }
                    }
                }
            }

            if (!os_name_found) {
                info.os_name = try allocator.dupe(u8, "Linux");
            }
        },
        .macos => info.os_name = try allocator.dupe(u8, "macOS"),
        .windows => info.os_name = try allocator.dupe(u8, "Windows"),
        else => info.os_name = try allocator.dupe(u8, @tagName(builtin.os.tag)),
    }

    // Kernel Version
    if (builtin.os.tag == .linux) {
        var utsname: os.linux.utsname = undefined;
        _ = os.linux.uname(&utsname);
        info.kernel_version = try allocator.dupe(u8, &utsname.release);
    } else {
        // For non-Linux platforms, provide a basic version
        info.kernel_version = try allocator.dupe(u8, "N/A");
    }

    // Hostname
    var hostname_buffer: [64]u8 = undefined;
    const hostname_len = try std.posix.gethostname(&hostname_buffer);
    info.hostname = try allocator.dupe(u8, hostname_len);
    //info.hostname = try allocator.dupe(u8, hostname_buffer[0..hostname_len]);

    // Uptime
    if (builtin.os.tag == .linux) {
        var uptime_buffer: [256]u8 = undefined;
        const uptime_file = try fs.openFileAbsolute("/proc/uptime", .{});
        defer uptime_file.close();

        const uptime_bytes = try uptime_file.readAll(&uptime_buffer);
        const uptime_str = uptime_buffer[0..uptime_bytes];

        const space_pos = mem.indexOf(u8, uptime_str, " ") orelse uptime_str.len;
        const uptime_seconds_str = uptime_str[0..space_pos];

        const float_uptime: f64 = 0;
        _ = try std.fmt.parseFloat(f64, uptime_seconds_str);
        info.uptime = @intFromFloat(float_uptime);
    } else {
        // Default uptime for non-Linux systems
        info.uptime = 0;
    }

    // Shell
    if (std.process.getEnvVarOwned(allocator, "SHELL")) |shell| {
        info.shell = shell;
    } else |_| {
        info.shell = try allocator.dupe(u8, "Unknown");
    }

    // Terminal
    if (std.process.getEnvVarOwned(allocator, "TERM")) |term| {
        info.terminal = term;
    } else |_| {
        info.terminal = try allocator.dupe(u8, "Unknown");
    }

    // CPU Information
    info.cpu_model = try allocator.dupe(u8, "Unknown");
    info.cpu_cores = 1;

    if (builtin.os.tag == .linux) {
        var cpu_buffer: [4096]u8 = undefined;
        const cpu_file = fs.openFileAbsolute("/proc/cpuinfo", .{}) catch {
            return info;
        };
        defer cpu_file.close();

        const cpu_bytes = try cpu_file.readAll(&cpu_buffer);
        const cpu_info = cpu_buffer[0..cpu_bytes];

        var model_name_found = false;
        var core_count: usize = 0;

        var lines_it = mem.splitSequence(u8, cpu_info, "\n");
        while (lines_it.next()) |line| {
            if (mem.startsWith(u8, line, "model name")) {
                const colon_pos = mem.indexOf(u8, line, ":") orelse continue;
                const model_name = mem.trim(u8, line[colon_pos + 1 ..], " \t");

                if (!model_name_found) {
                    allocator.free(info.cpu_model);
                    info.cpu_model = try allocator.dupe(u8, model_name);
                    model_name_found = true;
                }
            } else if (mem.startsWith(u8, line, "processor")) {
                core_count += 1;
            }
        }

        if (core_count > 0) {
            info.cpu_cores = core_count;
        }
    }

    // Memory information
    info.ram_total = 0;
    info.ram_used = 0;

    if (builtin.os.tag == .linux) {
        var mem_buffer: [4096]u8 = undefined;
        const mem_file = fs.openFileAbsolute("/proc/meminfo", .{}) catch {
            return info;
        };
        defer mem_file.close();

        const mem_bytes = try mem_file.readAll(&mem_buffer);
        const mem_info = mem_buffer[0..mem_bytes];

        var mem_total: ?u64 = null;
        var mem_free: ?u64 = null;
        var mem_available: ?u64 = null;
        var mem_buffers: ?u64 = null;
        var mem_cached: ?u64 = null;

        var lines_it = mem.splitSequence(u8, mem_info, "\n");
        while (lines_it.next()) |line| {
            if (mem.startsWith(u8, line, "MemTotal:")) {
                const value_str = extractNumericValue(line);
                mem_total = std.fmt.parseInt(u64, value_str, 10) catch continue;
            } else if (mem.startsWith(u8, line, "MemFree:")) {
                const value_str = extractNumericValue(line);
                mem_free = std.fmt.parseInt(u64, value_str, 10) catch continue;
            } else if (mem.startsWith(u8, line, "MemAvailable:")) {
                const value_str = extractNumericValue(line);
                mem_available = std.fmt.parseInt(u64, value_str, 10) catch continue;
            } else if (mem.startsWith(u8, line, "Buffers:")) {
                const value_str = extractNumericValue(line);
                mem_buffers = std.fmt.parseInt(u64, value_str, 10) catch continue;
            } else if (mem.startsWith(u8, line, "Cached:")) {
                if (!mem.containsAtLeast(u8, line, 1, "SwapCached:")) {
                    const value_str = extractNumericValue(line);
                    mem_cached = std.fmt.parseInt(u64, value_str, 10) catch continue;
                }
            }
        }

        if (mem_total) |total| {
            info.ram_total = total * 1024; // Convert from KB to bytes

            if (mem_available) |available| {
                info.ram_used = total - available;
            } else if (mem_free != null and mem_buffers != null and mem_cached != null) {
                const free = mem_free.? + mem_buffers.? + mem_cached.?;
                info.ram_used = if (total > free) total - free else 0;
            }
        }
    }

    return info;
}

fn extractNumericValue(line: []const u8) []const u8 {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (ascii.isDigit(line[i])) {
            var j: usize = i;
            while (j < line.len and ascii.isDigit(line[j])) : (j += 1) {}
            return line[i..j];
        }
    }
    return "";
}

fn formatUptime(allocator: mem.Allocator, seconds: u64) ![]const u8 {
    const days = seconds / 86400;
    const hours = (seconds % 86400) / 3600;
    const minutes = (seconds % 3600) / 60;
    const secs = seconds % 60;

    var result: []u8 = undefined;

    if (days > 0) {
        result = try std.fmt.allocPrint(allocator, "{d}d {d}h {d}m {d}s", .{ days, hours, minutes, secs });
    } else if (hours > 0) {
        result = try std.fmt.allocPrint(allocator, "{d}h {d}m {d}s", .{ hours, minutes, secs });
    } else if (minutes > 0) {
        result = try std.fmt.allocPrint(allocator, "{d}m {d}s", .{ minutes, secs });
    } else {
        result = try std.fmt.allocPrint(allocator, "{d}s", .{secs});
    }

    return result;
}

fn displayLogo(writer: anytype, os_name: []const u8) !void {
    // Simple ASCII logos for different operating systems
    if (mem.eql(u8, os_name, "Linux") or
        mem.indexOf(u8, os_name, "Linux") != null or
        mem.indexOf(u8, os_name, "Ubuntu") != null or
        mem.indexOf(u8, os_name, "Debian") != null or
        mem.indexOf(u8, os_name, "Fedora") != null)
    {
        try writer.print("{s}    .---.{s}\n", .{ Color.Yellow, Color.Reset });
        try writer.print("{s}   /     \\{s}   {s}z{s}{s}f{s}{s}e{s}{s}t{s}{s}c{s}{s}h{s}\n", .{
            Color.Yellow, Color.Reset,
            Color.Bold,   Color.Red,
            Color.Bold,   Color.Green,
            Color.Bold,   Color.Yellow,
            Color.Bold,   Color.Blue,
            Color.Bold,   Color.Magenta,
            Color.Bold,   Color.Cyan,
        });
        try writer.print("{s}  |       |{s}\n", .{ Color.Yellow, Color.Reset });
        try writer.print("{s}  |  {s}L{s}{s}  |{s}\n", .{ Color.Yellow, Color.Red, Color.Bold, Color.Yellow, Color.Reset });
        try writer.print("{s}  |       |{s}\n", .{ Color.Yellow, Color.Reset });
        try writer.print("{s}   \\_____/{s}\n", .{ Color.Yellow, Color.Reset });
    } else if (mem.eql(u8, os_name, "macOS") or mem.indexOf(u8, os_name, "Darwin") != null) {
        try writer.print("{s}       .{s}\n", .{ Color.Cyan, Color.Reset });
        try writer.print("{s}      .{s}{s}z{s}{s}f{s}{s}e{s}{s}t{s}{s}c{s}{s}h{s}\n", .{
            Color.Cyan, Color.Reset,
            Color.Bold, Color.Red,
            Color.Bold, Color.Green,
            Color.Bold, Color.Yellow,
            Color.Bold, Color.Blue,
            Color.Bold, Color.Magenta,
            Color.Bold, Color.Cyan,
        });
        try writer.print("{s}     .{s}\n", .{ Color.Cyan, Color.Reset });
        try writer.print("{s}    .{s}  {s}.{s}\n", .{ Color.Cyan, Color.Reset, Color.Cyan, Color.Reset });
        try writer.print("{s}   .{s}  {s}.{s}\n", .{ Color.Cyan, Color.Reset, Color.Cyan, Color.Reset });
        try writer.print("{s}  .{s}{s}_____{s}\n", .{ Color.Cyan, Color.Reset, Color.Cyan, Color.Reset });
    } else if (mem.eql(u8, os_name, "Windows") or mem.indexOf(u8, os_name, "Windows") != null) {
        try writer.print("{s}  ______{s}\n", .{ Color.Blue, Color.Reset });
        try writer.print("{s} |  |   |{s}  {s}z{s}{s}f{s}{s}e{s}{s}t{s}{s}c{s}{s}h{s}\n", .{
            Color.Blue, Color.Reset,
            Color.Bold, Color.Red,
            Color.Bold, Color.Green,
            Color.Bold, Color.Yellow,
            Color.Bold, Color.Blue,
            Color.Bold, Color.Magenta,
            Color.Bold, Color.Cyan,
        });
        try writer.print("{s} |  |___|{s}\n", .{ Color.Blue, Color.Reset });
        try writer.print("{s} |  |   |{s}\n", .{ Color.Blue, Color.Reset });
        try writer.print("{s} |__|___|{s}\n", .{ Color.Blue, Color.Reset });
    } else {
        try writer.print("{s}   ____{s}\n", .{ Color.Magenta, Color.Reset });
        try writer.print("{s}  /    \\{s}   {s}z{s}{s}f{s}{s}e{s}{s}t{s}{s}c{s}{s}h{s}\n", .{
            Color.Magenta, Color.Reset,
            Color.Bold,    Color.Red,
            Color.Bold,    Color.Green,
            Color.Bold,    Color.Yellow,
            Color.Bold,    Color.Blue,
            Color.Bold,    Color.Magenta,
            Color.Bold,    Color.Cyan,
        });
        try writer.print("{s} |  ()  |{s}\n", .{ Color.Magenta, Color.Reset });
        try writer.print("{s}  \\____/{s}\n", .{ Color.Magenta, Color.Reset });
    }
}
