const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");

// ============================================================================
// IoT INTEGRATION LAYER - Telemetry, Sensors, Real-time Data
// ============================================================================

/// Telemetry data point with timestamp
pub const TelemetryPoint = struct {
    timestamp: types.SimTime,
    sensor_id: []const u8,
    value: TelemetryValue,

    pub const TelemetryValue = union(enum) {
        float: f32,
        int: i32,
        bool: bool,
        position: types.Coordinates,
        string: []const u8,
    };
};

/// Aircraft telemetry stream
pub const AircraftTelemetryStream = struct {
    allocator: std.mem.Allocator,
    aircraft_id: u32,
    update_frequency_hz: f32, // Updates per second
    last_update: types.SimTime,
    data_points: std.ArrayList(TelemetryPoint),

    pub fn init(allocator: std.mem.Allocator, aircraft_id: u32) AircraftTelemetryStream {
        return .{
            .allocator = allocator,
            .aircraft_id = aircraft_id,
            .update_frequency_hz = 1.0, // 1 Hz default
            .last_update = types.SimTime{ .seconds = 0 },
            .data_points = std.ArrayList(TelemetryPoint){},
        };
    }

    pub fn deinit(self: *AircraftTelemetryStream) void {
        self.data_points.deinit(self.allocator);
    }

    pub fn shouldUpdate(self: AircraftTelemetryStream, current_time: types.SimTime) bool {
        const elapsed = current_time.seconds - self.last_update.seconds;
        const update_interval = @as(u64, @intFromFloat(1.0 / self.update_frequency_hz));
        return elapsed >= update_interval;
    }

    pub fn addDataPoint(self: *AircraftTelemetryStream, point: TelemetryPoint) !void {
        try self.data_points.append(self.allocator, point);

        // Keep only last 1000 points to prevent unbounded growth
        if (self.data_points.items.len > 1000) {
            _ = self.data_points.orderedRemove(0);
        }
    }

    pub fn collectTelemetry(self: *AircraftTelemetryStream, aircraft: *const entities.Aircraft, current_time: types.SimTime) !void {
        if (!self.shouldUpdate(current_time)) return;

        // Position
        try self.addDataPoint( .{
            .timestamp = current_time,
            .sensor_id = "position",
            .value = .{ .position = aircraft.current_position },
        });

        // Altitude
        try self.addDataPoint( .{
            .timestamp = current_time,
            .sensor_id = "altitude",
            .value = .{ .float = aircraft.current_altitude },
        });

        // Speed
        try self.addDataPoint( .{
            .timestamp = current_time,
            .sensor_id = "speed",
            .value = .{ .float = aircraft.current_speed },
        });

        // Heading
        try self.addDataPoint( .{
            .timestamp = current_time,
            .sensor_id = "heading",
            .value = .{ .float = aircraft.heading },
        });

        // Fuel
        try self.addDataPoint( .{
            .timestamp = current_time,
            .sensor_id = "fuel_remaining",
            .value = .{ .float = aircraft.telemetry.fuel_remaining },
        });

        // Engine status
        for (aircraft.telemetry.engine_status, 0..) |status, i| {
            const sensor_name = try std.fmt.allocPrint(
                self.allocator,
                "engine_{d}_status",
                .{i},
            );
            defer self.allocator.free(sensor_name);

            try self.addDataPoint( .{
                .timestamp = current_time,
                .sensor_id = sensor_name,
                .value = .{ .bool = status },
            });
        }

        self.last_update = current_time;
    }

    pub fn getLatestValue(self: AircraftTelemetryStream, sensor_id: []const u8) ?TelemetryPoint {
        var i = self.data_points.items.len;
        while (i > 0) {
            i -= 1;
            const point = self.data_points.items[i];
            if (std.mem.eql(u8, point.sensor_id, sensor_id)) {
                return point;
            }
        }
        return null;
    }
};

