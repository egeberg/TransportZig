const std = @import("std");
const types = @import("types.zig");
const economics = @import("economics.zig");

// ============================================================================
// AVIATION ENTITIES - Aircraft, Airports, Cargo
// ============================================================================

/// Aircraft entity with IoT telemetry support
pub const Aircraft = struct {
    id: u32,
    registration: [8]u8, // e.g., "N12345"
    aircraft_type: types.AircraftType,
    owner_company_id: u32,

    // Current state
    status: AircraftStatus,
    current_location: ?u32, // Airport ID (null if in flight)
    current_position: types.Coordinates, // Real-time position
    current_altitude: f32, // meters
    current_speed: f32, // km/h
    heading: f32, // degrees

    // Economics
    purchase_date: types.SimTime,
    purchase_cost: types.Money,
    total_flight_hours: f32,
    total_cycles: u32, // takeoff/landing cycles

    // Maintenance
    maintenance_schedule: economics.MaintenanceEconomics.MaintenanceSchedule,
    next_maintenance_due: types.SimTime,

    // Cargo capacity
    current_cargo_weight: f32, // tons
    current_cargo_volume: f32, // cubic meters

    // IoT Telemetry
    telemetry: AircraftTelemetry,

    pub const AircraftStatus = enum {
        parked,
        maintenance,
        boarding,
        taxiing,
        takeoff,
        climbing,
        cruise,
        descending,
        approach,
        landing,
        grounded, // Out of service
    };

    pub const AircraftTelemetry = struct {
        fuel_remaining: f32, // liters
        fuel_consumption_rate: f32, // liters/hour
        engine_temperature: [4]f32, // celsius (max 4 engines)
        engine_status: [4]bool,
        hydraulic_pressure: f32, // psi
        cabin_pressure: f32, // psi
        outside_air_temperature: f32, // celsius
        weight_on_wheels: bool,
        autopilot_engaged: bool,
        last_update: types.SimTime,

        pub fn init() AircraftTelemetry {
            return .{
                .fuel_remaining = 0,
                .fuel_consumption_rate = 0,
                .engine_temperature = [_]f32{0} ** 4,
                .engine_status = [_]bool{false} ** 4,
                .hydraulic_pressure = 3000,
                .cabin_pressure = 14.7,
                .outside_air_temperature = -50,
                .weight_on_wheels = true,
                .autopilot_engaged = false,
                .last_update = types.SimTime{ .seconds = 0 },
            };
        }

        pub fn isHealthy(self: AircraftTelemetry) bool {
            // Basic health check
            if (self.fuel_remaining <= 0) return false;

            var engines_ok: u8 = 0;
            for (self.engine_status) |status| {
                if (status) engines_ok += 1;
            }
            if (engines_ok == 0) return false;

            if (self.hydraulic_pressure < 2000) return false;

            return true;
        }
    };

    pub fn init(
        id: u32,
        registration: [8]u8,
        aircraft_type: types.AircraftType,
        owner_company_id: u32,
        purchase_time: types.SimTime,
    ) Aircraft {
        return .{
            .id = id,
            .registration = registration,
            .aircraft_type = aircraft_type,
            .owner_company_id = owner_company_id,
            .status = .parked,
            .current_location = null,
            .current_position = types.Coordinates{ .latitude = 0, .longitude = 0 },
            .current_altitude = 0,
            .current_speed = 0,
            .heading = 0,
            .purchase_date = purchase_time,
            .purchase_cost = aircraft_type.purchaseCost(),
            .total_flight_hours = 0,
            .total_cycles = 0,
            .maintenance_schedule = .{
                .aircraft_id = id,
                .last_a_check = purchase_time,
                .last_b_check = purchase_time,
                .last_c_check = purchase_time,
                .last_d_check = purchase_time,
                .total_flight_hours = 0,
                .cycles = 0,
            },
            .next_maintenance_due = purchase_time.addHours(500),
            .current_cargo_weight = 0,
            .current_cargo_volume = 0,
            .telemetry = AircraftTelemetry.init(),
        };
    }

    pub fn canAcceptCargo(self: Aircraft, weight_tons: f32, volume_m3: f32) bool {
        const weight_available = self.aircraft_type.payloadCapacity() - self.current_cargo_weight;
        const volume_available = self.aircraft_type.volumeCapacity() - self.current_cargo_volume;
        return weight_tons <= weight_available and volume_m3 <= volume_available;
    }

    pub fn isOperational(self: Aircraft, time: types.SimTime) bool {
        if (self.status == .grounded or self.status == .maintenance) return false;
        if (time.seconds >= self.next_maintenance_due.seconds) return false;
        if (!self.telemetry.isHealthy()) return false;
        return true;
    }

    pub fn updatePosition(self: *Aircraft, position: types.Coordinates, altitude: f32, speed: f32, heading: f32, time: types.SimTime) void {
        self.current_position = position;
        self.current_altitude = altitude;
        self.current_speed = speed;
        self.heading = heading;
        self.telemetry.last_update = time;
    }
};

