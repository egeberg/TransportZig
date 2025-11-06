const std = @import("std");

// ============================================================================
// AVIATION TRANSPORT SIMULATION - CORE TYPES
// ============================================================================

/// Geographic coordinates (WGS84)
pub const Coordinates = struct {
    latitude: f32,
    longitude: f32,
    altitude: f32 = 0.0, // meters above sea level

    /// Calculate great-circle distance in kilometers
    pub fn distanceTo(self: Coordinates, other: Coordinates) f32 {
        const R = 6371.0; // Earth radius in km
        const lat1 = self.latitude * std.math.pi / 180.0;
        const lat2 = other.latitude * std.math.pi / 180.0;
        const dlat = lat2 - lat1;
        const dlon = (other.longitude - self.longitude) * std.math.pi / 180.0;

        const a = @sin(dlat / 2.0) * @sin(dlat / 2.0) +
            @cos(lat1) * @cos(lat2) * @sin(dlon / 2.0) * @sin(dlon / 2.0);
        const c = 2.0 * std.math.atan2(@sqrt(a), @sqrt(1.0 - a));

        return R * c;
    }

    /// Convert to 3D world space for rendering
    pub fn toWorldSpace(self: Coordinates, scale: f32) [3]f32 {
        const x = self.longitude * scale;
        const y = self.altitude / 1000.0; // Convert to km for rendering
        const z = -self.latitude * scale; // Negative for coordinate system
        return .{ x, y, z };
    }
};

/// Financial amount (stored as cents for precision)
pub const Money = struct {
    amount: i64,

    pub fn init(dollars: f64) Money {
        return .{ .amount = @intFromFloat(dollars * 100.0) };
    }

    pub fn toDollars(self: Money) f64 {
        return @as(f64, @floatFromInt(self.amount)) / 100.0;
    }

    pub fn add(self: Money, other: Money) Money {
        return .{ .amount = self.amount + other.amount };
    }

    pub fn subtract(self: Money, other: Money) Money {
        return .{ .amount = self.amount - other.amount };
    }

    pub fn multiply(self: Money, factor: f64) Money {
        return .{ .amount = @intFromFloat(@as(f64, @floatFromInt(self.amount)) * factor) };
    }

    pub fn isNegative(self: Money) bool {
        return self.amount < 0;
    }
};

/// Simulation time
pub const SimTime = struct {
    seconds: u64,

    pub fn addMinutes(self: SimTime, minutes: u64) SimTime {
        return .{ .seconds = self.seconds + (minutes * 60) };
    }

    pub fn addHours(self: SimTime, hours: u64) SimTime {
        return .{ .seconds = self.seconds + (hours * 3600) };
    }

    pub fn addDays(self: SimTime, days: u64) SimTime {
        return .{ .seconds = self.seconds + (days * 86400) };
    }

    pub fn elapsedHours(self: SimTime, since: SimTime) f64 {
        return @as(f64, @floatFromInt(self.seconds - since.seconds)) / 3600.0;
    }
};

/// Cargo types with aviation-specific handling
pub const CargoType = enum {
    general_freight,
    express_mail,
    perishable,
    livestock,
    dangerous_goods,
    valuable_cargo,
    medical_supplies,

    pub fn handlingCostPerKg(self: CargoType) Money {
        return switch (self) {
            .general_freight => Money.init(0.50),
            .express_mail => Money.init(2.00),
            .perishable => Money.init(1.50),
            .livestock => Money.init(3.00),
            .dangerous_goods => Money.init(5.00),
            .valuable_cargo => Money.init(10.00),
            .medical_supplies => Money.init(4.00),
        };
    }

    pub fn revenuePerKgPerKm(self: CargoType) f64 {
        return switch (self) {
            .general_freight => 0.20,
            .express_mail => 0.80,
            .perishable => 0.50,
            .livestock => 0.60,
            .dangerous_goods => 1.00,
            .valuable_cargo => 2.00,
            .medical_supplies => 1.50,
        };
    }

    pub fn requiresSpecialHandling(self: CargoType) bool {
        return switch (self) {
            .general_freight, .express_mail => false,
            else => true,
        };
    }
};

