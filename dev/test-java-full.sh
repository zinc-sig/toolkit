#!/bin/bash

# Full integration test for Java compilation and execution
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Full Java Compilation + Execution Test"
echo "=========================================="

# Step 1: Compile the Java program
echo ""
echo "1️⃣ Compiling Java program with InputReader..."

# Create a test config that compiles InputReader
cat > test-configs/compilation/java-inputreader.test.yaml << 'EOF'
---
name: Java InputReader Compilation
mock_resources:
  submission:
    files:
      InputReader.java: |
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
    ls -la compilation-output/
EOF

./dev.sh test compilation/java.yaml --config test-configs/compilation/java-inputreader.test.yaml

# Step 2: Download the compiled JAR from MinIO
echo ""
echo "2️⃣ Downloading compiled JAR from MinIO..."
mc alias set minio http://localhost:9001 minioadmin minioadmin 2>/dev/null || true
mc cp minio/task-outputs/inputreader.jar /tmp/inputreader.jar

# Step 3: Now test execution with the compiled JAR
echo ""
echo "3️⃣ Testing Java execution with compiled JAR..."

# Create execution test config
cat > test-configs/execution/java-exec.test.yaml << 'EOF'
---
name: Java Execution Test with Real JAR
mock_resources:
  submission:
    files:
      placeholder.txt: "placeholder"
  
  assignment_assets:
    files:
      test-1/input.txt: |
        5
        10
      test-2/input.txt: |
        Hello
        World
  
  compilation_output:
    files:
      inputreader.jar: "WILL_BE_REPLACED"

task_parameters:
  execution_type: "jar"
  execution_target: "compilation-output/inputreader.jar"
  classpath: ""
  java_flags: ""
  execution_flags: ""
  input_path: "assignment-assets/test-1/input.txt"
  output_path: "output.txt"
  stderr_path: "stderr.txt"
  repository: "openjdk"
  version: "17"
  variant: "jre"
  score: "20"

verification:
  image:
    repository: busybox
    tag: latest
  script: |
    echo "Checking Java execution output..."
    if [ -f execution-output/output.txt ]; then
      echo "✅ Output file created"
      echo "Output content:"
      cat execution-output/output.txt
      
      # Check if output matches expected
      if grep -q "Sum: 15" execution-output/output.txt; then
        echo "✅ Correct output: Sum of 5 + 10 = 15"
      else
        echo "❌ Output doesn't match expected"
        exit 1
      fi
    else
      echo "❌ Output file not found"
      exit 1
    fi
EOF

# Upload the JAR to MinIO in the location where the test expects it
echo "Uploading JAR to test location..."
mc cp /tmp/inputreader.jar minio/task-inputs/inputreader.jar

# Now run the execution test
./dev.sh test execution/java.yaml --config test-configs/execution/java-exec.test.yaml

echo ""
echo "4️⃣ Testing execution with command line arguments..."

# Create another test with arguments
cat > test-configs/execution/java-exec-args.test.yaml << 'EOF'
---
name: Java Execution with Arguments
mock_resources:
  submission:
    files:
      placeholder.txt: "placeholder"
  
  assignment_assets:
    files:
      test-1/input.txt: |
        5
        10
  
  compilation_output:
    files:
      inputreader.jar: "WILL_BE_REPLACED"

task_parameters:
  execution_type: "jar"
  execution_target: "compilation-output/inputreader.jar"
  classpath: ""
  java_flags: "-Xmx128m"
  execution_flags: "arg1 arg2 arg3"
  input_path: "assignment-assets/test-1/input.txt"
  output_path: "output.txt"
  stderr_path: "stderr.txt"
  repository: "openjdk"
  version: "17"
  variant: "jre"
  score: "20"

verification:
  image:
    repository: busybox
    tag: latest
  script: |
    echo "Checking output with arguments..."
    cat execution-output/output.txt
    if grep -q "Arguments: arg1, arg2, arg3" execution-output/output.txt; then
      echo "✅ Arguments passed correctly!"
    else
      echo "❌ Arguments not found in output"
      exit 1
    fi
EOF

./dev.sh test execution/java.yaml --config test-configs/execution/java-exec-args.test.yaml

echo ""
echo "✅ All Java execution tests passed!"