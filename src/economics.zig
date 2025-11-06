const std = @import("std");
const types = @import("types.zig");
const Money = types.Money;
const AircraftType = types.AircraftType;
const CargoType = types.CargoType;
const SimTime = types.SimTime;

// ============================================================================
// AVIATION ECONOMICS MODULE
// ============================================================================

/// Fuel pricing model
pub const FuelPricing = struct {
    base_price_per_liter: Money, // Base jet fuel price
    volatility: f32, // Price volatility factor
    regional_adjustment: f32, // Regional price variations

    pub fn init() FuelPricing {
        return .{
            .base_price_per_liter = Money.init(0.85), // ~$0.85/liter jet fuel
            .volatility = 0.15,
            .regional_adjustment = 1.0,
        };
    }

    pub fn getCurrentPrice(self: FuelPricing, time: SimTime) Money {
        // Simulate price fluctuations based on time
        const time_factor = @as(f32, @floatFromInt(time.seconds % 86400)) / 86400.0;
        const fluctuation = 1.0 + (self.volatility * @sin(time_factor * 2.0 * std.math.pi));
        return self.base_price_per_liter.multiply(fluctuation * self.regional_adjustment);
    }

    pub fn calculateFlightFuelCost(
        self: FuelPricing,
        aircraft: AircraftType,
        flight_hours: f32,
        weather_multiplier: f32,
        time: SimTime,
    ) Money {
        const fuel_consumed = aircraft.fuelBurnPerHour() * flight_hours * weather_multiplier;
        const price = self.getCurrentPrice(time);
        return price.multiply(fuel_consumed);
    }
};

/// Crew management and costs
pub const CrewEconomics = struct {
    pub const CrewMember = struct {
        id: u32,
        role: CrewRole,
        salary_per_hour: Money,
        experience_level: u8, // 1-10
        flight_hours: u32,
        rest_required_until: SimTime,

        pub fn isAvailable(self: CrewMember, time: SimTime) bool {
            return time.seconds >= self.rest_required_until.seconds;
        }

        pub fn calculateFlightCost(self: CrewMember, flight_hours: f32) Money {
            return self.salary_per_hour.multiply(flight_hours);
        }
    };

    pub const CrewRole = enum {
        captain,
        first_officer,
        flight_engineer,
        loadmaster,

        pub fn baseSalaryPerHour(self: CrewRole) Money {
            return switch (self) {
                .captain => Money.init(150),
                .first_officer => Money.init(100),
                .flight_engineer => Money.init(80),
                .loadmaster => Money.init(50),
            };
        }

        pub fn requiredRestHours(self: CrewRole) u64 {
            return switch (self) {
                .captain, .first_officer => 12,
                .flight_engineer => 10,
                .loadmaster => 8,
            };
        }
    };

    pub fn calculateCrewCost(crew: []const CrewMember, flight_hours: f32) Money {
        var total = Money.init(0);
        for (crew) |member| {
            total = total.add(member.calculateFlightCost(flight_hours));
        }
        return total;
    }
};

/// Aircraft maintenance economics
pub const MaintenanceEconomics = struct {
    pub const MaintenanceSchedule = struct {
        aircraft_id: u32,
        last_a_check: SimTime, // ~500 flight hours
        last_b_check: SimTime, // ~4-6 months
        last_c_check: SimTime, // ~18-24 months
        last_d_check: SimTime, // ~6-10 years
        total_flight_hours: f32,
        cycles: u32, // Takeoff/landing cycles

        pub fn needsMaintenance(self: MaintenanceSchedule, time: SimTime) bool {
            const hours_since_a = time.elapsedHours(self.last_a_check);
            return hours_since_a >= 500.0;
        }

        pub fn getNextMaintenanceCost(self: MaintenanceSchedule, aircraft: AircraftType) Money {
            const hours_since_a = self.total_flight_hours - @as(f32, @floatFromInt(self.last_a_check.seconds)) / 3600.0;

            if (hours_since_a >= 500.0) {
                return switch (aircraft) {
                    .small_cargo => Money.init(5_000),
                    .medium_cargo => Money.init(25_000),
                    .large_cargo => Money.init(100_000),
                    .heavy_cargo => Money.init(200_000),
                    .super_heavy => Money.init(300_000),
                };
            }
            return Money.init(0);
        }
    };
};

/// Airport slot pricing (landing/takeoff rights)
pub const SlotEconomics = struct {
    pub const TimeSlot = enum {
        night, // 00:00-06:00 (cheaper)
        morning, // 06:00-10:00 (premium)
        midday, // 10:00-16:00 (normal)
        evening, // 16:00-20:00 (premium)
        late, // 20:00-24:00 (normal)

        pub fn priceMultiplier(self: TimeSlot) f32 {
            return switch (self) {
                .night => 0.7,
                .morning => 1.5,
                .midday => 1.0,
                .evening => 1.5,
                .late => 1.0,
            };
        }

        pub fn fromTime(time: SimTime) TimeSlot {
            const hour = (time.seconds / 3600) % 24;
            if (hour < 6) return .night;
            if (hour < 10) return .morning;
            if (hour < 16) return .midday;
            if (hour < 20) return .evening;
            return .late;
        }
    };

    pub fn calculateSlotCost(
        airport_class: types.AirportClass,
        aircraft: AircraftType,
        time: SimTime,
    ) Money {
        const base_fee = airport_class.landingFee(aircraft);
        const slot_multiplier = TimeSlot.fromTime(time).priceMultiplier();
        return base_fee.multiply(slot_multiplier);
    }
};

