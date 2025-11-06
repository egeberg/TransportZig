const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");
const simulation = @import("simulation.zig");
const scenario = @import("scenario.zig");
const optimization = @import("optimization.zig");

// ============================================================================
// BUSINESS ANALYTICS AND KPIs
// ============================================================================

/// Key Performance Indicators
pub const KPIs = struct {
    // Financial KPIs
    total_revenue: types.Money,
    total_costs: types.Money,
    gross_profit: types.Money,
    profit_margin_percent: f64,
    revenue_per_flight: types.Money,
    cost_per_flight: types.Money,
    break_even_point: types.Money,

    // Operational KPIs
    fleet_utilization_percent: f64, // % of time aircraft are flying
    on_time_performance_percent: f64,
    average_load_factor_percent: f64, // % of cargo capacity used
    flights_per_day: f64,
    cargo_delivered_tons_per_day: f64,

    // Quality KPIs
    customer_satisfaction: f64, // 0-100
    safety_rating: f64, // 0-100
    cargo_damage_rate_percent: f64,
    delivery_success_rate_percent: f64,

    // Efficiency KPIs
    fuel_efficiency_kg_per_km: f64,
    cost_per_ton_km: f64,
    revenue_per_ton_km: f64,
    average_flight_time_hours: f64,

    // Growth KPIs
    revenue_growth_percent: f64,
    market_share_percent: f64,
    fleet_expansion_rate: f64,

    pub fn calculate(world: *simulation.SimulationWorld) KPIs {
        var kpis = KPIs{
            .total_revenue = types.Money.init(0),
            .total_costs = types.Money.init(0),
            .gross_profit = types.Money.init(0),
            .profit_margin_percent = 0,
            .revenue_per_flight = types.Money.init(0),
            .cost_per_flight = types.Money.init(0),
            .break_even_point = types.Money.init(0),
            .fleet_utilization_percent = 0,
            .on_time_performance_percent = 95.0,
            .average_load_factor_percent = 0,
            .flights_per_day = 0,
            .cargo_delivered_tons_per_day = 0,
            .customer_satisfaction = 85.0,
            .safety_rating = 100.0,
            .cargo_damage_rate_percent = 0.5,
            .delivery_success_rate_percent = 98.5,
            .fuel_efficiency_kg_per_km = 0,
            .cost_per_ton_km = 0,
            .revenue_per_ton_km = 0,
            .average_flight_time_hours = 0,
            .revenue_growth_percent = 0,
            .market_share_percent = 0,
            .fleet_expansion_rate = 0,
        };

        // Aggregate company financials
        for (world.companies.items) |company| {
            kpis.total_revenue = kpis.total_revenue.add(company.total_revenue);
            kpis.total_costs = kpis.total_costs.add(company.total_costs);
        }

        kpis.gross_profit = kpis.total_revenue.subtract(kpis.total_costs);

        // Calculate profit margin
        const rev = kpis.total_revenue.toDollars();
        if (rev > 0) {
            kpis.profit_margin_percent = (kpis.gross_profit.toDollars() / rev) * 100.0;
        }

        // Calculate per-flight metrics
        const completed_flights = world.stats.total_flights_completed;
        if (completed_flights > 0) {
            const flights_f64 = @as(f64, @floatFromInt(completed_flights));
            kpis.revenue_per_flight = kpis.total_revenue.multiply(1.0 / flights_f64);
            kpis.cost_per_flight = kpis.total_costs.multiply(1.0 / flights_f64);
        }

        // Fleet utilization
        var total_flying: u32 = 0;
        for (world.aircraft.items) |aircraft| {
            if (aircraft.status == .cruise or
                aircraft.status == .climbing or
                aircraft.status == .descending)
            {
                total_flying += 1;
            }
        }
        if (world.aircraft.items.len > 0) {
            kpis.fleet_utilization_percent = (@as(f64, @floatFromInt(total_flying)) /
                @as(f64, @floatFromInt(world.aircraft.items.len))) * 100.0;
        }

        // Load factor
        var total_capacity: f32 = 0;
        var total_load: f32 = 0;
        for (world.aircraft.items) |aircraft| {
            total_capacity += aircraft.aircraft_type.payloadCapacity();
            total_load += aircraft.current_cargo_weight;
        }
        if (total_capacity > 0) {
            kpis.average_load_factor_percent = (total_load / total_capacity) * 100.0;
        }

        // Flights per day
        const days = @max(1, world.current_time.seconds / 86400);
        kpis.flights_per_day = @as(f64, @floatFromInt(completed_flights)) / @as(f64, @floatFromInt(days));

        // Cargo delivered per day
        kpis.cargo_delivered_tons_per_day = world.stats.total_cargo_weight_kg / (1000.0 * @as(f64, @floatFromInt(days)));

        // Delivery success rate
        const total_cargo = world.stats.total_cargo_created;
        const delivered_cargo = world.stats.total_cargo_delivered;
        if (total_cargo > 0) {
            kpis.delivery_success_rate_percent = (@as(f64, @floatFromInt(delivered_cargo)) /
                @as(f64, @floatFromInt(total_cargo))) * 100.0;
        }

        return kpis;
    }

    pub fn printReport(self: KPIs) void {
        std.debug.print("\n=== BUSINESS ANALYTICS REPORT ===\n", .{});
        std.debug.print("\nFINANCIAL METRICS:\n", .{});
        std.debug.print("  Total Revenue: ${d:.2}\n", .{self.total_revenue.toDollars()});
        std.debug.print("  Total Costs: ${d:.2}\n", .{self.total_costs.toDollars()});
        std.debug.print("  Gross Profit: ${d:.2}\n", .{self.gross_profit.toDollars()});
        std.debug.print("  Profit Margin: {d:.2}%\n", .{self.profit_margin_percent});
        std.debug.print("  Revenue per Flight: ${d:.2}\n", .{self.revenue_per_flight.toDollars()});
        std.debug.print("  Cost per Flight: ${d:.2}\n", .{self.cost_per_flight.toDollars()});

        std.debug.print("\nOPERATIONAL METRICS:\n", .{});
        std.debug.print("  Fleet Utilization: {d:.1}%\n", .{self.fleet_utilization_percent});
        std.debug.print("  On-Time Performance: {d:.1}%\n", .{self.on_time_performance_percent});
        std.debug.print("  Average Load Factor: {d:.1}%\n", .{self.average_load_factor_percent});
        std.debug.print("  Flights per Day: {d:.2}\n", .{self.flights_per_day});
        std.debug.print("  Cargo Delivered: {d:.2} tons/day\n", .{self.cargo_delivered_tons_per_day});

        std.debug.print("\nQUALITY METRICS:\n", .{});
        std.debug.print("  Customer Satisfaction: {d:.1}/100\n", .{self.customer_satisfaction});
        std.debug.print("  Safety Rating: {d:.1}/100\n", .{self.safety_rating});
        std.debug.print("  Delivery Success Rate: {d:.2}%\n", .{self.delivery_success_rate_percent});

        std.debug.print("\n================================\n\n", .{});
    }
};

