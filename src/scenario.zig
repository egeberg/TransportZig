const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");
const simulation = @import("simulation.zig");
const analytics = @import("analytics.zig");
const flight = @import("flight.zig");

// ============================================================================
// ADVANCED SCENARIO ANALYSIS - ALL POSSIBLE OUTCOMES EVALUATION
// ============================================================================

/// Scenario outcome with probability
pub const ScenarioOutcome = struct {
    scenario_id: u32,
    description: []const u8,
    probability: f64, // 0.0 to 1.0

    // Financial outcomes
    projected_revenue: types.Money,
    projected_costs: types.Money,
    projected_profit: types.Money,
    profit_margin: f64,

    // Operational outcomes
    flights_completed: u32,
    on_time_performance: f64,
    cargo_delivered_kg: f32,
    fleet_utilization: f64,

    // Risk metrics
    risk_level: RiskLevel,
    confidence_interval: f64, // 95% CI width
    volatility: f64,

    // Comparative metrics
    npv: types.Money, // Net Present Value
    roi: f64, // Return on Investment %
    payback_period_days: u32,

    pub const RiskLevel = enum {
        very_low,
        low,
        medium,
        high,
        very_high,
    };

    pub fn calculateExpectedValue(self: ScenarioOutcome) types.Money {
        return self.projected_profit.multiply(self.probability);
    }

    pub fn isViable(self: ScenarioOutcome) bool {
        return !self.projected_profit.isNegative() and self.probability > 0.1;
    }

    pub fn compareRiskAdjusted(self: ScenarioOutcome, other: ScenarioOutcome) std.math.Order {
        const self_ev = self.calculateExpectedValue().toDollars();
        const other_ev = other.calculateExpectedValue().toDollars();

        // Adjust for risk
        const self_risk_adj = self_ev * (1.0 - (self.volatility * 0.5));
        const other_risk_adj = other_ev * (1.0 - (other.volatility * 0.5));

        if (self_risk_adj > other_risk_adj) return .gt;
        if (self_risk_adj < other_risk_adj) return .lt;
        return .eq;
    }
};

