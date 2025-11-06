# Aviation Transport Simulation - Business Application

A professional aviation cargo transport simulation with 3D visualization, IoT integration, real-world weather data, NOTAM integration, and comprehensive business analytics.

## Features

### Core Business Systems
- **Aviation Economics**: Fuel pricing, crew costs, maintenance scheduling, airport slot pricing
- **Fleet Management**: Aircraft types from small cargo to super-heavy freighters
- **Route Planning**: Automated waypoint generation, flight time estimation
- **Cargo Management**: Multiple cargo types with handling requirements
- **Financial Tracking**: Revenue, costs, P&L, profit margins

### Real-World Data Integration
- **Weather Data**: Live weather from OpenWeatherMap API or simulated data
  - Temperature, wind speed/direction, visibility, pressure
  - Precipitation (rain/snow) detection
  - Weather alerts for critical conditions (low visibility, high winds, thunderstorms)
  - Automatic impact on flight operations and fuel consumption
  - 30-minute update intervals (configurable)
- **NOTAM Integration**: Notice to Airmen from FAA/ICAO sources
  - ICAO format parser and decoder
  - Runway/taxiway/aerodrome closures
  - Navigation aid status (VOR, ILS, NDB)
  - Airspace restrictions and temporary flight restrictions (TFR)
  - Obstacle and construction warnings
  - Fuel availability notices
  - Automatic operational impact assessment
  - Hourly updates (configurable)

### IoT Integration
- **Aircraft Telemetry**: Real-time position, altitude, speed, heading tracking
- **Sensor Networks**: Airport weather stations, runway sensors, visibility monitoring
- **Data Aggregation**: Collection and analysis of telemetry streams
- **Alert System**: Critical condition monitoring and notifications
- **Data Export**: JSON/CSV export capabilities for external systems

### 3D Visualization (Raylib)
- **Interactive 3D World**: Global map with airports and aircraft
- **Flight Path Rendering**: Visual representation of routes and waypoints
- **Real-time Updates**: Aircraft positions update during flight
- **Camera Controls**: Rotate, zoom, and navigate the 3D environment
- **HUD Overlay**: Flight statistics, financial metrics, market conditions

### Business Analytics
- **KPI Dashboard**: 20+ key performance indicators
- **Decision Support**: AI-powered recommendations based on performance
- **Route Profitability**: Analysis of individual route performance
- **Forecasting**: Revenue and cost projections
- **Market Analysis**: Economic condition tracking and impact

## Architecture

### Module Structure
```
src/
├── main.zig           - Main application loop
├── types.zig          - Core type definitions
├── entities.zig       - Aircraft, airports, cargo, companies
├── economics.zig      - Financial models and calculations
├── flight.zig         - Flight planning and management
├── simulation.zig     - Simulation engine and world state
├── iot.zig           - IoT telemetry and sensor networks
├── weather.zig       - Real-world weather data integration
├── notam.zig         - NOTAM fetching, parsing, and decoding
├── renderer.zig      - 3D visualization with raylib
└── analytics.zig     - Business intelligence and KPIs
```

### Data Flow
1. **Simulation Engine** updates world state based on time
2. **IoT Layer** collects telemetry from aircraft and airports
3. **Flight Scheduler** manages active flights and updates positions
4. **Economics Module** calculates costs and revenues
5. **Analytics** generates KPIs and recommendations
6. **Renderer** visualizes everything in 3D

## Building

### Requirements
- Zig 0.13.0 or later
- raylib (system library)

### Build Commands
```bash
# Build the application
zig build

# Run the application
zig build run

# Run tests
zig build test
```

## Configuration

### Weather API Integration

The application can use real-world weather data from OpenWeatherMap:

