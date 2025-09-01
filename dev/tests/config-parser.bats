#!/usr/bin/env bats

# Test suite for lib/config-parser.sh

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Setup function runs before each test
setup() {
    # Source the library being tested
    source "${BATS_TEST_DIRNAME}/../lib/config-parser.sh"
    
    # Create temp directory for test files
    export TEST_TEMP_DIR=$(mktemp -d)
    
    # Set fixtures directory
    export FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
}

# Teardown function runs after each test
teardown() {
    # Clean up temp files
    rm -rf "$TEST_TEMP_DIR"
}

# ============================================================================
# Tests for load_test_config
# ============================================================================

@test "load_test_config: loads valid configuration successfully" {
    # Don't use 'run' here since we need the exported variables
    load_test_config "${FIXTURES_DIR}/valid-config.yaml"
    
    # Check that variables were set
    [ "$TEST_CONFIG_NAME" = "Test Configuration" ]
    [ "$TEST_CONFIG_DESCRIPTION" = "A valid test configuration for testing" ]
    [ "$TEST_VERIFY_IMAGE_REPO" = "busybox" ]
    [ "$TEST_VERIFY_IMAGE_TAG" = "latest" ]
}

@test "load_test_config: fails on missing file" {
    run load_test_config "/nonexistent/file.yaml"
    assert_failure
    assert_output --partial "Error: Test configuration file not found"
}

@test "load_test_config: fails on invalid YAML syntax" {
    run load_test_config "${FIXTURES_DIR}/invalid-yaml.yaml"
    assert_failure
    assert_output --partial "Error: Invalid YAML"
}

# ============================================================================
# Tests for validate_config
# ============================================================================

@test "validate_config: accepts valid configuration" {
    run validate_config "${FIXTURES_DIR}/valid-config.yaml"
    assert_success
}

@test "validate_config: detects missing required fields" {
    run validate_config "${FIXTURES_DIR}/missing-fields.yaml"
    assert_failure
    assert_output --partial "Missing required field"
}

@test "validate_config: detects invalid YAML syntax" {
    run validate_config "${FIXTURES_DIR}/invalid-yaml.yaml"
    assert_failure
    assert_output --partial "Invalid YAML syntax"
}

@test "validate_config: requires verification.image.repository" {
    cat > "$TEST_TEMP_DIR/no-verify-image.yaml" <<EOF
name: Test
mock_resources:
  submission:
    files:
      test.py: "print('test')"
task_parameters:
  param: value
verification:
  script: "echo test"
EOF
    
    run validate_config "$TEST_TEMP_DIR/no-verify-image.yaml"
    assert_failure
    assert_output --partial "verification.image.repository"
}

@test "validate_config: requires verification script or script_file" {
    cat > "$TEST_TEMP_DIR/no-verify-script.yaml" <<EOF
name: Test
mock_resources:
  submission:
    files:
      test.py: "print('test')"
task_parameters:
  param: value
verification:
  image:
    repository: busybox
EOF
    
    run validate_config "$TEST_TEMP_DIR/no-verify-script.yaml"
    assert_failure
    assert_output --partial "Missing verification script"
}

# ============================================================================
# Tests for get_parameter
# ============================================================================

@test "get_parameter: returns existing parameter value" {
    result=$(get_parameter "${FIXTURES_DIR}/valid-config.yaml" "source_file" "default")
    assert_equal "$result" "submission/main.c"
}

@test "get_parameter: returns default for missing parameter" {
    result=$(get_parameter "${FIXTURES_DIR}/valid-config.yaml" "nonexistent" "my_default")
    assert_equal "$result" "my_default"
}

@test "get_parameter: handles empty default value" {
    result=$(get_parameter "${FIXTURES_DIR}/valid-config.yaml" "nonexistent")
    assert_equal "$result" ""
}

# ============================================================================
# Tests for mock file functions
# ============================================================================

@test "list_mock_files: lists submission files correctly" {
    run list_mock_files "${FIXTURES_DIR}/valid-config.yaml" "submission"
    assert_success
    assert_line "main.c"
    assert_line "helper.c"
}

@test "list_mock_files: lists assignment_assets files correctly" {
    run list_mock_files "${FIXTURES_DIR}/valid-config.yaml" "assignment_assets"
    assert_success
    assert_line "input.txt"
    assert_line "expected.txt"
}

@test "list_mock_files: returns empty for no files" {
    run list_mock_files "${FIXTURES_DIR}/empty-files.yaml" "submission"
    assert_output ""
}

@test "get_mock_file_content: retrieves file content" {
    content=$(get_mock_file_content "${FIXTURES_DIR}/valid-config.yaml" "assignment_assets" "input.txt")
    assert_equal "$content" "test input"
}

@test "get_mock_file_content: returns empty for nonexistent file" {
    content=$(get_mock_file_content "${FIXTURES_DIR}/valid-config.yaml" "submission" "nonexistent.txt")
    assert_equal "$content" ""
}

# ============================================================================
# Tests for variant functions
# ============================================================================