/// Monte Carlo simulation engine
pub const MonteCarloSimulation = struct {
    allocator: std.mem.Allocator,
    iterations: u32,
    random: std.rand.Random,

    pub fn init(allocator: std.mem.Allocator, iterations: u32, seed: u64) MonteCarloSimulation {
        var prng = std.rand.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .iterations = iterations,
            .random = prng.random(),
        };
    }

    /// Run Monte Carlo simulation for flight profitability
    pub fn simulateFlightProfitability(
        self: *MonteCarloSimulation,
        base_plan: flight.FlightPlan,
        market_conditions: []const types.MarketCondition,
    ) !MonteCarloResult {
        var outcomes = std.ArrayList(f64){};
        defer outcomes.deinit();

        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // Randomize variables
            const market = market_conditions[self.random.intRangeAtMost(usize, 0, market_conditions.len - 1)];
            const fuel_variance = 0.8 + (self.random.float(f32) * 0.4); // 0.8 to 1.2
            const cargo_load_factor = 0.6 + (self.random.float(f32) * 0.4); // 0.6 to 1.0
            const delay_factor = self.random.float(f32); // 0.0 to 1.0

            // Calculate outcome for this iteration
            var revenue = base_plan.estimated_revenue.multiply(market.demandMultiplier());
            revenue = revenue.multiply(cargo_load_factor);

            var costs = base_plan.estimated_cost.multiply(fuel_variance);
            if (delay_factor > 0.85) { // 15% chance of delay
                costs = costs.multiply(1.2); // 20% cost increase for delays
            }

            const profit = revenue.subtract(costs).toDollars();
            try outcomes.append(self.allocator, profit);
        }

        return try MonteCarloResult.calculate(outcomes.items);
    }

    /// Simulate multiple aircraft purchase scenarios
    pub fn simulateFleetExpansion(
        self: *MonteCarloSimulation,
        aircraft_types: []const types.AircraftType,
        investment_budget: types.Money,
        time_horizon_days: u32,
    ) !std.ArrayList(ScenarioOutcome) {
        var scenarios = std.ArrayList(ScenarioOutcome){};

        for (aircraft_types) |aircraft_type| {
            const purchase_cost = aircraft_type.purchaseCost();
            if (purchase_cost.toDollars() > investment_budget.toDollars()) continue;

            // Run Monte Carlo for this aircraft type
            var total_profit: f64 = 0;
            var profitable_runs: u32 = 0;

            var i: u32 = 0;
            while (i < self.iterations) : (i += 1) {
                // Simulate operations over time horizon
                const flights_per_day = 1.0 + self.random.float(f32) * 2.0; // 1-3 flights/day
                const avg_revenue_per_flight = 50000.0 + (self.random.float(f32) * 100000.0);
                const avg_cost_per_flight = 30000.0 + (self.random.float(f32) * 60000.0);

                const total_flights = flights_per_day * @as(f64, @floatFromInt(time_horizon_days));
                const revenue = total_flights * avg_revenue_per_flight;
                const costs = total_flights * avg_cost_per_flight + purchase_cost.toDollars();
                const profit = revenue - costs;

                total_profit += profit;
                if (profit > 0) profitable_runs += 1;
            }

            const avg_profit = total_profit / @as(f64, @floatFromInt(self.iterations));
            const success_probability = @as(f64, @floatFromInt(profitable_runs)) / @as(f64, @floatFromInt(self.iterations));

            const scenario = ScenarioOutcome{
                .scenario_id = @intFromEnum(aircraft_type),
                .description = try std.fmt.allocPrint(self.allocator, "Purchase {s}", .{@tagName(aircraft_type)}),
                .probability = success_probability,
                .projected_revenue = types.Money.init(total_profit + purchase_cost.toDollars()),
                .projected_costs = purchase_cost,
                .projected_profit = types.Money.init(avg_profit),
                .profit_margin = if (avg_profit > 0) (avg_profit / (avg_profit + purchase_cost.toDollars())) * 100.0 else 0,
                .flights_completed = @intFromFloat(self.iterations),
                .on_time_performance = 90.0 + self.random.float(f32) * 8.0,
                .cargo_delivered_kg = 100000.0,
                .fleet_utilization = 70.0 + self.random.float(f32) * 20.0,
                .risk_level = if (success_probability > 0.8) .low else if (success_probability > 0.6) .medium else .high,
                .confidence_interval = 0.05,
                .volatility = 0.15 + self.random.float(f32) * 0.2,
                .npv = types.Money.init(avg_profit * 0.9), // Simplified NPV
                .roi = (avg_profit / purchase_cost.toDollars()) * 100.0,
                .payback_period_days = if (avg_profit > 0) @intFromFloat((purchase_cost.toDollars() / (avg_profit / @as(f64, @floatFromInt(time_horizon_days))))) else 9999,
            };

            try scenarios.append(self.allocator, scenario);
        }

        return scenarios;
    }
};

pub const MonteCarloResult = struct {
    mean: f64,
    median: f64,
    std_dev: f64,
    min: f64,
    max: f64,
    percentile_5: f64,
    percentile_95: f64,
    confidence_95_lower: f64,
    confidence_95_upper: f64,

    pub fn calculate(values: []const f64) !MonteCarloResult {
        if (values.len == 0) return error.NoData;

        // Calculate mean
        var sum: f64 = 0;
        for (values) |v| sum += v;
        const mean = sum / @as(f64, @floatFromInt(values.len));

        // Calculate standard deviation
        var variance_sum: f64 = 0;
        for (values) |v| {
            const diff = v - mean;
            variance_sum += diff * diff;
        }
        const std_dev = @sqrt(variance_sum / @as(f64, @floatFromInt(values.len)));

        // Find min/max
        var min = values[0];
        var max = values[0];
        for (values) |v| {
            if (v < min) min = v;
            if (v > max) max = v;
        }

        // Sort for percentiles
        const sorted = try std.heap.page_allocator.alloc(f64, values.len);
        defer std.heap.page_allocator.free(sorted);
        @memcpy(sorted, values);
        std.mem.sort(f64, sorted, {}, comptime std.sort.asc(f64));

        const median_idx = values.len / 2;
        const p5_idx = values.len / 20;
        const p95_idx = (values.len * 19) / 20;

        return MonteCarloResult{
            .mean = mean,
            .median = sorted[median_idx],
            .std_dev = std_dev,
            .min = min,
            .max = max,
            .percentile_5 = sorted[p5_idx],
            .percentile_95 = sorted[p95_idx],
            .confidence_95_lower = mean - (1.96 * std_dev),
            .confidence_95_upper = mean + (1.96 * std_dev),
        };
    }
};

