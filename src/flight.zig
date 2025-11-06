const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");

// ============================================================================
// FLIGHT MANAGEMENT SYSTEM
// ============================================================================

/// Flight plan defining a route between airports
pub const FlightPlan = struct {
    allocator: std.mem.Allocator,
    id: u32,
    callsign: [8]u8, // e.g., "CRG001"
    aircraft_id: u32,
    departure_airport: u32,
    arrival_airport: u32,

    // Route
    waypoints: std.ArrayList(Waypoint),
    total_distance_km: f32,
    planned_altitude: f32, // meters
    planned_speed: f32, // km/h

    // Timing
    scheduled_departure: types.SimTime,
    estimated_departure: types.SimTime,
    estimated_arrival: types.SimTime,
    scheduled_arrival: types.SimTime,

    // Cargo
    cargo_manifest: std.ArrayList(u32), // Cargo IDs
    total_cargo_weight: f32, // tons
    total_cargo_volume: f32, // m3

    // Crew assignment
    assigned_crew: std.ArrayList(u32), // Crew member IDs

    // Status
    status: types.FlightStatus,
    weather_forecast: types.WeatherCondition,

    // Economics
    estimated_cost: types.Money,
    estimated_revenue: types.Money,

    pub const Waypoint = struct {
        position: types.Coordinates,
        name: [8]u8,
        waypoint_type: WaypointType,
        altitude: f32,
        speed: f32,

        pub const WaypointType = enum {
            departure,
            climb,
            cruise,
            descent,
            approach,
            arrival,
        };
    };

    pub fn init(allocator: std.mem.Allocator, id: u32, callsign: [8]u8, aircraft_id: u32) FlightPlan {
        return .{
            .allocator = allocator,
            .id = id,
            .callsign = callsign,
            .aircraft_id = aircraft_id,
            .departure_airport = 0,
            .arrival_airport = 0,
            .waypoints = std.ArrayList(Waypoint){},
            .total_distance_km = 0,
            .planned_altitude = 10000, // 10km default cruise altitude
            .planned_speed = 800,
            .scheduled_departure = types.SimTime{ .seconds = 0 },
            .estimated_departure = types.SimTime{ .seconds = 0 },
            .estimated_arrival = types.SimTime{ .seconds = 0 },
            .scheduled_arrival = types.SimTime{ .seconds = 0 },
            .cargo_manifest = std.ArrayList(u32){},
            .total_cargo_weight = 0,
            .total_cargo_volume = 0,
            .assigned_crew = std.ArrayList(u32){},
            .status = .scheduled,
            .weather_forecast = .clear,
            .estimated_cost = types.Money.init(0),
            .estimated_revenue = types.Money.init(0),
        };
    }

    pub fn deinit(self: *FlightPlan) void {
        self.waypoints.deinit();
        self.cargo_manifest.deinit();
        self.assigned_crew.deinit();
    }

    pub fn calculateRoute(
        self: *FlightPlan,
        departure: entities.Airport,
        arrival: entities.Airport,
        aircraft_type: types.AircraftType,
    ) !void {
        self.departure_airport = departure.id;
        self.arrival_airport = arrival.id;
        self.total_distance_km = departure.distanceTo(arrival);

        // Calculate cruise altitude (higher for longer flights)
        self.planned_altitude = if (self.total_distance_km < 500)
            7000 // 7km for short flights
        else if (self.total_distance_km < 2000)
            10000 // 10km for medium flights
        else
            11000; // 11km for long flights

        self.planned_speed = aircraft_type.cruiseSpeed();

        // Create waypoints
        try self.waypoints.append(self.allocator, .{
            .position = departure.location,
            .name = departure.icao_code,
            .waypoint_type = .departure,
            .altitude = 0,
            .speed = 250, // 250 km/h takeoff speed
        });

        // Climb waypoint (20% of route)
        const climb_factor = 0.2;
        try self.waypoints.append(self.allocator, .{
            .position = self.interpolatePosition(departure.location, arrival.location, climb_factor),
            .name = [_]u8{ 'C', 'L', 'I', 'M', 'B', 0, 0, 0 },
            .waypoint_type = .climb,
            .altitude = self.planned_altitude,
            .speed = self.planned_speed * 0.8,
        });

        // Cruise waypoint (60% of route)
        const cruise_factor = 0.6;
        try self.waypoints.append(self.allocator, .{
            .position = self.interpolatePosition(departure.location, arrival.location, cruise_factor),
            .name = [_]u8{ 'C', 'R', 'U', 'I', 'S', 'E', 0, 0 },
            .waypoint_type = .cruise,
            .altitude = self.planned_altitude,
            .speed = self.planned_speed,
        });

        // Descent waypoint (90% of route)
        const descent_factor = 0.9;
        try self.waypoints.append(self.allocator, .{
            .position = self.interpolatePosition(departure.location, arrival.location, descent_factor),
            .name = [_]u8{ 'D', 'E', 'S', 'C', 'N', 'D', 0, 0 },
            .waypoint_type = .descent,
            .altitude = 1000,
            .speed = 400,
        });

        // Arrival waypoint
        try self.waypoints.append(self.allocator, .{
            .position = arrival.location,
            .name = arrival.icao_code,
            .waypoint_type = .arrival,
            .altitude = 0,
            .speed = 250,
        });

        // Calculate estimated times
        const flight_hours = self.total_distance_km / self.planned_speed;
        self.estimated_arrival = self.scheduled_departure.addHours(@intFromFloat(@ceil(flight_hours)));
        self.scheduled_arrival = self.estimated_arrival;
    }

    fn interpolatePosition(self: FlightPlan, start: types.Coordinates, end: types.Coordinates, factor: f32) types.Coordinates {
        _ = self;
        return .{
            .latitude = start.latitude + (end.latitude - start.latitude) * factor,
            .longitude = start.longitude + (end.longitude - start.longitude) * factor,
            .altitude = 0,
        };
    }

    pub fn addCargo(self: *FlightPlan, cargo_id: u32, weight_tons: f32, volume_m3: f32) !bool {
        self.total_cargo_weight += weight_tons;
        self.total_cargo_volume += volume_m3;
        try self.cargo_manifest.append(self.allocator, cargo_id);
        return true;
    }

    pub fn estimateCosts(
        self: *FlightPlan,
        aircraft: types.AircraftType,
        departure: types.AirportClass,
        arrival: types.AirportClass,
        fuel_pricing: economics.FuelPricing,
        crew: []const economics.CrewEconomics.CrewMember,
    ) void {
        const weather_multiplier = self.weather_forecast.fuelConsumptionMultiplier();

        const costs = economics.FlightEconomics.calculateTotalFlightCost(
            aircraft,
            self.total_distance_km,
            departure,
            arrival,
            crew,
            weather_multiplier,
            fuel_pricing,
            self.scheduled_departure,
        );

        self.estimated_cost = costs.total();
    }

    pub fn estimateRevenue(self: *FlightPlan, market: types.MarketCondition, cargo_list: []const entities.Cargo) void {
        var revenue = types.Money.init(0);
        for (cargo_list) |cargo| {
            const cargo_revenue = economics.RevenueModel.calculateCargoRevenue(
                cargo.cargo_type,
                cargo.weight_kg,
                self.total_distance_km,
                market,
            );
            revenue = revenue.add(cargo_revenue);
        }
        self.estimated_revenue = revenue;
    }

    pub fn isProfitable(self: FlightPlan) bool {
        return !self.estimated_revenue.subtract(self.estimated_cost).isNegative();
    }

    pub fn getEstimatedProfit(self: FlightPlan) types.Money {
        return self.estimated_revenue.subtract(self.estimated_cost);
    }
};