/// Decision support recommendations
pub const DecisionSupport = struct {
    pub const Recommendation = struct {
        priority: Priority,
        category: Category,
        message: []const u8,
        estimated_impact: f64, // Expected profit/cost impact

        pub const Priority = enum {
            low,
            medium,
            high,
            critical,
        };

        pub const Category = enum {
            financial,
            operational,
            strategic,
            risk,
        };
    };

    pub fn analyzeAndRecommend(allocator: std.mem.Allocator, world: *simulation.SimulationWorld) !std.ArrayList(Recommendation) {
        var recommendations = std.ArrayList(Recommendation).init(allocator);
        const kpis = KPIs.calculate(world);

        // Financial recommendations
        if (kpis.profit_margin_percent < 10.0) {
            try recommendations.append(.{
                .priority = .high,
                .category = .financial,
                .message = "Low profit margin - Consider optimizing routes or increasing cargo rates",
                .estimated_impact = kpis.total_revenue.toDollars() * 0.05,
            });
        }

        // Fleet utilization
        if (kpis.fleet_utilization_percent < 60.0) {
            try recommendations.append(.{
                .priority = .medium,
                .category = .operational,
                .message = "Low fleet utilization - Schedule more flights or reduce fleet size",
                .estimated_impact = kpis.total_costs.toDollars() * 0.1,
            });
        }

        // Load factor
        if (kpis.average_load_factor_percent < 70.0) {
            try recommendations.append(.{
                .priority = .medium,
                .category = .operational,
                .message = "Low cargo load factor - Improve cargo acquisition or use smaller aircraft",
                .estimated_impact = kpis.total_revenue.toDollars() * 0.08,
            });
        }

        // Market conditions
        switch (world.market_condition) {
            .boom, .growth => {
                try recommendations.append(.{
                    .priority = .high,
                    .category = .strategic,
                    .message = "Favorable market conditions - Consider expanding fleet",
                    .estimated_impact = kpis.total_revenue.toDollars() * 0.25,
                });
            },
            .recession => {
                try recommendations.append(.{
                    .priority = .critical,
                    .category = .risk,
                    .message = "Market recession - Focus on cost reduction and efficiency",
                    .estimated_impact = kpis.total_costs.toDollars() * -0.15,
                });
            },
            else => {},
        }

        // Profitability check
        if (kpis.gross_profit.isNegative()) {
            try recommendations.append(.{
                .priority = .critical,
                .category = .financial,
                .message = "CRITICAL: Operating at a loss - Immediate action required",
                .estimated_impact = -kpis.gross_profit.toDollars(),
            });
        }

        return recommendations;
    }
};

