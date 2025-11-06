const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");
const flight = @import("flight.zig");

// ============================================================================
// SIMULATION ENGINE
// ============================================================================

pub const SimulationWorld = struct {
    allocator: std.mem.Allocator,

    // Time management
    current_time: types.SimTime,
    time_scale: f32, // 1.0 = real-time, 60.0 = 1 min per second
    total_runtime_seconds: f64,

    // World entities
    airports: std.ArrayList(entities.Airport),
    aircraft: std.ArrayList(entities.Aircraft),
    cargo: std.ArrayList(entities.Cargo),
    companies: std.ArrayList(entities.Company),
    crew_members: std.ArrayList(economics.CrewEconomics.CrewMember),

    // Flight management
    flight_scheduler: flight.FlightScheduler,

    // Economics
    fuel_pricing: economics.FuelPricing,
    market_condition: types.MarketCondition,

    // Counters for ID generation
    next_airport_id: u32,
    next_aircraft_id: u32,
    next_cargo_id: u32,
    next_company_id: u32,
    next_crew_id: u32,
    next_flight_id: u32,

    // Statistics
    stats: SimulationStats,

    pub fn init(allocator: std.mem.Allocator) SimulationWorld {
        return .{
            .allocator = allocator,
            .current_time = types.SimTime{ .seconds = 0 },
            .time_scale = 60.0, // Default: 1 minute per second
            .total_runtime_seconds = 0,
            .airports = std.ArrayList(entities.Airport).init(allocator),
            .aircraft = std.ArrayList(entities.Aircraft).init(allocator),
            .cargo = std.ArrayList(entities.Cargo).init(allocator),
            .companies = std.ArrayList(entities.Company).init(allocator),
            .crew_members = std.ArrayList(economics.CrewEconomics.CrewMember).init(allocator),
            .flight_scheduler = flight.FlightScheduler.init(allocator),
            .fuel_pricing = economics.FuelPricing.init(),
            .market_condition = .normal,
            .next_airport_id = 1,
            .next_aircraft_id = 1,
            .next_cargo_id = 1,
            .next_company_id = 1,
            .next_crew_id = 1,
            .next_flight_id = 1,
            .stats = SimulationStats.init(),
        };
    }

    pub fn deinit(self: *SimulationWorld) void {
        self.airports.deinit();
        self.aircraft.deinit();
        self.cargo.deinit();
        for (self.companies.items) |*company| {
            company.deinit();
        }
        self.companies.deinit();
        self.crew_members.deinit();
        self.flight_scheduler.deinit();
    }

    /// Main update loop - advances simulation
    pub fn update(self: *SimulationWorld, delta_time_seconds: f32) !void {
        // Advance simulation time
        const sim_delta = @as(u64, @intFromFloat(delta_time_seconds * self.time_scale));
        self.current_time.seconds += sim_delta;
        self.total_runtime_seconds += delta_time_seconds;

        // Update active flights
        try self.flight_scheduler.updateActiveFlights(self.current_time, delta_time_seconds);

        // Update aircraft positions from active flights
        for (self.flight_scheduler.active_flights.items) |*active_flight| {
            for (self.aircraft.items) |*aircraft| {
                if (aircraft.id == active_flight.flight_plan.aircraft_id) {
                    aircraft.updatePosition(
                        active_flight.current_position,
                        active_flight.current_altitude,
                        active_flight.current_speed,
                        active_flight.heading,
                        self.current_time,
                    );
                    aircraft.status = self.flightStatusToAircraftStatus(active_flight.flight_plan.status);
                    break;
                }
            }
        }

        // Update cargo status
        self.updateCargoStatus();

        // Update airport sensors (simulate environmental changes)
        self.updateAirportSensors();

        // Update market conditions periodically
        if (self.current_time.seconds % 86400 == 0) { // Daily update
            self.updateMarketConditions();
        }

        // Update statistics
        self.stats.update(self);
    }

    fn flightStatusToAircraftStatus(self: SimulationWorld, status: types.FlightStatus) entities.Aircraft.AircraftStatus {
        _ = self;
        return switch (status) {
            .scheduled => .parked,
            .boarding => .boarding,
            .departed => .takeoff,
            .in_flight => .cruise,
            .approach => .approach,
            .landed => .landing,
            .delayed => .parked,
            .cancelled => .parked,
        };
    }

    fn updateCargoStatus(self: *SimulationWorld) void {
        for (self.cargo.items) |*c| {
            // Check if cargo is on an active flight
            for (self.flight_scheduler.active_flights.items) |active_flight| {
                for (active_flight.flight_plan.cargo_manifest.items) |cargo_id| {
                    if (c.id == cargo_id) {
                        c.status = .in_transit;
                        c.current_location = active_flight.flight_plan.aircraft_id;
                    }
                }
            }

            // Check for delivery
            if (c.status == .in_transit and c.current_location == c.destination_airport) {
                c.status = .delivered;
                c.actual_delivery_time = self.current_time;
            }
        }
    }

    fn updateAirportSensors(self: *SimulationWorld) void {
        // Simple weather simulation
        const time_factor = @as(f32, @floatFromInt(self.current_time.seconds % 86400)) / 86400.0;
        const weather_random = @sin(time_factor * 6.28) * 0.5 + 0.5;

        for (self.airports.items) |*airport| {
            airport.sensors.last_update = self.current_time;

            // Simulate temperature variation
            airport.sensors.temperature = 15.0 + @sin(time_factor * 6.28) * 10.0;

            // Simulate wind
            airport.sensors.wind_speed = 5.0 + weather_random * 20.0;
            airport.sensors.wind_direction = weather_random * 360.0;

            // Update weather condition
            if (weather_random < 0.2) {
                airport.weather = .clear;
                airport.sensors.runway_condition = .dry;
            } else if (weather_random < 0.6) {
                airport.weather = .light_clouds;
                airport.sensors.runway_condition = .dry;
            } else if (weather_random < 0.8) {
                airport.weather = .rain;
                airport.sensors.runway_condition = .wet;
            } else {
                airport.weather = .storm;
                airport.sensors.runway_condition = .wet;
            }
        }
    }

    fn updateMarketConditions(self: *SimulationWorld) void {
        // Simple market cycle simulation
        const day = self.current_time.seconds / 86400;
        const cycle = @mod(day, 365);

        self.market_condition = if (cycle < 90)
            .slow
        else if (cycle < 180)
            .normal
        else if (cycle < 270)
            .growth
        else if (cycle < 330)
            .normal
        else
            .slow;
    }

    // ========================================================================
    // Entity creation methods
    // ========================================================================

    pub fn createAirport(
        self: *SimulationWorld,
        icao: [4]u8,
        iata: [3]u8,
        name: []const u8,
        location: types.Coordinates,
        airport_class: types.AirportClass,
    ) !u32 {
        const id = self.next_airport_id;
        self.next_airport_id += 1;

        const airport = entities.Airport.init(id, icao, iata, name, location, airport_class);
        try self.airports.append(airport);

        return id;
    }

    pub fn createAircraft(
        self: *SimulationWorld,
        registration: [8]u8,
        aircraft_type: types.AircraftType,
        owner_company_id: u32,
    ) !u32 {
        const id = self.next_aircraft_id;
        self.next_aircraft_id += 1;

        const aircraft = entities.Aircraft.init(id, registration, aircraft_type, owner_company_id, self.current_time);
        try self.aircraft.append(aircraft);

        // Add to company fleet
        for (self.companies.items) |*company| {
            if (company.id == owner_company_id) {
                try company.owned_aircraft.append(id);
                company.addCost(aircraft_type.purchaseCost());
                break;
            }
        }

        return id;
    }

    pub fn createCargo(
        self: *SimulationWorld,
        cargo_type: types.CargoType,
        weight_kg: f32,
        volume_m3: f32,
        origin: u32,
        destination: u32,
        shipper_id: u32,
    ) !u32 {
        const id = self.next_cargo_id;
        self.next_cargo_id += 1;

        const cargo = entities.Cargo.init(
            id,
            cargo_type,
            weight_kg,
            volume_m3,
            origin,
            destination,
            shipper_id,
            self.current_time,
        );
        try self.cargo.append(cargo);

        self.stats.total_cargo_created += 1;
        self.stats.total_cargo_weight_kg += weight_kg;

        return id;
    }

    pub fn createCompany(self: *SimulationWorld, name: []const u8, starting_capital: types.Money) !u32 {
        const id = self.next_company_id;
        self.next_company_id += 1;

        const company = try entities.Company.init(self.allocator, id, name, starting_capital);
        try self.companies.append(company);

        return id;
    }

    pub fn createCrewMember(
        self: *SimulationWorld,
        role: economics.CrewEconomics.CrewRole,
        experience_level: u8,
    ) !u32 {
        const id = self.next_crew_id;
        self.next_crew_id += 1;

        const salary = role.baseSalaryPerHour().multiply(1.0 + (@as(f64, @floatFromInt(experience_level)) * 0.1));

        const crew = economics.CrewEconomics.CrewMember{
            .id = id,
            .role = role,
            .salary_per_hour = salary,
            .experience_level = experience_level,
            .flight_hours = 0,
            .rest_required_until = self.current_time,
        };
        try self.crew_members.append(crew);

        return id;
    }

    pub fn createFlightPlan(
        self: *SimulationWorld,
        callsign: [8]u8,
        aircraft_id: u32,
        departure_airport_id: u32,
        arrival_airport_id: u32,
        departure_time: types.SimTime,
    ) !u32 {
        const id = self.next_flight_id;
        self.next_flight_id += 1;

        var plan = flight.FlightPlan.init(self.allocator, id, callsign, aircraft_id);
        plan.scheduled_departure = departure_time;
        plan.estimated_departure = departure_time;

        // Find airports
        var dep_airport: ?entities.Airport = null;
        var arr_airport: ?entities.Airport = null;

        for (self.airports.items) |airport| {
            if (airport.id == departure_airport_id) dep_airport = airport;
            if (airport.id == arrival_airport_id) arr_airport = airport;
        }

        if (dep_airport != null and arr_airport != null) {
            // Find aircraft type
            var aircraft_type: ?types.AircraftType = null;
            for (self.aircraft.items) |a| {
                if (a.id == aircraft_id) {
                    aircraft_type = a.aircraft_type;
                    break;
                }
            }

            if (aircraft_type) |at| {
                try plan.calculateRoute(dep_airport.?, arr_airport.?, at);
            }
        }

        try self.flight_scheduler.addFlight(plan);

        return id;
    }

    pub fn launchFlight(self: *SimulationWorld, flight_id: u32) !bool {
        return try self.flight_scheduler.launchFlight(flight_id, self.current_time);
    }

    // ========================================================================
    // Query methods
    // ========================================================================

    pub fn getAirportById(self: *SimulationWorld, id: u32) ?*entities.Airport {
        for (self.airports.items) |*airport| {
            if (airport.id == id) return airport;
        }
        return null;
    }

    pub fn getAircraftById(self: *SimulationWorld, id: u32) ?*entities.Aircraft {
        for (self.aircraft.items) |*aircraft| {
            if (aircraft.id == id) return aircraft;
        }
        return null;
    }

    pub fn getCompanyById(self: *SimulationWorld, id: u32) ?*entities.Company {
        for (self.companies.items) |*company| {
            if (company.id == id) return company;
        }
        return null;
    }
};

