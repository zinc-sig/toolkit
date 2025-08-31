# Pipeline Examples

This directory contains working examples of Concourse CI pipelines for testing zinc-sig toolkit task files.

## Example: test-gcc-minio.yml

**Purpose**: Demonstrates how to test compilation task files using MinIO storage

**Key Features**:
- Uses GitHub releases to fetch ghost binary
- Stores task YAML in MinIO to avoid variable interpolation issues
- Shows proper configuration of GHOST_UPLOAD_CONFIG_* environment variables
- Demonstrates input mapping for task resources

## How to Use This Example

1. Start the development environment:
   ```bash
   cd toolkit/dev
   ./dev.sh start
   ```

2. Upload task YAML to MinIO:
   ```bash
   # The dev.sh script handles this automatically when testing
   ./dev.sh test compilation/gcc.yaml
   ```

3. Or deploy the example manually:
   ```bash
   ./dev.sh pipeline examples/test-gcc-minio.yml gcc-test
   ```

## Key Patterns

### Using GitHub Release for Ghost
```yaml
- name: ghost
  type: github-release
  source:
    owner: zinc-sig
    repository: ghost
    release: true
    pre_release: false
```

### Storing Task YAMLs in MinIO
```yaml
- name: task-yaml
  type: s3
  source:
    endpoint: http://172.19.0.2:9000
    bucket: task-inputs
    regexp: gcc-(.*).yaml
```

### Configuring Ghost for MinIO Upload
```yaml
params:
  GHOST_UPLOAD_CONFIG_ENDPOINT: http://172.19.0.2:9000
  GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
  GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
  GHOST_UPLOAD_CONFIG_BUCKET: task-outputs
```

## Testing Task Files

The recommended way to test task files is using the dev.sh script:

```bash
# Test compilation tasks
./dev.sh test compilation/gcc.yaml

# Test execution tasks  
./dev.sh test execution/stdio.yaml

# Test testing tasks
./dev.sh test testing/diff.yaml
```

The script automatically:
- Discovers test configurations from test-configs/ directory
- Uploads task YAML to MinIO
- Creates appropriate test pipeline with variants
- Runs the test using configuration-driven approach
- Shows uploaded files in MinIO
- Cleans up after completion