@test "has_variants: detects configurations with variants" {
    result=$(has_variants "${FIXTURES_DIR}/with-variants.yaml")
    assert_equal "$result" "true"
}

@test "has_variants: returns false for no variants" {
    result=$(has_variants "${FIXTURES_DIR}/valid-config.yaml")
    [ -z "$result" ] || [ "$result" = "false" ]
}

@test "list_variants: lists all variant names" {
    run list_variants "${FIXTURES_DIR}/with-variants.yaml"
    assert_success
    assert_line "debug-mode"
    assert_line "optimized"
    assert_line "custom-verification"
}

@test "list_variants: returns empty for no variants" {
    run list_variants "${FIXTURES_DIR}/valid-config.yaml"
    assert_output ""
}

@test "get_variant_config: retrieves specific variant" {
    result=$(get_variant_config "${FIXTURES_DIR}/with-variants.yaml" "debug-mode")
    echo "$result" | grep -q "debug-mode"
    echo "$result" | grep -q "Run with debug flags"
}

@test "get_variant_config: returns empty for nonexistent variant" {
    result=$(get_variant_config "${FIXTURES_DIR}/with-variants.yaml" "nonexistent")
    assert_equal "$result" ""
}

# ============================================================================
# Tests for preparation functions
# ============================================================================

@test "load_preparation_config: loads prepare configuration" {
    load_preparation_config "${FIXTURES_DIR}/with-prepare.yaml"
    
    assert_equal "$TEST_HAS_PREPARE" "true"
    assert_equal "$TEST_PREPARE_IMAGE_REPO" "openjdk"
    assert_equal "$TEST_PREPARE_IMAGE_TAG" "11-jdk"
    [ -n "$TEST_PREPARE_SCRIPT" ]
}

@test "load_preparation_config: sets false when no preparation" {
    load_preparation_config "${FIXTURES_DIR}/valid-config.yaml"
    
    assert_equal "$TEST_HAS_PREPARE" "false"
}

@test "has_prepare_outputs: detects prepare outputs" {
    run has_prepare_outputs "${FIXTURES_DIR}/with-prepare.yaml"
    assert_success
}

@test "has_prepare_outputs: returns false for no outputs" {
    run has_prepare_outputs "${FIXTURES_DIR}/valid-config.yaml"
    assert_failure
}

# ============================================================================
# Tests for verification functions
# ============================================================================

@test "has_verify_inputs: detects custom verification inputs" {
    run has_verify_inputs "${FIXTURES_DIR}/with-prepare.yaml"
    assert_success
}

@test "has_verify_inputs: returns false for default inputs" {
    run has_verify_inputs "${FIXTURES_DIR}/valid-config.yaml"
    assert_failure
}

# ============================================================================
# Tests for find_test_config
# ============================================================================

@test "find_test_config: finds matching test configuration" {
    # Create a mock test-configs directory structure
    mkdir -p "$TEST_TEMP_DIR/test-configs/compilation"
    cp "${FIXTURES_DIR}/valid-config.yaml" "$TEST_TEMP_DIR/test-configs/compilation/gcc.test.yaml"
    
    result=$(find_test_config "compilation/gcc.yaml" "$TEST_TEMP_DIR/test-configs")
    assert_equal "$result" "$TEST_TEMP_DIR/test-configs/compilation/gcc.test.yaml"
}

@test "find_test_config: returns error for missing config" {
    run find_test_config "nonexistent/task.yaml" "$TEST_TEMP_DIR/test-configs"
    assert_failure
}

# ============================================================================
# Tests for variant merging (CRITICAL - catches the Python issue!)
# ============================================================================

@test "variant merging: should override task parameters" {
    # This test catches if variants properly override base config
    merged_config=$(merge_variant_with_base "${FIXTURES_DIR}/variant-override.yaml" "override-params")
    
    # Check that variant parameter overrides base
    param1=$(echo "$merged_config" | yq eval '.task_parameters.param1' -)
    assert_equal "$param1" "variant_value"
    
    # Check that non-overridden parameter remains
    param2=$(echo "$merged_config" | yq eval '.task_parameters.param2' -)
    assert_equal "$param2" "unchanged"
    
    # Check that new parameter from variant is added
    param3=$(echo "$merged_config" | yq eval '.task_parameters.param3' -)
    assert_equal "$param3" "new_param"
}

@test "variant merging: should override verification script" {
    # This is THE test that would have caught the Python variant issue!
    merged_config=$(merge_variant_with_base "${FIXTURES_DIR}/variant-override.yaml" "override-verification")
    
    # Check that verification script is overridden
    verify_script=$(echo "$merged_config" | yq eval '.verification.script' -)
    echo "$verify_script" | grep -q "Variant verification script"
    
    # Check that image repository remains from base (not overridden)
    image_repo=$(echo "$merged_config" | yq eval '.verification.image.repository' -)
    assert_equal "$image_repo" "python"
}

