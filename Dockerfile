FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (for better caching)
COPY requirements.txt .
COPY requirements-dev.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir -r requirements-dev.txt

# Copy application code
COPY streaming/ ./streaming/
COPY src/ ./src/
COPY analytics/ ./analytics/

# Create logs directory
RUN mkdir -p /app/logs

# Expose UDP port
EXPOSE 12345/udp

# Set Python path
ENV PYTHONPATH=/app

# Command to run the streaming service
CMD ["python", "streaming/udp_receiver.py"]

# Start from Python base image
FROM python:3.10-slim

# Set working directory inside the container
WORKDIR /app

# Copy requirement file and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy your source code into container
COPY src/ ./src/

# Set environment variables (can also use .env file outside Docker)
ENV PYTHONUNBUFFERED=1

# Run your main Python script (e.g., data logger)
CMD ["python", "src/logger.py"]
