#!/bin/bash

# Configuration Parser Library using yq
# Much cleaner and more reliable YAML parsing

# Load a test configuration file and set variables
# Usage: load_test_config config.yaml
load_test_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Test configuration file not found: $config_file" >&2
        return 1
    fi
    
    # Validate YAML syntax first
    if ! yq eval '.' "$config_file" > /dev/null 2>&1; then
        echo "Error: Invalid YAML in configuration file: $config_file" >&2
        return 1
    fi
    
    # Export basic configuration
    export TEST_CONFIG_NAME=$(yq eval '.name // ""' "$config_file")
    export TEST_CONFIG_DESCRIPTION=$(yq eval '.description // ""' "$config_file")
    
    # Load verification settings
    export TEST_VERIFY_IMAGE_REPO=$(yq eval '.verification.image.repository // "busybox"' "$config_file")
    export TEST_VERIFY_IMAGE_TAG=$(yq eval '.verification.image.tag // "latest"' "$config_file")
    export TEST_VERIFY_SCRIPT=$(yq eval '.verification.script // ""' "$config_file")
    export TEST_VERIFY_SCRIPT_FILE=$(yq eval '.verification.script_file // ""' "$config_file")
    
    # Store config file path for later use
    export TEST_CONFIG_FILE="$config_file"
    
    return 0
}

# Generate mock resource files for pipeline
# Usage: generate_mock_submission config.yaml output_file
generate_mock_submission() {
    local config_file="$1"
    local output_file="$2"
    
    # Check if submission files exist
    if ! yq eval '.mock_resources.submission.files' "$config_file" > /dev/null 2>&1; then
        echo "        placeholder.txt: \"No submission files defined\"" >> "$output_file"
        return 0
    fi
    
    # Generate files section
    yq eval '.mock_resources.submission.files | to_entries | .[] | "        " + .key + ": |" + "\n" + (.value | split("\n") | map("          " + .) | join("\n"))' "$config_file" >> "$output_file"
}

# Generate mock assignment assets for pipeline
# Usage: generate_mock_assets config.yaml output_file
generate_mock_assets() {
    local config_file="$1"
    local output_file="$2"
    
    # Check if asset files exist
    if ! yq eval '.mock_resources.assignment_assets.files' "$config_file" > /dev/null 2>&1; then
        echo "        placeholder.txt: \"placeholder\"" >> "$output_file"
        return 0
    fi
    
    # Generate files section
    yq eval '.mock_resources.assignment_assets.files | to_entries | .[] | "        " + .key + ": |" + "\n" + (.value | split("\n") | map("          " + .) | join("\n"))' "$config_file" >> "$output_file"
}

# Generate task parameters section
# Usage: generate_task_parameters config.yaml output_file
generate_task_parameters() {
    local config_file="$1"
    local output_file="$2"
    
    # Check if parameters exist
    if ! yq eval '.task_parameters' "$config_file" > /dev/null 2>&1; then
        echo "          # No parameters defined" >> "$output_file"
        return 0
    fi
    
    # Generate parameters section with proper YAML formatting
    yq eval '.task_parameters | to_entries | .[] | "          " + .key + ": " + (.value | @json)' "$config_file" >> "$output_file"
}

# Generate directories if specified
# Usage: generate_mock_directories config.yaml resource_type output_file
generate_mock_directories() {
    local config_file="$1"
    local resource_type="$2"  # "submission" or "assignment_assets"
    local output_file="$3"
    
    # Note: Mock resource type doesn't support create_directories
    # Directories are automatically created when files with paths are specified
    # This function is kept for backward compatibility but does nothing
    return 0
}

# Get parameter value with default
# Usage: get_parameter config.yaml "parameter_name" "default_value"
get_parameter() {
    local config_file="$1"
    local param_name="$2"
    local default_value="${3:-}"
    
    yq eval ".task_parameters.${param_name} // \"${default_value}\"" "$config_file"
}