1. **Get an API key**: Sign up at [OpenWeatherMap](https://openweathermap.org/api) (free tier available)
2. **Set environment variable**:
   ```bash
   export OPENWEATHER_API_KEY="your_api_key_here"
   ```
3. **Run the application**:
   ```bash
   zig build run
   ```

If no API key is provided, the application will use simulated weather data.

### NOTAM Integration

NOTAMs are fetched from open sources:
- **FAA NOTAM Search**: https://notams.aim.faa.gov/notamSearch/
- **ICAO**: International NOTAMs via standard APIs

The application includes:
- Automatic ICAO format parsing
- NOTAM categorization (runway closures, navaid status, etc.)
- Severity classification (low, medium, high, critical)
- Operational impact assessment

NOTAMs update hourly (configurable in `NotamConfig`).

## Aircraft Types

| Type | Payload | Speed | Range | Purchase Cost |
|------|---------|-------|-------|---------------|
| Small Cargo | 3 tons | 350 km/h | 1,500 km | $2M |
| Medium Cargo | 20 tons | 500 km/h | 2,500 km | $35M |
| Large Cargo | 60 tons | 850 km/h | 7,000 km | $200M |
| Heavy Cargo | 110 tons | 900 km/h | 9,000 km | $350M |
| Super Heavy | 150 tons | 850 km/h | 5,000 km | $450M |

## Cargo Types

- **General Freight**: Standard cargo
- **Express Mail**: Time-sensitive documents
- **Perishable**: Food, medicine (temperature controlled)
- **Livestock**: Live animals
- **Dangerous Goods**: Chemicals, fuels
- **Valuable Cargo**: High-value items
- **Medical Supplies**: Emergency medical equipment

## Economic Model

### Cost Components
1. **Fuel**: Variable based on distance, aircraft type, weather
2. **Crew**: Hourly wages for pilots and engineers
3. **Maintenance**: Per-flight-hour costs
4. **Airport Slots**: Landing/takeoff fees (time-dependent)
5. **Cargo Handling**: Per-ton handling charges

### Revenue Model
- Revenue = Weight × Distance × Base Rate × Market Multiplier
- Different rates for each cargo type
- Market conditions affect demand and pricing

### Market Conditions
- **Recession**: 60% demand, lower prices
- **Slow**: 80% demand, reduced prices
- **Normal**: 100% baseline
- **Growth**: 140% demand, higher prices
- **Boom**: 180% demand, premium prices

## Controls

- **Arrow Keys**: Rotate camera
- **Mouse Wheel**: Zoom in/out
- **Space**: Pause/unpause simulation
- **ESC**: Exit application

## Business Metrics

### Financial KPIs
- Total Revenue
- Total Costs
- Gross Profit
- Profit Margin
- Revenue per Flight
- Cost per Flight

### Operational KPIs
- Fleet Utilization %
- On-Time Performance %
- Average Load Factor %
- Flights per Day
- Cargo Delivered (tons/day)

### Quality KPIs
- Customer Satisfaction (0-100)
- Safety Rating (0-100)
- Delivery Success Rate %

## IoT Features

### Aircraft Telemetry
- GPS Position (lat/lon/alt)
- Ground Speed
- Heading
- Fuel Remaining
- Engine Status (per engine)
- Hydraulic Pressure
- Cabin Pressure
- Outside Air Temperature

### Airport Sensors
- Weather Stations
- Wind Speed/Direction
- Visibility Sensors
- Barometric Pressure
- Runway Surface Conditions
- Traffic Radar

## Future Enhancements

- [ ] Multi-modal transport (trucks, trains, ships)
- [ ] Dynamic pricing algorithms
- [ ] Weather routing optimization
- [ ] Crew fatigue simulation
- [ ] Maintenance scheduling optimization
- [ ] Real-time competitive AI airlines
- [ ] Stock market integration
- [ ] Regulatory compliance system
- [ ] Environmental impact tracking (CO2 emissions)
- [ ] Historical data visualization and replay

## License

This is a business simulation application for educational and demonstration purposes.

## Development Status

✅ Core simulation engine
✅ Aviation economics model
✅ IoT integration layer
✅ Real-world weather data integration (OpenWeatherMap API)
✅ NOTAM fetching, parsing and decoding (FAA/ICAO)
✅ 3D visualization
✅ Business analytics
✅ Flight management system
✅ Cargo handling
✅ Multi-airport network
✅ Weather alerts and operational impact
✅ NOTAM operational impact assessment

Ready for testing and deployment as an IoT-enabled business solution!