/// Route profitability analyzer
pub const RouteAnalyzer = struct {
    pub const RoutePerformance = struct {
        origin_id: u32,
        destination_id: u32,
        total_flights: u32,
        total_revenue: types.Money,
        total_costs: types.Money,
        profit_margin: f64,
        average_load_factor: f64,
        is_profitable: bool,
    };

    pub fn analyzeRoute(
        origin: u32,
        destination: u32,
        world: *simulation.SimulationWorld,
    ) RoutePerformance {
        var route_perf = RoutePerformance{
            .origin_id = origin,
            .destination_id = destination,
            .total_flights = 0,
            .total_revenue = types.Money.init(0),
            .total_costs = types.Money.init(0),
            .profit_margin = 0,
            .average_load_factor = 0,
            .is_profitable = false,
        };

        // Analyze completed flights on this route
        for (world.flight_scheduler.completed_flights.items) |completed| {
            if (completed.departure_airport == origin and
                completed.arrival_airport == destination)
            {
                route_perf.total_flights += 1;
                route_perf.total_revenue = route_perf.total_revenue.add(completed.estimated_revenue);
                route_perf.total_costs = route_perf.total_costs.add(completed.estimated_cost);
            }
        }

        if (route_perf.total_flights > 0) {
            const profit = route_perf.total_revenue.subtract(route_perf.total_costs);
            const rev = route_perf.total_revenue.toDollars();
            if (rev > 0) {
                route_perf.profit_margin = (profit.toDollars() / rev) * 100.0;
            }
            route_perf.is_profitable = !profit.isNegative();
        }

        return route_perf;
    }

    pub fn findMostProfitableRoutes(
        allocator: std.mem.Allocator,
        world: *simulation.SimulationWorld,
        top_n: usize,
    ) !std.ArrayList(RoutePerformance) {
        _ = allocator;
        _ = world;
        _ = top_n;
        // Placeholder for route ranking algorithm
        return std.ArrayList(RoutePerformance).init(allocator);
    }
};

/// Forecasting and predictive analytics
pub const Forecasting = struct {
    pub const Forecast = struct {
        period: u32, // days
        projected_revenue: types.Money,
        projected_costs: types.Money,
        projected_profit: types.Money,
        confidence_level: f64, // 0-100
    };

    pub fn forecastFinancials(world: *simulation.SimulationWorld, days_ahead: u32) Forecast {
        const kpis = KPIs.calculate(world);

        // Simple linear extrapolation based on current performance
        const current_days = @max(1, world.current_time.seconds / 86400);
        const daily_revenue = kpis.total_revenue.multiply(1.0 / @as(f64, @floatFromInt(current_days)));
        const daily_costs = kpis.total_costs.multiply(1.0 / @as(f64, @floatFromInt(current_days)));

        const projected_revenue = daily_revenue.multiply(@as(f64, @floatFromInt(days_ahead)));
        const projected_costs = daily_costs.multiply(@as(f64, @floatFromInt(days_ahead)));

        // Adjust for market conditions
        const market_factor = world.market_condition.demandMultiplier();
        const adjusted_revenue = projected_revenue.multiply(market_factor);

        return .{
            .period = days_ahead,
            .projected_revenue = adjusted_revenue,
            .projected_costs = projected_costs,
            .projected_profit = adjusted_revenue.subtract(projected_costs),
            .confidence_level = 75.0, // Medium confidence
        };
    }
};

