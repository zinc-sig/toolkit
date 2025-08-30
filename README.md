# Zinc-Sig Toolkit

A collection of reusable Concourse CI task templates for automated code grading in the zinc-sig grading system.

## Overview

The toolkit provides standardized Concourse CI task definitions that are used by the zinc-sig core grading system to compile, execute, and test student submissions. These tasks run in isolated Docker containers as part of automated grading pipelines.

## Architecture

This toolkit is part of the larger zinc-sig grading ecosystem:

```
+-------------------+     +----------------+     +---------------+
|   Core System     | --> | Concourse CI   | --> |   Toolkit     |
| (Pipeline Gen)    |     |  (Executor)    |     |   (Tasks)     |
+-------------------+     +----------------+     +---------------+
```

- **Core System**: Generates Concourse pipelines from grading configurations
- **Concourse CI**: Executes the pipelines with proper isolation
- **Toolkit**: Provides reusable task templates referenced by pipelines

## Task Categories

### Compilation (`/compilation`)
Tasks for compiling source code into executables:
- `gcc.yaml`: C/C++ compilation using GCC/G++

### Execution (`/execution`)
Tasks for running programs with various runtime environments:
- `stdio.yaml`: Execute binaries with standard I/O redirection
- `python.yaml`: Python script execution
- `python-nvidia.yaml`: Python with NVIDIA GPU support
- `java.yaml`: Java program execution
- `valgrind.yaml`: Memory debugging with Valgrind
- `pylint.yaml`: Python code linting

### Testing (`/testing`)
Tasks for validating outputs and generating results:
- `diff.yaml`: File comparison with scoring support
- `gtest.yaml`: Google Test framework for C++
- `junit.yaml`: JUnit testing for Java
- `pytest.yaml`: Python testing framework

## Integration with Ghost

