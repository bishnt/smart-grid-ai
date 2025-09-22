# Smart Grid AI System Startup Script
# This script starts the complete system: InfluxDB, Grafana, and UDP streaming service

param(
    [Parameter(HelpMessage="Mode: 'dev' for development, 'docker' for containerized")]
    [ValidateSet('dev', 'docker')]
    [string]$Mode = 'docker',
    
    [Parameter(HelpMessage="Start test data streaming")]
    [switch]$StartTest,
    
    [Parameter(HelpMessage="Skip dependency checks")]
    [switch]$SkipChecks,
    
    [Parameter(HelpMessage="Verbose output")]
    [switch]$Verbose
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Enable verbose output if requested
if ($Verbose) {
    $VerbosePreference = "Continue"
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Smart Grid AI System Startup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Green
Write-Host "Current Directory: $(Get-Location)" -ForegroundColor Green
Write-Host ""

# Function to check if a command exists
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to check if a port is in use
function Test-Port {
    param([int]$Port)
    try {
        $connection = Test-NetConnection -ComputerName "localhost" -Port $Port -WarningAction SilentlyContinue
        return $connection.TcpTestSucceeded
    } catch {
        return $false
    }
}

# Function to wait for service to be ready
function Wait-ForService {
    param(
        [string]$ServiceName,
        [int]$Port,
        [int]$TimeoutSeconds = 60
    )
    
    Write-Host "Waiting for $ServiceName to be ready on port $Port..." -ForegroundColor Yellow
    
    $timer = 0
    while ($timer -lt $TimeoutSeconds) {
        if (Test-Port -Port $Port) {
            Write-Host "✓ $ServiceName is ready!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 2
        $timer += 2
        Write-Host "." -NoNewline -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "✗ Timeout waiting for $ServiceName" -ForegroundColor Red
    return $false
}

# Check prerequisites
if (-not $SkipChecks) {
    Write-Host "Checking prerequisites..." -ForegroundColor Blue
    
    if ($Mode -eq 'docker') {
        if (-not (Test-Command 'docker')) {
            Write-Host "✗ Docker is not installed or not in PATH" -ForegroundColor Red
            Write-Host "Please install Docker Desktop: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
            exit 1
        }
        
        if (-not (Test-Command 'docker-compose')) {
            Write-Host "✗ Docker Compose is not installed or not in PATH" -ForegroundColor Red
            Write-Host "Please install Docker Compose" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "✓ Docker and Docker Compose are available" -ForegroundColor Green
    } else {
        if (-not (Test-Command 'python')) {
            Write-Host "✗ Python is not installed or not in PATH" -ForegroundColor Red
            Write-Host "Please install Python 3.11 or later" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "✓ Python is available" -ForegroundColor Green
    }
}

# Create necessary directories
$directories = @("logs", "data", "grafana")
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "✓ Created directory: $dir" -ForegroundColor Green
    }
}

# Create .env file if it doesn't exist
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env" -Force
    Write-Host "✓ Created .env file from .env.example" -ForegroundColor Green
    Write-Host "Please edit .env file with your specific configuration" -ForegroundColor Yellow
}

try {
    if ($Mode -eq 'docker') {
        Write-Host "Starting system with Docker Compose..." -ForegroundColor Blue
        
        # Check if any containers are already running
        $runningContainers = docker ps --format "table {{.Names}}" | Select-String -Pattern "(influxdb|grafana|streaming-service)"
        if ($runningContainers) {
            Write-Host "Some containers are already running:" -ForegroundColor Yellow
            $runningContainers | Write-Host
            
            $response = Read-Host "Stop existing containers? (y/N)"
            if ($response -eq 'y' -or $response -eq 'Y') {
                Write-Host "Stopping existing containers..." -ForegroundColor Yellow
                docker-compose down
                Start-Sleep -Seconds 3
            }
        }
        
        # Build and start services
        Write-Host "Building and starting services..." -ForegroundColor Blue
        docker-compose up --build -d
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ Failed to start services with Docker Compose" -ForegroundColor Red
            exit 1
        }
        
        # Wait for services to be ready
        Write-Host "Checking service status..." -ForegroundColor Blue
        
        if (-not (Wait-ForService -ServiceName "InfluxDB" -Port 8086)) {
            Write-Host "✗ InfluxDB failed to start" -ForegroundColor Red
            exit 1
        }
        
        if (-not (Wait-ForService -ServiceName "Grafana" -Port 3000)) {
            Write-Host "✗ Grafana failed to start" -ForegroundColor Red
            exit 1
        }
        
        # Check UDP service (it doesn't have an HTTP port to check)
        Start-Sleep -Seconds 5
        $udpService = docker ps --filter "name=streaming-service" --format "table {{.Status}}"
        if ($udpService -like "*Up*") {
            Write-Host "✓ UDP Streaming Service is running" -ForegroundColor Green
        } else {
            Write-Host "✗ UDP Streaming Service failed to start" -ForegroundColor Red
            Write-Host "Check logs with: docker-compose logs streaming-service" -ForegroundColor Yellow
        }
        
    } else {
        Write-Host "Starting system in development mode..." -ForegroundColor Blue
        
        # Check if InfluxDB and Grafana are already running locally
        $influxRunning = Test-Port -Port 8086
        $grafanaRunning = Test-Port -Port 3000
        
        if (-not $influxRunning -or -not $grafanaRunning) {
            Write-Host "InfluxDB and/or Grafana are not running locally." -ForegroundColor Yellow
            Write-Host "Starting them with Docker..." -ForegroundColor Blue
            
            # Start only InfluxDB and Grafana
            docker-compose up influxdb grafana -d
            
            if (-not (Wait-ForService -ServiceName "InfluxDB" -Port 8086)) {
                exit 1
            }
            if (-not (Wait-ForService -ServiceName "Grafana" -Port 3000)) {
                exit 1
            }
        } else {
            Write-Host "✓ InfluxDB and Grafana are already running" -ForegroundColor Green
        }
        
        # Install Python dependencies
        Write-Host "Installing Python dependencies..." -ForegroundColor Blue
        python -m pip install --quiet --upgrade pip
        python -m pip install --quiet -r requirements.txt
        
        # Start UDP streaming service in background
        Write-Host "Starting UDP streaming service..." -ForegroundColor Blue
        $job = Start-Job -ScriptBlock {
            param($WorkingDirectory)
            Set-Location $WorkingDirectory
            python streaming/udp_receiver.py
        } -ArgumentList (Get-Location).Path
        
        Write-Host "✓ UDP streaming service started (Job ID: $($job.Id))" -ForegroundColor Green
    }
    
    # Display service information
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  System Started Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Service URLs:" -ForegroundColor Blue
    Write-Host "  • InfluxDB:  http://localhost:8086" -ForegroundColor White
    Write-Host "  • Grafana:   http://localhost:3000" -ForegroundColor White
    Write-Host "  • UDP Port:  localhost:12345" -ForegroundColor White
    Write-Host ""
    Write-Host "Default Credentials:" -ForegroundColor Blue
    Write-Host "  • InfluxDB:  admin / admin123" -ForegroundColor White
    Write-Host "  • Grafana:   admin / admin123" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Blue
    Write-Host "  1. Configure Grafana dashboards" -ForegroundColor White
    Write-Host "  2. Start your Simulink simulation with UDP output" -ForegroundColor White
    Write-Host "  3. Monitor data flow in Grafana" -ForegroundColor White
    Write-Host ""
    
    # Start test data streaming if requested
    if ($StartTest) {
        Write-Host "Starting test data streaming..." -ForegroundColor Blue
        Start-Sleep -Seconds 2
        
        if ($Mode -eq 'dev') {
            python streaming/test_udp_stream.py --test stream --duration 300 --rate 0.1
        } else {
            $testJob = Start-Job -ScriptBlock {
                param($WorkingDirectory)
                Set-Location $WorkingDirectory
                python streaming/test_udp_stream.py --test stream --duration 300 --rate 0.1
            } -ArgumentList (Get-Location).Path
            
            Write-Host "✓ Test data streaming started (Job ID: $($testJob.Id))" -ForegroundColor Green
        }
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "✗ Error starting system: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check logs for more details" -ForegroundColor Yellow
    exit 1
}