# Get mock file content
# Usage: get_mock_file_content config.yaml "resource_type" "filename"
get_mock_file_content() {
    local config_file="$1"
    local resource_type="$2"  # "submission" or "assignment_assets"
    local filename="$3"
    
    yq eval ".mock_resources.${resource_type}.files.\"${filename}\" // \"\"" "$config_file"
}

# List all mock files
# Usage: list_mock_files config.yaml "resource_type"
list_mock_files() {
    local config_file="$1"
    local resource_type="$2"
    
    yq eval ".mock_resources.${resource_type}.files | keys | .[]" "$config_file" 2>/dev/null
}

# Get variant configuration
# Usage: get_variant_config config.yaml "variant_name"
get_variant_config() {
    local config_file="$1"
    local variant_name="$2"
    
    yq eval ".variants[] | select(.name == \"${variant_name}\")" "$config_file" 2>/dev/null
}

# List all available variants
# Usage: list_variants config.yaml
list_variants() {
    local config_file="$1"
    
    yq eval '.variants[]?.name' "$config_file" 2>/dev/null
}

# Check if configuration has variants
# Usage: has_variants config.yaml
has_variants() {
    local config_file="$1"
    
    yq eval '.variants | length > 0' "$config_file" 2>/dev/null
}

# Find test configuration for a task
# Usage: find_test_config "compilation/gcc.yaml"
find_test_config() {
    local task_path="$1"
    local config_dir="${2:-test-configs}"
    
    # Remove .yaml extension and construct config path
    local base_path="${task_path%.yaml}"
    local config_path="${config_dir}/${base_path}.test.yaml"
    
    if [[ -f "$config_path" ]]; then
        echo "$config_path"
        return 0
    fi
    
    # Try without directory structure
    local task_name=$(basename "$base_path")
    config_path="${config_dir}/${task_name}.test.yaml"
    
    if [[ -f "$config_path" ]]; then
        echo "$config_path"
        return 0
    fi
    
    return 1
}

# Validate configuration against schema
# Usage: validate_config config.yaml [schema.yaml]
validate_config() {
    local config_file="$1"
    local schema_file="${2:-test-config.schema.yaml}"
    
    # Basic YAML validation
    if ! yq eval '.' "$config_file" > /dev/null 2>&1; then
        echo "Invalid YAML syntax in $config_file" >&2
        return 1
    fi
    
    # Check required fields
    local required_fields=("name" "mock_resources" "task_parameters" "verification")
    
    for field in "${required_fields[@]}"; do
        if ! yq eval "has(\"$field\")" "$config_file" | grep -q "true"; then
            echo "Missing required field: $field in $config_file" >&2
            return 1
        fi
    done
    
    # Check verification has required fields
    if ! yq eval '.verification.image.repository != null' "$config_file" | grep -q "true"; then
        echo "Missing required field: verification.image.repository in $config_file" >&2
        return 1
    fi
    
    if ! yq eval '.verification.script != null or .verification.script_file != null' "$config_file" | grep -q "true"; then
        echo "Missing verification script: need either verification.script or verification.script_file in $config_file" >&2
        return 1
    fi
    
    return 0
}

# Pretty print configuration summary
# Usage: show_config_summary config.yaml
show_config_summary() {
    local config_file="$1"
    
    echo "Configuration Summary:"
    echo "====================="
    echo "Name: $(yq eval '.name' "$config_file")"
    echo "Description: $(yq eval '.description // "No description"' "$config_file")"
    echo ""
    
    echo "Mock Submission Files:"
    list_mock_files "$config_file" "submission" | sed 's/^/  - /'
    echo ""
    
    echo "Task Parameters:"
    yq eval '.task_parameters | to_entries | .[] | "  " + .key + ": " + (.value | @json)' "$config_file"
    echo ""
    
    echo "Verification Image: $(yq eval '.verification.image.repository' "$config_file"):$(yq eval '.verification.image.tag // "latest"' "$config_file")"
    
    if has_variants "$config_file" | grep -q "true"; then
        echo ""
        echo "Available Variants:"
        list_variants "$config_file" | sed 's/^/  - /'
    fi
}