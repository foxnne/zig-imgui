const std = @import("std");
const build_options = @import("build-options");
const imgui = @import("imgui");
const imgui_mach = imgui.backends.mach;
const mach = @import("mach");
const Core = mach.Core;
const gpu = mach.gpu;

pub const App = @This();

pub const mach_module = .app;

pub const mach_systems = .{ .main, .init, .tick, .deinit };

pub const main = mach.schedule(.{
    .{ mach.Core, .init },
    .{ App, .init },
    .{ mach.Core, .main },
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

window: mach.ObjectID,
title_timer: mach.time.Timer,
f: f32 = 0.0,
color: [3]f32 = undefined,

pub fn init(app: *App, core: *Core, app_mod: mach.Mod(App)) !void {
    core.on_tick = app_mod.id.tick;
    core.on_exit = app_mod.id.deinit;
    allocator = gpa.allocator();

    const window = try core.windows.new(.{
        .title = "ImGui",
        .vsync_mode = .double,
    });

    app.* = .{
        .title_timer = try mach.time.Timer.start(),
        .window = window,
    };
}

pub fn lateInit(app: *App, core: *Core) !void {
    const window = core.windows.getValue(app.window);

    imgui.setZigAllocator(&allocator);
    _ = imgui.createContext(null);

    try imgui_mach.init(core, allocator, window.device, .{ .color_format = window.framebuffer_format });

    var io = imgui.getIO();
    io.config_flags |= imgui.ConfigFlags_NavEnableKeyboard;
    io.font_global_scale = 1.0 / io.display_framebuffer_scale.y;

    const font_data = @embedFile("Roboto-Medium.ttf");
    const size_pixels = 12 * io.display_framebuffer_scale.y;

    var font_cfg: imgui.FontConfig = std.mem.zeroes(imgui.FontConfig);
    font_cfg.font_data_owned_by_atlas = false;
    font_cfg.oversample_h = 2;
    font_cfg.oversample_v = 1;
    font_cfg.glyph_max_advance_x = std.math.floatMax(f32);
    font_cfg.rasterizer_multiply = 1.0;
    font_cfg.rasterizer_density = 1.0;
    font_cfg.ellipsis_char = imgui.UNICODE_CODEPOINT_MAX;
    _ = io.fonts.?.addFontFromMemoryTTF(@constCast(@ptrCast(font_data.ptr)), font_data.len, size_pixels, &font_cfg, null);
}

pub fn deinit(app: *App) void {
    _ = app;
    defer _ = gpa.deinit();

    imgui_mach.shutdown();
    imgui.destroyContext(null);
}

pub fn tick(app: *App, core: *Core) !void {
    while (core.nextEvent()) |event| {
        switch (event) {
            .window_open => {
                try lateInit(app, core);
            },
            .close => {},
            else => {},
        }
        _ = imgui_mach.processEvent(event);
    }

    try render(app, core);

    // update the window title every second
    // if (app.title_timer.read() >= 1.0) {
    //     app.title_timer.reset();
    //     try core.printTitle("ImGui [ {d}fps ] [ Input {d}hz ]", .{
    //         core.frameRate(),
    //         core.inputRate(),
    //     });
    // }
}

fn render(app: *App, core: *Core) !void {
    const window = core.windows.getValue(app.window);

    const io = imgui.getIO();

    imgui_mach.newFrame() catch return;
    imgui.newFrame();

    imgui.text("Hello, world!");
    _ = imgui.sliderFloat("float", &app.f, 0.0, 1.0);
    _ = imgui.colorEdit3("color", &app.color, imgui.ColorEditFlags_None);
    imgui.text("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / io.framerate, io.framerate);
    imgui.showDemoWindow(null);

    imgui.render();

    const back_buffer_view = window.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = gpu.Color{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = window.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const pass = encoder.beginRenderPass(&render_pass_info);
    imgui_mach.renderDrawData(imgui.getDrawData().?, pass) catch {};
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    var queue = window.queue;
    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    window.swap_chain.present();
    back_buffer_view.release();
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
