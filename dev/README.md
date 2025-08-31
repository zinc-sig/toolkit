# Task YAML Development Environment

A local development environment for testing Concourse CI task YAMLs in the zinc-sig toolkit. This environment allows you to test compilation, execution, and testing tasks with real MinIO integration and the ghost binary for output capture.

## 🚀 Quick Start

```bash
# 1. Start the environment
./dev.sh start

# 2. Test a task YAML (example: gcc compilation)
cd /home/system/workspace/stommydx/zinc-sig/toolkit
docker run --rm --network toolkit-dev-network -v $(pwd):/workspace --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc cp /workspace/compilation/gcc.yaml minio/task-inputs/gcc-v1.yaml"

./bin/fly -t dev set-pipeline -p gcc-test -c examples/test-gcc-minio.yml -n
./bin/fly -t dev trigger-job -j gcc-test/test-gcc-task --watch

# 3. Clean up when done
./dev.sh stop
```

## 📋 Prerequisites

- Docker Desktop installed and running
- Linux/macOS (Windows users: use WSL2)
- 4GB free RAM
- Ports 8080, 9000, 9001 available

## What This Environment Provides

- **Concourse CI**: Local pipeline orchestration (http://localhost:8080)
- **MinIO**: S3-compatible object storage for artifacts (http://localhost:9001)
- **Ghost Binary**: Command runner that captures execution metadata and uploads to MinIO
- **Mock Resources**: Test data providers for submissions and assets
- **Fly CLI**: Command-line tool for managing Concourse

## 🛠️ Development Workflow

### Step 1: Start Environment
```bash
./dev.sh start
```
This starts Concourse CI, MinIO storage, and PostgreSQL database.

### Step 2: Test a Task
```bash
# Test an existing task
./dev.sh test ../compilation/gcc.yaml

# Test with custom parameters
./dev.sh test my-task.yaml
```

### Step 3: Deploy a Pipeline
```bash
# Deploy a pipeline
./dev.sh pipeline examples/01-simple-test.yml my-pipeline

# View in browser
open http://localhost:8080/teams/main/pipelines/my-pipeline
```

### Step 4: Clean Up
```bash
./dev.sh stop   # Stop services (data preserved)
./dev.sh clean  # Remove everything
```

## 📁 Directory Structure

```
dev/
├── dev.sh                 # Main CLI tool
├── docker-compose.yml     # Service definitions
├── examples/              # Working pipeline examples
│   ├── 01-simple-test.yml
│   └── 02-with-compilation.yml
├── mock-resources/        # Test data
│   ├── submissions/       # Sample code
│   ├── assignment-assets/ # Test cases
│   └── ghost/            # Ghost binary
├── LESSONS_LEARNED.md     # What we learned (MUST READ!)
└── TROUBLESHOOTING.md     # Common issues & solutions
```

## Key Commands

### Environment Management
```bash
./dev.sh start    # Start all services
./dev.sh stop     # Stop services
./dev.sh status   # Check status
./dev.sh clean    # Remove everything
```

### Pipeline Testing
```bash
# Generate a test pipeline from task YAML
./generate-task-pipeline.sh compilation/gcc.yaml --output test.yml

# Deploy and run
./bin/fly -t dev set-pipeline -p test -c test.yml -n
./bin/fly -t dev trigger-job -j test/test-task --watch
```

### Debugging
```bash
# Check resource issues
./bin/fly -t dev check-resource -r pipeline/resource-name
./bin/fly -t dev resource-versions -r pipeline/resource-name

# Check MinIO files
docker run --rm --network toolkit-dev-network --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc ls minio/task-outputs/"
```

## Critical Things to Remember

1. **Always use IP addresses** (172.19.0.2 for MinIO) - DNS doesn't work in containerd workers
2. **Ghost needs `GHOST_UPLOAD_CONFIG_*` environment variables** for MinIO uploads
3. **Store task YAMLs in MinIO** to avoid variable interpolation issues with mock resources
4. **Be patient with GitHub releases** - Ghost download can take 2-5 minutes

## Project Structure

```
dev/
├── bin/                        # fly CLI and ghost binary
├── examples/                   # Working pipeline examples
│   └── test-gcc-minio.yml     # Example gcc test with MinIO
├── task-testing/              # Test files
│   ├── submissions/           # Sample source code
│   └── assets/               # Test inputs
├── docker-compose.yml         # Infrastructure definition
├── dev.sh                    # Main management script
├── generate-task-pipeline.sh # Pipeline generator
├── README.md                 # This file
├── DEVELOPER_GUIDE.md        # Complete technical guide
└── TROUBLESHOOTING.md        # Debugging and solutions
```

## Documentation

- **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** - Complete guide with architecture, concepts, and detailed instructions
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues, debugging techniques, and solutions

## 🌐 Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Concourse Web UI | http://localhost:8080 | dev / dev |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| MinIO API | http://localhost:9000 | minioadmin / minioadmin |

## Requirements

- Docker and Docker Compose
- Linux or macOS (WSL2 on Windows)
- 4GB+ free RAM
- Ports 8080, 9000, 9001 available