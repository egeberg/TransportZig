const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");
const flight = @import("flight.zig");
const weather = @import("weather.zig");
const notam = @import("notam.zig");

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

    // Weather service
    weather_service: weather.WeatherService,
    last_weather_update: types.SimTime,

    // NOTAM service
    notam_service: notam.NotamService,
    last_notam_update: types.SimTime,

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
            .weather_service = weather.WeatherService.init(allocator, weather.WeatherConfig.initDefault()),
            .last_weather_update = types.SimTime{ .seconds = 0 },
            .notam_service = notam.NotamService.init(allocator, notam.NotamConfig.initDefault()),
            .last_notam_update = types.SimTime{ .seconds = 0 },
            .next_airport_id = 1,
            .next_aircraft_id = 1,
            .next_cargo_id = 1,
            .next_company_id = 1,
            .next_crew_id = 1,
            .next_flight_id = 1,
            .stats = SimulationStats.init(),
        };
    }

    pub fn initWithWeatherAPI(allocator: std.mem.Allocator, api_key: []const u8) SimulationWorld {
        var world = init(allocator);
        world.weather_service = weather.WeatherService.init(
            allocator,
            weather.WeatherConfig.initOpenWeatherMap(api_key),
        );
        return world;
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
        self.weather_service.deinit();
        self.notam_service.deinit();
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

        // Update airport sensors with real-world weather data
        // Refresh weather every 30 minutes (configurable)
        const time_since_last_weather_update = self.current_time.seconds - self.last_weather_update.seconds;
        if (time_since_last_weather_update >= self.weather_service.config.update_interval_seconds) {
            try self.updateAirportWeather();
            self.last_weather_update = self.current_time;
        }

        // Update NOTAMs every hour (configurable)
        const time_since_last_notam_update = self.current_time.seconds - self.last_notam_update.seconds;
        if (time_since_last_notam_update >= self.notam_service.config.update_interval_seconds) {
            try self.updateAirportNotams();
            self.last_notam_update = self.current_time;
        }

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

    fn updateAirportWeather(self: *SimulationWorld) !void {
        // Fetch real-world weather data for all airports
        std.debug.print("\n[Weather Update] Fetching weather data for {d} airports...\n", .{self.airports.items.len});

        for (self.airports.items) |*airport| {
            const weather_data = try self.weather_service.fetchWeatherForAirport(
                airport.id,
                airport.location.latitude,
                airport.location.longitude,
            );

            // Apply weather data to airport sensors
            weather_data.applyToAirportSensors(airport);
            airport.sensors.last_update = self.current_time;

            // Check for weather alerts
            if (weather.WeatherAlert.checkWeatherAlerts(weather_data, airport.id)) |alert| {
                std.debug.print("[WEATHER ALERT] {s} ({s}): {s}\n", .{
                    std.mem.sliceTo(&airport.iata_code, 0),
                    @tagName(alert.severity),
                    alert.message,
                });
            }
        }
    }

    fn updateAirportNotams(self: *SimulationWorld) !void {
        // Fetch NOTAMs for all airports
        try self.notam_service.updateAllAirports(self.airports.items);
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
