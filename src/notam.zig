const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");

// ============================================================================
// NOTAM (Notice to Airmen) INTEGRATION AND DECODING
// ============================================================================

/// NOTAM data source configuration
pub const NotamConfig = struct {
    enabled: bool,
    update_interval_seconds: u64,
    faa_endpoint: []const u8,
    icao_endpoint: []const u8,
    radius_km: f32, // Search radius around airport

    pub fn initDefault() NotamConfig {
        return .{
            .enabled = true,
            .update_interval_seconds = 3600, // Update every hour
            .faa_endpoint = "https://notams.aim.faa.gov/notamSearch/search",
            .icao_endpoint = "https://www.notams.faa.gov/dinsQueryWeb/",
            .radius_km = 50.0, // 50km radius around airport
        };
    }

    pub fn initDisabled() NotamConfig {
        return .{
            .enabled = false,
            .update_interval_seconds = 3600,
            .faa_endpoint = "",
            .icao_endpoint = "",
            .radius_km = 50.0,
        };
    }
};

/// NOTAM classification categories
pub const NotamCategory = enum {
    // Aerodrome
    aerodrome_closure,
    runway_closure,
    taxiway_closure,
    apron_closure,

    // Navigation aids
    navaid_unserviceable,
    navaid_limited,

    // Lighting
    lighting_unserviceable,
    approach_lighting,

    // Airspace
    airspace_restriction,
    temporary_flight_restriction,
    military_activity,

    // Obstacles
    obstacle_new,
    obstacle_change,
    construction,

    // Services
    fuel_unavailable,
    customs_closed,
    atc_service_change,

    // Meteorological
    weather_reporting_limited,

    // Other
    general_warning,
    bird_activity,
    other,

    pub fn getSeverity(self: NotamCategory) NotamSeverity {
        return switch (self) {
            .aerodrome_closure, .runway_closure, .airspace_restriction, .temporary_flight_restriction => .critical,
            .navaid_unserviceable, .lighting_unserviceable, .taxiway_closure => .high,
            .navaid_limited, .approach_lighting, .fuel_unavailable, .construction => .medium,
            .weather_reporting_limited, .bird_activity, .general_warning, .other => .low,
            else => .medium,
        };
    }
};

pub const NotamSeverity = enum {
    low,
    medium,
    high,
    critical,
};

/// Decoded NOTAM
pub const Notam = struct {
    id: []const u8, // NOTAM identifier (e.g., "!JFK 01/001")
    location: []const u8, // ICAO code
    category: NotamCategory,
    severity: NotamSeverity,

    // Time validity
    start_time: u64, // Unix timestamp
    end_time: u64, // Unix timestamp
    is_permanent: bool,

    // Content
    subject: []const u8,
    condition: []const u8,
    raw_text: []const u8,

    // Affected areas/items
    affected_runway: ?[]const u8,
    affected_navaid: ?[]const u8,

    // Coordinates (if applicable)
    latitude: ?f32,
    longitude: ?f32,
    radius_nm: ?f32,

    // Altitudes (if applicable)
    lower_limit_ft: ?u32,
    upper_limit_ft: ?u32,

    // Schedule (if applicable)
    schedule: ?[]const u8, // Human readable schedule

    pub fn isActive(self: Notam, current_time: u64) bool {
        if (self.is_permanent) return true;
        return current_time >= self.start_time and current_time <= self.end_time;
    }

    pub fn affectsAirport(self: Notam, icao_code: [4]u8) bool {
        const icao_str = std.mem.sliceTo(&icao_code, 0);
        return std.mem.eql(u8, self.location, icao_str);
    }

    pub fn formatForDisplay(self: Notam, allocator: std.mem.Allocator) ![]u8 {
        const severity_str = switch (self.severity) {
            .low => "LOW",
            .medium => "MEDIUM",
            .high => "HIGH",
            .critical => "CRITICAL",
        };

        const category_str = @tagName(self.category);

        return try std.fmt.allocPrint(allocator,
            "[{s}] {s} - {s}\n{s}: {s}\nValid: {d} to {d}\n{s}",
            .{
                severity_str,
                self.id,
                category_str,
                self.subject,
                self.condition,
                self.start_time,
                self.end_time,
                self.raw_text,
            }
        );
    }
};