@test "variant merging: should handle deep merge correctly" {
    # Should merge variant over base, keeping non-overridden values
    merged_config=$(merge_variant_with_base "${FIXTURES_DIR}/variant-override.yaml" "override-both")
    
    # Check that variant parameter overrides
    param1=$(echo "$merged_config" | yq eval '.task_parameters.param1' -)
    assert_equal "$param1" "both_variant_value"
    
    # Check that non-overridden parameter remains
    param2=$(echo "$merged_config" | yq eval '.task_parameters.param2' -)
    assert_equal "$param2" "unchanged"
    
    # Check that verification is fully overridden
    image_repo=$(echo "$merged_config" | yq eval '.verification.image.repository' -)
    assert_equal "$image_repo" "alpine"
    
    verify_script=$(echo "$merged_config" | yq eval '.verification.script' -)
    echo "$verify_script" | grep -q "Both overridden"
}

@test "variant merging: fails with nonexistent variant" {
    run merge_variant_with_base "${FIXTURES_DIR}/variant-override.yaml" "nonexistent"
    assert_failure
    assert_output --partial "Variant 'nonexistent' not found"
}

@test "variant merging: fails with missing file" {
    run merge_variant_with_base "/nonexistent/file.yaml" "some-variant"
    assert_failure
    assert_output --partial "Configuration file not found"
}

# ============================================================================
# Tests for show_config_summary
# ============================================================================

@test "show_config_summary: displays configuration summary" {
    run show_config_summary "${FIXTURES_DIR}/valid-config.yaml"
    assert_success
    assert_output --partial "Name: Test Configuration"
    assert_output --partial "Mock Submission Files:"
    assert_output --partial "Task Parameters:"
    assert_output --partial "Verification Image:"
}

@test "show_config_summary: shows variants when present" {
    run show_config_summary "${FIXTURES_DIR}/with-variants.yaml"
    assert_success
    assert_output --partial "Available Variants:"
    assert_output --partial "debug-mode"
}

# ============================================================================
# Tests for generate functions (mock resources)
# ============================================================================

@test "generate_mock_submission: generates submission files" {
    echo "  submission:" > "$TEST_TEMP_DIR/output.yaml"
    echo "    type: mock" >> "$TEST_TEMP_DIR/output.yaml"
    echo "    source:" >> "$TEST_TEMP_DIR/output.yaml"
    echo "      create_files:" >> "$TEST_TEMP_DIR/output.yaml"
    
    generate_mock_submission "${FIXTURES_DIR}/valid-config.yaml" "$TEST_TEMP_DIR/output.yaml"
    
    grep -q "main.c:" "$TEST_TEMP_DIR/output.yaml"
    grep -q "helper.c:" "$TEST_TEMP_DIR/output.yaml"
}

@test "generate_mock_submission: handles empty files" {
    echo "" > "$TEST_TEMP_DIR/output.yaml"
    
    generate_mock_submission "${FIXTURES_DIR}/empty-files.yaml" "$TEST_TEMP_DIR/output.yaml"
    
    # Current behavior: when files section exists but is empty, nothing is generated
    # This may need to be fixed in the function to add a placeholder
    # For now, test the actual behavior
    [ $(wc -l < "$TEST_TEMP_DIR/output.yaml") -eq 1 ]  # Only the initial empty line
}

@test "generate_task_parameters: generates parameters section" {
    echo "" > "$TEST_TEMP_DIR/output.yaml"
    
    generate_task_parameters "${FIXTURES_DIR}/valid-config.yaml" "$TEST_TEMP_DIR/output.yaml"
    
    grep -q "source_file:" "$TEST_TEMP_DIR/output.yaml"
    grep -q "compiler_flags:" "$TEST_TEMP_DIR/output.yaml"
}

@test "generate_prepare_outputs: generates prepare outputs list" {
    echo "" > "$TEST_TEMP_DIR/output.yaml"
    
    generate_prepare_outputs "${FIXTURES_DIR}/with-prepare.yaml" "$TEST_TEMP_DIR/output.yaml"
    
    grep -q "outputs:" "$TEST_TEMP_DIR/output.yaml"
    grep -q "compilation-output" "$TEST_TEMP_DIR/output.yaml"
    grep -q "test-resources" "$TEST_TEMP_DIR/output.yaml"
}

@test "generate_verify_inputs: generates custom verification inputs" {
    echo "" > "$TEST_TEMP_DIR/output.yaml"
    
    generate_verify_inputs "${FIXTURES_DIR}/with-prepare.yaml" "$TEST_TEMP_DIR/output.yaml"
    
    grep -q "inputs:" "$TEST_TEMP_DIR/output.yaml"
    grep -q "compilation-output" "$TEST_TEMP_DIR/output.yaml"
    grep -q "test-resources" "$TEST_TEMP_DIR/output.yaml"
}

@test "generate_verify_inputs: uses default for configs without inputs" {
    echo "" > "$TEST_TEMP_DIR/output.yaml"
    
    generate_verify_inputs "${FIXTURES_DIR}/valid-config.yaml" "$TEST_TEMP_DIR/output.yaml"
    
    grep -q "inputs:" "$TEST_TEMP_DIR/output.yaml"
    grep -q "compilation-output" "$TEST_TEMP_DIR/output.yaml"
}