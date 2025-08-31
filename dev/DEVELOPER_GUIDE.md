# Developer Guide - Task YAML Testing Environment

## Table of Contents
1. [Architecture](#architecture)
2. [Key Concepts](#key-concepts)
3. [Complete Setup Guide](#complete-setup-guide)
4. [Testing Task YAMLs](#testing-task-yamls)
5. [Debugging with Fly CLI](#debugging-with-fly-cli)
6. [MinIO Operations](#minio-operations)
7. [Known Issues & Solutions](#known-issues--solutions)
8. [Technical Details](#technical-details)

## Architecture

### System Overview
```
┌─────────────────────────────────────────────────────────┐
│                    Concourse CI                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Pipeline Configuration               │   │
│  │                                                   │   │
│  │  Resources:                                       │   │
│  │  • ghost (GitHub Release)                         │   │
│  │  • task-yaml (S3/MinIO)                          │   │
│  │  • submission (Mock)                              │   │
│  │  • assignment-assets (Mock)                       │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    Task Execution                        │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Docker Container (gcc:latest)          │   │
│  │                                                   │   │
│  │  Environment Variables:                           │   │
│  │  • GHOST_UPLOAD_CONFIG_ENDPOINT                   │   │
│  │  • GHOST_UPLOAD_CONFIG_ACCESS_KEY                 │   │
│  │  • GHOST_UPLOAD_CONFIG_SECRET_KEY                 │   │
│  │  • GHOST_UPLOAD_CONFIG_BUCKET                     │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                         MinIO                            │
│  ┌──────────────────────────────────────────────────┐   │
│  │              task-outputs bucket                  │   │
│  │  • compile.log, compile.err, binaries             │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Network Configuration
- **Network**: toolkit-dev-network (bridge)
- **MinIO IP**: 172.19.0.2 (always use IP, DNS doesn't work)
- **Concourse**: localhost:8080
- **MinIO Console**: localhost:9001

## Key Concepts

### 1. Variable Interpolation (`vars:`)
Replaces `(())` placeholders in task YAML at pipeline time:
```yaml
- task: run-task
  file: task-yaml/gcc.yaml
  vars:
    source_file: submission/hello.c  # Replaces ((source_file))
    output_binary: hello              # Replaces ((output_binary))
    compiler_flags: "-Wall -O2"       # Replaces ((compiler_flags))
    language: c                      # Replaces ((language))
    score: "10"                      # Replaces ((score))
```

### 2. Environment Variables (`params:`)
Sets environment variables for the task runtime:
```yaml
- task: run-task
  params:
    # Ghost reads these GHOST_UPLOAD_CONFIG_* variables
    GHOST_UPLOAD_CONFIG_ENDPOINT: http://172.19.0.2:9000
    GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
    GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
    GHOST_UPLOAD_CONFIG_BUCKET: task-outputs
```

### 3. Resource Types

#### Mock Resources
For test data that doesn't change:
```yaml
- name: submission
  type: mock
  source:
    create_files:
      hello.c: |
        #include <stdio.h>
        int main() {
          printf("Hello, World!\\n");
          return 0;
        }
```

#### S3 Resources (MinIO)
For task YAMLs to avoid interpolation issues:
```yaml
- name: task-yaml
  type: s3
  source:
    endpoint: http://172.19.0.2:9000
    bucket: task-inputs
    regexp: gcc-(.*).yaml  # Must match exact filename
    access_key_id: minioadmin
    secret_access_key: minioadmin
    disable_ssl: true
    use_v2_signing: true
```

#### GitHub Release Resources
For downloading ghost binary:
```yaml
- name: ghost
  type: github-release
  source:
    owner: zinc-sig
    repository: ghost
    release: true       # MUST have both
    pre_release: false  # of these fields
```

## Complete Setup Guide

### Prerequisites
```bash
# Check Docker is running
docker info

# Check ports are free
lsof -i :8080,9000,9001
```

### Start Environment
```bash
# Start all services
./dev.sh start

# This will:
# 1. Start Concourse, MinIO, PostgreSQL
# 2. Download fly CLI if needed
# 3. Configure fly target
# 4. Create MinIO buckets (task-inputs, task-outputs)
```

### Prepare Task YAML for Testing

#### Option A: Using MinIO (Recommended)
```bash
# Upload task YAML to MinIO
cd /home/system/workspace/stommydx/zinc-sig/toolkit
docker run --rm --network toolkit-dev-network -v $(pwd):/workspace --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc cp /workspace/compilation/gcc.yaml minio/task-inputs/gcc-v1.yaml"
```

#### Option B: Using Generator Script
```bash
./generate-task-pipeline.sh compilation/gcc.yaml \
  --params source_file=submission/hello.c \
  --params output_binary=hello \
  --output test-gcc.yml
```

### Deploy and Run Pipeline
```bash
# Set pipeline
./bin/fly -t dev set-pipeline -p test-gcc -c test-gcc-minio.yml -n

# Trigger job
./bin/fly -t dev trigger-job -j test-gcc/test-gcc-task --watch
```

## Testing Task YAMLs

### Example: Testing gcc.yaml

1. **Create pipeline configuration** (test-gcc-minio.yml):
```yaml
resources:
  - name: ghost
    type: github-release
    source:
      owner: zinc-sig
      repository: ghost
      release: true
      pre_release: false

  - name: task-yaml
    type: s3
    source:
      endpoint: http://172.19.0.2:9000
      bucket: task-inputs
      regexp: gcc-(.*).yaml
      access_key_id: minioadmin
      secret_access_key: minioadmin
      disable_ssl: true
      use_v2_signing: true

  - name: submission
    type: mock
    source:
      create_files:
        hello.c: |
          #include <stdio.h>
          int main() {
              printf("Hello, World!\\n");
              return 0;
          }

  - name: assignment-assets
    type: mock
    source:
      create_files:
        placeholder.txt: "placeholder"

jobs:
  - name: test-gcc-task
    plan:
      - in_parallel:
        - get: ghost
        - get: submission
        - get: assignment-assets
        - get: task-yaml

      - task: compile-with-ghost
        file: task-yaml/gcc-v1.yaml
        vars:
          source_file: submission/hello.c
          output_binary: hello
          compiler_flags: "-Wall -Wextra -O2"
          language: c
          score: "10"
        params:
          GHOST_UPLOAD_CONFIG_ENDPOINT: http://172.19.0.2:9000
          GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_BUCKET: task-outputs
```

2. **Upload task YAML to MinIO**:
```bash
cd /home/system/workspace/stommydx/zinc-sig/toolkit
docker run --rm --network toolkit-dev-network -v $(pwd):/workspace --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc cp /workspace/compilation/gcc.yaml minio/task-inputs/gcc-v1.yaml"
```

3. **Deploy and run**:
```bash
./bin/fly -t dev set-pipeline -p gcc-test -c test-gcc-minio.yml -n
./bin/fly -t dev trigger-job -j gcc-test/test-gcc-task --watch
```

## Debugging with Fly CLI

### Essential Commands

```bash
# Pipeline Management
./bin/fly -t dev pipelines                          # List all pipelines
./bin/fly -t dev set-pipeline -p name -c file.yml -n # Create/update pipeline
./bin/fly -t dev destroy-pipeline -p name -n         # Delete pipeline
./bin/fly -t dev get-pipeline -p name                # Show pipeline config

# Job Management
./bin/fly -t dev trigger-job -j pipeline/job --watch # Run and watch job
./bin/fly -t dev builds -j pipeline/job              # List job builds
./bin/fly -t dev watch -j pipeline/job -b 123        # Watch specific build

# Resource Debugging
./bin/fly -t dev check-resource -r pipeline/resource # Force resource check
./bin/fly -t dev resource-versions -r pipeline/resource # List found versions
```

### Debugging Hanging Resources

When a pipeline hangs with "latest version of resource not found":

1. **Check resource status**:
```bash
./bin/fly -t dev check-resource -r pipeline/resource
```

2. **List versions found**:
```bash
./bin/fly -t dev resource-versions -r pipeline/resource
```

3. **For S3 resources, verify file exists**:
```bash
docker run --rm --network toolkit-dev-network --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc ls minio/bucket-name/"
```

### Cleanup All Pipelines
```bash
for p in $(./bin/fly -t dev pipelines | tail -n +2 | awk '{print $2}'); do
  ./bin/fly -t dev destroy-pipeline -p "$p" -n
done
```

## MinIO Operations

### List Files
```bash
# List files in bucket
docker run --rm --network toolkit-dev-network --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc ls minio/task-outputs/"
```

### Upload Files
```bash
# Upload task YAML
cd /home/system/workspace/stommydx/zinc-sig/toolkit
docker run --rm --network toolkit-dev-network -v $(pwd):/workspace --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc cp /workspace/compilation/gcc.yaml minio/task-inputs/gcc-v1.yaml"
```

### Download Files
```bash
# Download from MinIO
docker run --rm --network toolkit-dev-network -v $(pwd):/workspace --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc cp minio/task-outputs/hello /workspace/hello"
```

### Get Container IPs
```bash
# Get MinIO IP address
docker inspect toolkit-minio --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# View all container IPs
docker network inspect toolkit-dev-network | grep -A 5 "IPv4"
```

## Known Issues & Solutions

### ✅ SOLVED Issues

#### Ghost MinIO Configuration
**Solution**: Use `GHOST_UPLOAD_CONFIG_*` environment variables:
```yaml
params:
  GHOST_UPLOAD_CONFIG_ENDPOINT: http://172.19.0.2:9000
  GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
  GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
  GHOST_UPLOAD_CONFIG_BUCKET: task-outputs
```

### ⚠️ Persistent Issues

#### 1. DNS Resolution Doesn't Work
**Problem**: Concourse workers with containerd runtime cannot resolve Docker container hostnames.

**Solution**: Always use IP addresses:
```yaml
# Wrong: http://toolkit-minio:9000
# Right: http://172.19.0.2:9000
```

#### 2. Variable Interpolation in Mock Resources
**Problem**: Mock resources try to interpolate `(())` placeholders causing "undefined vars" errors.

**Solution**: Store task YAMLs in MinIO/S3 instead of mock resources.

#### 3. GitHub Release Resource is Slow
**Problem**: Ghost binary download from GitHub takes 2-5 minutes.

**Workaround**: Be patient. Ensure configuration includes:
```yaml
release: true
pre_release: false
```

#### 4. S3 Resource "latest version not found"
**Problem**: S3 resource can't find files.

**Solutions**:
- Ensure file matches regexp pattern exactly (anchored on both ends)
- Use versioned naming: `gcc-v1.yaml` matches `gcc-(.*).yaml`
- Verify file exists in MinIO first

## Technical Details

### Task YAML Requirements
Tasks must follow Concourse specification:
- `platform`: Target OS (linux)
- `image_resource`: Docker image to use
- `inputs`: Resources consumed
- `outputs`: Resources produced
- `params`: Parameters with `(())` placeholders
- `run`: Command to execute

### Ghost Binary
Ghost is a command runner that:
- Captures stdout/stderr
- Measures execution time
- Uploads results to MinIO
- Returns JSON metadata

Configuration via environment:
- `GHOST_UPLOAD_CONFIG_ENDPOINT`
- `GHOST_UPLOAD_CONFIG_ACCESS_KEY`
- `GHOST_UPLOAD_CONFIG_SECRET_KEY`
- `GHOST_UPLOAD_CONFIG_BUCKET`

### Docker Compose Services
- **concourse**: CI/CD orchestrator
- **concourse-db**: PostgreSQL for Concourse
- **toolkit-minio**: S3-compatible storage
- Network: toolkit-dev-network (bridge)

## Best Practices

### DO:
1. Use IP addresses (172.19.0.2 for MinIO)
2. Store task YAMLs in MinIO/S3
3. Use `vars:` for variable interpolation
4. Use `GHOST_UPLOAD_CONFIG_*` environment variables
5. Be patient with GitHub releases
6. Create MinIO buckets before testing
7. Use fly CLI for debugging

### DON'T:
1. Use container hostnames (DNS doesn't work)
2. Put task YAMLs with `(())` in mock resources
3. Expect ghost to download quickly from GitHub
4. Modify the actual task files in compilation/, execution/, testing/

## Directory Structure
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
├── README.md                 # Quick start guide
├── DEVELOPER_GUIDE.md        # This file
└── TROUBLESHOOTING.md        # Issue resolution guide
```