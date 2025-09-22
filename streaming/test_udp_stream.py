"""
Test script for UDP streaming functionality
This script can simulate Simulink data transmission for testing
"""

import socket
import struct
import json
import time
import threading
import numpy as np
from datetime import datetime
from typing import Dict, Any

class UDPTestSender:
    """Simulate Simulink UDP data transmission for testing"""
    
    def __init__(self, host: str = "localhost", port: int = 12345):
        self.host = host
        self.port = port
        self.running = False
        
    def generate_test_data(self, time_offset: float = 0) -> Dict[str, float]:
        """Generate realistic test data similar to power grid measurements"""
        
        # Base values
        base_voltage = 13800.0  # 13.8 kV
        base_frequency = 50.0   # 50 Hz
        base_power = 10000.0    # 10 MW
        
        # Add time-based variations and noise
        t = time_offset
        voltage_var = 0.05 * np.sin(2*np.pi*0.1*t) + 0.02*np.random.randn()
        freq_var = 0.2 * np.sin(2*np.pi*0.05*t) + 0.1*np.random.randn()
        power_var = 0.3 * np.sin(2*np.pi*0.02*t) + 0.1*np.random.randn()
        
        # Fault simulation (5% probability)
        fault_indicator = 1 if np.random.rand() < 0.05 else 0
        if fault_indicator:
            voltage_var -= 0.2  # Voltage drop during fault
        
        data = {
            'bus_voltage': base_voltage * (1 + voltage_var),
            'bus_frequency': base_frequency + freq_var,
            'active_power': base_power * (1 + power_var),
            'reactive_power': base_power * 0.3 * (1 + 0.5*power_var),
            'current_magnitude': abs(base_power * (1 + power_var) / (base_voltage * (1 + voltage_var)) * np.sqrt(3)),
            'current_phase': 30 * np.sin(2*np.pi*0.03*t),
            'temperature': 25 + 10*np.sin(2*np.pi*t/3600) + 2*np.random.randn(),
            'load_demand': base_power * (0.7 + 0.3*np.sin(2*np.pi*t/3600)),
            'generation_output': base_power * (0.7 + 0.3*np.sin(2*np.pi*t/3600)) * (1.05 + 0.05*np.random.randn()),
            'grid_stability_index': 1.0 - 0.1*abs(voltage_var) - 0.1*abs(freq_var/base_frequency),
            'fault_indicator': fault_indicator
        }
        
        return data
    
    def send_binary_data(self, data: Dict[str, float]):
        """Send data in binary format (matches MATLAB implementation)"""
        values = [
            data['bus_voltage'],
            data['bus_frequency'],
            data['active_power'],
            data['reactive_power'],
            data['current_magnitude'],
            data['current_phase'],
            data['temperature'],
            data['load_demand'],
            data['generation_output'],
            data['grid_stability_index'],
            float(data['fault_indicator'])
        ]
        
        # Pack as 11 little-endian doubles (88 bytes total)
        binary_data = struct.pack('<11d', *values)
        
        # Send UDP packet
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.sendto(binary_data, (self.host, self.port))
        finally:
            sock.close()
    
    def send_json_data(self, data: Dict[str, float]):
        """Send data in JSON format"""
        # Add timestamp
        data['timestamp'] = datetime.now().isoformat()
        
        json_str = json.dumps(data).encode('utf-8')
        
        # Send UDP packet
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.sendto(json_str, (self.host, self.port))
        finally:
            sock.close()
    
    def start_streaming(self, duration: float = 60.0, sample_rate: float = 0.1, 
                       data_format: str = 'binary'):
        """Start continuous data streaming"""
        self.running = True
        start_time = time.time()
        sample_count = 0
        
        print(f"Starting UDP test stream to {self.host}:{self.port}")
        print(f"Format: {data_format}, Rate: {1/sample_rate:.1f} Hz, Duration: {duration}s")
        
        try:
            while self.running and (time.time() - start_time) < duration:
                # Generate test data
                time_offset = time.time() - start_time
                test_data = self.generate_test_data(time_offset)
                
                # Send data
                if data_format.lower() == 'json':
                    self.send_json_data(test_data)
                else:
                    self.send_binary_data(test_data)
                
                sample_count += 1
                
                # Print status every 10 seconds
                if sample_count % int(10 / sample_rate) == 0:
                    elapsed = time.time() - start_time
                    print(f"Sent {sample_count} samples in {elapsed:.1f}s")
                
                # Wait for next sample
                time.sleep(sample_rate)
                
        except KeyboardInterrupt:
            print("Streaming interrupted by user")
        except Exception as e:
            print(f"Streaming error: {e}")
        
        self.running = False
        print(f"Streaming complete. Total samples sent: {sample_count}")
    
    def stop_streaming(self):
        """Stop the streaming"""
        self.running = False

