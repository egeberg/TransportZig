const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");
const simulation = @import("simulation.zig");
const flight = @import("flight.zig");
const iot = @import("iot.zig");
// const renderer = @import("renderer.zig"); // Optional: requires raylib
const analytics = @import("analytics.zig");
const weather = @import("weather.zig");
const notam = @import("notam.zig");
// const ui = @import("ui.zig"); // Optional: requires Capy UI

// ============================================================================
// AVIATION TRANSPORT SIMULATION - MAIN APPLICATION
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Aviation Transport Simulation ===\n", .{});
    std.debug.print("Initializing business application...\n\n", .{});

    // Check for Weather API key from environment
    const weather_api_key = std.process.getEnvVarOwned(allocator, "OPENWEATHER_API_KEY") catch null;
    defer if (weather_api_key) |key| allocator.free(key);

    // Initialize simulation world
    var world = if (weather_api_key) |key| blk: {
        std.debug.print("✓ Weather API key found - using real-world weather data\n", .{});
        break :blk simulation.SimulationWorld.initWithWeatherAPI(allocator, key);
    } else blk: {
        std.debug.print("⚠ No Weather API key - using simulated weather data\n", .{});
        std.debug.print("  Set OPENWEATHER_API_KEY environment variable for real data\n", .{});
        break :blk simulation.SimulationWorld.init(allocator);
    };
    defer world.deinit();

    // Initialize IoT data aggregator
    var iot_aggregator = iot.IoTDataAggregator.init(allocator);
    defer iot_aggregator.deinit();

    // Set up demo scenario
    try setupDemoScenario(&world, &iot_aggregator);

    // Simulation state
    var last_analytics_time: u64 = 0;
    const simulation_days = 30; // Run for 30 simulated days

    std.debug.print("Simulation initialized successfully!\n", .{});
    std.debug.print("Running headless simulation for {d} days...\n\n", .{simulation_days});

    // Main application loop (headless mode)
    var updates: u32 = 0;
    const updates_per_day = 60 * 60 * 24; // Simulate 24 hours per day
    const max_updates = updates_per_day * simulation_days;

    while (updates < max_updates) : (updates += 1) {
        const delta = 1.0; // 1 second per update

        // Update simulation
        try world.update(delta);

        // Collect IoT telemetry periodically
        if (@mod(updates, 3600) == 0) { // Every hour
            try iot_aggregator.collectAllTelemetry(
                world.aircraft.items,
                world.airports.items,
                world.current_time,
            );
        }

        // Print analytics every 10 simulation days
        const current_day = world.current_time.seconds / 86400;
        if (current_day > 0 and current_day != last_analytics_time and @mod(current_day, 10) == 0) {
            last_analytics_time = current_day;
            printAnalytics(&world, &iot_aggregator);
        }

        // Print progress
        if (@mod(updates, updates_per_day) == 0) {
            std.debug.print("Day {d}/{d} completed\n", .{ updates / updates_per_day, simulation_days });
        }
    }

    // Final report
    std.debug.print("\n\n=== FINAL SIMULATION REPORT ===\n", .{});
    const final_kpis = analytics.KPIs.calculate(&world);
    final_kpis.printReport();

    // IoT Analytics
    const iot_analytics = iot_aggregator.generateAnalytics();
    std.debug.print("IoT Analytics:\n", .{});
    std.debug.print("  Aircraft Tracked: {d}\n", .{iot_analytics.total_aircraft_tracked});
    std.debug.print("  Airports Monitored: {d}\n", .{iot_analytics.total_airports_monitored});
    std.debug.print("  Total Sensors: {d}\n", .{iot_analytics.total_sensors});
    std.debug.print("  Data Points Collected: {d}\n", .{iot_analytics.total_data_points});

    std.debug.print("\nSimulation completed successfully!\n", .{});
}

