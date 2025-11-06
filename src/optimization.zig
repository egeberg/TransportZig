const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const economics = @import("economics.zig");
const simulation = @import("simulation.zig");

// ============================================================================
// OPTIMIZATION ALGORITHMS - RESOURCE ALLOCATION & DECISION OPTIMIZATION
// ============================================================================

/// Route optimization result
pub const RouteOptimization = struct {
    route_id: u32,
    origin_id: u32,
    destination_id: u32,
    optimal_aircraft: types.AircraftType,
    optimal_frequency: u32, // flights per week
    expected_annual_profit: types.Money,
    utilization_score: f64,

    pub fn compare(a: RouteOptimization, b: RouteOptimization) std.math.Order {
        const a_profit = a.expected_annual_profit.toDollars();
        const b_profit = b.expected_annual_profit.toDollars();
        if (a_profit > b_profit) return .gt;
        if (a_profit < b_profit) return .lt;
        return .eq;
    }
};

/// Fleet composition optimizer
pub const FleetOptimizer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FleetOptimizer {
        return .{ .allocator = allocator };
    }

    /// Find optimal fleet mix given budget and demand
    pub fn optimizeFleetMix(
        self: FleetOptimizer,
        total_budget: types.Money,
        demand_tons_per_day: f32,
        route_distances: []const f32,
    ) !FleetMixSolution {
        var best_solution = FleetMixSolution.init(self.allocator);
        var best_score: f64 = -std.math.inf(f64);

        // Try different combinations
        const aircraft_types = [_]types.AircraftType{
            .small_cargo,
            .medium_cargo,
            .large_cargo,
            .heavy_cargo,
        };

        // Greedy algorithm with dynamic programming
        var remaining_budget = total_budget.toDollars();
        var remaining_demand = demand_tons_per_day;

        for (aircraft_types) |aircraft_type| {
            const cost = aircraft_type.purchaseCost().toDollars();
            if (cost > remaining_budget) continue;

            const capacity = aircraft_type.payloadCapacity();
            const count = @min(
                @as(u32, @intFromFloat(remaining_budget / cost)),
                @as(u32, @intFromFloat(remaining_demand / capacity)) + 1,
            );

            if (count > 0) {
                try best_solution.aircraft_counts.put(aircraft_type, count);
                remaining_budget -= cost * @as(f64, @floatFromInt(count));
                remaining_demand -= capacity * @as(f32, @floatFromInt(count));

                best_solution.total_cost = best_solution.total_cost.add(
                    aircraft_type.purchaseCost().multiply(@as(f64, @floatFromInt(count))),
                );
                best_solution.total_capacity += capacity * @as(f32, @floatFromInt(count));
            }
        }

        // Calculate average distance compatibility
        var avg_distance: f32 = 0;
        for (route_distances) |d| avg_distance += d;
        avg_distance /= @as(f32, @floatFromInt(route_distances.len));
        best_solution.avg_route_distance = avg_distance;

        best_solution.capacity_utilization = @min(100.0, (demand_tons_per_day / best_solution.total_capacity) * 100.0);
        best_solution.total_aircraft = @intCast(best_solution.aircraft_counts.count());

        return best_solution;
    }

    pub const FleetMixSolution = struct {
        aircraft_counts: std.AutoHashMap(types.AircraftType, u32),
        total_cost: types.Money,
        total_capacity: f32,
        total_aircraft: u32,
        capacity_utilization: f64,
        avg_route_distance: f32,

        pub fn init(allocator: std.mem.Allocator) FleetMixSolution {
            return .{
                .aircraft_counts = std.AutoHashMap(types.AircraftType, u32).init(allocator),
                .total_cost = types.Money.init(0),
                .total_capacity = 0,
                .total_aircraft = 0,
                .capacity_utilization = 0,
                .avg_route_distance = 0,
            };
        }

        pub fn deinit(self: *FleetMixSolution) void {
            self.aircraft_counts.deinit();
        }
    };
};