class UDPStreamTester:
    """Complete test suite for UDP streaming"""
    
    def __init__(self, receiver_host: str = "localhost", receiver_port: int = 12345):
        self.receiver_host = receiver_host
        self.receiver_port = receiver_port
        self.sender = UDPTestSender(receiver_host, receiver_port)
    
    def test_single_packet(self, data_format: str = 'binary'):
        """Test sending a single packet"""
        print(f"\n--- Testing single {data_format} packet ---")
        
        test_data = self.sender.generate_test_data()
        print("Generated test data:", test_data)
        
        try:
            if data_format.lower() == 'json':
                self.sender.send_json_data(test_data)
            else:
                self.sender.send_binary_data(test_data)
            print("✓ Packet sent successfully")
        except Exception as e:
            print(f"✗ Failed to send packet: {e}")
    
    def test_burst_transmission(self, num_packets: int = 100, data_format: str = 'binary'):
        """Test burst transmission"""
        print(f"\n--- Testing burst transmission ({num_packets} packets) ---")
        
        start_time = time.time()
        success_count = 0
        
        for i in range(num_packets):
            try:
                test_data = self.sender.generate_test_data(i * 0.1)
                
                if data_format.lower() == 'json':
                    self.sender.send_json_data(test_data)
                else:
                    self.sender.send_binary_data(test_data)
                
                success_count += 1
                
            except Exception as e:
                print(f"✗ Failed to send packet {i+1}: {e}")
        
        elapsed = time.time() - start_time
        rate = success_count / elapsed if elapsed > 0 else 0
        
        print(f"✓ Sent {success_count}/{num_packets} packets in {elapsed:.2f}s ({rate:.1f} packets/s)")
    
    def test_continuous_stream(self, duration: float = 10.0, sample_rate: float = 0.1):
        """Test continuous streaming"""
        print(f"\n--- Testing continuous stream ---")
        
        # Start streaming in a separate thread
        stream_thread = threading.Thread(
            target=self.sender.start_streaming,
            args=(duration, sample_rate, 'binary'),
            daemon=True
        )
        
        stream_thread.start()
        
        # Let it run for a bit, then check if it's still running
        time.sleep(min(5.0, duration / 2))
        
        if stream_thread.is_alive():
            print("✓ Continuous streaming is active")
        else:
            print("✗ Continuous streaming stopped unexpectedly")
        
        # Wait for completion
        stream_thread.join(timeout=duration + 5)
    
    def test_data_validation(self):
        """Test data generation and validation"""
        print(f"\n--- Testing data validation ---")
        
        # Generate multiple data points
        data_points = [self.sender.generate_test_data(i * 0.1) for i in range(10)]
        
        # Validate data ranges
        valid_count = 0
        
        for i, data in enumerate(data_points):
            try:
                # Check voltage range (reasonable for power grid)
                assert 5000 < data['bus_voltage'] < 25000, f"Voltage out of range: {data['bus_voltage']}"
                
                # Check frequency range (50 Hz ± reasonable deviation)
                assert 45 < data['bus_frequency'] < 55, f"Frequency out of range: {data['bus_frequency']}"
                
                # Check power values
                assert -50000 < data['active_power'] < 50000, f"Active power out of range: {data['active_power']}"
                
                # Check stability index
                assert 0 <= data['grid_stability_index'] <= 2, f"Stability index out of range: {data['grid_stability_index']}"
                
                # Check fault indicator
                assert data['fault_indicator'] in [0, 1], f"Invalid fault indicator: {data['fault_indicator']}"
                
                valid_count += 1
                
            except AssertionError as e:
                print(f"✗ Data validation failed for sample {i+1}: {e}")
        
        print(f"✓ {valid_count}/10 data points passed validation")
    
    def run_all_tests(self):
        """Run complete test suite"""
        print("=" * 60)
        print("UDP STREAMING TEST SUITE")
        print("=" * 60)
        
        # Data validation
        self.test_data_validation()
        
        # Single packet tests
        self.test_single_packet('binary')
        self.test_single_packet('json')
        
        # Burst transmission
        self.test_burst_transmission(50, 'binary')
        
        # Continuous stream (short test)
        self.test_continuous_stream(5.0, 0.1)
        
        print("\n" + "=" * 60)
        print("TEST SUITE COMPLETE")
        print("=" * 60)

def main():
    """Main test function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="UDP Streaming Test Suite")
    parser.add_argument('--host', default='localhost', help='Receiver host (default: localhost)')
    parser.add_argument('--port', type=int, default=12345, help='Receiver port (default: 12345)')
    parser.add_argument('--test', choices=['single', 'burst', 'stream', 'all'], default='all',
                      help='Test type to run (default: all)')
    parser.add_argument('--format', choices=['binary', 'json'], default='binary',
                      help='Data format (default: binary)')
    parser.add_argument('--duration', type=float, default=60.0,
                      help='Stream duration in seconds (default: 60)')
    parser.add_argument('--rate', type=float, default=0.1,
                      help='Sample rate in seconds (default: 0.1)')
    
    args = parser.parse_args()
    
    # Create tester
    tester = UDPStreamTester(args.host, args.port)
    
    if args.test == 'single':
        tester.test_single_packet(args.format)
    elif args.test == 'burst':
        tester.test_burst_transmission(100, args.format)
    elif args.test == 'stream':
        sender = UDPTestSender(args.host, args.port)
        sender.start_streaming(args.duration, args.rate, args.format)
    else:
        tester.run_all_tests()

if __name__ == "__main__":
    main()