/// Advanced Analytics Engine - Evaluates all possible scenarios and outcomes
pub const AdvancedAnalytics = struct {
    allocator: std.mem.Allocator,
    monte_carlo: scenario.MonteCarloSimulation,
    what_if: scenario.WhatIfAnalysis,
    fleet_optimizer: optimization.FleetOptimizer,
    resource_allocator: optimization.ResourceAllocator,

    pub fn init(allocator: std.mem.Allocator, seed: u64) AdvancedAnalytics {
        return .{
            .allocator = allocator,
            .monte_carlo = scenario.MonteCarloSimulation.init(allocator, 1000, seed),
            .what_if = scenario.WhatIfAnalysis.init(allocator),
            .fleet_optimizer = optimization.FleetOptimizer.init(allocator),
            .resource_allocator = optimization.ResourceAllocator.init(allocator),
        };
    }

    /// Run comprehensive scenario analysis covering all possibilities
    pub fn runComprehensiveAnalysis(
        self: *AdvancedAnalytics,
        world: *simulation.SimulationWorld,
    ) !ComprehensiveAnalysisReport {
        var report = ComprehensiveAnalysisReport{
            .scenarios = std.ArrayList(scenario.ScenarioOutcome).init(self.allocator),
            .optimizations = std.ArrayList(OptimizationResult).init(self.allocator),
            .recommendations = std.ArrayList(StrategicRecommendation).init(self.allocator),
        };

        // 1. Analyze pricing scenarios (-20% to +20%)
        const price_changes = [_]f64{ -20, -10, -5, 0, 5, 10, 15, 20 };
        for (price_changes) |change| {
            const outcome = try self.what_if.analyzePricingChange(world, change);
            try report.scenarios.append(outcome);
        }

        // 2. Analyze fleet expansion scenarios
        const aircraft_types = [_]types.AircraftType{
            .medium_cargo,
            .large_cargo,
            .heavy_cargo,
        };

        const fleet_scenarios = try self.monte_carlo.simulateFleetExpansion(
            &aircraft_types,
            types.Money.init(100_000_000), // $100M budget
            365, // 1 year horizon
        );
        defer fleet_scenarios.deinit();

        for (fleet_scenarios.items) |fleet_scenario| {
            try report.scenarios.append(fleet_scenario);
        }

        // 3. Route optimization
        if (world.airports.items.len >= 2) {
            for (world.airports.items[0..@min(3, world.airports.items.len)]) |origin| {
                for (world.airports.items[0..@min(3, world.airports.items.len)]) |destination| {
                    if (origin.id == destination.id) continue;

                    const route_outcome = try self.what_if.analyzeNewRoute(
                        origin,
                        destination,
                        .medium_cargo,
                        3, // 3x per week
                    );
                    try report.scenarios.append(route_outcome);
                }
            }
        }

        // 4. Fleet mix optimization
        if (world.cargo.items.len > 0) {
            var total_demand: f32 = 0;
            for (world.cargo.items) |c| total_demand += c.weight_kg / 1000.0; // to tons

            const daily_demand = @max(10.0, total_demand / 30.0); // Estimate daily

            const fleet_mix = try self.fleet_optimizer.optimizeFleetMix(
                types.Money.init(50_000_000),
                daily_demand,
                &[_]f32{ 1000, 2000, 3000 }, // Sample distances
            );
            defer fleet_mix.deinit();

            try report.optimizations.append(.{
                .type = .fleet_composition,
                .description = try std.fmt.allocPrint(
                    self.allocator,
                    "Optimal Fleet: {d} aircraft, {d:.1} tons capacity",
                    .{ fleet_mix.total_aircraft, fleet_mix.total_capacity },
                ),
                .expected_benefit = types.Money.init(5_000_000), // Estimated
                .implementation_cost = fleet_mix.total_cost,
                .payback_period_days = 365,
            });
        }

        // 5. Dynamic pricing optimization
        const pricing_opt = optimization.PricingOptimizer.optimizePrice(
            1000.0, // base demand
            100.0, // base price
            60.0, // cost per unit
            -0.8, // elasticity
        );

        try report.optimizations.append(.{
            .type = .pricing_strategy,
            .description = try std.fmt.allocPrint(
                self.allocator,
                "Optimal Price: ${d:.2} (margin: {d:.1}%)",
                .{ pricing_opt.price, pricing_opt.margin_percent },
            ),
            .expected_benefit = types.Money.init(pricing_opt.expected_profit),
            .implementation_cost = types.Money.init(0),
            .payback_period_days = 0,
        });

        // 6. Generate strategic recommendations
        try report.recommendations.append(try self.generateTopRecommendation(report.scenarios.items));

        // 7. Sort scenarios by expected value
        scenario.ScenarioComparator.rankByExpectedValue(report.scenarios.items);

        return report;
    }

    fn generateTopRecommendation(
        self: *AdvancedAnalytics,
        scenarios: []scenario.ScenarioOutcome,
    ) !StrategicRecommendation {
        if (scenarios.len == 0) {
            return StrategicRecommendation{
                .priority = .medium,
                .category = .strategic,
                .title = "Insufficient Data",
                .description = "Not enough data to generate recommendations",
                .expected_impact = types.Money.init(0),
                .confidence = 0.5,
            };
        }

        // Find best scenario
        var best = scenarios[0];
        for (scenarios) |s| {
            if (s.calculateExpectedValue().toDollars() > best.calculateExpectedValue().toDollars()) {
                best = s;
            }
        }

        return StrategicRecommendation{
            .priority = if (best.risk_level == .low and best.roi > 20) .high else .medium,
            .category = .strategic,
            .title = try self.allocator.dupe(u8, best.description),
            .description = try std.fmt.allocPrint(
                self.allocator,
                "Expected Value: ${d:.2} | ROI: {d:.1}% | Risk: {s}",
                .{ best.calculateExpectedValue().toDollars(), best.roi, @tagName(best.risk_level) },
            ),
            .expected_impact = best.projected_profit,
            .confidence = best.probability,
        };
    }

    pub const ComprehensiveAnalysisReport = struct {
        scenarios: std.ArrayList(scenario.ScenarioOutcome),
        optimizations: std.ArrayList(OptimizationResult),
        recommendations: std.ArrayList(StrategicRecommendation),

        pub fn deinit(self: *ComprehensiveAnalysisReport) void {
            self.scenarios.deinit();
            self.optimizations.deinit();
            self.recommendations.deinit();
        }

        pub fn printSummary(self: ComprehensiveAnalysisReport) void {
            std.debug.print("\n=== COMPREHENSIVE ANALYSIS REPORT ===\n\n", .{});
            std.debug.print("Total Scenarios Evaluated: {d}\n", .{self.scenarios.items.len});
            std.debug.print("Optimization Opportunities: {d}\n", .{self.optimizations.items.len});
            std.debug.print("Strategic Recommendations: {d}\n\n", .{self.recommendations.items.len});

            if (self.scenarios.items.len > 0) {
                std.debug.print("Top 3 Scenarios:\n", .{});
                for (self.scenarios.items[0..@min(3, self.scenarios.items.len)], 0..) |s, i| {
                    std.debug.print("  {d}. {s}\n", .{ i + 1, s.description });
                    std.debug.print("     Expected Value: ${d:.2}\n", .{s.calculateExpectedValue().toDollars()});
                    std.debug.print("     ROI: {d:.1}% | Risk: {s}\n\n", .{ s.roi, @tagName(s.risk_level) });
                }
            }

            if (self.recommendations.items.len > 0) {
                std.debug.print("Top Recommendation:\n", .{});
                const rec = self.recommendations.items[0];
                std.debug.print("  [{s}] {s}\n", .{ @tagName(rec.priority), rec.title });
                std.debug.print("  {s}\n", .{rec.description});
                std.debug.print("  Expected Impact: ${d:.2}\n", .{rec.expected_impact.toDollars()});
                std.debug.print("  Confidence: {d:.1}%\n", .{rec.confidence * 100.0});
            }
        }
    };

    pub const OptimizationResult = struct {
        type: OptimizationType,
        description: []const u8,
        expected_benefit: types.Money,
        implementation_cost: types.Money,
        payback_period_days: u32,

        pub const OptimizationType = enum {
            fleet_composition,
            route_network,
            pricing_strategy,
            resource_allocation,
            schedule_optimization,
        };
    };

    pub const StrategicRecommendation = struct {
        priority: Priority,
        category: Category,
        title: []const u8,
        description: []const u8,
        expected_impact: types.Money,
        confidence: f64, // 0-1

        pub const Priority = enum {
            low,
            medium,
            high,
            critical,
        };

        pub const Category = enum {
            financial,
            operational,
            strategic,
            risk_mitigation,
        };
    };
};
