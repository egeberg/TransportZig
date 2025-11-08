const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Parse a simple URI
    const uri = try std.Uri.parse("http://example.com");

    std.debug.print("Testing HTTP Client API methods...\n", .{});

    // KEY: Need server_header_buffer for client.open()!
    var server_header_buffer: [2048]u8 = undefined;
    var request = try client.open(.GET, uri, .{
        .server_header_buffer = &server_header_buffer,
    });
    defer request.deinit();

    std.debug.print("Request created with open()\n", .{});

    try request.send();
    std.debug.print("Request sent\n", .{});

    try request.finish();
    std.debug.print("Request finished\n", .{});

    try request.wait();
    std.debug.print("Response received\n", .{});

    // Read response body
    const body = try request.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(body);

    std.debug.print("Response body length: {d} bytes\n", .{body.len});
    std.debug.print("Status: {}\n", .{request.response.status});

    std.debug.print("\n✓ HTTP Client API works!\n", .{});
}
