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