/// NOTAM parser for ICAO format
pub const NotamParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NotamParser {
        return .{ .allocator = allocator };
    }

    /// Parse ICAO format NOTAM
    /// Format: (Q) (A) (B) (C) (D) (E) (F) (G)
    /// Example:
    /// Q) KZNY/QFALT/IV/BO/A/000/999/4038N07346W005
    /// A) KJFK
    /// B) 2401151200
    /// C) 2401291200
    /// E) RWY 13R/31L CLSD
    pub fn parseICAO(self: *NotamParser, raw_text: []const u8) !Notam {
        var lines = std.mem.split(u8, raw_text, "\n");

        var q_line: ?[]const u8 = null;
        var a_line: ?[]const u8 = null;
        var b_line: ?[]const u8 = null;
        var c_line: ?[]const u8 = null;
        var e_line: ?[]const u8 = null;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\n\t");
            if (trimmed.len < 2) continue;

            if (std.mem.startsWith(u8, trimmed, "Q)")) q_line = trimmed;
            if (std.mem.startsWith(u8, trimmed, "A)")) a_line = trimmed;
            if (std.mem.startsWith(u8, trimmed, "B)")) b_line = trimmed;
            if (std.mem.startsWith(u8, trimmed, "C)")) c_line = trimmed;
            if (std.mem.startsWith(u8, trimmed, "E)")) e_line = trimmed;
        }

        // Extract location (A line)
        const location = if (a_line) |a|
            std.mem.trim(u8, a[2..], " ")
        else
            "UNKN";

        // Extract start time (B line) - format: YYMMDDhhmm
        const start_time = if (b_line) |b|
            try self.parseNotamTime(std.mem.trim(u8, b[2..], " "))
        else
            @as(u64, @intCast(std.time.timestamp()));

        // Extract end time (C line)
        const end_time = if (c_line) |c| blk: {
            const time_str = std.mem.trim(u8, c[2..], " ");
            if (std.mem.eql(u8, time_str, "PERM") or std.mem.eql(u8, time_str, "PERMANENT")) {
                break :blk start_time + (365 * 86400); // 1 year
            } else {
                break :blk try self.parseNotamTime(time_str);
            }
        } else start_time + 86400;

        const is_permanent = if (c_line) |c|
            std.mem.indexOf(u8, c, "PERM") != null
        else
            false;

        // Extract condition (E line)
        const condition = if (e_line) |e|
            try self.allocator.dupe(u8, std.mem.trim(u8, e[2..], " "))
        else
            try self.allocator.dupe(u8, "NO CONDITION SPECIFIED");

        // Categorize based on Q line and E line content
        const category = self.categorizeNotam(q_line, e_line);

        // Parse coordinates from Q line if present
        var latitude: ?f32 = null;
        var longitude: ?f32 = null;
        var radius_nm: ?f32 = null;

        if (q_line) |q| {
            // Q line format includes coordinates: .../XXXXNYYYYYYW999
            // Try to extract coordinates
            if (std.mem.indexOf(u8, q, "N")) |n_pos| {
                if (std.mem.indexOf(u8, q[n_pos..], "W")) |w_offset| {
                    const w_pos = n_pos + w_offset;
                    // Parse lat/lon (simplified)
                    latitude = 40.0; // Placeholder
                    longitude = -73.0; // Placeholder
                }
            }
        }

        // Generate NOTAM ID
        const id = try std.fmt.allocPrint(self.allocator, "!{s} {d}", .{ location, start_time });

        return Notam{
            .id = id,
            .location = try self.allocator.dupe(u8, location),
            .category = category,
            .severity = category.getSeverity(),
            .start_time = start_time,
            .end_time = end_time,
            .is_permanent = is_permanent,
            .subject = try self.extractSubject(q_line, e_line),
            .condition = condition,
            .raw_text = try self.allocator.dupe(u8, raw_text),
            .affected_runway = try self.extractRunway(e_line),
            .affected_navaid = try self.extractNavaid(e_line),
            .latitude = latitude,
            .longitude = longitude,
            .radius_nm = radius_nm,
            .lower_limit_ft = null,
            .upper_limit_ft = null,
            .schedule = null,
        };
    }

    fn parseNotamTime(self: NotamParser, time_str: []const u8) !u64 {
        _ = self;
        // NOTAM time format: YYMMDDhhmm
        // Simplified parser - in production should handle full date parsing

        if (time_str.len < 10) return @as(u64, @intCast(std.time.timestamp()));

        // For now, return current time + offset
        // In production, parse the actual date/time
        const now = @as(u64, @intCast(std.time.timestamp()));
        return now + 3600; // 1 hour from now
    }

    fn categorizeNotam(self: NotamParser, q_line: ?[]const u8, e_line: ?[]const u8) NotamCategory {
        _ = self;

        // Check Q line codes
        if (q_line) |q| {
            if (std.mem.indexOf(u8, q, "/QFALT/") != null) return .aerodrome_closure;
            if (std.mem.indexOf(u8, q, "/QMRLT/") != null) return .runway_closure;
            if (std.mem.indexOf(u8, q, "/QMXLT/") != null) return .taxiway_closure;
            if (std.mem.indexOf(u8, q, "/QNMAS/") != null) return .navaid_unserviceable;
            if (std.mem.indexOf(u8, q, "/QOLAS/") != null) return .lighting_unserviceable;
            if (std.mem.indexOf(u8, q, "/QRTCA/") != null) return .temporary_flight_restriction;
        }

        // Check E line keywords
        if (e_line) |e| {
            const upper = std.ascii.upperString(e, e) catch return .other;

            if (std.mem.indexOf(u8, upper, "RWY") != null and std.mem.indexOf(u8, upper, "CLSD") != null)
                return .runway_closure;
            if (std.mem.indexOf(u8, upper, "CLOSED") != null)
                return .aerodrome_closure;
            if (std.mem.indexOf(u8, upper, "TWY") != null and std.mem.indexOf(u8, upper, "CLSD") != null)
                return .taxiway_closure;
            if (std.mem.indexOf(u8, upper, "OBST") != null)
                return .obstacle_new;
            if (std.mem.indexOf(u8, upper, "CONSTRUCTION") != null or std.mem.indexOf(u8, upper, "CONST") != null)
                return .construction;
            if (std.mem.indexOf(u8, upper, "FUEL") != null and std.mem.indexOf(u8, upper, "UNAVBL") != null)
                return .fuel_unavailable;
            if (std.mem.indexOf(u8, upper, "NAVAID") != null or std.mem.indexOf(u8, upper, "VOR") != null or
                std.mem.indexOf(u8, upper, "ILS") != null)
                return .navaid_unserviceable;
            if (std.mem.indexOf(u8, upper, "LIGHT") != null)
                return .lighting_unserviceable;
            if (std.mem.indexOf(u8, upper, "AIRSPACE") != null or std.mem.indexOf(u8, upper, "TFR") != null)
                return .airspace_restriction;
            if (std.mem.indexOf(u8, upper, "BIRD") != null)
                return .bird_activity;
        }

        return .other;
    }

    fn extractSubject(self: NotamParser, q_line: ?[]const u8, e_line: ?[]const u8) ![]const u8 {
        if (e_line) |e| {
            // Extract first part of E line as subject
            const trimmed = std.mem.trim(u8, e[2..], " ");
            if (trimmed.len > 50) {
                return try self.allocator.dupe(u8, trimmed[0..50]);
            }
            return try self.allocator.dupe(u8, trimmed);
        }

        if (q_line) |q| {
            return try self.allocator.dupe(u8, "See Q line for details");
        }

        return try self.allocator.dupe(u8, "NOTAM");
    }

    fn extractRunway(self: NotamParser, e_line: ?[]const u8) !?[]const u8 {
        if (e_line) |e| {
            // Look for runway designators like "RWY 13R/31L" or "RUNWAY 09"
            if (std.mem.indexOf(u8, e, "RWY ")) |idx| {
                const start = idx + 4;
                const end = std.mem.indexOfAnyPos(u8, e, start, " \n\r") orelse e.len;
                const runway = std.mem.trim(u8, e[start..end], " /");
                if (runway.len > 0 and runway.len < 10) {
                    return try self.allocator.dupe(u8, runway);
                }
            }
        }
        return null;
    }

    fn extractNavaid(self: NotamParser, e_line: ?[]const u8) !?[]const u8 {
        if (e_line) |e| {
            // Look for navaid identifiers
            const navaids = [_][]const u8{ "VOR", "DME", "NDB", "ILS", "TACAN", "LOC" };
            for (navaids) |navaid| {
                if (std.mem.indexOf(u8, e, navaid)) |_| {
                    return try self.allocator.dupe(u8, navaid);
                }
            }
        }
        return null;
    }
};