All compilation and execution tasks use [ghost](https://github.com/zinc-sig/ghost), a command runner that captures execution metadata in structured JSON format. Ghost provides:
- Standardized I/O redirection
- Execution timing and timeout handling
- Exit code capture
- JSON output for result processing

## How Tasks Are Used

The core grading system references these tasks in pipeline configurations:

```hcl
stage "compilation" {
  uses "toolkit/compilation/gcc" {
    options = {
      source_file    = "main.c"
      output_binary  = "main"
      compiler_flags = "-Wall -Wextra -Werror"
      language       = "c"
    }
  }
}

stage "execution" {
  use "toolkit/execution/stdio" {
    scenario "test-1" {
      parameters = {
        args = "test_input_1"
      }
    }
    options = {
      execution_binary = "compilation-output/main"
      execution_flags  = "((.:scenario.args))"
      input_path       = "assignment-assets/((.:scenario.code))/input.txt"
      output_path      = "output.txt"
      stderr_path      = "stderr.txt"
    }
  }
}
```

## Task Schemas

Each task has a `.schema.yaml` file documenting its parameters. These schemas provide:
- Parameter descriptions and types
- Default values
- Example usage with templating
- Support for Concourse's `((.:scenario.*))` templating syntax

## Variable Templating

Tasks support Concourse variable interpolation. For tasks executed with scenarios (matrix execution), these special variables are available:
- `((.:scenario.code))` - The scenario identifier (e.g., "test-1", "test-2")
- `((.:scenario.args))` - Custom 'args' parameter from the scenario
- `((.:scenario.score))` - Custom 'score' parameter from the scenario
- `((.:scenario.any_param))` - Any custom parameter defined in the scenario

**Important for output handling:** With the latest ghost integration, output files are directly uploaded to the configured storage location. This means:
- Input paths from `assignment-assets` still need `((.:scenario.code))` to locate scenario-specific files
- Output paths are now relative to the output directory (no resource prefix needed)
- Ghost handles uploading via environment variables configured by the system

## Path Resolution

**Important**: All paths in task parameters are relative to their respective resources:
- Input paths are relative to the input resource root (e.g., `submission/`, `assignment-assets/`, `compilation-output/`)
- Output paths are now simple filenames or relative paths (e.g., `main`, `output.txt`, `stderr.txt`)
- Ghost automatically creates parent directories for output files
- Output files are uploaded directly to the configured storage location via ghost

## Task Structure

Each task file follows the Concourse CI task specification:

```yaml
platform: linux
image_resource:
  type: registry-image
  source:
    repository: <docker-image>
    tag: <version>
inputs:
  - name: submission        # Student code
  - name: assignment-assets # Test cases and helper files
  - name: ghost            # Command runner binary
  - name: <other-inputs>
outputs:
  - name: <output-name>
params:
  PARAM_NAME: ((param_value))  # Configurable parameters
run:
  path: <shell>
  args:
    - <script>
```

## Resource Flow

1. **submission**: Student submitted code (from MinIO storage)
2. **assignment-assets**: Test cases, inputs, expected outputs (from MinIO)
3. **toolkit**: This repository (cloned via Git)
4. **ghost**: Command runner (downloaded from GitHub releases)
5. **compilation-output**: Results from compilation stage
6. **execution-output**: Results from execution stage (per scenario)
7. **testing-output**: Results from testing stage (per scenario)

## Input/Output Resources by Task Type

### Compilation Tasks
**Inputs:**
- `submission`: Student source code
- `assignment-assets`: Header files, libraries, helper resources
- `ghost`: Command runner binary

**Outputs:**
- `compilation-output`: Compiled binaries and compilation logs

**Common Path Examples:**
```yaml
source_file: submission/main.c          # Reads from submission/main.c
output_binary: main  # Output binary relative to output directory
```

### Execution Tasks
**Inputs:**
- `submission`: Original source code (if needed)
- `compilation-output`: Compiled binaries from compilation stage
- `assignment-assets`: Test input files
- `ghost`: Command runner binary

**Outputs:**
- `execution-output`: Program outputs, stderr, and execution logs (one per scenario)

**Common Path Examples:**
```yaml
execution_binary: compilation-output/main                     # Reads from compilation-output/main
input_path: assignment-assets/((.:scenario.code))/input.txt   # Input file for test case
output_path: output.txt                                       # Stdout saved relative to output directory
stderr_path: stderr.txt                                       # Stderr saved relative to output directory
```

**Note:** Output paths are relative to the output directory. Ghost handles uploading to the correct location based on environment configuration.

### Testing Tasks
**Inputs:**
- `execution-output`: Actual program outputs from execution stage
- `assignment-assets`: Expected output files
- `ghost`: Command runner binary

**Outputs:**
- `testing-output`: Test results, diff outputs, and scores (one per scenario)

**Common Path Examples:**
```yaml
input_path: execution-output/output.txt                            # Actual output from scenario's execution
expected_path: assignment-assets/((.:scenario.code))/expected.txt  # Expected output
output_path: diff.txt                                              # Diff results saved relative to output directory
```

**Note:** Output paths are relative to the output directory. Ghost handles uploading to the correct location based on environment configuration.

## Pipeline Execution

When a grading pipeline runs:

1. Core system generates a Concourse pipeline from configuration
2. Pipeline references task templates using `toolkit/<category>/<task>` paths
3. Concourse fetches resources (submission, assets, toolkit, ghost)
4. Tasks execute in isolated Docker containers
5. Ghost captures execution results in JSON format
6. Results flow between stages via input/output connections
7. Final results are stored back to MinIO

## Development

### Testing Task Files

To test a task file locally with Concourse CI's fly CLI:

```bash
fly -t <target> execute -c <task-file>.yaml \
  -i submission=<path> \
  -i assignment-assets=<path> \
  -i ghost=<path>
```

### Adding New Tasks

1. Create task file in appropriate category directory
2. Use standard inputs/outputs for compatibility
3. Integrate ghost for command execution when applicable
4. Document parameters in task comments
5. Test with sample inputs

### Task Requirements

- Use appropriate Docker images for the language/tool
- Include ghost as input when executing commands
- Set executable permissions: `chmod +x ghost/ghost-linux-amd64`
- Use ghost path: `./ghost/ghost-linux-amd64`
- Handle errors gracefully
- Create output directories as needed
- Follow existing naming conventions

## Context

This toolkit is designed for the zinc-sig grading system control plane:
- Tasks execute in Concourse CI workers
- Full system uses Temporal for workflow orchestration
- MinIO provides object storage for configurations and results
- Designed for security with isolated execution environments

## Related Repositories

- [zinc-sig/core](https://github.com/zinc-sig/core): Main grading system
- [zinc-sig/ghost](https://github.com/zinc-sig/ghost): Command runner
- [zinc-sig/concourse](https://github.com/concourse/concourse): CI/CD platform