/// Airport entity with cargo handling and slots
pub const Airport = struct {
    id: u32,
    icao_code: [4]u8, // e.g., "KJFK"
    iata_code: [3]u8, // e.g., "JFK"
    name: []const u8,
    location: types.Coordinates,
    airport_class: types.AirportClass,

    // Capacity
    total_slots: u32,
    available_slots: u32,
    max_aircraft_size: types.AircraftType,

    // Cargo handling
    cargo_capacity: f32, // tons
    current_cargo: f32, // tons
    cargo_handling_rate: f32, // tons/hour

    // Economics
    landing_fee_base: types.Money,
    handling_cost_per_ton: types.Money,
    parking_fee_per_hour: types.Money,

    // Operations
    weather: types.WeatherCondition,
    operational_status: bool,

    // IoT Sensors
    sensors: AirportSensors,

    pub const AirportSensors = struct {
        runway_status: [4]RunwayStatus,
        temperature: f32, // celsius
        wind_speed: f32, // km/h
        wind_direction: f32, // degrees
        visibility: f32, // km
        barometric_pressure: f32, // hPa
        precipitation: bool,
        runway_condition: RunwayCondition,
        last_update: types.SimTime,

        pub const RunwayStatus = struct {
            runway_id: [4]u8, // e.g., "09L"
            is_active: bool,
            is_occupied: bool,
            surface_condition: RunwayCondition,
        };

        pub const RunwayCondition = enum {
            dry,
            wet,
            icy,
            snow_covered,
            contaminated,
        };

        pub fn init() AirportSensors {
            return .{
                .runway_status = [_]RunwayStatus{
                    .{ .runway_id = [_]u8{'0','1','L',0}, .is_active = true, .is_occupied = false, .surface_condition = .dry },
                } ** 4,
                .temperature = 20,
                .wind_speed = 10,
                .wind_direction = 270,
                .visibility = 10,
                .barometric_pressure = 1013.25,
                .precipitation = false,
                .runway_condition = .dry,
                .last_update = types.SimTime{ .seconds = 0 },
            };
        }

        pub fn isSafeForLanding(self: AirportSensors) bool {
            if (self.visibility < 1.0) return false; // Low visibility
            if (self.wind_speed > 60) return false; // High winds
            if (self.runway_condition == .icy or self.runway_condition == .contaminated) return false;
            return true;
        }
    };

    pub fn init(
        id: u32,
        icao: [4]u8,
        iata: [3]u8,
        name: []const u8,
        location: types.Coordinates,
        airport_class: types.AirportClass,
    ) Airport {
        return .{
            .id = id,
            .icao_code = icao,
            .iata_code = iata,
            .name = name,
            .location = location,
            .airport_class = airport_class,
            .total_slots = airport_class.availableSlots(),
            .available_slots = airport_class.availableSlots(),
            .max_aircraft_size = airport_class.maxAircraftSize(),
            .cargo_capacity = switch (airport_class) {
                .regional => 100,
                .domestic => 500,
                .international => 2000,
                .mega_hub => 5000,
            },
            .current_cargo = 0,
            .cargo_handling_rate = switch (airport_class) {
                .regional => 5,
                .domestic => 20,
                .international => 50,
                .mega_hub => 100,
            },
            .landing_fee_base = types.Money.init(500),
            .handling_cost_per_ton = airport_class.handlingCostPerTon(),
            .parking_fee_per_hour = types.Money.init(50),
            .weather = .clear,
            .operational_status = true,
            .sensors = AirportSensors.init(),
        };
    }

    pub fn canAccommodate(self: Airport, aircraft: types.AircraftType) bool {
        return @intFromEnum(aircraft) <= @intFromEnum(self.max_aircraft_size);
    }

    pub fn requestSlot(self: *Airport) bool {
        if (self.available_slots > 0) {
            self.available_slots -= 1;
            return true;
        }
        return false;
    }

    pub fn releaseSlot(self: *Airport) void {
        if (self.available_slots < self.total_slots) {
            self.available_slots += 1;
        }
    }

    pub fn distanceTo(self: Airport, other: Airport) f32 {
        return self.location.distanceTo(other.location);
    }
};