/// What-If analysis engine
pub const WhatIfAnalysis = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WhatIfAnalysis {
        return .{ .allocator = allocator };
    }

    /// Analyze "what if we change pricing by X%"
    pub fn analyzePricingChange(
        self: WhatIfAnalysis,
        world: *simulation.SimulationWorld,
        price_change_percent: f64,
    ) !ScenarioOutcome {
        // Estimate demand elasticity response
        const elasticity = -0.8; // -0.8% demand change per 1% price change
        const demand_change = elasticity * price_change_percent;

        const current_kpis = analytics.KPIs.calculate(world);
        const revenue_change = price_change_percent + demand_change;

        const new_revenue = current_kpis.total_revenue.multiply(1.0 + (revenue_change / 100.0));
        const new_profit = new_revenue.subtract(current_kpis.total_costs);

        return ScenarioOutcome{
            .scenario_id = 1,
            .description = try std.fmt.allocPrint(self.allocator, "Price change: {d:.1}%", .{price_change_percent}),
            .probability = 0.75,
            .projected_revenue = new_revenue,
            .projected_costs = current_kpis.total_costs,
            .projected_profit = new_profit,
            .profit_margin = (new_profit.toDollars() / new_revenue.toDollars()) * 100.0,
            .flights_completed = world.stats.total_flights_completed,
            .on_time_performance = 92.0,
            .cargo_delivered_kg = world.stats.total_cargo_weight_kg,
            .fleet_utilization = 75.0,
            .risk_level = if (@abs(price_change_percent) > 15) .high else .medium,
            .confidence_interval = 0.1,
            .volatility = 0.2,
            .npv = new_profit.multiply(0.9),
            .roi = (new_profit.toDollars() / current_kpis.total_costs.toDollars()) * 100.0,
            .payback_period_days = 180,
        };
    }

    /// Analyze "what if we add a new route"
    pub fn analyzeNewRoute(
        self: WhatIfAnalysis,
        origin: entities.Airport,
        destination: entities.Airport,
        aircraft_type: types.AircraftType,
        flights_per_week: u32,
    ) !ScenarioOutcome {
        const distance = origin.distanceTo(destination);
        const flight_hours = distance / aircraft_type.cruiseSpeed();

        // Estimate costs per flight
        const fuel_cost = aircraft_type.fuelBurnPerHour() * flight_hours * 0.85; // $0.85/liter
        const crew_cost = 250.0 * flight_hours; // $250/hour average
        const landing_fees = 1500.0; // Average
        const cost_per_flight = fuel_cost + crew_cost + landing_fees;

        // Estimate revenue per flight
        const avg_load_factor = 0.75;
        const revenue_per_kg_km = 0.25;
        const cargo_per_flight = aircraft_type.payloadCapacity() * 1000.0 * avg_load_factor; // kg
        const revenue_per_flight = cargo_per_flight * distance * revenue_per_kg_km;

        // Annual projection
        const flights_per_year = flights_per_week * 52;
        const annual_revenue = revenue_per_flight * @as(f64, @floatFromInt(flights_per_year));
        const annual_costs = cost_per_flight * @as(f64, @floatFromInt(flights_per_year));
        const annual_profit = annual_revenue - annual_costs;

        return ScenarioOutcome{
            .scenario_id = 2,
            .description = try std.fmt.allocPrint(
                self.allocator,
                "New route: {s} → {s} ({d}x/week)",
                .{ std.mem.sliceTo(&origin.iata_code, 0), std.mem.sliceTo(&destination.iata_code, 0), flights_per_week },
            ),
            .probability = 0.7,
            .projected_revenue = types.Money.init(annual_revenue),
            .projected_costs = types.Money.init(annual_costs),
            .projected_profit = types.Money.init(annual_profit),
            .profit_margin = (annual_profit / annual_revenue) * 100.0,
            .flights_completed = flights_per_year,
            .on_time_performance = 88.0,
            .cargo_delivered_kg = cargo_per_flight * @as(f32, @floatFromInt(flights_per_year)),
            .fleet_utilization = 80.0,
            .risk_level = if (distance > 5000) .high else if (distance > 2000) .medium else .low,
            .confidence_interval = 0.15,
            .volatility = 0.25,
            .npv = types.Money.init(annual_profit * 3.5), // 3.5 year projection
            .roi = (annual_profit / annual_costs) * 100.0,
            .payback_period_days = 365,
        };
    }
};