fn setupDemoScenario(world: *simulation.SimulationWorld, iot_agg: *iot.IoTDataAggregator) !void {
    std.debug.print("Setting up demo scenario...\n", .{});

    // Create major airports
    const jfk_id = try world.createAirport(
        [_]u8{ 'K', 'J', 'F', 'K' },
        [_]u8{ 'J', 'F', 'K' },
        "John F. Kennedy International",
        types.Coordinates{ .latitude = 40.6413, .longitude = -73.7781 },
        .mega_hub,
    );
    try iot_agg.registerAirport(jfk_id);

    const lax_id = try world.createAirport(
        [_]u8{ 'K', 'L', 'A', 'X' },
        [_]u8{ 'L', 'A', 'X' },
        "Los Angeles International",
        types.Coordinates{ .latitude = 33.9416, .longitude = -118.4085 },
        .mega_hub,
    );
    try iot_agg.registerAirport(lax_id);

    const ord_id = try world.createAirport(
        [_]u8{ 'K', 'O', 'R', 'D' },
        [_]u8{ 'O', 'R', 'D' },
        "O'Hare International",
        types.Coordinates{ .latitude = 41.9742, .longitude = -87.9073 },
        .mega_hub,
    );
    try iot_agg.registerAirport(ord_id);

    const dfw_id = try world.createAirport(
        [_]u8{ 'K', 'D', 'F', 'W' },
        [_]u8{ 'D', 'F', 'W' },
        "Dallas/Fort Worth International",
        types.Coordinates{ .latitude = 32.8998, .longitude = -97.0403 },
        .international,
    );
    try iot_agg.registerAirport(dfw_id);

    const atl_id = try world.createAirport(
        [_]u8{ 'K', 'A', 'T', 'L' },
        [_]u8{ 'A', 'T', 'L' },
        "Hartsfield-Jackson Atlanta International",
        types.Coordinates{ .latitude = 33.6407, .longitude = -84.4277 },
        .mega_hub,
    );
    try iot_agg.registerAirport(atl_id);

    std.debug.print("  Created {d} airports\n", .{world.airports.items.len});

    // Create airline company
    const company_id = try world.createCompany("SkyFreight Cargo", types.Money.init(50_000_000));
    std.debug.print("  Created company: SkyFreight Cargo\n", .{});

    // Create fleet
    const aircraft1 = try world.createAircraft(
        [_]u8{ 'N', '1', '2', '3', 'C', 'F', 0, 0 },
        .heavy_cargo,
        company_id,
    );
    try iot_agg.registerAircraft(aircraft1);

    const aircraft2 = try world.createAircraft(
        [_]u8{ 'N', '4', '5', '6', 'C', 'F', 0, 0 },
        .large_cargo,
        company_id,
    );
    try iot_agg.registerAircraft(aircraft2);

    const aircraft3 = try world.createAircraft(
        [_]u8{ 'N', '7', '8', '9', 'C', 'F', 0, 0 },
        .medium_cargo,
        company_id,
    );
    try iot_agg.registerAircraft(aircraft3);

    std.debug.print("  Created {d} aircraft\n", .{world.aircraft.items.len});

    // Create crew members
    _ = try world.createCrewMember(.captain, 8);
    _ = try world.createCrewMember(.first_officer, 6);
    _ = try world.createCrewMember(.flight_engineer, 5);
    _ = try world.createCrewMember(.captain, 7);
    _ = try world.createCrewMember(.first_officer, 5);
    _ = try world.createCrewMember(.flight_engineer, 4);

    std.debug.print("  Created {d} crew members\n", .{world.crew_members.items.len});

    // Create cargo shipments
    _ = try world.createCargo(.general_freight, 5000, 40, jfk_id, lax_id, 1);
    _ = try world.createCargo(.express_mail, 800, 10, jfk_id, ord_id, 1);
    _ = try world.createCargo(.perishable, 3000, 25, lax_id, atl_id, 1);
    _ = try world.createCargo(.valuable_cargo, 500, 5, ord_id, dfw_id, 1);
    _ = try world.createCargo(.medical_supplies, 1200, 15, dfw_id, jfk_id, 1);

    std.debug.print("  Created {d} cargo shipments\n", .{world.cargo.items.len});

    // Create flight plans
    const flight1 = try world.createFlightPlan(
        [_]u8{ 'S', 'F', 'C', '0', '0', '1', 0, 0 },
        aircraft1,
        jfk_id,
        lax_id,
        types.SimTime{ .seconds = 3600 },
    );

    const flight2 = try world.createFlightPlan(
        [_]u8{ 'S', 'F', 'C', '0', '0', '2', 0, 0 },
        aircraft2,
        ord_id,
        atl_id,
        types.SimTime{ .seconds = 7200 },
    );

    const flight3 = try world.createFlightPlan(
        [_]u8{ 'S', 'F', 'C', '0', '0', '3', 0, 0 },
        aircraft3,
        dfw_id,
        jfk_id,
        types.SimTime{ .seconds = 10800 },
    );

    std.debug.print("  Created {d} flight plans\n", .{world.flight_scheduler.scheduled_flights.items.len});

    // Launch first flight immediately
    _ = try world.launchFlight(flight1);
    std.debug.print("  Launched flight SFC001\n", .{});

    // Schedule other flights to launch later
    _ = flight2;
    _ = flight3;

    std.debug.print("Demo scenario setup complete!\n\n", .{});
}

