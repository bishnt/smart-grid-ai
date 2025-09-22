"""
Configuration settings for the UDP streaming service
"""

import os
from typing import Dict, Any
from dataclasses import dataclass

@dataclass
class UDPConfig:
    """UDP receiver configuration"""
    host: str = "localhost"
    port: int = 12345
    buffer_size: int = 1024
    timeout: float = 1.0

@dataclass
class InfluxDBConfig:
    """InfluxDB configuration"""
    url: str = "http://localhost:8086"
    token: str = None
    org: str = "smartgrid-org"
    bucket: str = "grid-data"
    timeout: int = 10000  # milliseconds

@dataclass
class BufferConfig:
    """Data buffering configuration"""
    max_size: int = 100
    flush_interval: float = 1.0  # seconds
    retry_attempts: int = 3
    retry_delay: float = 1.0  # seconds

@dataclass
class LoggingConfig:
    """Logging configuration"""
    level: str = "INFO"
    format: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    file: str = None  # None for stdout

@dataclass
class GridDataConfig:
    """Power grid data structure configuration"""
    measurement_name: str = "grid_measurements"
    data_source_tag: str = "simulink"
    grid_section_tag: str = "main_bus"
    
    # Data validation ranges
    voltage_range: tuple = (0.0, 50000.0)  # Volts
    frequency_range: tuple = (45.0, 65.0)  # Hz
    power_range: tuple = (-100000.0, 100000.0)  # Watts
    current_range: tuple = (0.0, 10000.0)  # Amperes
    temperature_range: tuple = (-50.0, 150.0)  # Celsius
    stability_range: tuple = (0.0, 2.0)  # Stability index

class StreamingConfig:
    """Main configuration class"""
    
    def __init__(self, config_file: str = None):
        self.udp = UDPConfig()
        self.influx = InfluxDBConfig()
        self.buffer = BufferConfig()
        self.logging = LoggingConfig()
        self.grid = GridDataConfig()
        
        # Load from environment variables
        self._load_from_env()
        
        # Load from config file if provided
        if config_file:
            self._load_from_file(config_file)
    
    def _load_from_env(self):
        """Load configuration from environment variables"""
        
        # UDP settings
        self.udp.host = os.getenv('UDP_HOST', self.udp.host)
        self.udp.port = int(os.getenv('UDP_PORT', self.udp.port))
        self.udp.buffer_size = int(os.getenv('UDP_BUFFER_SIZE', self.udp.buffer_size))
        self.udp.timeout = float(os.getenv('UDP_TIMEOUT', self.udp.timeout))
        
        # InfluxDB settings
        self.influx.url = os.getenv('INFLUX_URL', self.influx.url)
        self.influx.token = os.getenv('INFLUX_TOKEN', self.influx.token)
        self.influx.org = os.getenv('INFLUX_ORG', self.influx.org)
        self.influx.bucket = os.getenv('INFLUX_BUCKET', self.influx.bucket)
        self.influx.timeout = int(os.getenv('INFLUX_TIMEOUT', self.influx.timeout))
        
        # Buffer settings
        self.buffer.max_size = int(os.getenv('BUFFER_MAX_SIZE', self.buffer.max_size))
        self.buffer.flush_interval = float(os.getenv('BUFFER_FLUSH_INTERVAL', self.buffer.flush_interval))
        self.buffer.retry_attempts = int(os.getenv('BUFFER_RETRY_ATTEMPTS', self.buffer.retry_attempts))
        self.buffer.retry_delay = float(os.getenv('BUFFER_RETRY_DELAY', self.buffer.retry_delay))
        
        # Logging settings
        self.logging.level = os.getenv('LOG_LEVEL', self.logging.level)
        self.logging.file = os.getenv('LOG_FILE', self.logging.file)
        
        # Grid data settings
        self.grid.measurement_name = os.getenv('GRID_MEASUREMENT_NAME', self.grid.measurement_name)
        self.grid.data_source_tag = os.getenv('GRID_DATA_SOURCE_TAG', self.grid.data_source_tag)
        self.grid.grid_section_tag = os.getenv('GRID_SECTION_TAG', self.grid.grid_section_tag)
    
    def _load_from_file(self, config_file: str):
        """Load configuration from JSON file"""
        import json
        try:
            with open(config_file, 'r') as f:
                config_data = json.load(f)
                
            # Update configurations
            if 'udp' in config_data:
                for key, value in config_data['udp'].items():
                    if hasattr(self.udp, key):
                        setattr(self.udp, key, value)
            
            if 'influx' in config_data:
                for key, value in config_data['influx'].items():
                    if hasattr(self.influx, key):
                        setattr(self.influx, key, value)
            
            if 'buffer' in config_data:
                for key, value in config_data['buffer'].items():
                    if hasattr(self.buffer, key):
                        setattr(self.buffer, key, value)
            
            if 'logging' in config_data:
                for key, value in config_data['logging'].items():
                    if hasattr(self.logging, key):
                        setattr(self.logging, key, value)
            
            if 'grid' in config_data:
                for key, value in config_data['grid'].items():
                    if hasattr(self.grid, key):
                        setattr(self.grid, key, value)
                        
        except Exception as e:
            print(f"Warning: Could not load config file {config_file}: {e}")
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert configuration to dictionary"""
        return {
            'udp': {
                'host': self.udp.host,
                'port': self.udp.port,
                'buffer_size': self.udp.buffer_size,
                'timeout': self.udp.timeout
            },
            'influx': {
                'url': self.influx.url,
                'org': self.influx.org,
                'bucket': self.influx.bucket,
                'timeout': self.influx.timeout
                # Note: token is intentionally excluded for security
            },
            'buffer': {
                'max_size': self.buffer.max_size,
                'flush_interval': self.buffer.flush_interval,
                'retry_attempts': self.buffer.retry_attempts,
                'retry_delay': self.buffer.retry_delay
            },
            'logging': {
                'level': self.logging.level,
                'format': self.logging.format,
                'file': self.logging.file
            },
            'grid': {
                'measurement_name': self.grid.measurement_name,
                'data_source_tag': self.grid.data_source_tag,
                'grid_section_tag': self.grid.grid_section_tag
            }
        }
    
    def validate(self) -> bool:
        """Validate configuration settings"""
        errors = []
        
        # UDP validation
        if not (1 <= self.udp.port <= 65535):
            errors.append(f"Invalid UDP port: {self.udp.port}")
        
        if self.udp.timeout <= 0:
            errors.append(f"Invalid UDP timeout: {self.udp.timeout}")
        
        # InfluxDB validation
        if not self.influx.url:
            errors.append("InfluxDB URL is required")
        
        if not self.influx.org:
            errors.append("InfluxDB organization is required")
        
        if not self.influx.bucket:
            errors.append("InfluxDB bucket is required")
        
        # Buffer validation
        if self.buffer.max_size <= 0:
            errors.append(f"Invalid buffer max size: {self.buffer.max_size}")
        
        if self.buffer.flush_interval <= 0:
            errors.append(f"Invalid buffer flush interval: {self.buffer.flush_interval}")
        
        if errors:
            print("Configuration validation errors:")
            for error in errors:
                print(f"  - {error}")
            return False
        
        return True

# Default configuration instance
default_config = StreamingConfig()