/// Active flight tracking
pub const ActiveFlight = struct {
    flight_plan: FlightPlan,

    // Real-time status
    actual_departure_time: types.SimTime,
    current_waypoint_index: usize,
    progress: f32, // 0.0 to 1.0
    current_position: types.Coordinates,
    current_altitude: f32,
    current_speed: f32,
    heading: f32,

    // Actual costs
    fuel_consumed: f32,
    actual_cost: types.Money,

    // Delays
    delay_minutes: u32,
    delay_reason: ?DelayReason,

    pub const DelayReason = enum {
        weather,
        maintenance,
        crew_unavailable,
        airport_congestion,
        cargo_loading,
        air_traffic_control,
    };

    pub fn init(flight_plan: FlightPlan, departure_time: types.SimTime) ActiveFlight {
        const start_pos = if (flight_plan.waypoints.items.len > 0)
            flight_plan.waypoints.items[0].position
        else
            types.Coordinates{ .latitude = 0, .longitude = 0 };

        return .{
            .flight_plan = flight_plan,
            .actual_departure_time = departure_time,
            .current_waypoint_index = 0,
            .progress = 0.0,
            .current_position = start_pos,
            .current_altitude = 0,
            .current_speed = 0,
            .heading = 0,
            .fuel_consumed = 0,
            .actual_cost = types.Money.init(0),
            .delay_minutes = 0,
            .delay_reason = null,
        };
    }

    pub fn update(self: *ActiveFlight, current_time: types.SimTime, _: f32) void {
        const elapsed = current_time.elapsedHours(self.actual_departure_time);
        const total_flight_hours = self.flight_plan.total_distance_km / self.flight_plan.planned_speed;

        if (elapsed >= total_flight_hours) {
            self.progress = 1.0;
            self.flight_plan.status = .landed;
            return;
        }

        self.progress = @min(1.0, @as(f32, @floatCast(elapsed / total_flight_hours)));

        // Update position along route
        if (self.flight_plan.waypoints.items.len >= 2) {
            const total_waypoints = self.flight_plan.waypoints.items.len;
            const waypoint_progress = self.progress * @as(f32, @floatFromInt(total_waypoints - 1));
            self.current_waypoint_index = @min(
                total_waypoints - 2,
                @as(usize, @intFromFloat(@floor(waypoint_progress))),
            );

            const local_progress = waypoint_progress - @floor(waypoint_progress);
            const wp1 = self.flight_plan.waypoints.items[self.current_waypoint_index];
            const wp2 = self.flight_plan.waypoints.items[self.current_waypoint_index + 1];

            self.current_position = .{
                .latitude = wp1.position.latitude + (wp2.position.latitude - wp1.position.latitude) * local_progress,
                .longitude = wp1.position.longitude + (wp2.position.longitude - wp1.position.longitude) * local_progress,
            };
            self.current_altitude = wp1.altitude + (wp2.altitude - wp1.altitude) * local_progress;
            self.current_speed = wp1.speed + (wp2.speed - wp1.speed) * local_progress;

            // Calculate heading
            const dlat = wp2.position.latitude - wp1.position.latitude;
            const dlon = wp2.position.longitude - wp1.position.longitude;
            self.heading = std.math.atan2(dlon, dlat) * 180.0 / std.math.pi;
        }

        // Update flight status based on phase
        if (self.progress < 0.05) {
            self.flight_plan.status = .departed;
        } else if (self.progress < 0.95) {
            self.flight_plan.status = .in_flight;
        } else {
            self.flight_plan.status = .approach;
        }
    }

    pub fn isComplete(self: ActiveFlight) bool {
        return self.progress >= 1.0 or self.flight_plan.status == .landed;
    }

    pub fn getTimeToArrival(self: ActiveFlight, current_time: types.SimTime) f32 {
        const elapsed = current_time.elapsedHours(self.actual_departure_time);
        const total_hours = self.flight_plan.total_distance_km / self.flight_plan.planned_speed;
        return @max(0, @as(f32, @floatCast(total_hours - elapsed)));
    }
};

