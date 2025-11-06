const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});
const types = @import("types.zig");
const entities = @import("entities.zig");
const simulation = @import("simulation.zig");
const flight = @import("flight.zig");

// ============================================================================
// 3D VISUALIZATION WITH RAYLIB
// ============================================================================

pub const Renderer = struct {
    camera: rl.Camera3D,
    world_scale: f32, // km to world units
    camera_target: rl.Vector3,
    camera_rotation: f32,
    camera_distance: f32,

    pub fn init() Renderer {
        const camera = rl.Camera3D{
            .position = .{ .x = 100.0, .y = 150.0, .z = 100.0 },
            .target = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            .fovy = 45.0,
            .projection = rl.CAMERA_PERSPECTIVE,
        };

        return .{
            .camera = camera,
            .world_scale = 0.01, // 1 world unit = 100 km
            .camera_target = .{ .x = 0, .y = 0, .z = 0 },
            .camera_rotation = 0,
            .camera_distance = 200,
        };
    }

    pub fn updateCamera(self: *Renderer) void {
        // Handle camera controls
        if (rl.IsKeyDown(rl.KEY_LEFT)) self.camera_rotation += 1.0;
        if (rl.IsKeyDown(rl.KEY_RIGHT)) self.camera_rotation -= 1.0;
        if (rl.IsKeyDown(rl.KEY_UP)) self.camera_distance -= 2.0;
        if (rl.IsKeyDown(rl.KEY_DOWN)) self.camera_distance += 2.0;

        // Clamp distance
        self.camera_distance = std.math.clamp(self.camera_distance, 50, 500);

        // Update camera position
        const rad = self.camera_rotation * std.math.pi / 180.0;
        self.camera.position.x = self.camera_target.x + @cos(rad) * self.camera_distance;
        self.camera.position.z = self.camera_target.z + @sin(rad) * self.camera_distance;
        self.camera.position.y = self.camera_distance * 0.7;
        self.camera.target = self.camera_target;

        // Mouse wheel zoom
        const wheel = rl.GetMouseWheelMove();
        if (wheel != 0) {
            self.camera_distance -= wheel * 10.0;
            self.camera_distance = std.math.clamp(self.camera_distance, 50, 500);
        }
    }

    pub fn render(self: *Renderer, world: *simulation.SimulationWorld) void {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.Color{ .r = 10, .g = 20, .b = 40, .a = 255 });

        rl.BeginMode3D(self.camera);
        defer rl.EndMode3D();

        // Draw grid (world map reference)
        self.drawGrid();

        // Draw airports
        for (world.airports.items) |airport| {
            self.drawAirport(airport);
        }

        // Draw flight routes
        for (world.flight_scheduler.active_flights.items) |active_flight| {
            self.drawFlightPath(active_flight.flight_plan);
        }

        // Draw aircraft
        for (world.aircraft.items) |aircraft| {
            if (aircraft.status != .parked) {
                self.drawAircraft(aircraft);
            }
        }

        // Draw UI overlay
        self.drawUI(world);
    }

    fn drawGrid(self: Renderer) void {
        // Draw world coordinate grid
        const grid_size = 200;
        const grid_spacing = 10;

        var i: i32 = -grid_size;
        while (i <= grid_size) : (i += grid_spacing) {
            const color = if (@mod(i, 50) == 0)
                rl.Color{ .r = 80, .g = 80, .b = 100, .a = 255 }
            else
                rl.Color{ .r = 40, .g = 40, .b = 60, .a = 255 };

            const fi = @as(f32, @floatFromInt(i));
            const fgrid = @as(f32, @floatFromInt(grid_size));

            rl.DrawLine3D(
                .{ .x = fi, .y = 0, .z = -fgrid },
                .{ .x = fi, .y = 0, .z = fgrid },
                color,
            );
            rl.DrawLine3D(
                .{ .x = -fgrid, .y = 0, .z = fi },
                .{ .x = fgrid, .y = 0, .z = fi },
                color,
            );
        }
    }

    fn drawAirport(self: Renderer, airport: entities.Airport) void {
        const pos = airport.location.toWorldSpace(self.world_scale);
        const world_pos = rl.Vector3{ .x = pos[0], .y = pos[1], .z = pos[2] };

        // Airport size based on class
        const size: f32 = switch (airport.airport_class) {
            .regional => 2.0,
            .domestic => 3.5,
            .international => 5.0,
            .mega_hub => 7.0,
        };

        // Draw airport base
        const color = if (airport.operational_status)
            rl.Color{ .r = 50, .g = 200, .b = 50, .a = 255 }
        else
            rl.Color{ .r = 200, .g = 50, .b = 50, .a = 255 };

        rl.DrawCube(world_pos, size, 0.5, size, color);
        rl.DrawCubeWires(world_pos, size, 0.5, size, rl.WHITE);

        // Draw runways
        rl.DrawLine3D(
            .{ .x = world_pos.x - size, .y = 0.1, .z = world_pos.z },
            .{ .x = world_pos.x + size, .y = 0.1, .z = world_pos.z },
            rl.GRAY,
        );

        // Draw airport code label (billboard)
        const iata_str = std.mem.sliceTo(&airport.iata_code, 0);
        if (iata_str.len > 0) {
            const label_pos = rl.Vector3{
                .x = world_pos.x,
                .y = world_pos.y + 2,
                .z = world_pos.z,
            };
            // Text drawing would be done in 2D overlay
            _ = label_pos;
        }
    }

    fn drawAircraft(self: Renderer, aircraft: entities.Aircraft) void {
        const pos = aircraft.current_position.toWorldSpace(self.world_scale);
        const alt_scale = aircraft.current_altitude / 10000.0; // Scale altitude for visibility

        const world_pos = rl.Vector3{
            .x = pos[0],
            .y = alt_scale * 5.0, // Exaggerate altitude for visibility
            .z = pos[2],
        };

        // Aircraft size based on type
        const size: f32 = switch (aircraft.aircraft_type) {
            .small_cargo => 0.8,
            .medium_cargo => 1.2,
            .large_cargo => 1.8,
            .heavy_cargo => 2.5,
            .super_heavy => 3.0,
        };

        // Color based on status
        const color = switch (aircraft.status) {
            .cruise => rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 },
            .climbing => rl.Color{ .r = 100, .g = 255, .b = 100, .a = 255 },
            .descending => rl.Color{ .r = 255, .g = 200, .b = 100, .a = 255 },
            .approach => rl.Color{ .r = 255, .g = 150, .b = 100, .a = 255 },
            else => rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 },
        };

        // Draw aircraft as a stylized plane shape
        rl.DrawCube(world_pos, size * 1.5, size * 0.3, size * 0.5, color);

        // Draw wings
        const wing_pos = world_pos;
        rl.DrawCube(wing_pos, size * 0.3, size * 0.1, size * 2.0, color);

        // Draw direction indicator
        const heading_rad = aircraft.heading * std.math.pi / 180.0;
        const dir_end = rl.Vector3{
            .x = world_pos.x + @cos(heading_rad) * size * 2,
            .y = world_pos.y,
            .z = world_pos.z + @sin(heading_rad) * size * 2,
        };
        rl.DrawLine3D(world_pos, dir_end, rl.YELLOW);

        // Draw altitude indicator (vertical line to ground)
        rl.DrawLine3D(
            world_pos,
            .{ .x = world_pos.x, .y = 0, .z = world_pos.z },
            rl.Color{ .r = 100, .g = 100, .b = 100, .a = 100 },
        );
    }

    fn drawFlightPath(self: Renderer, plan: flight.FlightPlan) void {
        if (plan.waypoints.items.len < 2) return;

        for (plan.waypoints.items[0 .. plan.waypoints.items.len - 1], 0..) |waypoint, i| {
            const next_waypoint = plan.waypoints.items[i + 1];

            const pos1 = waypoint.position.toWorldSpace(self.world_scale);
            const pos2 = next_waypoint.position.toWorldSpace(self.world_scale);

            const alt1_scale = waypoint.altitude / 10000.0;
            const alt2_scale = next_waypoint.altitude / 10000.0;

            const start = rl.Vector3{
                .x = pos1[0],
                .y = alt1_scale * 5.0,
                .z = pos1[2],
            };

            const end = rl.Vector3{
                .x = pos2[0],
                .y = alt2_scale * 5.0,
                .z = pos2[2],
            };

            // Color based on waypoint type
            const color = switch (waypoint.waypoint_type) {
                .departure => rl.GREEN,
                .climb => rl.LIME,
                .cruise => rl.SKYBLUE,
                .descent => rl.ORANGE,
                .approach => rl.RED,
                .arrival => rl.MAROON,
            };

            rl.DrawLine3D(start, end, color);

            // Draw waypoint marker
            rl.DrawSphere(start, 0.5, color);
        }
    }

    fn drawUI(self: *Renderer, world: *simulation.SimulationWorld) void {
        _ = self;

        // Display simulation info
        const time_hours = world.current_time.seconds / 3600;
        const days = time_hours / 24;
        const hours = @mod(time_hours, 24);

        var buffer: [256]u8 = undefined;
        const time_str = std.fmt.bufPrintZ(
            &buffer,
            "Day {d} - {d:0>2}:00",
            .{ days, hours },
        ) catch "Time Error";

        rl.DrawText(time_str.ptr, 10, 10, 20, rl.WHITE);

        // Flight statistics
        const flight_counts = world.flight_scheduler.getFlightCount();
        const stats_str = std.fmt.bufPrintZ(
            &buffer,
            "Flights - Scheduled: {d} | Active: {d} | Completed: {d}",
            .{ flight_counts.scheduled, flight_counts.active, flight_counts.completed },
        ) catch "Stats Error";

        rl.DrawText(stats_str.ptr, 10, 35, 16, rl.LIGHTGRAY);

        // Aircraft count
        const aircraft_str = std.fmt.bufPrintZ(
            &buffer,
            "Aircraft: {d} | Airports: {d} | Cargo: {d}",
            .{ world.aircraft.items.len, world.airports.items.len, world.cargo.items.len },
        ) catch "Entity Error";

        rl.DrawText(aircraft_str.ptr, 10, 55, 16, rl.LIGHTGRAY);

        // Market condition
        const market_str = switch (world.market_condition) {
            .recession => "Market: RECESSION",
            .slow => "Market: SLOW",
            .normal => "Market: NORMAL",
            .growth => "Market: GROWTH",
            .boom => "Market: BOOM",
        };

        rl.DrawText(market_str.ptr, 10, 75, 16, rl.GOLD);

        // Camera controls help
        rl.DrawText("Controls: Arrows=Rotate | Mouse Wheel=Zoom | Space=Pause", 10, 105, 14, rl.DARKGRAY);

        // Financial summary
        const total_revenue = world.stats.total_revenue.toDollars();
        const total_costs = world.stats.total_costs.toDollars();
        const profit = total_revenue - total_costs;

        const finance_str = std.fmt.bufPrintZ(
            &buffer,
            "Revenue: ${d:.2} | Costs: ${d:.2} | Profit: ${d:.2}",
            .{ total_revenue, total_costs, profit },
        ) catch "Finance Error";

        const profit_color = if (profit >= 0) rl.GREEN else rl.RED;
        rl.DrawText(finance_str.ptr, 10, 125, 16, profit_color);
    }
};

pub fn initWindow() void {
    rl.InitWindow(1600, 900, "Aviation Transport Simulation");
    rl.SetTargetFPS(60);
}

pub fn closeWindow() void {
    rl.CloseWindow();
}

pub fn shouldClose() bool {
    return rl.WindowShouldClose();
}
