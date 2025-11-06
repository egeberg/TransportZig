const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");

// ============================================================================
// REAL-WORLD WEATHER DATA INTEGRATION
// ============================================================================

/// Weather data provider configuration
pub const WeatherConfig = struct {
    api_key: []const u8,
    api_endpoint: []const u8,
    update_interval_seconds: u64,
    enabled: bool,

    pub fn initOpenWeatherMap(api_key: []const u8) WeatherConfig {
        return .{
            .api_key = api_key,
            .api_endpoint = "https://api.openweathermap.org/data/2.5/weather",
            .update_interval_seconds = 1800, // Update every 30 minutes
            .enabled = api_key.len > 0,
        };
    }

    pub fn initDefault() WeatherConfig {
        // Default config without API key - will use simulated weather
        return .{
            .api_key = "",
            .api_endpoint = "",
            .update_interval_seconds = 1800,
            .enabled = false,
        };
    }
};

/// Real-time weather data from API
pub const WeatherData = struct {
    temperature: f32, // Celsius
    feels_like: f32, // Celsius
    pressure: f32, // hPa
    humidity: u8, // Percentage
    visibility: f32, // km
    wind_speed: f32, // km/h
    wind_direction: f32, // degrees
    wind_gust: ?f32, // km/h
    clouds: u8, // Cloud coverage percentage
    rain_1h: ?f32, // Rain volume last hour (mm)
    snow_1h: ?f32, // Snow volume last hour (mm)
    weather_condition: WeatherConditionCode,
    timestamp: u64, // Unix timestamp

    pub const WeatherConditionCode = enum {
        clear,
        few_clouds,
        scattered_clouds,
        broken_clouds,
        shower_rain,
        rain,
        thunderstorm,
        snow,
        mist,
        fog,

        pub fn toSimulationWeather(self: WeatherConditionCode) types.WeatherCondition {
            return switch (self) {
                .clear => .clear,
                .few_clouds => .light_clouds,
                .scattered_clouds, .broken_clouds => .overcast,
                .shower_rain, .rain => .rain,
                .thunderstorm => .storm,
                .snow => .snow,
                .mist, .fog => .fog,
            };
        }
    };

    pub fn fromOpenWeatherMapJSON(allocator: std.mem.Allocator, json_str: []const u8) !WeatherData {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Extract main weather parameters
        const main = root.get("main").?.object;
        const temperature = @as(f32, @floatCast(main.get("temp").?.float - 273.15)); // Kelvin to Celsius
        const feels_like = @as(f32, @floatCast(main.get("feels_like").?.float - 273.15));
        const pressure = @as(f32, @floatCast(main.get("pressure").?.float));
        const humidity = @as(u8, @intFromFloat(main.get("humidity").?.float));

        // Wind data
        const wind = root.get("wind").?.object;
        const wind_speed = @as(f32, @floatCast(wind.get("speed").?.float * 3.6)); // m/s to km/h
        const wind_deg = @as(f32, @floatCast(wind.get("deg").?.float));
        const wind_gust = if (wind.get("gust")) |gust|
            @as(f32, @floatCast(gust.float * 3.6))
        else
            null;

        // Visibility
        const visibility_m = if (root.get("visibility")) |vis|
            @as(f32, @floatCast(vis.float))
        else
            10000.0;
        const visibility = visibility_m / 1000.0; // meters to km

        // Clouds
        const clouds = root.get("clouds").?.object;
        const cloud_coverage = @as(u8, @intFromFloat(clouds.get("all").?.float));

        // Rain/Snow (optional)
        const rain_1h = if (root.get("rain")) |rain|
            if (rain.object.get("1h")) |r| @as(f32, @floatCast(r.float)) else null
        else
            null;

        const snow_1h = if (root.get("snow")) |snow|
            if (snow.object.get("1h")) |s| @as(f32, @floatCast(s.float)) else null
        else
            null;

        // Weather condition
        const weather_array = root.get("weather").?.array;
        const weather_obj = weather_array.items[0].object;
        const weather_main = weather_obj.get("main").?.string;

        const condition = parseWeatherCondition(weather_main);

        // Timestamp
        const dt = @as(u64, @intFromFloat(root.get("dt").?.float));

        return WeatherData{
            .temperature = temperature,
            .feels_like = feels_like,
            .pressure = pressure,
            .humidity = humidity,
            .visibility = visibility,
            .wind_speed = wind_speed,
            .wind_direction = wind_deg,
            .wind_gust = wind_gust,
            .clouds = cloud_coverage,
            .rain_1h = rain_1h,
            .snow_1h = snow_1h,
            .weather_condition = condition,
            .timestamp = dt,
        };
    }

    fn parseWeatherCondition(condition_str: []const u8) WeatherConditionCode {
        if (std.mem.eql(u8, condition_str, "Clear")) return .clear;
        if (std.mem.eql(u8, condition_str, "Clouds")) return .broken_clouds;
        if (std.mem.eql(u8, condition_str, "Rain")) return .rain;
        if (std.mem.eql(u8, condition_str, "Drizzle")) return .shower_rain;
        if (std.mem.eql(u8, condition_str, "Thunderstorm")) return .thunderstorm;
        if (std.mem.eql(u8, condition_str, "Snow")) return .snow;
        if (std.mem.eql(u8, condition_str, "Mist")) return .mist;
        if (std.mem.eql(u8, condition_str, "Fog")) return .fog;
        return .clear;
    }

    /// Apply this weather data to airport sensors
    pub fn applyToAirportSensors(self: WeatherData, airport: *entities.Airport) void {
        airport.sensors.temperature = self.temperature;
        airport.sensors.wind_speed = self.wind_speed;
        airport.sensors.wind_direction = self.wind_direction;
        airport.sensors.visibility = self.visibility;
        airport.sensors.barometric_pressure = self.pressure;
        airport.sensors.precipitation = (self.rain_1h != null and self.rain_1h.? > 0) or
            (self.snow_1h != null and self.snow_1h.? > 0);

        // Update runway condition based on precipitation
        if (self.snow_1h != null and self.snow_1h.? > 0) {
            airport.sensors.runway_condition = .snow_covered;
        } else if (self.rain_1h != null and self.rain_1h.? > 5.0) {
            airport.sensors.runway_condition = .wet;
        } else if (self.rain_1h != null and self.rain_1h.? > 0) {
            airport.sensors.runway_condition = .wet;
        } else {
            airport.sensors.runway_condition = .dry;
        }

        // Update overall weather condition
        airport.weather = self.weather_condition.toSimulationWeather();
    }
};