/// Airport sensor network
pub const AirportSensorNetwork = struct {
    allocator: std.mem.Allocator,
    airport_id: u32,
    sensors: std.ArrayList(Sensor),
    alert_threshold: AlertThresholds,

    pub const Sensor = struct {
        id: []const u8,
        sensor_type: SensorType,
        location: types.Coordinates,
        current_value: f32,
        status: SensorStatus,
        last_maintenance: types.SimTime,

        pub const SensorType = enum {
            weather_station,
            wind_sensor,
            visibility_sensor,
            pressure_sensor,
            temperature_sensor,
            runway_surface_sensor,
            radar,
            camera,
            cargo_scale,
            fuel_level_sensor,
        };

        pub const SensorStatus = enum {
            operational,
            degraded,
            failed,
            maintenance,
        };
    };

    pub const AlertThresholds = struct {
        max_wind_speed: f32 = 60.0, // km/h
        min_visibility: f32 = 1.0, // km
        max_temperature: f32 = 45.0, // celsius
        min_temperature: f32 = -40.0,
    };

    pub fn init(allocator: std.mem.Allocator, airport_id: u32) AirportSensorNetwork {
        return .{
            .allocator = allocator,
            .airport_id = airport_id,
            .sensors = std.ArrayList(Sensor){},
            .alert_threshold = AlertThresholds{},
        };
    }

    pub fn deinit(self: *AirportSensorNetwork) void {
        self.sensors.deinit(self.allocator);
    }

    pub fn addSensor(self: *AirportSensorNetwork, sensor: Sensor) !void {
        try self.sensors.append(self.allocator, sensor);
    }

    pub fn updateSensors(self: *AirportSensorNetwork, airport: *const entities.Airport, current_time: types.SimTime) void {
        for (self.sensors.items) |*sensor| {
            switch (sensor.sensor_type) {
                .weather_station => sensor.current_value = airport.sensors.temperature,
                .wind_sensor => sensor.current_value = airport.sensors.wind_speed,
                .visibility_sensor => sensor.current_value = airport.sensors.visibility,
                .pressure_sensor => sensor.current_value = airport.sensors.barometric_pressure,
                .temperature_sensor => sensor.current_value = airport.sensors.temperature,
                else => {},
            }

            // Simulate sensor degradation
            const hours_since_maintenance = current_time.elapsedHours(sensor.last_maintenance);
            if (hours_since_maintenance > 720) { // 30 days
                sensor.status = .degraded;
            }
        }
    }

    pub fn checkAlerts(self: AirportSensorNetwork, allocator: std.mem.Allocator) std.ArrayList(Alert) {
        var alerts = std.ArrayList(Alert){};

        for (self.sensors.items) |sensor| {
            switch (sensor.sensor_type) {
                .wind_sensor => {
                    if (sensor.current_value > self.alert_threshold.max_wind_speed) {
                        alerts.append(allocator, Alert{
                            .severity = .warning,
                            .message = "High wind speed detected",
                            .sensor_id = sensor.id,
                            .value = sensor.current_value,
                        }) catch {};
                    }
                },
                .visibility_sensor => {
                    if (sensor.current_value < self.alert_threshold.min_visibility) {
                        alerts.append(allocator, Alert{
                            .severity = .critical,
                            .message = "Low visibility",
                            .sensor_id = sensor.id,
                            .value = sensor.current_value,
                        }) catch {};
                    }
                },
                .temperature_sensor => {
                    if (sensor.current_value > self.alert_threshold.max_temperature or
                        sensor.current_value < self.alert_threshold.min_temperature)
                    {
                        alerts.append(allocator, Alert{
                            .severity = .warning,
                            .message = "Extreme temperature",
                            .sensor_id = sensor.id,
                            .value = sensor.current_value,
                        }) catch {};
                    }
                },
                else => {},
            }

            // Sensor health alerts
            if (sensor.status == .failed) {
                alerts.append(allocator, Alert{
                    .severity = .critical,
                    .message = "Sensor failure",
                    .sensor_id = sensor.id,
                    .value = 0,
                }) catch {};
            }
        }

        return alerts;
    }

    pub const Alert = struct {
        severity: AlertSeverity,
        message: []const u8,
        sensor_id: []const u8,
        value: f32,

        pub const AlertSeverity = enum {
            info,
            warning,
            critical,
        };
    };
};

