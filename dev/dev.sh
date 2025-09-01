#!/bin/bash

# Toolkit Development CLI - Configuration-Driven Language Testing
# Clean, robust, language-agnostic testing with yq-based YAML parsing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLY_CMD="$SCRIPT_DIR/bin/fly"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Source the configuration parser
source "$SCRIPT_DIR/lib/config-parser.sh"

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

# Check dependencies
check_dependencies() {
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed. Please install yq first:"
        echo "  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O yq"
        echo "  chmod +x yq && sudo mv yq /usr/local/bin/yq"
        exit 1
    fi
    
    # Check if Docker is running
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
    
    # Create buckets using MinIO client via Docker
    docker run --rm --network toolkit-dev-network --entrypoint sh \
        minio/mc:latest -c \
        "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
         mc mb --ignore-existing minio/task-outputs && \
         mc mb --ignore-existing minio/task-inputs" 2>/dev/null || true
    
    print_success "MinIO buckets initialized"
}

# Start development environment
start_env() {
    check_dependencies
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

# Create a test pipeline from yq-parsed configuration
create_test_pipeline_from_config() {
    local task_name="$1"
    local version="$2"
    local output_file="$3"
    local minio_ip="$4"
    local config_file="$5"
    local variant="$6"
    
    # If variant is specified, merge it with base configuration
    local config_to_use="$config_file"
    if [[ -n "$variant" ]]; then
        # Create a temporary merged configuration
        local merged_config=$(mktemp --suffix=.yaml)
        if ! merge_variant_with_base "$config_file" "$variant" > "$merged_config"; then
            print_error "Failed to merge variant '$variant'"
            rm -f "$merged_config"
            return 1
        fi
        config_to_use="$merged_config"
    fi
    
    # Load and validate the configuration (now potentially merged with variant)
    if ! validate_config "$config_to_use"; then
        [[ -n "$variant" ]] && rm -f "$config_to_use"
        return 1
    fi
    
    load_test_config "$config_to_use"
    
    print_info "Using test configuration: $TEST_CONFIG_NAME"
    [[ -n "$TEST_CONFIG_DESCRIPTION" ]] && print_info "Description: $TEST_CONFIG_DESCRIPTION"
    [[ -n "$variant" ]] && print_info "Using variant: $variant"
    
    # Start building the pipeline
    cat > "$output_file" << EOF
# Generated from: $config_file
# Configuration: $TEST_CONFIG_NAME
# $TEST_CONFIG_DESCRIPTION

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
EOF
    
    # Add directories if they exist
    generate_mock_directories "$config_to_use" "submission" "$output_file"
    
    # Add submission files
    echo "      create_files:" >> "$output_file"
    generate_mock_submission "$config_to_use" "$output_file"
    
    # Add assignment assets
    cat >> "$output_file" << EOF

  - name: assignment-assets
    type: mock
    source:
EOF
    
    generate_mock_directories "$config_to_use" "assignment_assets" "$output_file"
    echo "      create_files:" >> "$output_file"
    generate_mock_assets "$config_to_use" "$output_file"
    
    # Add job definition
    cat >> "$output_file" << EOF

jobs:
  - name: test-task
    plan:
      - in_parallel:
        - get: ghost
        - get: submission
        - get: assignment-assets
        - get: task-yaml
EOF
    
    # Check if prepare step is needed
    load_preparation_config "$config_to_use"
    
    if [[ "$TEST_HAS_PREPARE" == "true" ]]; then
        cat >> "$output_file" << EOF

      - task: prepare
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: $TEST_PREPARE_IMAGE_REPO
              tag: $TEST_PREPARE_IMAGE_TAG
          inputs:
            - name: submission
            - name: assignment-assets
EOF
        
        # Add outputs if defined
        generate_prepare_outputs "$config_to_use" "$output_file"
        
        cat >> "$output_file" << EOF
          run:
            path: sh
            args:
              - -c
              - |
EOF
        
        # Add preparation script
        if [[ -n "$TEST_PREPARE_SCRIPT" ]]; then
            echo "$TEST_PREPARE_SCRIPT" | sed 's/^/                /' >> "$output_file"
        else
            echo "                echo 'Empty prepare step'" >> "$output_file"
        fi
    fi
    
    cat >> "$output_file" << EOF

      - task: run-task
        file: task-yaml/${task_name}-${version}.yaml
        vars:
EOF
    
    # Add task parameters (now from potentially merged config)
    generate_task_parameters "$config_to_use" "$output_file"
    
    # Add ghost configuration
    cat >> "$output_file" << EOF
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
            source:
              repository: $TEST_VERIFY_IMAGE_REPO
              tag: $TEST_VERIFY_IMAGE_TAG
EOF
    
    # Generate verification inputs
    generate_verify_inputs "$config_to_use" "$output_file"
    
    cat >> "$output_file" << EOF
          run:
            path: sh
            args:
              - -c
              - |
EOF
    
    # Add verification script
    if [[ -n "$TEST_VERIFY_SCRIPT" ]]; then
        # Indent the script properly
        echo "$TEST_VERIFY_SCRIPT" | sed 's/^/                /' >> "$output_file"
    elif [[ -n "$TEST_VERIFY_SCRIPT_FILE" ]] && [[ -f "$TEST_VERIFY_SCRIPT_FILE" ]]; then
        # Load external script file
        sed 's/^/                /' "$TEST_VERIFY_SCRIPT_FILE" >> "$output_file"
    else
        cat >> "$output_file" << 'EOF'
                echo "No verification script provided"
                echo "Contents of compilation-output:"
                ls -la compilation-output/ 2>/dev/null || echo "No output directory"
EOF
    fi
    
    # Clean up temporary merged config if created
    if [[ -n "$variant" ]] && [[ "$config_to_use" != "$config_file" ]]; then
        rm -f "$config_to_use"
    fi
}

# Test a task file with configuration-driven approach
test_task_yaml() {
    local task_path="$1"
    local config_path="$2"
    local variant="$3"
    local show_summary="$4"
    
    if [ -z "$task_path" ]; then
        print_error "Usage: $0 test <task-path> [--config <config-file>] [--variant <variant>] [--summary]"
        echo ""
        echo "Examples:"
        echo "  $0 test compilation/gcc.yaml"
        echo "  $0 test compilation/java.yaml --variant classes-only"
        echo "  $0 test compilation/python.yaml --config my-custom.yaml"
        echo "  $0 test compilation/gcc.yaml --summary"
        exit 1
    fi
    
    # Check if task file exists
    local full_path="../$task_path"
    if [ ! -f "$full_path" ]; then
        print_error "Task file not found: $full_path"
        exit 1
    fi
    
    check_dependencies
    check_fly
    
    # Find or use provided config
    if [ -z "$config_path" ]; then
        config_path=$(find_test_config "$task_path")
        if [ $? -ne 0 ]; then
            print_error "No test configuration found for $task_path"
            print_info "Create a configuration at: test-configs/$task_path"
            echo ""
            echo "Quick template:"
            cat << 'EOF'
---
name: My Task Test
mock_resources:
  submission:
    files:
      main.ext: |
        # Your test code here
task_parameters:
  param1: value1
  param2: value2
verification:
  image:
    repository: appropriate-image
  script: |
    echo "Verification commands here"
EOF
            exit 1
        fi
    fi
    
    # Show configuration summary if requested
    if [[ "$show_summary" == "true" ]]; then
        show_config_summary "$config_path"
        echo ""
        return 0
    fi
    
    # Validate variant if provided
    if [[ -n "$variant" ]]; then
        if ! get_variant_config "$config_path" "$variant" > /dev/null; then
            print_error "Variant '$variant' not found in configuration"
            echo "Available variants:"
            list_variants "$config_path" | sed 's/^/  - /'
            exit 1
        fi
    fi
    
    # Extract task type and name
    local task_type=$(echo "$task_path" | cut -d'/' -f1)
    local task_name=$(basename "$task_path" .yaml)
    local pipeline_name="${task_name}-test"
    [[ -n "$variant" ]] && pipeline_name="${task_name}-${variant}-test"
    
    print_info "Testing $task_type task: $task_name"
    print_info "Using configuration: $config_path"
    
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
    
    # Create test pipeline from configuration
    local pipeline_file="$SCRIPT_DIR/.test-${task_name}${variant:+-$variant}.yml"
    create_test_pipeline_from_config "$task_name" "$version" "$pipeline_file" "$minio_ip" "$config_path" "$variant"
    
    # Deploy pipeline
    print_info "Deploying test pipeline..."
    $FLY_CMD -t dev set-pipeline -p "$pipeline_name" -c "$pipeline_file" -n > /dev/null 2>&1
    
    # Unpause the pipeline
    $FLY_CMD -t dev unpause-pipeline -p "$pipeline_name" > /dev/null 2>&1
    
    # Trigger job
    print_info "Running test..."
    $FLY_CMD -t dev trigger-job -j "$pipeline_name/test-task" --watch
    
    # Check results in MinIO
    print_info "Checking results in MinIO..."
    docker run --rm --network toolkit-dev-network \
        --entrypoint sh minio/mc:latest -c \
        "mc alias set minio http://${minio_ip}:9000 minioadmin minioadmin && \
         echo '📦 Files in task-outputs:' && \
         mc ls minio/task-outputs/ 2>/dev/null || echo 'No files in task-outputs'"
    
    # Cleanup
    print_info "Cleaning up..."
    $FLY_CMD -t dev destroy-pipeline -p "$pipeline_name" -n > /dev/null 2>&1
    rm -f "$pipeline_file"
    
    print_success "Test completed!"
}

# Show help
show_help() {
    cat << EOF
Toolkit Development CLI - Configuration-Driven Language Testing

Usage: $0 <command> [options]

Commands:
  start      Start the development environment
  stop       Stop the development environment  
  clean      Clean everything (containers, volumes, pipelines)
  test       Test a task with configuration-driven setup
  help       Show this help message

Test Command Options:
  --config FILE    Use specific configuration file
  --variant NAME   Use specific test variant
  --summary        Show configuration summary without running test

Examples:
  $0 start                                    # Start environment
  $0 test compilation/gcc.yaml                # Auto-discover config
  $0 test compilation/java.yaml --variant classes-only
  $0 test compilation/python.yaml --config custom.yaml
  $0 test compilation/gcc.yaml --summary      # Show config info only

Adding New Language Support:
  1. Create task file: compilation/newlang.yaml
  2. Create test config: test-configs/compilation/newlang.test.yaml  
  3. Run: $0 test compilation/newlang.yaml
  ✨ No code changes to this script needed!

Configuration Features:
  ✅ Automatic config discovery
  ✅ Test variants for different scenarios
  ✅ Mock resource generation
  ✅ Flexible verification scripts
  ✅ YAML validation with helpful errors

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
    test)
        shift
        config_path=""
        task_path=""
        variant=""
        show_summary="false"
        
        # Parse arguments
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --config|-c)
                    config_path="$2"
                    shift 2
                    ;;
                --variant|-v)
                    variant="$2"
                    shift 2
                    ;;
                --summary|-s)
                    show_summary="true"
                    shift
                    ;;
                *)
                    task_path="$1"
                    shift
                    ;;
            esac
        done
        
        test_task_yaml "$task_path" "$config_path" "$variant" "$show_summary"
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