"""
UDP Receiver Service for Power Grid Simulation Data
Receives real-time data from Simulink via UDP and streams to InfluxDB
"""

import socket
import json
import struct
import threading
import logging
import time
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import numpy as np
from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class GridDataPoint:
    """Data structure for power grid measurements"""
    timestamp: datetime
    bus_voltage: float
    bus_frequency: float
    active_power: float
    reactive_power: float
    current_magnitude: float
    current_phase: float
    temperature: float
    load_demand: float
    generation_output: float
    grid_stability_index: float
    fault_indicator: int
    
    def to_influx_point(self, measurement_name: str = "grid_measurements") -> Point:
        """Convert to InfluxDB Point"""
        point = Point(measurement_name)
        point.time(self.timestamp, WritePrecision.MS)
        
        # Add fields
        point.field("bus_voltage", self.bus_voltage)
        point.field("bus_frequency", self.bus_frequency)
        point.field("active_power", self.active_power)
        point.field("reactive_power", self.reactive_power)
        point.field("current_magnitude", self.current_magnitude)
        point.field("current_phase", self.current_phase)
        point.field("temperature", self.temperature)
        point.field("load_demand", self.load_demand)
        point.field("generation_output", self.generation_output)
        point.field("grid_stability_index", self.grid_stability_index)
        point.field("fault_indicator", self.fault_indicator)
        
        # Add tags for better querying
        point.tag("data_source", "simulink")
        point.tag("grid_section", "main_bus")
        
        return point

class UDPReceiver:
    """UDP receiver for Simulink data streaming"""
    
    def __init__(self, host: str = "localhost", port: int = 12345, 
                 influx_url: str = "http://localhost:8086",
                 influx_token: str = None,
                 influx_org: str = "smartgrid-org",
                 influx_bucket: str = "grid-data"):
        
        self.host = host
        self.port = port
        self.socket = None
        self.running = False
        
        # InfluxDB connection
        self.influx_client = InfluxDBClient(url=influx_url, token=influx_token, org=influx_org)
        self.write_api = self.influx_client.write_api(write_options=SYNCHRONOUS)
        self.bucket = influx_bucket
        self.org = influx_org
        
        # Buffer for batch writing
        self.data_buffer = []
        self.buffer_size = 100
        self.last_flush = time.time()
        self.flush_interval = 1.0  # seconds
        
        logger.info(f"UDP Receiver initialized on {host}:{port}")
    
    def start_server(self):
        """Start the UDP server"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.bind((self.host, self.port))
            self.socket.settimeout(1.0)  # Non-blocking with timeout
            self.running = True
            
            logger.info(f"UDP server started on {self.host}:{self.port}")
            
            # Start buffer flush thread
            flush_thread = threading.Thread(target=self._buffer_flush_loop, daemon=True)
            flush_thread.start()
            
            self._listen_loop()
            
        except Exception as e:
            logger.error(f"Error starting UDP server: {e}")
            self.stop_server()
    
    def _listen_loop(self):
        """Main listening loop"""
        packet_count = 0
        
        while self.running:
            try:
                data, addr = self.socket.recvfrom(1024)
                packet_count += 1
                
                if packet_count % 1000 == 0:
                    logger.info(f"Received {packet_count} packets from {addr}")
                
                # Parse and process data
                grid_data = self._parse_data(data)
                if grid_data:
                    self._buffer_data(grid_data)
                    
            except socket.timeout:
                continue  # Continue listening
            except Exception as e:
                logger.error(f"Error receiving data: {e}")
                continue
    
    def _parse_data(self, data: bytes) -> Optional[GridDataPoint]:
        """Parse UDP data packet from Simulink"""
        try:
            # Expected data format: 11 doubles (8 bytes each) = 88 bytes
            if len(data) != 88:
                logger.warning(f"Unexpected data length: {len(data)} bytes")
                return None
            
            # Unpack binary data (assuming little-endian doubles)
            values = struct.unpack('<11d', data)
            
            grid_data = GridDataPoint(
                timestamp=datetime.now(),
                bus_voltage=values[0],
                bus_frequency=values[1],
                active_power=values[2],
                reactive_power=values[3],
                current_magnitude=values[4],
                current_phase=values[5],
                temperature=values[6],
                load_demand=values[7],
                generation_output=values[8],
                grid_stability_index=values[9],
                fault_indicator=int(values[10])
            )
            
            return grid_data
            
        except Exception as e:
            logger.error(f"Error parsing data: {e}")
            return None
    
    def _buffer_data(self, grid_data: GridDataPoint):
        """Buffer data for batch writing to InfluxDB"""
        self.data_buffer.append(grid_data)
        
        # Flush if buffer is full
        if len(self.data_buffer) >= self.buffer_size:
            self._flush_buffer()
    
    def _flush_buffer(self):
        """Flush data buffer to InfluxDB"""
        if not self.data_buffer:
            return
            
        try:
            points = [data.to_influx_point() for data in self.data_buffer]
            self.write_api.write(bucket=self.bucket, org=self.org, record=points)
            
            logger.info(f"Flushed {len(self.data_buffer)} points to InfluxDB")
            self.data_buffer.clear()
            self.last_flush = time.time()
            
        except Exception as e:
            logger.error(f"Error writing to InfluxDB: {e}")
            # Keep data in buffer for retry
    
    def _buffer_flush_loop(self):
        """Background thread to periodically flush buffer"""
        while self.running:
            try:
                current_time = time.time()
                if current_time - self.last_flush > self.flush_interval:
                    self._flush_buffer()
                
                time.sleep(0.1)  # Check every 100ms
                
            except Exception as e:
                logger.error(f"Error in flush loop: {e}")
                time.sleep(1.0)
    
    def stop_server(self):
        """Stop the UDP server"""
        self.running = False
        
        # Flush remaining data
        self._flush_buffer()
        
        if self.socket:
            self.socket.close()
        
        if self.influx_client:
            self.influx_client.close()
        
        logger.info("UDP server stopped")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get receiver statistics"""
        return {
            "running": self.running,
            "buffer_size": len(self.data_buffer),
            "host": self.host,
            "port": self.port,
            "last_flush": self.last_flush
        }

class JSONUDPReceiver(UDPReceiver):
    """Alternative receiver for JSON-formatted data"""
    
    def _parse_data(self, data: bytes) -> Optional[GridDataPoint]:
        """Parse JSON UDP data packet"""
        try:
            json_data = json.loads(data.decode('utf-8'))
            
            grid_data = GridDataPoint(
                timestamp=datetime.fromisoformat(json_data.get('timestamp', datetime.now().isoformat())),
                bus_voltage=float(json_data.get('bus_voltage', 0.0)),
                bus_frequency=float(json_data.get('bus_frequency', 50.0)),
                active_power=float(json_data.get('active_power', 0.0)),
                reactive_power=float(json_data.get('reactive_power', 0.0)),
                current_magnitude=float(json_data.get('current_magnitude', 0.0)),
                current_phase=float(json_data.get('current_phase', 0.0)),
                temperature=float(json_data.get('temperature', 25.0)),
                load_demand=float(json_data.get('load_demand', 0.0)),
                generation_output=float(json_data.get('generation_output', 0.0)),
                grid_stability_index=float(json_data.get('grid_stability_index', 1.0)),
                fault_indicator=int(json_data.get('fault_indicator', 0))
            )
            
            return grid_data
            
        except Exception as e:
            logger.error(f"Error parsing JSON data: {e}")
            return None

def main():
    """Main entry point"""
    import os
    from dotenv import load_dotenv
    
    load_dotenv()
    
    # Configuration
    UDP_HOST = os.getenv('UDP_HOST', 'localhost')
    UDP_PORT = int(os.getenv('UDP_PORT', 12345))
    INFLUX_URL = os.getenv('INFLUX_URL', 'http://localhost:8086')
    INFLUX_TOKEN = os.getenv('INFLUX_TOKEN', 'admin123')  # Default for dev
    INFLUX_ORG = os.getenv('INFLUX_ORG', 'smartgrid-org')
    INFLUX_BUCKET = os.getenv('INFLUX_BUCKET', 'grid-data')
    DATA_FORMAT = os.getenv('DATA_FORMAT', 'binary')  # 'binary' or 'json'
    
    # Choose receiver type
    if DATA_FORMAT.lower() == 'json':
        receiver = JSONUDPReceiver(
            host=UDP_HOST,
            port=UDP_PORT,
            influx_url=INFLUX_URL,
            influx_token=INFLUX_TOKEN,
            influx_org=INFLUX_ORG,
            influx_bucket=INFLUX_BUCKET
        )
    else:
        receiver = UDPReceiver(
            host=UDP_HOST,
            port=UDP_PORT,
            influx_url=INFLUX_URL,
            influx_token=INFLUX_TOKEN,
            influx_org=INFLUX_ORG,
            influx_bucket=INFLUX_BUCKET
        )
    
    try:
        logger.info("Starting UDP receiver service...")
        receiver.start_server()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        receiver.stop_server()

if __name__ == "__main__":
    main()