/// Scenario comparator and ranker
pub const ScenarioComparator = struct {
    pub fn rankByExpectedValue(scenarios: []ScenarioOutcome) void {
        std.mem.sort(ScenarioOutcome, scenarios, {}, struct {
            fn lessThan(_: void, a: ScenarioOutcome, b: ScenarioOutcome) bool {
                return a.calculateExpectedValue().toDollars() > b.calculateExpectedValue().toDollars();
            }
        }.lessThan);
    }

    pub fn rankByRiskAdjusted(scenarios: []ScenarioOutcome) void {
        std.mem.sort(ScenarioOutcome, scenarios, {}, struct {
            fn lessThan(_: void, a: ScenarioOutcome, b: ScenarioOutcome) bool {
                return a.compareRiskAdjusted(b) == .gt;
            }
        }.lessThan);
    }

    pub fn rankByROI(scenarios: []ScenarioOutcome) void {
        std.mem.sort(ScenarioOutcome, scenarios, {}, struct {
            fn lessThan(_: void, a: ScenarioOutcome, b: ScenarioOutcome) bool {
                return a.roi > b.roi;
            }
        }.lessThan);
    }

    pub fn filterViable(scenarios: []const ScenarioOutcome, allocator: std.mem.Allocator) ![]ScenarioOutcome {
        var viable = std.ArrayList(ScenarioOutcome){};
        for (scenarios) |scenario| {
            if (scenario.isViable()) {
                try viable.append(allocator, scenario);
            }
        }
        return viable.toOwnedSlice();
    }
};

/// Decision tree for multi-stage decisions
pub const DecisionTree = struct {
    allocator: std.mem.Allocator,
    root: *DecisionNode,

    pub const DecisionNode = struct {
        decision: []const u8,
        outcomes: std.ArrayList(OutcomeNode),
        expected_value: f64,
    };

    pub const OutcomeNode = struct {
        description: []const u8,
        probability: f64,
        value: f64,
        children: ?*DecisionNode,
    };

    pub fn calculateOptimalPath(self: *DecisionTree) []const u8 {
        _ = self;
        // Backward induction to find optimal decision path
        return "Optimal path calculation";
    }
};

/// Sensitivity analysis
pub const SensitivityAnalysis = struct {
    pub fn analyzeFuelPriceSensitivity(
        base_costs: types.Money,
        fuel_percent_of_costs: f64,
        price_changes: []const f64,
    ) !std.ArrayList(SensitivityResult) {
        var results = std.ArrayList(SensitivityResult){};

        for (price_changes) |change| {
            const fuel_cost_change = base_costs.toDollars() * (fuel_percent_of_costs / 100.0) * (change / 100.0);
            const new_total_costs = base_costs.toDollars() + fuel_cost_change;

            try results.append(std.heap.page_allocator, .{
                .parameter = "Fuel Price",
                .change_percent = change,
                .resulting_value = new_total_costs,
                .impact_percent = (fuel_cost_change / base_costs.toDollars()) * 100.0,
            });
        }

        return results;
    }

    pub const SensitivityResult = struct {
        parameter: []const u8,
        change_percent: f64,
        resulting_value: f64,
        impact_percent: f64,
    };
};

/// Generate comprehensive scenario report
pub fn generateScenarioReport(
    _: std.mem.Allocator,
    scenarios: []const ScenarioOutcome,
) ![]u8 {
    var report = std.ArrayList(u8){};
    var writer = report.writer();

    try writer.print("\n=== COMPREHENSIVE SCENARIO ANALYSIS ===\n\n", .{});
    try writer.print("Total Scenarios Analyzed: {d}\n\n", .{scenarios.len});

    for (scenarios, 0..) |scenario, i| {
        try writer.print("Scenario {d}: {s}\n", .{ i + 1, scenario.description });
        try writer.print("  Probability: {d:.1}%\n", .{scenario.probability * 100.0});
        try writer.print("  Expected Profit: ${d:.2}\n", .{scenario.projected_profit.toDollars()});
        try writer.print("  Expected Value: ${d:.2}\n", .{scenario.calculateExpectedValue().toDollars()});
        try writer.print("  ROI: {d:.1}%\n", .{scenario.roi});
        try writer.print("  Risk Level: {s}\n", .{@tagName(scenario.risk_level)});
        try writer.print("  Payback Period: {d} days\n\n", .{scenario.payback_period_days});
    }

    return report.toOwnedSlice();
}