/// Weather service manager
pub const WeatherService = struct {
    allocator: std.mem.Allocator,
    config: WeatherConfig,
    cache: std.AutoHashMap(u32, CachedWeather), // Airport ID -> Weather
    http_client: std.http.Client,

    pub const CachedWeather = struct {
        data: WeatherData,
        fetched_at: u64, // Unix timestamp
        latitude: f32,
        longitude: f32,
    };

    pub fn init(allocator: std.mem.Allocator, config: WeatherConfig) WeatherService {
        return .{
            .allocator = allocator,
            .config = config,
            .cache = std.AutoHashMap(u32, CachedWeather).init(allocator),
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *WeatherService) void {
        self.cache.deinit();
        self.http_client.deinit();
    }

    /// Fetch weather for an airport
    pub fn fetchWeatherForAirport(
        self: *WeatherService,
        airport_id: u32,
        latitude: f32,
        longitude: f32,
    ) !WeatherData {
        const now = @as(u64, @intCast(std.time.timestamp()));

        // Check cache first
        if (self.cache.get(airport_id)) |cached| {
            if (now - cached.fetched_at < self.config.update_interval_seconds) {
                return cached.data;
            }
        }

        // Fetch from API if enabled
        if (self.config.enabled) {
            const weather_data = try self.fetchFromAPI(latitude, longitude);

            // Update cache
            try self.cache.put(airport_id, .{
                .data = weather_data,
                .fetched_at = now,
                .latitude = latitude,
                .longitude = longitude,
            });

            return weather_data;
        } else {
            // Return simulated weather if API not enabled
            return self.generateSimulatedWeather(latitude, longitude, now);
        }
    }

    fn fetchFromAPI(self: *WeatherService, latitude: f32, longitude: f32) !WeatherData {
        // Build URL
        var url_buffer: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buffer, "{s}?lat={d:.4}&lon={d:.4}&appid={s}", .{
            self.config.api_endpoint,
            latitude,
            longitude,
            self.config.api_key,
        });

        // Make HTTP request
        var response_buffer: [8192]u8 = undefined;
        var req = try self.http_client.open(.GET, try std.Uri.parse(url), .{
            .server_header_buffer = &response_buffer,
        });
        defer req.deinit();

        try req.send();
        try req.finish();
        try req.wait();

        // Read response
        var response_data = std.ArrayList(u8){};
        defer response_data.deinit();

        const body = req.reader();
        try body.readAllArrayList(&response_data, 16384);

        // Parse JSON
        return try WeatherData.fromOpenWeatherMapJSON(self.allocator, response_data.items);
    }

    fn generateSimulatedWeather(self: WeatherService, latitude: f32, longitude: f32, timestamp: u64) WeatherData {
        _ = self;

        // Simple weather simulation based on location and time
        const time_factor = @as(f32, @floatFromInt(timestamp % 86400)) / 86400.0;
        const lat_factor = @abs(latitude) / 90.0;

        // Temperature varies by latitude and time of day
        const base_temp = 15.0 + (1.0 - lat_factor) * 15.0; // Warmer near equator
        const daily_variation = @sin(time_factor * 2.0 * std.math.pi) * 10.0;
        const temperature = base_temp + daily_variation;

        // Wind speed varies with location
        const wind_speed = 10.0 + @sin(@as(f32, @floatFromInt(timestamp)) / 3600.0) * 15.0;

        // Visibility and conditions
        const random_factor = @mod(@as(f32, @floatFromInt(timestamp)), 1000.0) / 1000.0;
        const condition = if (random_factor < 0.6)
            WeatherData.WeatherConditionCode.clear
        else if (random_factor < 0.8)
            WeatherData.WeatherConditionCode.few_clouds
        else if (random_factor < 0.9)
            WeatherData.WeatherConditionCode.rain
        else
            WeatherData.WeatherConditionCode.broken_clouds;

        return WeatherData{
            .temperature = temperature,
            .feels_like = temperature - 2.0,
            .pressure = 1013.25,
            .humidity = 60,
            .visibility = if (condition == .rain) 5.0 else 10.0,
            .wind_speed = wind_speed,
            .wind_direction = @mod(longitude * 10.0, 360.0),
            .wind_gust = if (wind_speed > 20) wind_speed * 1.3 else null,
            .clouds = switch (condition) {
                .clear => 0,
                .few_clouds => 25,
                .broken_clouds => 75,
                else => 50,
            },
            .rain_1h = if (condition == .rain) 2.0 else null,
            .snow_1h = null,
            .weather_condition = condition,
            .timestamp = timestamp,
        };
    }

    /// Update weather for all airports
    pub fn updateAllAirports(self: *WeatherService, airports: []entities.Airport) !void {
        for (airports) |*airport| {
            const weather = try self.fetchWeatherForAirport(
                airport.id,
                airport.location.latitude,
                airport.location.longitude,
            );

            weather.applyToAirportSensors(airport);

            std.debug.print("Updated weather for {s}: {d:.1}°C, Wind: {d:.1} km/h, Vis: {d:.1} km\n", .{
                std.mem.sliceTo(&airport.iata_code, 0),
                weather.temperature,
                weather.wind_speed,
                weather.visibility,
            });
        }
    }

    /// Get weather report for display
    pub fn getWeatherReport(self: *WeatherService, airport_id: u32) ?[]const u8 {
        if (self.cache.get(airport_id)) |cached| {
            var buffer: [256]u8 = undefined;
            const report = std.fmt.bufPrint(&buffer,
                "Temp: {d:.1}°C, Wind: {d:.0} km/h @ {d:.0}°, Vis: {d:.1} km, Press: {d:.0} hPa",
                .{
                    cached.data.temperature,
                    cached.data.wind_speed,
                    cached.data.wind_direction,
                    cached.data.visibility,
                    cached.data.pressure,
                }
            ) catch return null;

            return report;
        }
        return null;
    }
};