pub const SimulationStats = struct {
    total_flights_scheduled: u32,
    total_flights_completed: u32,
    total_flights_cancelled: u32,
    total_cargo_created: u32,
    total_cargo_delivered: u32,
    total_cargo_weight_kg: f32,
    total_revenue: types.Money,
    total_costs: types.Money,
    average_on_time_performance: f32,

    pub fn init() SimulationStats {
        return .{
            .total_flights_scheduled = 0,
            .total_flights_completed = 0,
            .total_flights_cancelled = 0,
            .total_cargo_created = 0,
            .total_cargo_delivered = 0,
            .total_cargo_weight_kg = 0,
            .total_revenue = types.Money.init(0),
            .total_costs = types.Money.init(0),
            .average_on_time_performance = 100.0,
        };
    }

    pub fn update(self: *SimulationStats, world: *SimulationWorld) void {
        const flight_counts = world.flight_scheduler.getFlightCount();
        self.total_flights_scheduled = @intCast(flight_counts.scheduled);
        self.total_flights_completed = @intCast(flight_counts.completed);

        // Count delivered cargo
        var delivered: u32 = 0;
        for (world.cargo.items) |c| {
            if (c.status == .delivered) delivered += 1;
        }
        self.total_cargo_delivered = delivered;

        // Aggregate company financials
        var total_rev = types.Money.init(0);
        var total_cost = types.Money.init(0);
        for (world.companies.items) |company| {
            total_rev = total_rev.add(company.total_revenue);
            total_cost = total_cost.add(company.total_costs);
        }
        self.total_revenue = total_rev;
        self.total_costs = total_cost;
    }

    pub fn getProfitMargin(self: SimulationStats) f64 {
        const rev = self.total_revenue.toDollars();
        if (rev == 0) return 0.0;
        const profit = self.total_revenue.subtract(self.total_costs).toDollars();
        return (profit / rev) * 100.0;
    }
};
