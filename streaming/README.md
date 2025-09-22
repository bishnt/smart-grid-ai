# Smart Grid AI - UDP Streaming System

This directory contains the UDP streaming components for real-time power grid simulation data transfer from Simulink to InfluxDB.

## Overview

The UDP streaming system implements the data flow:
```
Simulink (Grid Simulation) → UDP → Python Service → InfluxDB → Grafana Dashboard
```

## Components

### Core Files

- **`udp_receiver.py`** - Main UDP receiver service that accepts data from Simulink and streams to InfluxDB
- **`config.py`** - Configuration management for all streaming components
- **`test_udp_stream.py`** - Test utilities for validating UDP streaming functionality

### MATLAB/Simulink Integration

- **`../simulink/udp_sender_example.m`** - Example MATLAB code for sending UDP data from Simulink

## Quick Start

### 1. Start the System

Using PowerShell (recommended):
```powershell
.\start-system.ps1
```

Using Batch file:
```cmd
start-system.bat
```

Using Docker Compose directly:
```bash
docker-compose up --build -d
```

### 2. Test UDP Streaming

Test with simulated data:
```bash
python streaming/test_udp_stream.py --test stream --duration 60
```

Test single packet:
```bash
python streaming/test_udp_stream.py --test single
```

### 3. Configure Simulink

Add the following to your Simulink model:

1. Add a MATLAB Function block
2. Connect your 11 grid measurement signals to the input
3. Use this code in the MATLAB Function block:

```matlab
function udp_send_grid_data(values)
    persistent udp_obj
    if isempty(udp_obj)
        udp_obj = udpport('datagram', 'IPV4');
    end
    binary_data = typecast(values, 'uint8');
    write(udp_obj, binary_data, 'string', '127.0.0.1', 12345);
end
```

## Data Format

### Grid Data Structure

The system expects 11 measurements per UDP packet:

1. **Bus Voltage** (V) - Main bus voltage
2. **Bus Frequency** (Hz) - Grid frequency  
3. **Active Power** (W) - Real power flow
4. **Reactive Power** (VAR) - Reactive power flow
5. **Current Magnitude** (A) - RMS current
6. **Current Phase** (°) - Current phase angle
7. **Temperature** (°C) - Equipment temperature
8. **Load Demand** (W) - Current load demand
9. **Generation Output** (W) - Generator output
10. **Grid Stability Index** - Stability indicator (0-2)
11. **Fault Indicator** - Binary fault flag (0 or 1)

### Binary Format (Recommended)

- 11 double-precision values (8 bytes each)
- Total packet size: 88 bytes
- Little-endian byte order
- High performance for real-time streaming

### JSON Format (Alternative)

- Human-readable JSON with field names
- Includes timestamp field
- Easier for debugging but slower
- Set `DATA_FORMAT=json` in environment

Example JSON:
```json
{
  "timestamp": "2024-09-22T16:47:56.123",
  "bus_voltage": 13542.5,
  "bus_frequency": 49.98,
  "active_power": 12500.0,
  "reactive_power": 3750.0,
  "current_magnitude": 537.2,
  "current_phase": 15.5,
  "temperature": 28.3,
  "load_demand": 12000.0,
  "generation_output": 12600.0,
  "grid_stability_index": 0.95,
  "fault_indicator": 0
}
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
# UDP Settings
UDP_HOST=localhost
UDP_PORT=12345
DATA_FORMAT=binary  # 'binary' or 'json'

# InfluxDB Settings
INFLUX_URL=http://localhost:8086
INFLUX_TOKEN=your_token_here
INFLUX_ORG=smartgrid-org
INFLUX_BUCKET=grid-data

# Buffer Settings
BUFFER_MAX_SIZE=100
BUFFER_FLUSH_INTERVAL=1.0
```

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `UDP_HOST` | UDP server bind address | `localhost` |
| `UDP_PORT` | UDP server port | `12345` |
| `DATA_FORMAT` | Data format ('binary' or 'json') | `binary` |
| `BUFFER_MAX_SIZE` | Points to buffer before writing | `100` |
| `BUFFER_FLUSH_INTERVAL` | Max time between flushes (seconds) | `1.0` |
| `INFLUX_URL` | InfluxDB server URL | `http://localhost:8086` |
| `INFLUX_ORG` | InfluxDB organization | `smartgrid-org` |
| `INFLUX_BUCKET` | InfluxDB bucket name | `grid-data` |