fn printAnalytics(world: *simulation.SimulationWorld, iot_agg: *iot.IoTDataAggregator) void {
    const kpis = analytics.KPIs.calculate(world);
    kpis.printReport();

    // Generate recommendations
    var recommendations = analytics.DecisionSupport.analyzeAndRecommend(
        world.allocator,
        world,
    ) catch return;
    defer recommendations.deinit();

    if (recommendations.items.len > 0) {
        std.debug.print("RECOMMENDATIONS:\n", .{});
        for (recommendations.items) |rec| {
            const priority_str = switch (rec.priority) {
                .low => "LOW",
                .medium => "MEDIUM",
                .high => "HIGH",
                .critical => "CRITICAL",
            };
            std.debug.print("  [{s}] {s}\n", .{ priority_str, rec.message });
            std.debug.print("    Estimated Impact: ${d:.2}\n", .{rec.estimated_impact});
        }
        std.debug.print("\n", .{});
    }

    // IoT summary
    const iot_analytics = iot_agg.generateAnalytics();
    std.debug.print("IoT STATUS:\n", .{});
    std.debug.print("  Active telemetry streams: {d}\n", .{iot_analytics.total_aircraft_tracked});
    std.debug.print("  Sensor networks: {d}\n", .{iot_analytics.total_airports_monitored});
    std.debug.print("  Operational sensors: {d}/{d}\n", .{
        iot_analytics.sensors_operational,
        iot_analytics.total_sensors,
    });
    std.debug.print("\n", .{});

    // Weather summary
    std.debug.print("WEATHER STATUS:\n", .{});
    for (world.airports.items) |airport| {
        std.debug.print("  {s}: {d:.1}°C, Wind {d:.0} km/h, Vis {d:.1} km - {s}\n", .{
            std.mem.sliceTo(&airport.iata_code, 0),
            airport.sensors.temperature,
            airport.sensors.wind_speed,
            airport.sensors.visibility,
            @tagName(airport.weather),
        });
    }
    std.debug.print("\n", .{});

    // NOTAM summary
    std.debug.print("NOTAM STATUS:\n", .{});
    var total_notams: u32 = 0;
    var critical_notams: u32 = 0;
    for (world.airports.items) |airport| {
        if (world.notam_service.cache.get(airport.id)) |airport_notams| {
            total_notams += airport_notams.active_count;
            critical_notams += airport_notams.critical_count;

            if (airport_notams.active_count > 0) {
                std.debug.print("  {s}: {d} active NOTAMs", .{
                    std.mem.sliceTo(&airport.iata_code, 0),
                    airport_notams.active_count,
                });
                if (airport_notams.critical_count > 0) {
                    std.debug.print(" ({d} CRITICAL)", .{airport_notams.critical_count});
                }
                std.debug.print("\n", .{});
            }
        }
    }
    std.debug.print("  Total: {d} active NOTAMs ({d} critical)\n", .{ total_notams, critical_notams });
    std.debug.print("\n", .{});
}

test "basic simulation test" {
    const allocator = std.testing.allocator;

    var world = simulation.SimulationWorld.init(allocator);
    defer world.deinit();

    // Create test airport
    const airport_id = try world.createAirport(
        [_]u8{ 'T', 'E', 'S', 'T' },
        [_]u8{ 'T', 'S', 'T' },
        "Test Airport",
        types.Coordinates{ .latitude = 0, .longitude = 0 },
        .regional,
    );

    try std.testing.expect(airport_id == 1);
    try std.testing.expect(world.airports.items.len == 1);

    // Create test company
    const company_id = try world.createCompany("Test Airline", types.Money.init(1_000_000));
    try std.testing.expect(company_id == 1);

    // Create test aircraft
    const aircraft_id = try world.createAircraft(
        [_]u8{ 'N', 'T', 'E', 'S', 'T', 0, 0, 0 },
        .small_cargo,
        company_id,
    );

    try std.testing.expect(aircraft_id == 1);
    try std.testing.expect(world.aircraft.items.len == 1);

    // Verify company owns aircraft
    const company = world.getCompanyById(company_id).?;
    try std.testing.expect(company.owned_aircraft.items.len == 1);
}