/// NOTAM service manager
pub const NotamService = struct {
    allocator: std.mem.Allocator,
    config: NotamConfig,
    cache: std.AutoHashMap(u32, AirportNotams), // Airport ID -> NOTAMs
    parser: NotamParser,
    http_client: std.http.Client,

    pub const AirportNotams = struct {
        airport_id: u32,
        notams: std.ArrayList(Notam),
        fetched_at: u64,
        active_count: u32,
        critical_count: u32,
    };

    pub fn init(allocator: std.mem.Allocator, config: NotamConfig) NotamService {
        return .{
            .allocator = allocator,
            .config = config,
            .cache = std.AutoHashMap(u32, AirportNotams).init(allocator),
            .parser = NotamParser.init(allocator),
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *NotamService) void {
        var it = self.cache.valueIterator();
        while (it.next()) |airport_notams| {
            for (airport_notams.notams.items) |notam| {
                self.allocator.free(notam.id);
                self.allocator.free(notam.location);
                self.allocator.free(notam.subject);
                self.allocator.free(notam.condition);
                self.allocator.free(notam.raw_text);
                if (notam.affected_runway) |rwy| self.allocator.free(rwy);
                if (notam.affected_navaid) |nav| self.allocator.free(nav);
            }
            airport_notams.notams.deinit();
        }
        self.cache.deinit();
        self.http_client.deinit();
    }

    /// Fetch NOTAMs for specific airport
    pub fn fetchNotamsForAirport(
        self: *NotamService,
        airport_id: u32,
        icao_code: [4]u8,
        latitude: f32,
        longitude: f32,
    ) !AirportNotams {
        const now = @as(u64, @intCast(std.time.timestamp()));

        // Check cache
        if (self.cache.get(airport_id)) |cached| {
            if (now - cached.fetched_at < self.config.update_interval_seconds) {
                return cached;
            }
        }

        if (self.config.enabled) {
            // Fetch from real sources
            const notams = try self.fetchFromAPI(icao_code, latitude, longitude);

            var airport_notams = AirportNotams{
                .airport_id = airport_id,
                .notams = notams,
                .fetched_at = now,
                .active_count = 0,
                .critical_count = 0,
            };

            // Count active and critical NOTAMs
            for (notams.items) |notam| {
                if (notam.isActive(now)) {
                    airport_notams.active_count += 1;
                    if (notam.severity == .critical) {
                        airport_notams.critical_count += 1;
                    }
                }
            }

            try self.cache.put(airport_id, airport_notams);
            return airport_notams;
        } else {
            // Generate simulated NOTAMs
            return try self.generateSimulatedNotams(airport_id, icao_code, now);
        }
    }

    fn fetchFromAPI(
        self: *NotamService,
        icao_code: [4]u8,
        latitude: f32,
        longitude: f32,
    ) !std.ArrayList(Notam) {
        _ = latitude;
        _ = longitude;

        var notams = std.ArrayList(Notam).init(self.allocator);

        // Build URL for FAA NOTAM search
        const icao_str = std.mem.sliceTo(&icao_code, 0);
        var url_buffer: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buffer,
            "{s}?icao={s}",
            .{ self.config.faa_endpoint, icao_str }
        );

        // Make HTTP request (simplified - production would handle auth, parsing, etc.)
        var req = self.http_client.open(.GET, try std.Uri.parse(url), .{}) catch {
            // If API fails, return empty list
            return notams;
        };
        defer req.deinit();

        req.send() catch return notams;
        req.finish() catch return notams;
        req.wait() catch return notams;

        // Read and parse response
        // In production, this would parse JSON/XML response from FAA
        // For now, return empty list on API call

        return notams;
    }

    fn generateSimulatedNotams(
        self: *NotamService,
        airport_id: u32,
        icao_code: [4]u8,
        timestamp: u64,
    ) !AirportNotams {
        const icao_str = std.mem.sliceTo(&icao_code, 0);
        var notams = std.ArrayList(Notam).init(self.allocator);

        // Generate 1-3 simulated NOTAMs per airport
        const notam_count = 1 + (@mod(airport_id, 3));

        var i: u32 = 0;
        while (i < notam_count) : (i += 1) {
            const category: NotamCategory = switch (@mod(airport_id + i, 8)) {
                0 => .construction,
                1 => .taxiway_closure,
                2 => .lighting_unserviceable,
                3 => .navaid_limited,
                4 => .bird_activity,
                5 => .general_warning,
                6 => .fuel_unavailable,
                else => .other,
            };

            const start_time = timestamp - 86400; // Started yesterday
            const end_time = timestamp + (7 * 86400); // Ends in 7 days

            const id = try std.fmt.allocPrint(self.allocator, "!{s} {d}/{d:0>3}", .{ icao_str, @mod(timestamp / 86400, 100), i + 1 });
            const subject = try std.fmt.allocPrint(self.allocator, "{s} - {s}", .{ icao_str, @tagName(category) });
            const condition = try std.fmt.allocPrint(self.allocator,
                "SIMULATED NOTAM FOR TESTING - {s}",
                .{ @tagName(category) }
            );
            const raw = try std.fmt.allocPrint(self.allocator,
                "Q) KZNY/Q{s}/IV/BO/A/000/999/\nA) {s}\nB) {d}\nC) {d}\nE) {s}",
                .{ "XXXX", icao_str, start_time, end_time, condition }
            );

            try notams.append(Notam{
                .id = id,
                .location = try self.allocator.dupe(u8, icao_str),
                .category = category,
                .severity = category.getSeverity(),
                .start_time = start_time,
                .end_time = end_time,
                .is_permanent = false,
                .subject = subject,
                .condition = condition,
                .raw_text = raw,
                .affected_runway = null,
                .affected_navaid = null,
                .latitude = null,
                .longitude = null,
                .radius_nm = null,
                .lower_limit_ft = null,
                .upper_limit_ft = null,
                .schedule = null,
            });
        }

        return AirportNotams{
            .airport_id = airport_id,
            .notams = notams,
            .fetched_at = timestamp,
            .active_count = @intCast(notams.items.len),
            .critical_count = 0,
        };
    }

    /// Update NOTAMs for all airports
    pub fn updateAllAirports(self: *NotamService, airports: []entities.Airport) !void {
        std.debug.print("\n[NOTAM Update] Fetching NOTAMs for {d} airports...\n", .{airports.len});

        for (airports) |*airport| {
            const airport_notams = try self.fetchNotamsForAirport(
                airport.id,
                airport.icao_code,
                airport.location.latitude,
                airport.location.longitude,
            );

            std.debug.print("  {s}: {d} active NOTAMs", .{
                std.mem.sliceTo(&airport.iata_code, 0),
                airport_notams.active_count,
            });

            if (airport_notams.critical_count > 0) {
                std.debug.print(" ({d} CRITICAL)", .{airport_notams.critical_count});
            }
            std.debug.print("\n", .{});

            // Apply operational impact
            self.applyNotamsToAirport(airport, &airport_notams);
        }
    }

    fn applyNotamsToAirport(self: NotamService, airport: *entities.Airport, airport_notams: *const AirportNotams) void {
        _ = self;
        const now = @as(u64, @intCast(std.time.timestamp()));

        for (airport_notams.notams.items) |notam| {
            if (!notam.isActive(now)) continue;

            switch (notam.category) {
                .aerodrome_closure => {
                    airport.operational_status = false;
                },
                .runway_closure => {
                    // Mark specific runway as closed
                    if (notam.affected_runway) |_| {
                        // In full implementation, mark specific runway
                    }
                },
                .fuel_unavailable => {
                    // Set fuel availability flag
                },
                .navaid_unserviceable => {
                    // Mark navigation aid as unavailable
                },
                else => {},
            }
        }
    }

    /// Get active NOTAMs for display
    pub fn getActiveNotams(self: *NotamService, airport_id: u32) ?[]Notam {
        if (self.cache.get(airport_id)) |airport_notams| {
            const now = @as(u64, @intCast(std.time.timestamp()));

            // Filter active NOTAMs
            var active = std.ArrayList(Notam).init(self.allocator);
            for (airport_notams.notams.items) |notam| {
                if (notam.isActive(now)) {
                    active.append(notam) catch continue;
                }
            }

            return active.toOwnedSlice() catch null;
        }
        return null;
    }
};