/// Dynamic pricing optimizer
pub const PricingOptimizer = struct {
    /// Find optimal price point using demand curve
    pub fn optimizePrice(
        base_demand: f64,
        base_price: f64,
        cost_per_unit: f64,
        elasticity: f64,
    ) OptimalPrice {
        // Using calculus: MR = MC for profit maximization
        // Demand: Q = base_demand * (base_price / P)^elasticity
        // Revenue: R = P * Q
        // MR = dR/dP, MC = cost_per_unit

        const optimal_markup = 1.0 / (1.0 + (1.0 / elasticity));
        const optimal_price = cost_per_unit / optimal_markup;

        const optimal_demand = base_demand * std.math.pow(f64, base_price / optimal_price, elasticity);
        const optimal_revenue = optimal_price * optimal_demand;
        const optimal_profit = (optimal_price - cost_per_unit) * optimal_demand;

        return .{
            .price = optimal_price,
            .expected_demand = optimal_demand,
            .expected_revenue = optimal_revenue,
            .expected_profit = optimal_profit,
            .margin_percent = ((optimal_price - cost_per_unit) / optimal_price) * 100.0,
        };
    }

    pub const OptimalPrice = struct {
        price: f64,
        expected_demand: f64,
        expected_revenue: f64,
        expected_profit: f64,
        margin_percent: f64,
    };
};

/// Resource allocation optimizer (Hungarian algorithm inspired)
pub const ResourceAllocator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResourceAllocator {
        return .{ .allocator = allocator };
    }

    /// Assign aircraft to routes optimally
    pub fn assignAircraftToRoutes(
        self: ResourceAllocator,
        aircraft: []const entities.Aircraft,
        routes: []const RouteRequest,
    ) !std.ArrayList(Assignment) {
        var assignments = std.ArrayList(Assignment).init(self.allocator);

        // Create cost matrix
        var cost_matrix = try self.allocator.alloc([]f64, aircraft.len);
        defer {
            for (cost_matrix) |row| self.allocator.free(row);
            self.allocator.free(cost_matrix);
        }

        for (cost_matrix, 0..) |*row, i| {
            row.* = try self.allocator.alloc(f64, routes.len);
            for (row.*, 0..) |*cell, j| {
                cell.* = calculateAssignmentCost(aircraft[i], routes[j]);
            }
        }

        // Greedy assignment (simplified Hungarian algorithm)
        var assigned_aircraft = std.AutoHashMap(u32, bool).init(self.allocator);
        defer assigned_aircraft.deinit();
        var assigned_routes = std.AutoHashMap(u32, bool).init(self.allocator);
        defer assigned_routes.deinit();

        while (assignments.items.len < @min(aircraft.len, routes.len)) {
            var best_cost: f64 = std.math.inf(f64);
            var best_aircraft_idx: usize = 0;
            var best_route_idx: usize = 0;

            for (cost_matrix, 0..) |row, i| {
                if (assigned_aircraft.contains(@intCast(i))) continue;

                for (row, 0..) |cost, j| {
                    if (assigned_routes.contains(@intCast(j))) continue;
                    if (cost < best_cost) {
                        best_cost = cost;
                        best_aircraft_idx = i;
                        best_route_idx = j;
                    }
                }
            }

            try assignments.append(.{
                .aircraft_id = aircraft[best_aircraft_idx].id,
                .route_id = routes[best_route_idx].id,
                .cost = best_cost,
                .profit_potential = routes[best_route_idx].estimated_profit - best_cost,
            });

            try assigned_aircraft.put(@intCast(best_aircraft_idx), true);
            try assigned_routes.put(@intCast(best_route_idx), true);
        }

        return assignments;
    }

    fn calculateAssignmentCost(aircraft: entities.Aircraft, route: RouteRequest) f64 {
        // Calculate suitability score (lower is better)
        var cost: f64 = 0;

        // Distance suitability
        const max_range = aircraft.aircraft_type.range();
        if (route.distance_km > max_range) {
            return std.math.inf(f64); // Impossible
        }

        const range_utilization = route.distance_km / max_range;
        cost += @abs(range_utilization - 0.8) * 1000.0; // Prefer 80% range utilization

        // Capacity match
        const capacity = aircraft.aircraft_type.payloadCapacity();
        const capacity_utilization = route.required_capacity_tons / capacity;
        if (capacity_utilization > 1.0) {
            return std.math.inf(f64); // Insufficient capacity
        }
        cost += @abs(capacity_utilization - 0.85) * 500.0; // Prefer 85% capacity

        // Operational cost
        const operating_cost = aircraft.aircraft_type.operatingCostPerKm().toDollars();
        cost += operating_cost * route.distance_km;

        return cost;
    }

    pub const RouteRequest = struct {
        id: u32,
        distance_km: f32,
        required_capacity_tons: f32,
        estimated_profit: f64,
    };

    pub const Assignment = struct {
        aircraft_id: u32,
        route_id: u32,
        cost: f64,
        profit_potential: f64,
    };
};

