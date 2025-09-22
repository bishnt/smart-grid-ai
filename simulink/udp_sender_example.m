% UDP Sender Example for Power Grid Simulation Data
% This script demonstrates how to send grid simulation data via UDP
% to the Python streaming service

function udp_sender_example()
    % Configuration
    TARGET_IP = '127.0.0.1';  % Python service IP
    TARGET_PORT = 12345;      % Python service port
    SAMPLE_RATE = 0.1;        % Send data every 100ms
    DURATION = 60;            % Run for 60 seconds
    
    % Create UDP object
    try
        udp_obj = udpport('datagram', 'IPV4');
        fprintf('UDP sender initialized successfully\n');
    catch ME
        error('Failed to initialize UDP: %s', ME.message);
    end
    
    % Simulation parameters
    t_start = tic;
    sample_count = 0;
    
    fprintf('Starting UDP data transmission to %s:%d\n', TARGET_IP, TARGET_PORT);
    fprintf('Sending data every %.1f seconds for %.1f seconds\n', SAMPLE_RATE, DURATION);
    
    try
        while toc(t_start) < DURATION
            % Generate simulated grid data
            grid_data = generate_grid_data(toc(t_start));
            
            % Send binary data (recommended for performance)
            send_binary_data(udp_obj, grid_data, TARGET_IP, TARGET_PORT);
            
            % Alternatively, send JSON data (easier for debugging)
            % send_json_data(udp_obj, grid_data, TARGET_IP, TARGET_PORT);
            
            sample_count = sample_count + 1;
            
            % Print status every 10 seconds
            if mod(sample_count, round(10/SAMPLE_RATE)) == 0
                fprintf('Sent %d samples in %.1f seconds\n', sample_count, toc(t_start));
            end
            
            % Wait for next sample
            pause(SAMPLE_RATE);
        end
        
    catch ME
        fprintf('Error during transmission: %s\n', ME.message);
    end
    
    fprintf('Transmission complete. Sent %d samples\n', sample_count);
    clear udp_obj;
end

function grid_data = generate_grid_data(time)
    % Generate realistic power grid simulation data
    
    % Base values with realistic variations
    base_voltage = 13800;  % 13.8 kV distribution voltage
    base_frequency = 50;   % 50 Hz (European standard)
    base_power = 10000;    % 10 MW base load
    
    % Add time-based variations and noise
    voltage_variation = 0.05 * sin(2*pi*0.1*time) + 0.02*randn(); % ±5% + noise
    frequency_variation = 0.2 * sin(2*pi*0.05*time) + 0.1*randn(); % ±0.2 Hz + noise
    power_variation = 0.3 * sin(2*pi*0.02*time) + 0.1*randn(); % ±30% + noise
    
    % Generate fault conditions occasionally (5% probability)
    fault_indicator = 0;
    if rand() < 0.05
        fault_indicator = 1;
        voltage_variation = voltage_variation - 0.2; % Voltage drop during fault
    end
    
    grid_data = struct();
    grid_data.bus_voltage = base_voltage * (1 + voltage_variation);
    grid_data.bus_frequency = base_frequency + frequency_variation;
    grid_data.active_power = base_power * (1 + power_variation);
    grid_data.reactive_power = base_power * 0.3 * (1 + 0.5*power_variation);
    grid_data.current_magnitude = abs(grid_data.active_power / grid_data.bus_voltage * sqrt(3));
    grid_data.current_phase = 30 * sin(2*pi*0.03*time); % Phase angle variation
    grid_data.temperature = 25 + 10*sin(2*pi*time/3600) + 2*randn(); % Daily temperature cycle
    grid_data.load_demand = base_power * (0.7 + 0.3*sin(2*pi*time/3600)); % Daily load cycle
    grid_data.generation_output = grid_data.load_demand * (1.05 + 0.05*randn()); % 5% reserve + noise
    grid_data.grid_stability_index = 1.0 - 0.1*abs(voltage_variation) - 0.1*abs(frequency_variation/base_frequency);
    grid_data.fault_indicator = fault_indicator;
end

function send_binary_data(udp_obj, grid_data, target_ip, target_port)
    % Send data in binary format (11 doubles = 88 bytes)
    % This matches the expected format in the Python UDP receiver
    
    values = [
        grid_data.bus_voltage, ...
        grid_data.bus_frequency, ...
        grid_data.active_power, ...
        grid_data.reactive_power, ...
        grid_data.current_magnitude, ...
        grid_data.current_phase, ...
        grid_data.temperature, ...
        grid_data.load_demand, ...
        grid_data.generation_output, ...
        grid_data.grid_stability_index, ...
        double(grid_data.fault_indicator)
    ];
    
    % Convert to binary (little-endian doubles)
    binary_data = typecast(values, 'uint8');
    
    % Send UDP packet
    write(udp_obj, binary_data, 'string', target_ip, target_port);
end

function send_json_data(udp_obj, grid_data, target_ip, target_port)
    % Send data in JSON format (alternative for debugging)
    % Note: Python receiver needs to be configured for JSON format
    
    % Add timestamp
    grid_data.timestamp = datestr(now, 'yyyy-mm-ddTHH:MM:SS.FFF');
    
    % Convert to JSON
    json_str = jsonencode(grid_data);
    
    % Send UDP packet
    write(udp_obj, json_str, 'string', target_ip, target_port);
end

% Function to test the UDP sender from Simulink
function udp_send_from_simulink(values)
    % This function can be called from a Simulink MATLAB Function block
    % Input: values (11-element vector of grid measurements)
    
    persistent udp_obj target_ip target_port
    
    if isempty(udp_obj)
        % Initialize UDP connection
        target_ip = '127.0.0.1';
        target_port = 12345;
        try
            udp_obj = udpport('datagram', 'IPV4');
        catch
            fprintf('Failed to initialize UDP in Simulink function\n');
            return;
        end
    end
    
    try
        % Convert to binary format
        binary_data = typecast(values, 'uint8');
        
        % Send UDP packet
        write(udp_obj, binary_data, 'string', target_ip, target_port);
        
    catch ME
        fprintf('UDP send error: %s\n', ME.message);
    end
end

% Simulink configuration helper
function create_simulink_udp_block()
    % Instructions for setting up UDP transmission in Simulink:
    %
    % 1. Add a MATLAB Function block to your Simulink model
    % 2. Set the function name to: udp_send_grid_data
    % 3. Copy this function code into the MATLAB Function block:
    
    fprintf('\n=== SIMULINK UDP BLOCK CONFIGURATION ===\n');
    fprintf('1. Add a MATLAB Function block to your model\n');
    fprintf('2. Connect your 11 grid measurement signals to the input\n');
    fprintf('3. Copy the following code into the MATLAB Function block:\n\n');
    
    fprintf('function udp_send_grid_data(values)\n');
    fprintf('    persistent udp_obj\n');
    fprintf('    if isempty(udp_obj)\n');
    fprintf('        udp_obj = udpport(''datagram'', ''IPV4'');\n');
    fprintf('    end\n');
    fprintf('    binary_data = typecast(values, ''uint8'');\n');
    fprintf('    write(udp_obj, binary_data, ''string'', ''127.0.0.1'', 12345);\n');
    fprintf('end\n\n');
    
    fprintf('4. Set input port dimensions to [11 1] for the 11 measurements\n');
    fprintf('5. Make sure the Python UDP receiver is running\n');
    fprintf('6. Run your Simulink simulation\n\n');
end

% Main execution (uncomment to run the example)
% udp_sender_example();
% create_simulink_udp_block();