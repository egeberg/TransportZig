const std = @import("std");
const capy = @import("capy");
const types = @import("types.zig");
const entities = @import("entities.zig");
const simulation = @import("simulation.zig");
const analytics = @import("analytics.zig");

// ============================================================================
// CAPY UI - BUSINESS DASHBOARD
// ============================================================================

pub const BusinessDashboard = struct {
    allocator: std.mem.Allocator,
    window: *capy.Window,

    // Dashboard panels
    kpi_panel: *capy.Container,
    flight_table: *capy.Container,
    airport_panel: *capy.Container,
    weather_panel: *capy.Container,
    notam_panel: *capy.Container,
    control_panel: *capy.Container,

    // Data labels (for updates)
    revenue_label: *capy.Label,
    profit_label: *capy.Label,
    flights_label: *capy.Label,
    utilization_label: *capy.Label,

    // State
    is_paused: bool,
    show_3d_view: bool,

    pub fn init(allocator: std.mem.Allocator) !BusinessDashboard {
        // Create main window
        var window = try capy.Window.init();

        try window.set(.{
            .title = "Aviation Transport Simulation - Business Dashboard",
            .width = 1400,
            .height = 900,
        });

        // Create dashboard layout
        const main_layout = try capy.column(.{
            .spacing = 10,
        }, .{
            try createHeaderBar(allocator),
            try capy.row(.{ .spacing = 10 }, .{
                try createKPIPanel(allocator),
                try createFlightPanel(allocator),
            }),
            try capy.row(.{ .spacing = 10 }, .{
                try createAirportPanel(allocator),
                try createWeatherPanel(allocator),
                try createNotamPanel(allocator),
            }),
            try createControlPanel(allocator),
        });

        try window.set(.{ .child = main_layout });

        return BusinessDashboard{
            .allocator = allocator,
            .window = window,
            .kpi_panel = undefined,
            .flight_table = undefined,
            .airport_panel = undefined,
            .weather_panel = undefined,
            .notam_panel = undefined,
            .control_panel = undefined,
            .revenue_label = undefined,
            .profit_label = undefined,
            .flights_label = undefined,
            .utilization_label = undefined,
            .is_paused = false,
            .show_3d_view = false,
        };
    }

    pub fn show(self: *BusinessDashboard) !void {
        self.window.show();
    }

    pub fn update(self: *BusinessDashboard, world: *simulation.SimulationWorld) !void {
        // Update KPIs
        const kpis = analytics.KPIs.calculate(world);

        try self.revenue_label.set(.{
            .text = try std.fmt.allocPrint(self.allocator, "${d:.2}", .{kpis.total_revenue.toDollars()})
        });

        try self.profit_label.set(.{
            .text = try std.fmt.allocPrint(self.allocator, "${d:.2} ({d:.1}%)", .{
                kpis.gross_profit.toDollars(),
                kpis.profit_margin_percent,
            })
        });

        try self.flights_label.set(.{
            .text = try std.fmt.allocPrint(self.allocator, "Active: {d} | Completed: {d}", .{
                world.flight_scheduler.active_flights.items.len,
                world.flight_scheduler.completed_flights.items.len,
            })
        });

        try self.utilization_label.set(.{
            .text = try std.fmt.allocPrint(self.allocator, "{d:.1}%", .{kpis.fleet_utilization_percent})
        });

        // Update flight table
        try self.updateFlightTable(world);

        // Update airport status
        try self.updateAirportPanel(world);

        // Update weather panel
        try self.updateWeatherPanel(world);

        // Update NOTAM panel
        try self.updateNotamPanel(world);
    }

    fn createHeaderBar(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.row(.{
            .spacing = 20,
        }, .{
            try capy.label(.{
                .text = "🛫 Aviation Transport Simulation",
                .font = .{ .size = 24, .weight = .bold },
            }),
            try capy.label(.{
                .text = "Business Dashboard",
                .font = .{ .size = 18 },
            }),
        });
    }

    fn createKPIPanel(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.column(.{
            .spacing = 10,
        }, .{
            try capy.label(.{
                .text = "Key Performance Indicators",
                .font = .{ .weight = .bold },
            }),
            try capy.row(.{ .spacing = 10 }, .{
                try createKPICard("Total Revenue", "$0.00", .blue),
                try createKPICard("Gross Profit", "$0.00", .green),
            }),
            try capy.row(.{ .spacing = 10 }, .{
                try createKPICard("Flights", "0", .purple),
                try createKPICard("Fleet Utilization", "0%", .orange),
            }),
        });
    }

    fn createKPICard(title: []const u8, value: []const u8, color: capy.Color) !*capy.Container {
        return try capy.column(.{
            .spacing = 5,
            .background = color.lighter(0.9),
            .padding = 15,
            .borderRadius = 8,
        }, .{
            try capy.label(.{
                .text = title,
                .font = .{ .size = 12 },
            }),
            try capy.label(.{
                .text = value,
                .font = .{ .size = 20, .weight = .bold },
            }),
        });
    }

    fn createFlightPanel(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.column(.{
            .spacing = 10,
        }, .{
            try capy.label(.{
                .text = "Active Flights",
                .font = .{ .weight = .bold },
            }),
            try capy.scrollable(.{
                .child = try capy.column(.{ .spacing = 5 }, .{
                    try createFlightRow("SFC001", "JFK", "LAX", "In Flight", 65.0),
                    try createFlightRow("SFC002", "ORD", "ATL", "Boarding", 0.0),
                    try createFlightRow("SFC003", "DFW", "JFK", "Scheduled", 0.0),
                }),
            }),
        });
    }

    fn createFlightRow(callsign: []const u8, origin: []const u8, dest: []const u8, status: []const u8, progress: f32) !*capy.Container {
        return try capy.row(.{
            .spacing = 10,
            .padding = 8,
            .background = .{ .r = 240, .g = 240, .b = 250, .a = 255 },
            .borderRadius = 4,
        }, .{
            try capy.label(.{ .text = callsign, .font = .{ .weight = .bold } }),
            try capy.label(.{ .text = origin }),
            try capy.label(.{ .text = "→" }),
            try capy.label(.{ .text = dest }),
            try capy.label(.{ .text = status }),
            try capy.progressBar(.{ .value = progress }),
        });
    }

    fn createAirportPanel(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.column(.{
            .spacing = 10,
        }, .{
            try capy.label(.{
                .text = "Airport Status",
                .font = .{ .weight = .bold },
            }),
            try capy.scrollable(.{
                .child = try capy.column(.{ .spacing = 5 }, .{
                    try createAirportRow("JFK", "Operational", 95, 150),
                    try createAirportRow("LAX", "Operational", 120, 200),
                    try createAirportRow("ORD", "Operational", 85, 150),
                }),
            }),
        });
    }

    fn createAirportRow(code: []const u8, status: []const u8, available_slots: u32, total_slots: u32) !*capy.Container {
        return try capy.row(.{
            .spacing = 10,
            .padding = 8,
        }, .{
            try capy.label(.{ .text = code, .font = .{ .weight = .bold } }),
            try capy.label(.{ .text = status }),
            try capy.label(.{ .text = try std.fmt.allocPrint(std.heap.page_allocator, "Slots: {d}/{d}", .{available_slots, total_slots}) }),
        });
    }

    fn createWeatherPanel(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.column(.{
            .spacing = 10,
        }, .{
            try capy.label(.{
                .text = "Weather Conditions",
                .font = .{ .weight = .bold },
            }),
            try capy.scrollable(.{
                .child = try capy.column(.{ .spacing = 5 }, .{
                    try createWeatherRow("JFK", "Clear", 15.0, 12.0, 10.0),
                    try createWeatherRow("LAX", "Light Clouds", 22.0, 8.0, 10.0),
                    try createWeatherRow("ORD", "Rain", 10.0, 25.0, 5.0),
                }),
            }),
        });
    }

    fn createWeatherRow(code: []const u8, condition: []const u8, temp: f32, wind: f32, vis: f32) !*capy.Container {
        return try capy.row(.{
            .spacing = 10,
            .padding = 8,
        }, .{
            try capy.label(.{ .text = code, .font = .{ .weight = .bold } }),
            try capy.label(.{ .text = condition }),
            try capy.label(.{ .text = try std.fmt.allocPrint(std.heap.page_allocator, "{d:.1}°C", .{temp}) }),
            try capy.label(.{ .text = try std.fmt.allocPrint(std.heap.page_allocator, "Wind: {d:.0} km/h", .{wind}) }),
            try capy.label(.{ .text = try std.fmt.allocPrint(std.heap.page_allocator, "Vis: {d:.1} km", .{vis}) }),
        });
    }

    fn createNotamPanel(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.column(.{
            .spacing = 10,
        }, .{
            try capy.label(.{
                .text = "Active NOTAMs",
                .font = .{ .weight = .bold },
            }),
            try capy.scrollable(.{
                .child = try capy.column(.{ .spacing = 5 }, .{
                    try createNotamRow("JFK", "Construction", "MEDIUM", "TWY B partially closed"),
                    try createNotamRow("LAX", "Lighting", "LOW", "Approach lights limited"),
                    try createNotamRow("ORD", "Closure", "HIGH", "RWY 10L/28R closed"),
                }),
            }),
        });
    }

    fn createNotamRow(airport: []const u8, category: []const u8, severity: []const u8, message: []const u8) !*capy.Container {
        const color = if (std.mem.eql(u8, severity, "HIGH"))
            capy.Color{ .r = 255, .g = 200, .b = 200, .a = 255 }
        else if (std.mem.eql(u8, severity, "MEDIUM"))
            capy.Color{ .r = 255, .g = 240, .b = 200, .a = 255 }
        else
            capy.Color{ .r = 240, .g = 240, .b = 240, .a = 255 };

        return try capy.row(.{
            .spacing = 10,
            .padding = 8,
            .background = color,
            .borderRadius = 4,
        }, .{
            try capy.label(.{ .text = airport, .font = .{ .weight = .bold } }),
            try capy.label(.{ .text = category }),
            try capy.label(.{ .text = severity }),
            try capy.label(.{ .text = message }),
        });
    }

    fn createControlPanel(allocator: std.mem.Allocator) !*capy.Container {
        _ = allocator;
        return try capy.row(.{
            .spacing = 10,
            .padding = 10,
        }, .{
            try capy.button(.{
                .label = "⏸ Pause/Resume",
                .onClick = onPauseClick,
            }),
            try capy.button(.{
                .label = "📊 Analytics Report",
                .onClick = onAnalyticsClick,
            }),
            try capy.button(.{
                .label = "🌍 3D View",
                .onClick = on3DViewClick,
            }),
            try capy.button(.{
                .label = "💾 Export Data",
                .onClick = onExportClick,
            }),
            try capy.button(.{
                .label = "⚙️ Settings",
                .onClick = onSettingsClick,
            }),
        });
    }

    fn updateFlightTable(self: *BusinessDashboard, world: *simulation.SimulationWorld) !void {
        // Clear and rebuild flight table with current data
        _ = self;
        _ = world;
        // Implementation would rebuild the flight list dynamically
    }

    fn updateAirportPanel(self: *BusinessDashboard, world: *simulation.SimulationWorld) !void {
        _ = self;
        _ = world;
        // Update airport status dynamically
    }

    fn updateWeatherPanel(self: *BusinessDashboard, world: *simulation.SimulationWorld) !void {
        _ = self;
        _ = world;
        // Update weather information dynamically
    }

    fn updateNotamPanel(self: *BusinessDashboard, world: *simulation.SimulationWorld) !void {
        _ = self;
        _ = world;
        // Update NOTAM list dynamically
    }

    // Button callbacks
    fn onPauseClick() void {
        std.debug.print("Pause/Resume clicked\n", .{});
    }

    fn onAnalyticsClick() void {
        std.debug.print("Analytics Report clicked\n", .{});
    }

    fn on3DViewClick() void {
        std.debug.print("3D View clicked\n", .{});
    }

    fn onExportClick() void {
        std.debug.print("Export Data clicked\n", .{});
    }

    fn onSettingsClick() void {
        std.debug.print("Settings clicked\n", .{});
    }
};

/// Initialize Capy UI backend
pub fn initUI() !void {
    try capy.backend.init();
}

/// Run Capy UI event loop
pub fn runUI() !void {
    try capy.runEventLoop();
}

/// Cleanup Capy UI
pub fn deinitUI() void {
    capy.backend.deinit();
}