/// Flight scheduler
pub const FlightScheduler = struct {
    allocator: std.mem.Allocator,
    scheduled_flights: std.ArrayList(FlightPlan),
    active_flights: std.ArrayList(ActiveFlight),
    completed_flights: std.ArrayList(FlightPlan),

    pub fn init(allocator: std.mem.Allocator) FlightScheduler {
        return .{
            .allocator = allocator,
            .scheduled_flights = std.ArrayList(FlightPlan){},
            .active_flights = std.ArrayList(ActiveFlight){},
            .completed_flights = std.ArrayList(FlightPlan){},
        };
    }

    pub fn deinit(self: *FlightScheduler) void {
        for (self.scheduled_flights.items) |*flight| {
            flight.deinit();
        }
        for (self.active_flights.items) |*flight| {
            flight.flight_plan.deinit();
        }
        for (self.completed_flights.items) |*flight| {
            flight.deinit();
        }
        self.scheduled_flights.deinit();
        self.active_flights.deinit();
        self.completed_flights.deinit();
    }

    pub fn addFlight(self: *FlightScheduler, flight: FlightPlan) !void {
        try self.scheduled_flights.append(self.allocator, flight);
    }

    pub fn launchFlight(self: *FlightScheduler, flight_id: u32, current_time: types.SimTime) !bool {
        for (self.scheduled_flights.items, 0..) |flight, i| {
            if (flight.id == flight_id) {
                const active = ActiveFlight.init(flight, current_time);
                try self.active_flights.append(self.allocator, active);
                _ = self.scheduled_flights.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn updateActiveFlights(self: *FlightScheduler, current_time: types.SimTime, delta_seconds: f32) !void {
        var i: usize = 0;
        while (i < self.active_flights.items.len) {
            var flight = &self.active_flights.items[i];
            flight.update(current_time, delta_seconds);

            if (flight.isComplete()) {
                try self.completed_flights.append(self.allocator, flight.flight_plan);
                _ = self.active_flights.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn getFlightCount(self: FlightScheduler) struct { scheduled: usize, active: usize, completed: usize } {
        return .{
            .scheduled = self.scheduled_flights.items.len,
            .active = self.active_flights.items.len,
            .completed = self.completed_flights.items.len,
        };
    }
};