/// IoT data aggregator and analytics
pub const IoTDataAggregator = struct {
    allocator: std.mem.Allocator,
    aircraft_streams: std.ArrayList(AircraftTelemetryStream),
    airport_networks: std.ArrayList(AirportSensorNetwork),

    pub fn init(allocator: std.mem.Allocator) IoTDataAggregator {
        return .{
            .allocator = allocator,
            .aircraft_streams = std.ArrayList(AircraftTelemetryStream){},
            .airport_networks = std.ArrayList(AirportSensorNetwork){},
        };
    }

    pub fn deinit(self: *IoTDataAggregator) void {
        for (self.aircraft_streams.items) |*stream| {
            stream.deinit();
        }
        for (self.airport_networks.items) |*network| {
            network.deinit();
        }
        self.aircraft_streams.deinit(self.allocator);
        self.airport_networks.deinit(self.allocator);
    }

    pub fn registerAircraft(self: *IoTDataAggregator, aircraft_id: u32) !void {
        const stream = AircraftTelemetryStream.init(self.allocator, aircraft_id);
        try self.aircraft_streams.append(self.allocator, stream);
    }

    pub fn registerAirport(self: *IoTDataAggregator, airport_id: u32) !void {
        var network = AirportSensorNetwork.init(self.allocator, airport_id);

        // Add default sensors
        try network.addSensor( .{
            .id = "weather_main",
            .sensor_type = .weather_station,
            .location = types.Coordinates{ .latitude = 0, .longitude = 0 },
            .current_value = 20,
            .status = .operational,
            .last_maintenance = types.SimTime{ .seconds = 0 },
        });

        try network.addSensor( .{
            .id = "wind_main",
            .sensor_type = .wind_sensor,
            .location = types.Coordinates{ .latitude = 0, .longitude = 0 },
            .current_value = 10,
            .status = .operational,
            .last_maintenance = types.SimTime{ .seconds = 0 },
        });

        try network.addSensor( .{
            .id = "visibility_main",
            .sensor_type = .visibility_sensor,
            .location = types.Coordinates{ .latitude = 0, .longitude = 0 },
            .current_value = 10,
            .status = .operational,
            .last_maintenance = types.SimTime{ .seconds = 0 },
        });

        try self.airport_networks.append(self.allocator, network);
    }

    pub fn collectAllTelemetry(
        self: *IoTDataAggregator,
        aircraft_list: []const entities.Aircraft,
        airport_list: []const entities.Airport,
        current_time: types.SimTime,
    ) !void {
        // Collect aircraft telemetry
        for (self.aircraft_streams.items) |*stream| {
            for (aircraft_list) |*aircraft| {
                if (aircraft.id == stream.aircraft_id) {
                    try stream.collectTelemetry(aircraft, current_time);
                    break;
                }
            }
        }

        // Update airport sensors
        for (self.airport_networks.items) |*network| {
            for (airport_list) |*airport| {
                if (airport.id == network.airport_id) {
                    network.updateSensors(airport, current_time);
                    break;
                }
            }
        }
    }

    pub fn getAircraftStream(self: *IoTDataAggregator, aircraft_id: u32) ?*AircraftTelemetryStream {
        for (self.aircraft_streams.items) |*stream| {
            if (stream.aircraft_id == aircraft_id) return stream;
        }
        return null;
    }

    pub fn getAirportNetwork(self: *IoTDataAggregator, airport_id: u32) ?*AirportSensorNetwork {
        for (self.airport_networks.items) |*network| {
            if (network.airport_id == airport_id) return network;
        }
        return null;
    }

    /// Generate analytics report from collected data
    pub fn generateAnalytics(self: IoTDataAggregator) Analytics {
        var analytics = Analytics{
            .total_aircraft_tracked = self.aircraft_streams.items.len,
            .total_airports_monitored = self.airport_networks.items.len,
            .total_sensors = 0,
            .sensors_operational = 0,
            .sensors_degraded = 0,
            .sensors_failed = 0,
            .total_data_points = 0,
        };

        for (self.aircraft_streams.items) |stream| {
            analytics.total_data_points += stream.data_points.items.len;
        }

        for (self.airport_networks.items) |network| {
            analytics.total_sensors += network.sensors.items.len;
            for (network.sensors.items) |sensor| {
                switch (sensor.status) {
                    .operational => analytics.sensors_operational += 1,
                    .degraded => analytics.sensors_degraded += 1,
                    .failed => analytics.sensors_failed += 1,
                    .maintenance => {},
                }
            }
        }

        return analytics;
    }

    pub const Analytics = struct {
        total_aircraft_tracked: usize,
        total_airports_monitored: usize,
        total_sensors: usize,
        sensors_operational: usize,
        sensors_degraded: usize,
        sensors_failed: usize,
        total_data_points: usize,
    };
};

/// Real-time data export for external systems
pub const DataExporter = struct {
    pub fn exportToJSON(allocator: std.mem.Allocator, telemetry: AircraftTelemetryStream) ![]u8 {
        _ = allocator;
        _ = telemetry;
        // Placeholder for JSON export functionality
        return "{}";
    }

    pub fn exportToCSV(allocator: std.mem.Allocator, telemetry: AircraftTelemetryStream) ![]u8 {
        _ = allocator;
        _ = telemetry;
        // Placeholder for CSV export functionality
        return "";
    }
};
