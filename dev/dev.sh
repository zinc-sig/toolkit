#!/bin/bash

# Toolkit Development CLI
# Unified interface for all development operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLY_CMD="$SCRIPT_DIR/bin/fly"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Check if fly CLI exists
check_fly() {
    if [ ! -f "$FLY_CMD" ]; then
        print_info "Fly CLI not found. Downloading..."
        mkdir -p "$SCRIPT_DIR/bin"
        curl -s 'http://localhost:8080/api/v1/cli?arch=amd64&platform=linux' -o "$FLY_CMD"
        chmod +x "$FLY_CMD"
        print_success "Fly CLI downloaded"
    fi
}

# Initialize MinIO buckets
init_minio_buckets() {
    print_info "Initializing MinIO buckets..."
    
    # Wait for MinIO to be ready
    for i in {1..10}; do
        if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # Get MinIO IP dynamically
    local minio_ip=$(docker inspect toolkit-minio --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    
    # Create buckets using MinIO client via Docker (using IP as DNS doesn't work)
    docker run --rm --network toolkit-dev-network --entrypoint sh \
        minio/mc:latest -c \
        "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
         mc mb --ignore-existing minio/task-outputs && \
         mc mb --ignore-existing minio/task-inputs" 2>/dev/null || true
    
    print_success "MinIO buckets initialized"
}

# Start development environment
start_env() {
    check_docker
    print_info "Starting development environment..."
    
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d
    
    # Wait for services
    print_info "Waiting for services to be ready..."
    sleep 5
    
    # Download fly if needed
    check_fly
    
    # Configure fly target
    $FLY_CMD -t dev login -c http://localhost:8080 -u dev -p dev -n main > /dev/null 2>&1 || true
    
    # Initialize MinIO buckets
    init_minio_buckets
    
    print_success "Development environment started!"
    echo ""
    echo "  Concourse UI: http://localhost:8080 (dev:dev)"
    echo "  MinIO Console: http://localhost:9001 (minioadmin:minioadmin)"
    echo ""
}

# Stop development environment
stop_env() {
    print_info "Stopping development environment..."
    docker compose -f "$DOCKER_COMPOSE_FILE" stop
    print_success "Environment stopped"
}

# Clean everything
clean_env() {
    print_info "Cleaning development environment..."
    
    # Destroy all pipelines
    if [ -f "$FLY_CMD" ]; then
        for pipeline in $($FLY_CMD -t dev pipelines 2>/dev/null | tail -n +2 | awk '{print $2}'); do
            print_info "Removing pipeline: $pipeline"
            $FLY_CMD -t dev destroy-pipeline -p "$pipeline" -n
        done
    fi
    
    # Stop and remove containers
    docker compose -f "$DOCKER_COMPOSE_FILE" down -v
    
    # Remove fly binary
    rm -f "$FLY_CMD"
    
    print_success "Environment cleaned"
}

# Show status
show_status() {
    echo "==================================="
    echo "Development Environment Status"
    echo "==================================="
    echo ""
    
    # Check Docker services
    if docker compose -f "$DOCKER_COMPOSE_FILE" ps --quiet 2>/dev/null | grep -q .; then
        print_success "Docker services running"
        docker compose -f "$DOCKER_COMPOSE_FILE" ps
    else
        print_error "Docker services not running"
    fi
    echo ""
    
    # Check Concourse
    if curl -s http://localhost:8080/api/v1/info > /dev/null 2>&1; then
        print_success "Concourse is accessible"
        
        # List pipelines
        if [ -f "$FLY_CMD" ]; then
            echo ""
            echo "Active pipelines:"
            $FLY_CMD -t dev pipelines 2>/dev/null || echo "  No pipelines configured"
        fi
    else
        print_error "Concourse is not accessible"
    fi
    echo ""
    
    # Check MinIO
    if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        print_success "MinIO is accessible"
    else
        print_error "MinIO is not accessible"
    fi
}

# Test a task file (old method - kept for compatibility)
test_task() {
    local task_file="$1"
    
    if [ -z "$task_file" ]; then
        print_error "Usage: $0 test <task-file.yaml>"
        exit 1
    fi
    
    if [ ! -f "$task_file" ]; then
        print_error "Task file not found: $task_file"
        exit 1
    fi
    
    check_fly
    
    print_info "Testing task: $task_file"
    
    # Prepare mock inputs
    MOCK_DIR="$SCRIPT_DIR/mock-resources"
    
    $FLY_CMD -t dev execute -c "$task_file" \
        -i submission="$MOCK_DIR/submissions" \
        -i assignment-assets="$MOCK_DIR/assignment-assets" \
        -i ghost="$MOCK_DIR/ghost"
}

# Test a toolkit task YAML with MinIO integration
test_task_yaml() {
    local task_path="$1"
    
    if [ -z "$task_path" ]; then
        print_error "Usage: $0 test <task-path>"
        echo ""
        echo "Examples:"
        echo "  $0 test compilation/gcc.yaml"
        echo "  $0 test execution/stdio.yaml"
        echo "  $0 test testing/diff.yaml"
        exit 1
    fi
    
    # Check if task file exists
    local full_path="../$task_path"
    if [ ! -f "$full_path" ]; then
        print_error "Task file not found: $full_path"
        exit 1
    fi
    
    check_fly
    
    # Extract task type and name
    local task_type=$(echo "$task_path" | cut -d'/' -f1)
    local task_name=$(basename "$task_path" .yaml)
    local pipeline_name="${task_name}-test"
    
    print_info "Testing $task_type task: $task_name"
    
    # Get MinIO IP dynamically
    local minio_ip=$(docker inspect toolkit-minio --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    if [ -z "$minio_ip" ]; then
        print_error "Cannot find MinIO container IP"
        exit 1
    fi
    
    # Upload task YAML to MinIO
    print_info "Uploading task YAML to MinIO (IP: $minio_ip)..."
    local version="v$(date +%s)"
    docker run --rm --network toolkit-dev-network \
        -v "$(dirname "$SCRIPT_DIR"):/workspace" \
        --entrypoint sh minio/mc:latest -c \
        "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
         mc cp /workspace/$task_path minio/task-inputs/${task_name}-${version}.yaml" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_error "Failed to upload task YAML to MinIO"
        exit 1
    fi
    
    # Create test pipeline based on task type
    local pipeline_file="$SCRIPT_DIR/.test-${task_name}.yml"
    
    if [ "$task_type" = "compilation" ]; then
        create_compilation_test_pipeline "$task_name" "$version" "$pipeline_file" "$minio_ip"
    elif [ "$task_type" = "execution" ]; then
        create_execution_test_pipeline "$task_name" "$version" "$pipeline_file" "$minio_ip"
    elif [ "$task_type" = "testing" ]; then
        create_testing_test_pipeline "$task_name" "$version" "$pipeline_file" "$minio_ip"
    else
        print_error "Unknown task type: $task_type"
        exit 1
    fi
    
    # Deploy pipeline
    print_info "Deploying test pipeline..."
    $FLY_CMD -t dev set-pipeline -p "$pipeline_name" -c "$pipeline_file" -n > /dev/null 2>&1
    
    # Unpause the pipeline (pipelines are paused by default)
    $FLY_CMD -t dev unpause-pipeline -p "$pipeline_name" > /dev/null 2>&1
    
    # Trigger job
    print_info "Running test..."
    $FLY_CMD -t dev trigger-job -j "$pipeline_name/test-task" --watch
    
    # Check results in MinIO based on task type
    print_info "Checking results in MinIO..."
    if [ "$task_type" = "compilation" ]; then
        docker run --rm --network toolkit-dev-network \
            --entrypoint sh minio/mc:latest -c \
            "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
             echo '📦 Files uploaded to compilation-outputs:' && \
             mc ls minio/compilation-outputs/ 2>/dev/null || echo 'No files in compilation-outputs' && \
             echo '' && \
             echo '📦 Files uploaded to task-outputs (by ghost):' && \
             mc ls minio/task-outputs/ 2>/dev/null || echo 'No files in task-outputs'"
    elif [ "$task_type" = "execution" ]; then
        docker run --rm --network toolkit-dev-network \
            --entrypoint sh minio/mc:latest -c \
            "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
             echo '📦 Files uploaded to execution-outputs:' && \
             mc ls minio/execution-outputs/ 2>/dev/null || echo 'No files in execution-outputs' && \
             echo '' && \
             echo '📦 Files uploaded to task-outputs (by ghost):' && \
             mc ls minio/task-outputs/ 2>/dev/null || echo 'No files in task-outputs'"
    elif [ "$task_type" = "testing" ]; then
        docker run --rm --network toolkit-dev-network \
            --entrypoint sh minio/mc:latest -c \
            "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
             echo '📦 Files uploaded to testing-outputs:' && \
             mc ls minio/testing-outputs/ 2>/dev/null || echo 'No files in testing-outputs' && \
             echo '' && \
             echo '📦 Files uploaded to task-outputs (by ghost):' && \
             mc ls minio/task-outputs/ 2>/dev/null || echo 'No files in task-outputs'"
    else
        docker run --rm --network toolkit-dev-network \
            --entrypoint sh minio/mc:latest -c \
            "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
             echo '📦 All MinIO buckets:' && \
             mc ls minio/ && \
             echo '' && \
             echo '📦 Files in task-outputs:' && \
             mc ls minio/task-outputs/ 2>/dev/null || echo 'No files in task-outputs'"
    fi
    
    # Cleanup
    print_info "Cleaning up..."
    $FLY_CMD -t dev destroy-pipeline -p "$pipeline_name" -n > /dev/null 2>&1
    rm -f "$pipeline_file"
    
    print_success "Test completed!"
}

# Create compilation test pipeline
create_compilation_test_pipeline() {
    local task_name="$1"
    local version="$2"
    local output_file="$3"
    local minio_ip="$4"
    
    cat > "$output_file" << EOF
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
      endpoint: http://${minio_ip}:9000
      bucket: task-inputs
      regexp: ${task_name}-(.*).yaml
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
              printf("Testing compilation task!\\n");
              return 0;
          }

  - name: assignment-assets
    type: mock
    source:
      create_files:
        placeholder.txt: "placeholder"

jobs:
  - name: test-task
    plan:
      - in_parallel:
        - get: ghost
        - get: submission
        - get: assignment-assets
        - get: task-yaml

      - task: compile
        file: task-yaml/${task_name}-${version}.yaml
        vars:
          source_file: submission/hello.c
          output_binary: hello
          compiler_flags: "-Wall -Wextra -O2"
          language: c
          score: "10"
        params:
          GHOST_UPLOAD_CONFIG_ENDPOINT: http://${minio_ip}:9000
          GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_BUCKET: task-outputs

      - task: verify
        config:
          platform: linux
          image_resource:
            type: registry-image
            source: {repository: busybox}
          inputs:
            - name: compilation-output
              optional: true
          run:
            path: sh
            args:
              - -c
              - |
                echo "Checking compilation output..."
                if [ -f compilation-output/hello ]; then
                  echo "✅ Binary created successfully"
                  chmod +x compilation-output/hello
                  echo "Running binary:"
                  ./compilation-output/hello
                else
                  echo "❌ Binary not found"
                  exit 1
                fi
EOF
}

# Create execution test pipeline
create_execution_test_pipeline() {
    local task_name="$1"
    local version="$2"
    local output_file="$3"
    local minio_ip="$4"
    
    cat > "$output_file" << EOF
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
      endpoint: http://${minio_ip}:9000
      bucket: task-inputs
      regexp: ${task_name}-(.*).yaml
      access_key_id: minioadmin
      secret_access_key: minioadmin
      disable_ssl: true
      use_v2_signing: true

  - name: compilation-output
    type: mock
    source:
      create_files:
        program: |
          #!/bin/sh
          echo "Hello from test program!"
          echo "Input received:"
          cat

  - name: submission
    type: mock
    source:
      create_files:
        placeholder.txt: "placeholder for submission"

  - name: assignment-assets
    type: mock
    source:
      create_files:
        input.txt: |
          Test input line 1
          Test input line 2

jobs:
  - name: test-task
    plan:
      - in_parallel:
        - get: ghost
        - get: compilation-output
        - get: submission
        - get: assignment-assets
        - get: task-yaml

      - task: prepare-binary
        config:
          platform: linux
          image_resource:
            type: registry-image
            source: {repository: busybox}
          inputs:
            - name: compilation-output
          outputs:
            - name: compilation-output-fixed
          run:
            path: sh
            args:
              - -c
              - |
                cp -r compilation-output/* compilation-output-fixed/
                chmod +x compilation-output-fixed/program

      - task: execute
        file: task-yaml/${task_name}-${version}.yaml
        input_mapping:
          compilation-output: compilation-output-fixed
        vars:
          execution_binary: compilation-output/program
          execution_flags: ""
          input_path: assignment-assets/input.txt
          output_path: output.txt
          stderr_path: stderr.txt
          score: "10"
        params:
          GHOST_UPLOAD_CONFIG_ENDPOINT: http://${minio_ip}:9000
          GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_BUCKET: task-outputs

      - task: verify
        config:
          platform: linux
          image_resource:
            type: registry-image
            source: {repository: busybox}
          inputs:
            - name: execution-output
              optional: true
          run:
            path: sh
            args:
              - -c
              - |
                echo "Checking execution output..."
                if [ -f execution-output/output.txt ]; then
                  echo "✅ Output file created"
                  echo "Program output:"
                  cat execution-output/output.txt
                else
                  echo "❌ Output file not found"
                  exit 1
                fi
EOF
}

# Create testing test pipeline (for diff.yaml)
create_testing_test_pipeline() {
    local task_name="$1"
    local version="$2"
    local output_file="$3"
    local minio_ip="$4"
    
    cat > "$output_file" << EOF
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
      endpoint: http://${minio_ip}:9000
      bucket: task-inputs
      regexp: ${task_name}-(.*).yaml
      access_key_id: minioadmin
      secret_access_key: minioadmin
      disable_ssl: true
      use_v2_signing: true

  - name: execution-output
    type: mock
    source:
      create_files:
        output.txt: |
          Hello, World!
          Test output line 2

  - name: assignment-assets
    type: mock
    source:
      create_files:
        expected.txt: |
          Hello, World!
          Test output line 2

jobs:
  - name: test-task
    plan:
      - in_parallel:
        - get: ghost
        - get: execution-output
        - get: assignment-assets
        - get: task-yaml

      - task: test-diff
        file: task-yaml/${task_name}-${version}.yaml
        vars:
          input_path: execution-output/output.txt
          expected_path: assignment-assets/expected.txt
          output_path: result.txt
          stderr_path: stderr.txt
          diff_flags: ""
          score: "10"
        params:
          GHOST_UPLOAD_CONFIG_ENDPOINT: http://${minio_ip}:9000
          GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
          GHOST_UPLOAD_CONFIG_BUCKET: task-outputs

      - task: verify
        config:
          platform: linux
          image_resource:
            type: registry-image
            source: {repository: busybox}
          inputs:
            - name: testing-output
              optional: true
          run:
            path: sh
            args:
              - -c
              - |
                echo "Checking testing output..."
                if [ -f testing-output/result.txt ]; then
                  echo "✅ Test result created"
                  echo "Test result:"
                  cat testing-output/result.txt
                else
                  echo "❌ Test result not found"
                fi
EOF
}

# Test a toolkit task YAML with proper environment (OLD - kept for compatibility)
task_test() {
    # Redirect to new function
    test_task_yaml "$@"
}

# Deploy a pipeline
deploy_pipeline() {
    local pipeline_file="$1"
    local pipeline_name="${2:-test}"
    
    if [ -z "$pipeline_file" ]; then
        print_error "Usage: $0 pipeline <pipeline.yml> [pipeline-name]"
        exit 1
    fi
    
    if [ ! -f "$pipeline_file" ]; then
        print_error "Pipeline file not found: $pipeline_file"
        exit 1
    fi
    
    check_fly
    
    print_info "Deploying pipeline: $pipeline_name"
    
    $FLY_CMD -t dev set-pipeline -p "$pipeline_name" -c "$pipeline_file" -n
    $FLY_CMD -t dev unpause-pipeline -p "$pipeline_name"
    
    print_success "Pipeline deployed!"
    echo "  View at: http://localhost:8080/teams/main/pipelines/$pipeline_name"
}

# Run example pipeline
run_example() {
    local example_file="$SCRIPT_DIR/examples/simple-pipeline.yml"
    
    if [ ! -f "$example_file" ]; then
        print_error "Example pipeline not found. Creating one..."
        mkdir -p "$SCRIPT_DIR/examples"
        create_simple_example
    fi
    
    deploy_pipeline "$example_file" "example"
    
    print_info "Triggering example job..."
    $FLY_CMD -t dev trigger-job -j example/test --watch
}

# Create a simple example if it doesn't exist
create_simple_example() {
    cat > "$SCRIPT_DIR/examples/simple-pipeline.yml" << 'EOF'
# Simple example pipeline for testing
resources:
  - name: code
    type: mock
    source:
      create_files:
        main.c: |
          #include <stdio.h>
          int main() {
              printf("Hello from toolkit dev environment!\n");
              return 0;
          }

jobs:
  - name: test
    plan:
      - get: code
        trigger: true
      - task: compile-and-run
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: gcc
              tag: latest
          inputs:
            - name: code
          run:
            path: bash
            args:
              - -c
              - |
                echo "Compiling C code..."
                gcc code/main.c -o program
                echo "Running program..."
                ./program
                echo "Success!"
EOF
}

# Show help
show_help() {
    cat << EOF
Toolkit Development CLI

Usage: $0 <command> [options]

Commands:
  start      Start the development environment
  stop       Stop the development environment
  clean      Clean everything (containers, volumes, pipelines)
  status     Show environment status
  test       Test a task YAML with automatic MinIO upload
             Example: $0 test compilation/gcc.yaml
             Example: $0 test execution/stdio.yaml
             Example: $0 test testing/diff.yaml
  pipeline   Deploy a pipeline
             Example: $0 pipeline my-pipeline.yml my-pipeline
  example    Run a simple example pipeline
  help       Show this help message

Examples:
  $0 start                      # Start environment
  $0 test compilation/gcc.yaml  # Test gcc compilation task
  $0 test execution/stdio.yaml  # Test stdio execution task
  $0 test testing/diff.yaml     # Test diff testing task
  $0 status                     # Check status
  $0 clean                      # Clean everything

EOF
}

# Main command dispatcher
case "${1:-help}" in
    start)
        start_env
        ;;
    stop)
        stop_env
        ;;
    clean)
        clean_env
        ;;
    status)
        show_status
        ;;
    test)
        test_task_yaml "$2"
        ;;
    task-test)
        shift  # Remove the command
        test_task_yaml "$@"
        ;;
    pipeline|deploy)
        deploy_pipeline "$2" "$3"
        ;;
    example)
        run_example
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac