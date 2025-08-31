# Configuration-Driven Task Development Environment

A modern, language-agnostic development environment for testing Concourse CI task YAMLs in the zinc-sig toolkit. This environment uses **configuration files** instead of hardcoded logic, enabling zero-code support for new programming languages.

## ✨ Key Features

- 🔧 **Zero-code language support** - Add new languages through configuration files only
- 🎛️ **yq-based YAML parsing** - Robust, reliable configuration processing
- 🔀 **Test variants** - Multiple test scenarios per language (JAR/classes, error-handling, etc.)
- 🛡️ **Schema validation** - Automatic configuration validation with helpful error messages
- 🚀 **One-command testing** - `./dev.sh test compilation/java.yaml --variant classes-only`

## 🚀 Quick Start

```bash
# 1. Start the environment
./dev.sh start

# 2. Test existing languages with zero setup
./dev.sh test compilation/gcc.yaml           # C/C++ compilation
./dev.sh test compilation/java.yaml          # Java JAR creation
./dev.sh test compilation/java.yaml --variant classes-only  # Java classes only
./dev.sh test execution/python.yaml          # Python execution

# 3. View configuration details
./dev.sh test compilation/java.yaml --summary

# 4. Clean up when done
./dev.sh clean
```

## 📋 Prerequisites

- Docker Desktop installed and running
- **yq** YAML processor ([install instructions](https://github.com/mikefarah/yq#install))
- Linux/macOS (Windows users: use WSL2)
- 4GB free RAM
- Ports 8080, 9000, 9001 available

## What This Environment Provides

- **Concourse CI**: Local pipeline orchestration (http://localhost:8080)
- **MinIO**: S3-compatible object storage for artifacts (http://localhost:9001)
- **Ghost Binary**: Command runner that captures execution metadata and uploads to MinIO
- **Configuration System**: YAML-based test configurations with variants and validation
- **Mock Resources**: Dynamically generated test data from configurations
- **Fly CLI**: Command-line tool for managing Concourse

## 🛠️ Development Workflow

### Step 1: Start Environment
```bash
./dev.sh start
```
This starts Concourse CI, MinIO storage, and PostgreSQL database.

### Step 2: Test Existing Languages
```bash
# Test with auto-discovered configuration
./dev.sh test compilation/gcc.yaml
./dev.sh test compilation/java.yaml

# Test with specific variants
./dev.sh test compilation/java.yaml --variant classes-only
./dev.sh test execution/python.yaml --variant error-handling

# Show configuration summary
./dev.sh test compilation/java.yaml --summary
```

### Step 3: Add New Language Support
```bash
# 1. Create the task YAML file
# 2. Create test configuration (see examples below)
# 3. Test immediately - no code changes needed!
./dev.sh test compilation/newlang.yaml
```

### Step 4: Clean Up
```bash
./dev.sh stop   # Stop services (data preserved)
./dev.sh clean  # Remove everything
```

## 📁 Directory Structure

```
dev/
├── dev.sh                    # Main configuration-driven CLI tool
├── lib/
│   └── config-parser.sh      # yq-based YAML configuration parser
├── test-configs/             # Language test configurations
│   ├── compilation/
│   │   ├── gcc.test.yaml     # C/C++ test configuration with variants
│   │   └── java.test.yaml    # Java test configuration (JAR/classes)
│   └── execution/
│       └── python.test.yaml  # Python execution configuration
├── test-config.schema.yaml   # Configuration schema for validation
├── docker-compose.yml        # Service definitions
├── examples/                 # Working pipeline examples
├── mock-resources/           # Legacy test data (auto-generated from configs)
└── TROUBLESHOOTING.md        # Common issues & solutions
```

## 🔧 Adding New Language Support

### Example: Adding Rust Support

1. **Create the task file**: `../compilation/rust.yaml`
2. **Create test configuration**: `test-configs/compilation/rust.test.yaml`

```yaml
---
name: Rust Compilation Test
description: Test configuration for Rust compilation with Cargo

mock_resources:
  submission:
    files:
      main.rs: |
        fn main() {
            println!("Hello from Rust!");
            println!("Compilation successful!");
        }
      Cargo.toml: |
        [package]
        name = "test-program"
        version = "0.1.0"
        edition = "2021"

task_parameters:
  source_pattern: "submission/*.rs"
  output_binary: "target/release/test-program"
  build_flags: "--release"
  score: "10"

verification:
  image:
    repository: rust
    tag: "1.70-slim"
  script: |
    echo "Checking Rust compilation..."
    if [ -f compilation-output/target/release/test-program ]; then
      echo "✅ Rust binary created successfully"
      ./compilation-output/target/release/test-program
    else
      echo "❌ Rust binary not found"
      exit 1
    fi

variants:
  - name: "debug-build"
    description: "Debug build for development"
    task_parameters:
      build_flags: ""
      output_binary: "target/debug/test-program"
```

3. **Test immediately**:
```bash
./dev.sh test compilation/rust.yaml
./dev.sh test compilation/rust.yaml --variant debug-build
```

## Key Commands

### Environment Management
```bash
./dev.sh start    # Start all services
./dev.sh stop     # Stop services (data preserved)
./dev.sh clean    # Remove everything
```

### Configuration-Driven Testing
```bash
# Test with auto-discovered config
./dev.sh test compilation/gcc.yaml

# Test specific variants
./dev.sh test compilation/java.yaml --variant classes-only
./dev.sh test compilation/java.yaml --variant package-structure

# Use custom configuration
./dev.sh test compilation/java.yaml --config my-custom.yaml

# Show configuration summary
./dev.sh test compilation/java.yaml --summary
```

## 🧪 Available Test Configurations

### Compilation Tasks
- **GCC (C/C++)**: `compilation/gcc.yaml`
  - Variants: `cpp-compilation`, `with-warnings-as-errors`, `optimized-build`
- **Java**: `compilation/java.yaml` 
  - Variants: `classes-only`, `package-structure`, `with-external-libs`

### Execution Tasks  
- **Python**: `execution/python.yaml`
  - Variants: `with-imports`, `error-handling`, `file-io`

## Configuration Features

### ✅ Automatic Config Discovery
```bash
# Automatically finds test-configs/compilation/gcc.test.yaml
./dev.sh test compilation/gcc.yaml
```

### ✅ Test Variants
```bash
# Use predefined test scenarios
./dev.sh test compilation/java.yaml --variant classes-only
./dev.sh test execution/python.yaml --variant error-handling
```

### ✅ Mock Resource Generation
Configuration files define test code and input files that are automatically generated as mock resources.

### ✅ Flexible Verification Scripts
Each configuration can define custom verification logic using any Docker image.

### ✅ YAML Validation
Configurations are validated against a schema with helpful error messages.

## Migration from Legacy System

The system has been completely rewritten to be configuration-driven:

- **Before**: Hardcoded language logic in shell scripts
- **After**: Data-driven YAML configurations with zero-code extensibility
- **Migration**: All existing functionality preserved, new features added

## 🌐 Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Concourse Web UI | http://localhost:8080 | dev / dev |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| MinIO API | http://localhost:9000 | minioadmin / minioadmin |

## 📚 Documentation

- **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** - Complete guide with architecture, concepts, and detailed instructions  
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues, debugging techniques, and solutions
- **[test-config.schema.yaml](test-config.schema.yaml)** - Configuration schema reference

## 🆘 Getting Help

1. **Check configuration syntax**: `./dev.sh test your-task.yaml --summary`
2. **Validate configuration**: Schema validation runs automatically
3. **View available variants**: Listed in summary output
4. **Common issues**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

**🎯 Goal Achieved**: Zero-code language support through configuration files only!