## Performance Considerations

### Optimal Settings

- **Sample Rate**: 10-100 Hz (0.01-0.1 second intervals)
- **Buffer Size**: 100 points for 1-second batches
- **Data Format**: Binary for best performance
- **Network**: Use localhost for single-machine setups

### Scaling Guidelines

| Sample Rate | Buffer Size | Flush Interval | Expected Throughput |
|-------------|-------------|----------------|-------------------|
| 10 Hz | 50 | 5.0s | ~600 points/min |
| 50 Hz | 100 | 2.0s | ~3,000 points/min |
| 100 Hz | 100 | 1.0s | ~6,000 points/min |

## Troubleshooting

### Common Issues

**UDP packets not being received:**
- Check Windows Firewall settings for port 12345
- Verify Simulink is sending to correct IP/port
- Test with `test_udp_stream.py` first

**InfluxDB connection errors:**
- Verify InfluxDB is running: `docker ps`
- Check InfluxDB logs: `docker-compose logs influxdb`
- Validate token and org settings

**High CPU usage:**
- Reduce sample rate in Simulink
- Increase buffer size and flush interval
- Use binary format instead of JSON

**Data not appearing in Grafana:**
- Check InfluxDB for data: Visit http://localhost:8086
- Verify bucket name matches configuration
- Check Grafana data source configuration

### Debugging Commands

Check service status:
```bash
docker-compose ps
```

View UDP receiver logs:
```bash
docker-compose logs streaming-service
```

Test connectivity:
```bash
python streaming/test_udp_stream.py --test single
```

Manual InfluxDB query:
```bash
# Access InfluxDB container
docker exec -it influxdb influx
```

### Log Files

When running in development mode, logs are written to:
- `logs/udp_receiver.log` - Main service logs
- `logs/influx_client.log` - Database connection logs

## Integration Examples

### MATLAB Standalone

```matlab
% Send single measurement
values = [13800, 50.0, 10000, 3000, 500, 0, 25, 9500, 10500, 1.0, 0];
udp_obj = udpport('datagram', 'IPV4');
binary_data = typecast(values, 'uint8');
write(udp_obj, binary_data, 'string', '127.0.0.1', 12345);
```

### Simulink Continuous

1. Use a Clock block for time reference
2. Connect measurements to a Mux block (11 signals)
3. Add MATLAB Function block with UDP code
4. Set sample time to your desired rate (e.g., 0.1 for 10 Hz)

### Python Alternative Sender

```python
import socket
import struct
import time

def send_measurement(values):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    binary_data = struct.pack('<11d', *values)
    sock.sendto(binary_data, ('localhost', 12345))
    sock.close()

# Example usage
measurements = [13800, 50.0, 10000, 3000, 500, 0, 25, 9500, 10500, 1.0, 0]
send_measurement(measurements)
```

## Architecture Notes

### Data Flow

1. **Simulink Model** generates grid measurements
2. **UDP Sender** (MATLAB Function) transmits data packets  
3. **UDP Receiver** (Python) receives and parses packets
4. **Data Buffer** accumulates points for batch writing
5. **InfluxDB Client** writes batched data to time-series database
6. **Grafana** queries InfluxDB for visualization

### Error Handling

- Malformed packets are logged and discarded
- InfluxDB connection failures trigger retries
- Buffer overflow protection prevents memory issues
- Graceful shutdown preserves buffered data

### Security Considerations

- UDP is unencrypted - use only on trusted networks
- InfluxDB token should be kept secure
- Consider VPN for remote access
- Firewall rules should restrict access to necessary ports

## Next Steps

1. **Start System**: Use provided startup scripts
2. **Test Streaming**: Validate with test utilities
3. **Configure Simulink**: Implement UDP output in your model
4. **Setup Grafana**: Create dashboards for visualization
5. **Implement Analytics**: Add ML analysis for the streamed data

For more advanced configuration and analytics setup, see the main project README.