/// Schedule optimizer for flight timing
pub const ScheduleOptimizer = struct {
    /// Find optimal departure times to maximize slot availability and minimize costs
    pub fn optimizeDepartureTimes(
        flights: []FlightRequest,
        time_window_hours: u32,
    ) !std.ArrayList(OptimalSchedule) {
        var schedules = std.ArrayList(OptimalSchedule).init(std.heap.page_allocator);

        // Sort by priority (profit potential)
        std.mem.sort(FlightRequest, flights, {}, struct {
            fn lessThan(_: void, a: FlightRequest, b: FlightRequest) bool {
                return a.priority > b.priority;
            }
        }.lessThan);

        var hour: u32 = 0;
        for (flights) |flight_req| {
            const optimal_hour = @mod(hour, time_window_hours);

            // Calculate slot cost multiplier
            const slot_multiplier = if (optimal_hour >= 6 and optimal_hour < 10)
                1.5 // Morning peak
            else if (optimal_hour >= 16 and optimal_hour < 20)
                1.5 // Evening peak
            else if (optimal_hour < 6)
                0.7 // Night discount
            else
                1.0; // Normal

            try schedules.append(.{
                .flight_id = flight_req.id,
                .departure_hour = optimal_hour,
                .slot_cost_multiplier = slot_multiplier,
                .expected_profit = flight_req.estimated_profit * (2.0 - slot_multiplier),
            });

            hour += 2; // Space flights 2 hours apart
        }

        return schedules;
    }

    pub const FlightRequest = struct {
        id: u32,
        priority: f64,
        estimated_profit: f64,
    };

    pub const OptimalSchedule = struct {
        flight_id: u32,
        departure_hour: u32,
        slot_cost_multiplier: f64,
        expected_profit: f64,
    };
};

/// Multi-objective optimization using weighted sum method
pub const MultiObjectiveOptimizer = struct {
    pub const Objective = enum {
        maximize_profit,
        minimize_risk,
        maximize_capacity_utilization,
        minimize_environmental_impact,
        maximize_customer_satisfaction,
    };

    pub const ObjectiveWeight = struct {
        objective: Objective,
        weight: f64, // 0.0 to 1.0
    };

    pub fn evaluateSolution(
        solution_metrics: SolutionMetrics,
        objectives: []const ObjectiveWeight,
    ) f64 {
        var total_score: f64 = 0;
        var total_weight: f64 = 0;

        for (objectives) |obj| {
            const score = switch (obj.objective) {
                .maximize_profit => solution_metrics.profit / 1000000.0, // Normalize
                .minimize_risk => 1.0 - solution_metrics.risk_score,
                .maximize_capacity_utilization => solution_metrics.capacity_utilization / 100.0,
                .minimize_environmental_impact => 1.0 - (solution_metrics.co2_tons / 10000.0),
                .maximize_customer_satisfaction => solution_metrics.customer_satisfaction / 100.0,
            };

            total_score += score * obj.weight;
            total_weight += obj.weight;
        }

        return if (total_weight > 0) total_score / total_weight else 0;
    }

    pub const SolutionMetrics = struct {
        profit: f64,
        risk_score: f64,
        capacity_utilization: f64,
        co2_tons: f64,
        customer_satisfaction: f64,
    };
};

/// Linear programming solver (simplified Simplex)
pub const LinearProgrammingSolver = struct {
    /// Solve: maximize c^T * x subject to A*x <= b, x >= 0
    pub fn solve(
        allocator: std.mem.Allocator,
        c: []const f64, // Objective coefficients
        A: []const []const f64, // Constraint matrix
        b: []const f64, // Constraint bounds
    ) !LPSolution {
        // Simplified solver - in production, use full Simplex algorithm
        var x = try allocator.alloc(f64, c.len);
        @memset(x, 0);

        // Greedy approximation
        for (c, 0..) |coef, i| {
            if (coef <= 0) continue;

            var max_feasible: f64 = std.math.inf(f64);
            for (A, 0..) |row, j| {
                if (row[i] > 0) {
                    max_feasible = @min(max_feasible, b[j] / row[i]);
                }
            }

            x[i] = @max(0, @min(max_feasible, 1000)); // Cap at 1000
        }

        var objective_value: f64 = 0;
        for (c, 0..) |coef, i| {
            objective_value += coef * x[i];
        }

        return .{
            .variables = x,
            .objective_value = objective_value,
            .is_optimal = false, // Approximation only
        };
    }

    pub const LPSolution = struct {
        variables: []f64,
        objective_value: f64,
        is_optimal: bool,
    };
};