/// Aircraft categories based on real aviation classifications
pub const AircraftType = enum {
    // Cargo Aircraft
    small_cargo, // < 10 tons (Cessna Caravan)
    medium_cargo, // 10-50 tons (ATR 72F, Boeing 737F)
    large_cargo, // 50-100 tons (Boeing 767F, Airbus A330F)
    heavy_cargo, // > 100 tons (Boeing 747F, 777F)
    super_heavy, // > 150 tons (Antonov An-124, Boeing 747-8F)

    pub fn payloadCapacity(self: AircraftType) f32 {
        return switch (self) {
            .small_cargo => 3.0, // tons
            .medium_cargo => 20.0,
            .large_cargo => 60.0,
            .heavy_cargo => 110.0,
            .super_heavy => 150.0,
        };
    }

    pub fn volumeCapacity(self: AircraftType) f32 {
        return switch (self) {
            .small_cargo => 15.0, // cubic meters
            .medium_cargo => 80.0,
            .large_cargo => 250.0,
            .heavy_cargo => 600.0,
            .super_heavy => 1000.0,
        };
    }

    pub fn purchaseCost(self: AircraftType) Money {
        return switch (self) {
            .small_cargo => Money.init(2_000_000),
            .medium_cargo => Money.init(35_000_000),
            .large_cargo => Money.init(200_000_000),
            .heavy_cargo => Money.init(350_000_000),
            .super_heavy => Money.init(450_000_000),
        };
    }

    pub fn cruiseSpeed(self: AircraftType) f32 {
        return switch (self) {
            .small_cargo => 350.0, // km/h
            .medium_cargo => 500.0,
            .large_cargo => 850.0,
            .heavy_cargo => 900.0,
            .super_heavy => 850.0,
        };
    }

    pub fn fuelBurnPerHour(self: AircraftType) f32 {
        return switch (self) {
            .small_cargo => 150.0, // liters
            .medium_cargo => 600.0,
            .large_cargo => 5000.0,
            .heavy_cargo => 8000.0,
            .super_heavy => 12000.0,
        };
    }

    pub fn range(self: AircraftType) f32 {
        return switch (self) {
            .small_cargo => 1500.0, // km
            .medium_cargo => 2500.0,
            .large_cargo => 7000.0,
            .heavy_cargo => 9000.0,
            .super_heavy => 5000.0,
        };
    }

    pub fn maintenanceCostPerFlightHour(self: AircraftType) Money {
        return switch (self) {
            .small_cargo => Money.init(200),
            .medium_cargo => Money.init(800),
            .large_cargo => Money.init(3000),
            .heavy_cargo => Money.init(5000),
            .super_heavy => Money.init(7000),
        };
    }

    pub fn crewRequired(self: AircraftType) u8 {
        return switch (self) {
            .small_cargo => 1, // Pilot only
            .medium_cargo => 2, // 2 pilots
            .large_cargo, .heavy_cargo, .super_heavy => 3, // 2 pilots + flight engineer
        };
    }
};

/// Airport classification
pub const AirportClass = enum {
    regional, // Small airports
    domestic, // National flights
    international, // International hub
    mega_hub, // Major global hub

    pub fn maxAircraftSize(self: AirportClass) AircraftType {
        return switch (self) {
            .regional => .small_cargo,
            .domestic => .medium_cargo,
            .international => .heavy_cargo,
            .mega_hub => .super_heavy,
        };
    }

    pub fn landingFee(self: AirportClass, aircraft: AircraftType) Money {
        const base = switch (self) {
            .regional => Money.init(100),
            .domestic => Money.init(300),
            .international => Money.init(800),
            .mega_hub => Money.init(1500),
        };
        const multiplier = switch (aircraft) {
            .small_cargo => 1.0,
            .medium_cargo => 2.0,
            .large_cargo => 3.5,
            .heavy_cargo => 5.0,
            .super_heavy => 7.0,
        };
        return base.multiply(multiplier);
    }

    pub fn handlingCostPerTon(self: AirportClass) Money {
        return switch (self) {
            .regional => Money.init(50),
            .domestic => Money.init(80),
            .international => Money.init(120),
            .mega_hub => Money.init(100), // Economies of scale
        };
    }

    pub fn availableSlots(self: AirportClass) u32 {
        return switch (self) {
            .regional => 20,
            .domestic => 50,
            .international => 150,
            .mega_hub => 300,
        };
    }
};

/// Flight status
pub const FlightStatus = enum {
    scheduled,
    boarding,
    departed,
    in_flight,
    approach,
    landed,
    delayed,
    cancelled,
};

/// Weather conditions affecting operations
pub const WeatherCondition = enum {
    clear,
    light_clouds,
    overcast,
    rain,
    storm,
    snow,
    fog,

    pub fn delayProbability(self: WeatherCondition) f32 {
        return switch (self) {
            .clear => 0.01,
            .light_clouds => 0.02,
            .overcast => 0.05,
            .rain => 0.15,
            .storm => 0.60,
            .snow => 0.40,
            .fog => 0.50,
        };
    }

    pub fn fuelConsumptionMultiplier(self: WeatherCondition) f32 {
        return switch (self) {
            .clear => 1.0,
            .light_clouds => 1.02,
            .overcast => 1.05,
            .rain => 1.10,
            .storm => 1.25,
            .snow => 1.15,
            .fog => 1.08,
        };
    }
};

/// Market demand patterns
pub const MarketCondition = enum {
    recession,
    slow,
    normal,
    growth,
    boom,

    pub fn demandMultiplier(self: MarketCondition) f64 {
        return switch (self) {
            .recession => 0.6,
            .slow => 0.8,
            .normal => 1.0,
            .growth => 1.4,
            .boom => 1.8,
        };
    }

    pub fn priceElasticity(self: MarketCondition) f64 {
        return switch (self) {
            .recession => 0.6, // Customers very price-sensitive
            .slow => 0.75,
            .normal => 1.0,
            .growth => 1.2,
            .boom => 1.5, // Customers less price-sensitive
        };
    }
};
