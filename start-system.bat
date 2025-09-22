@echo off
REM Smart Grid AI System Startup Script (Batch version)
REM This script provides a simple way to start the system

setlocal EnableDelayedExpansion

echo ========================================
echo   Smart Grid AI System Startup
echo ========================================
echo.

REM Parse command line arguments
set "MODE=docker"
set "START_TEST=false"
set "SKIP_CHECKS=false"

:parse_args
if "%~1"=="" goto :start_system
if "%~1"=="--mode" (
    set "MODE=%~2"
    shift
    shift
    goto :parse_args
)
if "%~1"=="--test" (
    set "START_TEST=true"
    shift
    goto :parse_args
)
if "%~1"=="--skip-checks" (
    set "SKIP_CHECKS=true"
    shift
    goto :parse_args
)
if "%~1"=="--help" (
    goto :show_help
)
shift
goto :parse_args

:start_system
echo Mode: %MODE%
echo Current Directory: %CD%
echo.

REM Check if PowerShell is available and use it for better functionality
where powershell >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo Using PowerShell for enhanced functionality...
    if "%START_TEST%"=="true" (
        powershell -ExecutionPolicy Bypass -File "start-system.ps1" -Mode %MODE% -StartTest
    ) else (
        powershell -ExecutionPolicy Bypass -File "start-system.ps1" -Mode %MODE%
    )
    goto :end
)

REM Fallback to basic batch functionality
echo PowerShell not available, using basic batch functionality...

REM Create necessary directories
if not exist "logs" mkdir logs
if not exist "data" mkdir data  
if not exist "grafana" mkdir grafana

REM Create .env file if it doesn't exist
if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo Created .env file from .env.example
)

REM Check prerequisites
if "%SKIP_CHECKS%"=="false" (
    echo Checking prerequisites...
    
    if "%MODE%"=="docker" (
        docker --version >nul 2>nul
        if !ERRORLEVEL! neq 0 (
            echo Error: Docker is not installed or not in PATH
            echo Please install Docker Desktop: https://www.docker.com/products/docker-desktop
            goto :error_exit
        )
        
        docker-compose --version >nul 2>nul
        if !ERRORLEVEL! neq 0 (
            echo Error: Docker Compose is not installed or not in PATH
            goto :error_exit
        )
        
        echo Docker and Docker Compose are available
    ) else (
        python --version >nul 2>nul
        if !ERRORLEVEL! neq 0 (
            echo Error: Python is not installed or not in PATH
            echo Please install Python 3.11 or later
            goto :error_exit
        )
        
        echo Python is available
    )
)

if "%MODE%"=="docker" (
    echo Starting system with Docker Compose...
    
    REM Stop any existing containers
    echo Stopping any existing containers...
    docker-compose down >nul 2>nul
    
    REM Build and start services
    echo Building and starting services...
    docker-compose up --build -d
    
    if !ERRORLEVEL! neq 0 (
        echo Error: Failed to start services with Docker Compose
        goto :error_exit
    )
    
    echo Waiting for services to start...
    timeout /t 10 /nobreak >nul
    
) else (
    echo Starting system in development mode...
    
    REM Start InfluxDB and Grafana with Docker
    echo Starting InfluxDB and Grafana...
    docker-compose up influxdb grafana -d
    
    REM Install Python dependencies
    echo Installing Python dependencies...
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet -r requirements.txt
    
    REM Start UDP streaming service in background
    echo Starting UDP streaming service...
    start /B python streaming/udp_receiver.py
)

echo.
echo ========================================
echo   System Started Successfully!
echo ========================================
echo.
echo Service URLs:
echo   • InfluxDB:  http://localhost:8086
echo   • Grafana:   http://localhost:3000  
echo   • UDP Port:  localhost:12345
echo.
echo Default Credentials:
echo   • InfluxDB:  admin / admin123
echo   • Grafana:   admin / admin123
echo.
echo Next Steps:
echo   1. Configure Grafana dashboards
echo   2. Start your Simulink simulation with UDP output
echo   3. Monitor data flow in Grafana
echo.

REM Start test data streaming if requested
if "%START_TEST%"=="true" (
    echo Starting test data streaming...
    timeout /t 2 /nobreak >nul
    start /B python streaming/test_udp_stream.py --test stream --duration 300 --rate 0.1
    echo Test data streaming started in background
)

echo ========================================
echo.
goto :end

:show_help
echo Usage: start-system.bat [options]
echo.
echo Options:
echo   --mode [docker^|dev]  Mode: 'docker' for containerized, 'dev' for development (default: docker)
echo   --test               Start test data streaming
echo   --skip-checks        Skip dependency checks  
echo   --help               Show this help message
echo.
echo Examples:
echo   start-system.bat                    Start in Docker mode
echo   start-system.bat --mode dev         Start in development mode
echo   start-system.bat --test             Start with test data streaming
echo   start-system.bat --mode dev --test  Start in dev mode with test streaming
echo.
goto :end

:error_exit
echo.
echo ========================================
echo   Error: System startup failed
echo ========================================
echo.
exit /b 1

:end
echo Press any key to exit...
pause >nul