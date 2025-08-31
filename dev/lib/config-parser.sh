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

# Load preparation configuration
# Usage: load_preparation_config config.yaml
load_preparation_config() {
    local config_file="$1"
    
    # Check if preparation section exists and is not null
    local prep_section=$(yq eval '.preparation' "$config_file" 2>/dev/null)
    if [[ "$prep_section" == "null" ]] || [[ -z "$prep_section" ]]; then
        export TEST_HAS_PREPARE="false"
        return 0
    fi
    
    export TEST_HAS_PREPARE="true"
    export TEST_PREPARE_IMAGE_REPO=$(yq eval '.preparation.image.repository // "busybox"' "$config_file")
    export TEST_PREPARE_IMAGE_TAG=$(yq eval '.preparation.image.tag // "latest"' "$config_file")
    export TEST_PREPARE_SCRIPT=$(yq eval '.preparation.script // ""' "$config_file")
    
    # Get outputs as array - empty by default
    export TEST_PREPARE_OUTPUTS=$(yq eval '.preparation.outputs // []' "$config_file")
}

# Load verification configuration
# Usage: load_verification_config config.yaml
load_verification_config() {
    local config_file="$1"
    
    # Get verification inputs - default to compilation-output for backward compatibility
    export TEST_VERIFY_INPUTS=$(yq eval '.verification.inputs // ["compilation-output"]' "$config_file")
}

# Check if verification has custom inputs
# Usage: has_verify_inputs config.yaml
has_verify_inputs() {
    local config_file="$1"
    local inputs=$(yq eval '.verification.inputs' "$config_file" 2>/dev/null)
    if [[ "$inputs" == "null" ]] || [[ -z "$inputs" ]]; then
        return 1
    fi
    yq eval '.verification.inputs | length > 0' "$config_file" 2>/dev/null | grep -q "true"
}

# Generate verify inputs list for pipeline
# Usage: generate_verify_inputs config.yaml output_file
generate_verify_inputs() {
    local config_file="$1"
    local output_file="$2"
    
    echo "          inputs:" >> "$output_file"
    if has_verify_inputs "$config_file"; then
        yq eval '.verification.inputs[] | "            - name: " + .' "$config_file" >> "$output_file"
    else
        # Default inputs for backward compatibility
        echo "            - name: compilation-output" >> "$output_file"
    fi
}

# Check if preparation has outputs
# Usage: has_prepare_outputs config.yaml
has_prepare_outputs() {
    local config_file="$1"
    local outputs=$(yq eval '.preparation.outputs' "$config_file" 2>/dev/null)
    if [[ "$outputs" == "null" ]] || [[ -z "$outputs" ]]; then
        return 1
    fi
    yq eval '.preparation.outputs | length > 0' "$config_file" 2>/dev/null | grep -q "true"
}

# Generate prepare outputs list for pipeline
# Usage: generate_prepare_outputs config.yaml output_file
generate_prepare_outputs() {
    local config_file="$1"
    local output_file="$2"
    
    if ! has_prepare_outputs "$config_file"; then
        return 0
    fi
    
    echo "          outputs:" >> "$output_file"
    yq eval '.preparation.outputs[] | "            - name: " + .' "$config_file" >> "$output_file"
}