/// Alternative weather providers
pub const WeatherProvider = enum {
    OpenWeatherMap,
    WeatherAPI,
    NOAA, // National Oceanic and Atmospheric Administration
    Simulated, // Fallback to simulated weather

    pub fn getEndpoint(self: WeatherProvider) []const u8 {
        return switch (self) {
            .OpenWeatherMap => "https://api.openweathermap.org/data/2.5/weather",
            .WeatherAPI => "https://api.weatherapi.com/v1/current.json",
            .NOAA => "https://api.weather.gov/points",
            .Simulated => "",
        };
    }

    pub fn requiresAPIKey(self: WeatherProvider) bool {
        return switch (self) {
            .OpenWeatherMap, .WeatherAPI => true,
            .NOAA, .Simulated => false,
        };
    }
};

/// Weather alert system for aviation
pub const WeatherAlert = struct {
    airport_id: u32,
    alert_type: AlertType,
    severity: Severity,
    message: []const u8,
    timestamp: u64,

    pub const AlertType = enum {
        low_visibility,
        high_winds,
        thunderstorm,
        ice,
        severe_turbulence,
    };

    pub const Severity = enum {
        advisory,
        warning,
        critical,
    };

    pub fn checkWeatherAlerts(weather: WeatherData, airport_id: u32) ?WeatherAlert {
        const now = @as(u64, @intCast(std.time.timestamp()));

        // Check for dangerous conditions
        if (weather.visibility < 1.0) {
            return WeatherAlert{
                .airport_id = airport_id,
                .alert_type = .low_visibility,
                .severity = .critical,
                .message = "Critical: Visibility below 1km - Consider flight delays",
                .timestamp = now,
            };
        }

        if (weather.wind_speed > 50.0 or (weather.wind_gust != null and weather.wind_gust.? > 60.0)) {
            return WeatherAlert{
                .airport_id = airport_id,
                .alert_type = .high_winds,
                .severity = .warning,
                .message = "Warning: High wind speeds detected",
                .timestamp = now,
            };
        }

        if (weather.weather_condition == .thunderstorm) {
            return WeatherAlert{
                .airport_id = airport_id,
                .alert_type = .thunderstorm,
                .severity = .critical,
                .message = "Critical: Thunderstorm activity - Ground all flights",
                .timestamp = now,
            };
        }

        return null;
    }
};
