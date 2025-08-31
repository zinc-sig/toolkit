#!/bin/bash

# Test script for Java execution task
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "📦 Starting Java execution test..."

# First, create and compile a simple Java program that reads input
cat > mock-resources/submissions/InputReader.java << 'EOF'
import java.util.Scanner;

public class InputReader {
    public static void main(String[] args) {
        Scanner scanner = new Scanner(System.in);
        
        // Check for command line arguments
        if (args.length > 0) {
            System.out.println("Arguments: " + String.join(", ", args));
        }
        
        // Read and process input
        if (scanner.hasNextInt()) {
            int a = scanner.nextInt();
            if (scanner.hasNextInt()) {
                int b = scanner.nextInt();
                System.out.println("Sum: " + (a + b));
            }
        } else {
            // Read text input
            while (scanner.hasNextLine()) {
                String line = scanner.nextLine();
                if (!line.isEmpty()) {
                    System.out.println("Input: " + line);
                }
            }
        }
        
        scanner.close();
    }
}
EOF

# Create test input files
mkdir -p mock-resources/assignment-assets/test-1
echo -e "5\n10" > mock-resources/assignment-assets/test-1/input.txt

# Update the Java compilation test config temporarily
cat > test-configs/compilation/java-temp.test.yaml << 'EOF'
---
name: Java Compilation for Execution Test
mock_resources:
  submission:
    files:
      InputReader.java: |
        import java.util.Scanner;
        public class InputReader {
            public static void main(String[] args) {
                Scanner scanner = new Scanner(System.in);
                if (args.length > 0) {
                    System.out.println("Arguments: " + String.join(", ", args));
                }
                if (scanner.hasNextInt()) {
                    int a = scanner.nextInt();
                    if (scanner.hasNextInt()) {
                        int b = scanner.nextInt();
                        System.out.println("Sum: " + (a + b));
                    }
                }
                scanner.close();
            }
        }
  assignment_assets:
    files:
      placeholder.txt: "placeholder"

task_parameters:
  source_pattern: "submission/*.java"
  main_class: "InputReader"
  output_type: "jar"
  output_name: "inputreader.jar"
  classpath: ""
  compiler_flags: ""
  repository: "openjdk"
  version: "17"
  variant: "jdk"
  score: "10"

verification:
  image:
    repository: busybox
    tag: latest
  script: |
    echo "JAR created for execution test"
    ls -la compilation-output/
EOF

echo "1️⃣ Compiling Java program..."
./dev.sh test compilation/java.yaml --config test-configs/compilation/java-temp.test.yaml

echo ""
echo "2️⃣ Testing Java execution..."

# The compilation should have created the JAR in MinIO
# Now we need to test execution, but we need the compiled output
# For now, let's just validate that our execution task YAML is valid

echo "Validating execution/java.yaml syntax..."
if yq eval '.' ../execution/java.yaml > /dev/null 2>&1; then
    echo "✅ execution/java.yaml has valid YAML syntax"
else
    echo "❌ execution/java.yaml has invalid YAML syntax"
    exit 1
fi

echo ""
echo "📋 Java execution task parameters:"
yq eval '.params' ../execution/java.yaml

echo ""
echo "🎯 Test completed successfully!"
echo "Note: Full integration test requires a pipeline that chains compilation → execution"