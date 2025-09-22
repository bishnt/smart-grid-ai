# Smart Grid AI System Stop Script
# This script stops all running services

param(
    [Parameter(HelpMessage="Force stop all services")]
    [switch]$Force,
    
    [Parameter(HelpMessage="Clean up volumes and data")]
    [switch]$CleanData,
    
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
Write-Host "  Smart Grid AI System Shutdown" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
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

# Function to stop running background jobs
function Stop-BackgroundJobs {
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" -and $_.Name -like "*udp*" -or $_.Name -like "*streaming*" }
    
    if ($jobs.Count -gt 0) {
        Write-Host "Stopping background streaming jobs..." -ForegroundColor Yellow
        foreach ($job in $jobs) {
            Write-Host "  Stopping job: $($job.Name) (ID: $($job.Id))" -ForegroundColor White
            Stop-Job $job -Force
            Remove-Job $job -Force
        }
        Write-Host "✓ Background jobs stopped" -ForegroundColor Green
    } else {
        Write-Host "No background streaming jobs found" -ForegroundColor Green
    }
}

# Function to stop Python processes
function Stop-PythonProcesses {
    $pythonProcesses = Get-Process | Where-Object { 
        $_.ProcessName -eq "python" -and 
        $_.MainModule.FileName -like "*udp_receiver*" -or
        $_.MainModule.FileName -like "*test_udp_stream*"
    } -ErrorAction SilentlyContinue
    
    if ($pythonProcesses.Count -gt 0) {
        Write-Host "Stopping Python streaming processes..." -ForegroundColor Yellow
        foreach ($process in $pythonProcesses) {
            Write-Host "  Stopping process: $($process.ProcessName) (PID: $($process.Id))" -ForegroundColor White
            if ($Force) {
                $process | Stop-Process -Force
            } else {
                $process | Stop-Process
            }
        }
        Write-Host "✓ Python processes stopped" -ForegroundColor Green
    } else {
        Write-Host "No Python streaming processes found" -ForegroundColor Green
    }
}

try {
    # Stop background PowerShell jobs
    Stop-BackgroundJobs
    
    # Stop Python processes
    Stop-PythonProcesses
    
    # Stop Docker containers if Docker is available
    if (Test-Command 'docker') {
        Write-Host "Checking Docker containers..." -ForegroundColor Blue
        
        # Get running containers for this project
        $containers = docker ps --filter "name=smart-grid" --format "{{.Names}}" 2>$null
        
        if (-not $containers) {
            # Fallback to checking by service names
            $containers = docker ps --filter "name=influxdb" --filter "name=grafana" --filter "name=streaming-service" --format "{{.Names}}" 2>$null
        }
        
        if ($containers) {
            Write-Host "Stopping Docker containers..." -ForegroundColor Yellow
            
            if (Test-Command 'docker-compose') {
                # Use docker-compose if available (preferred method)
                docker-compose down --remove-orphans
                
                if ($CleanData) {
                    Write-Host "Cleaning up Docker volumes..." -ForegroundColor Yellow
                    docker-compose down --volumes --remove-orphans
                    Write-Host "✓ Docker volumes cleaned" -ForegroundColor Green
                }
            } else {
                # Fallback to stopping containers manually
                $containerArray = $containers -split "`n" | Where-Object { $_ -ne "" }
                foreach ($container in $containerArray) {
                    Write-Host "  Stopping container: $container" -ForegroundColor White
                    if ($Force) {
                        docker kill $container 2>$null
                    } else {
                        docker stop $container 2>$null
                    }
                }
            }
            
            Write-Host "✓ Docker containers stopped" -ForegroundColor Green
        } else {
            Write-Host "No Docker containers found for this project" -ForegroundColor Green
        }
    } else {
        Write-Host "Docker not available - skipping container cleanup" -ForegroundColor Yellow
    }
    
    # Clean up temporary files if requested
    if ($CleanData) {
        Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
        
        $tempDirs = @("logs\temp", "data\temp", ".cache")
        foreach ($dir in $tempDirs) {
            if (Test-Path $dir) {
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  Removed: $dir" -ForegroundColor White
            }
        }
        
        # Clean up log files older than 7 days
        if (Test-Path "logs") {
            $oldLogs = Get-ChildItem "logs" -Filter "*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
            foreach ($log in $oldLogs) {
                Remove-Item $log.FullName -Force
                Write-Host "  Removed old log: $($log.Name)" -ForegroundColor White
            }
        }
        
        Write-Host "✓ Temporary files cleaned" -ForegroundColor Green
    }
    
    # Final status check
    Write-Host ""
    Write-Host "Performing final status check..." -ForegroundColor Blue
    
    # Check if any services are still running
    $stillRunning = @()
    
    # Check ports
    $ports = @(8086, 3000, 12345)
    foreach ($port in $ports) {
        try {
            $connection = Test-NetConnection -ComputerName "localhost" -Port $port -WarningAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                $serviceName = switch ($port) {
                    8086 { "InfluxDB" }
                    3000 { "Grafana" }
                    12345 { "UDP Service" }
                }
                $stillRunning += "$serviceName (port $port)"
            }
        } catch {
            # Port check failed - assume service is stopped
        }
    }
    
    if ($stillRunning.Count -gt 0) {
        Write-Host "⚠️  Some services may still be running:" -ForegroundColor Yellow
        foreach ($service in $stillRunning) {
            Write-Host "  • $service" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "If services are still running, try:" -ForegroundColor Yellow
        Write-Host "  • stop-system.ps1 -Force" -ForegroundColor White
        Write-Host "  • Manually stop the processes" -ForegroundColor White
    } else {
        Write-Host "✓ All services appear to be stopped" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  System Shutdown Complete" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($CleanData) {
        Write-Host "Note: Data cleanup was performed." -ForegroundColor Yellow
        Write-Host "You may need to reconfigure services on next startup." -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Error during shutdown: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Some services may still be running" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Manual cleanup options:" -ForegroundColor Blue
    Write-Host "  • docker-compose down --volumes" -ForegroundColor White
    Write-Host "  • Get-Process python | Stop-Process" -ForegroundColor White
    Write-Host "  • Get-Job | Stop-Job -Force; Get-Job | Remove-Job" -ForegroundColor White
    exit 1
}