/// Revenue calculation for cargo operations
pub const RevenueModel = struct {
    pub fn calculateCargoRevenue(
        cargo_type: CargoType,
        weight_kg: f32,
        distance_km: f32,
        market_condition: types.MarketCondition,
    ) Money {
        const base_rate = cargo_type.revenuePerKgPerKm();
        const market_multiplier = market_condition.priceElasticity();
        const revenue = weight_kg * distance_km * base_rate * market_multiplier;
        return Money.init(revenue);
    }

    pub fn calculateFlightRevenue(
        cargo_manifest: []const Cargo,
        distance_km: f32,
        market_condition: types.MarketCondition,
    ) Money {
        var total = Money.init(0);
        for (cargo_manifest) |cargo| {
            const revenue = calculateCargoRevenue(
                cargo.cargo_type,
                cargo.weight_kg,
                distance_km,
                market_condition,
            );
            total = total.add(revenue);
        }
        return total;
    }

    const Cargo = struct {
        cargo_type: CargoType,
        weight_kg: f32,
    };
};

/// Complete flight cost calculation
pub const FlightEconomics = struct {
    pub fn calculateTotalFlightCost(
        aircraft: AircraftType,
        distance_km: f32,
        departure_airport: types.AirportClass,
        arrival_airport: types.AirportClass,
        crew: []const CrewEconomics.CrewMember,
        weather_multiplier: f32,
        fuel_pricing: FuelPricing,
        time: SimTime,
    ) FlightCostBreakdown {
        const flight_hours = distance_km / aircraft.cruiseSpeed();

        // Calculate individual costs
        const fuel_cost = fuel_pricing.calculateFlightFuelCost(
            aircraft,
            flight_hours,
            weather_multiplier,
            time,
        );
        const crew_cost = CrewEconomics.calculateCrewCost(crew, flight_hours);
        const maintenance_cost = aircraft.maintenanceCostPerFlightHour().multiply(flight_hours);

        const departure_slot = SlotEconomics.calculateSlotCost(
            departure_airport,
            aircraft,
            time,
        );
        const arrival_slot = SlotEconomics.calculateSlotCost(
            arrival_airport,
            aircraft,
            time.addHours(@intFromFloat(@ceil(flight_hours))),
        );

        const handling_cost = departure_airport.handlingCostPerTon(aircraft)
            .add(arrival_airport.handlingCostPerTon(aircraft))
            .multiply(aircraft.payloadCapacity());

        return FlightCostBreakdown{
            .fuel = fuel_cost,
            .crew = crew_cost,
            .maintenance = maintenance_cost,
            .departure_slot = departure_slot,
            .arrival_slot = arrival_slot,
            .handling = handling_cost,
        };
    }

    pub const FlightCostBreakdown = struct {
        fuel: Money,
        crew: Money,
        maintenance: Money,
        departure_slot: Money,
        arrival_slot: Money,
        handling: Money,

        pub fn total(self: FlightCostBreakdown) Money {
            return self.fuel
                .add(self.crew)
                .add(self.maintenance)
                .add(self.departure_slot)
                .add(self.arrival_slot)
                .add(self.handling);
        }

        pub fn getBreakdownPercentages(self: FlightCostBreakdown) BreakdownPercent {
            const total_amount = self.total().toDollars();
            return BreakdownPercent{
                .fuel = (self.fuel.toDollars() / total_amount) * 100.0,
                .crew = (self.crew.toDollars() / total_amount) * 100.0,
                .maintenance = (self.maintenance.toDollars() / total_amount) * 100.0,
                .slots = ((self.departure_slot.toDollars() + self.arrival_slot.toDollars()) / total_amount) * 100.0,
                .handling = (self.handling.toDollars() / total_amount) * 100.0,
            };
        }
    };

    const BreakdownPercent = struct {
        fuel: f64,
        crew: f64,
        maintenance: f64,
        slots: f64,
        handling: f64,
    };
};

/// Profit/Loss calculation
pub const ProfitLoss = struct {
    revenue: Money,
    costs: Money,

    pub fn profit(self: ProfitLoss) Money {
        return self.revenue.subtract(self.costs);
    }

    pub fn profitMargin(self: ProfitLoss) f64 {
        const rev = self.revenue.toDollars();
        if (rev == 0) return 0.0;
        return (self.profit().toDollars() / rev) * 100.0;
    }

    pub fn isProfitable(self: ProfitLoss) bool {
        return !self.profit().isNegative();
    }
};