/// Cargo shipment
pub const Cargo = struct {
    id: u32,
    cargo_type: types.CargoType,
    weight_kg: f32,
    volume_m3: f32,
    origin_airport: u32,
    destination_airport: u32,
    shipper_id: u32,

    // Status
    status: CargoStatus,
    current_location: u32, // Airport or Aircraft ID

    // Economics
    declared_value: types.Money,
    insurance_cost: types.Money,

    // Time constraints
    created_time: types.SimTime,
    pickup_deadline: types.SimTime,
    delivery_deadline: types.SimTime,
    actual_delivery_time: ?types.SimTime,

    // Special requirements
    requires_refrigeration: bool,
    requires_special_handling: bool,
    is_fragile: bool,
    max_stacking_weight: f32, // kg that can be stacked on top

    pub const CargoStatus = enum {
        awaiting_pickup,
        in_transit,
        at_hub,
        out_for_delivery,
        delivered,
        delayed,
        lost,
    };

    pub fn init(
        id: u32,
        cargo_type: types.CargoType,
        weight_kg: f32,
        volume_m3: f32,
        origin: u32,
        destination: u32,
        shipper_id: u32,
        time: types.SimTime,
    ) Cargo {
        return .{
            .id = id,
            .cargo_type = cargo_type,
            .weight_kg = weight_kg,
            .volume_m3 = volume_m3,
            .origin_airport = origin,
            .destination_airport = destination,
            .shipper_id = shipper_id,
            .status = .awaiting_pickup,
            .current_location = origin,
            .declared_value = types.Money.init(@as(f64, @floatCast(weight_kg)) * 10.0), // $10/kg default
            .insurance_cost = types.Money.init(@as(f64, @floatCast(weight_kg)) * 0.5),
            .created_time = time,
            .pickup_deadline = time.addHours(24),
            .delivery_deadline = time.addDays(3),
            .actual_delivery_time = null,
            .requires_refrigeration = cargo_type == .perishable,
            .requires_special_handling = cargo_type.requiresSpecialHandling(),
            .is_fragile = cargo_type == .valuable_cargo,
            .max_stacking_weight = if (cargo_type == .valuable_cargo) 0 else weight_kg * 2,
        };
    }

    pub fn isLate(self: Cargo, current_time: types.SimTime) bool {
        return current_time.seconds > self.delivery_deadline.seconds and self.status != .delivered;
    }

    pub fn getHandlingCost(self: Cargo) types.Money {
        return self.cargo_type.handlingCostPerKg().multiply(self.weight_kg);
    }
};

/// Company (airline operator)
pub const Company = struct {
    id: u32,
    name: []const u8,
    cash_balance: types.Money,

    // Fleet
    owned_aircraft: std.ArrayList(u32), // Aircraft IDs

    // Business metrics
    total_revenue: types.Money,
    total_costs: types.Money,
    flights_completed: u32,
    cargo_delivered_kg: f32,

    // Reputation
    on_time_performance: f32, // percentage
    customer_satisfaction: f32, // 0-100
    safety_rating: f32, // 0-100

    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8, starting_capital: types.Money) !Company {
        return .{
            .id = id,
            .name = name,
            .cash_balance = starting_capital,
            .owned_aircraft = std.ArrayList(u32){},
            .total_revenue = types.Money.init(0),
            .total_costs = types.Money.init(0),
            .flights_completed = 0,
            .cargo_delivered_kg = 0,
            .on_time_performance = 95.0,
            .customer_satisfaction = 85.0,
            .safety_rating = 100.0,
        };
    }

    pub fn deinit(self: *Company) void {
        self.owned_aircraft.deinit();
    }

    pub fn addRevenue(self: *Company, amount: types.Money) void {
        self.total_revenue = self.total_revenue.add(amount);
        self.cash_balance = self.cash_balance.add(amount);
    }

    pub fn addCost(self: *Company, amount: types.Money) void {
        self.total_costs = self.total_costs.add(amount);
        self.cash_balance = self.cash_balance.subtract(amount);
    }

    pub fn getProfitLoss(self: Company) economics.ProfitLoss {
        return .{
            .revenue = self.total_revenue,
            .costs = self.total_costs,
        };
    }

    pub fn canAfford(self: Company, amount: types.Money) bool {
        return !self.cash_balance.subtract(amount).isNegative();
    }
};
