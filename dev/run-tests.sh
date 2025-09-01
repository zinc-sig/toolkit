#!/bin/bash

# Test runner for dev toolkit
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🧪 Running Bats Tests for Dev Toolkit"
echo "======================================"
echo ""

# Check if bats is installed
if [[ ! -f "tests/bats/bin/bats" ]]; then
    echo -e "${RED}❌ Bats not installed!${NC}"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# Run tests with different output formats based on arguments
if [[ "$1" == "--tap" ]]; then
    # TAP format for CI
    ./tests/bats/bin/bats --tap tests/*.bats
elif [[ "$1" == "--verbose" ]]; then
    # Verbose output
    ./tests/bats/bin/bats --verbose-run tests/*.bats
elif [[ -n "$1" ]]; then
    # Run specific test file or filter
    if [[ -f "tests/$1" ]]; then
        ./tests/bats/bin/bats "tests/$1"
    else
        # Use as filter
        ./tests/bats/bin/bats tests/*.bats -f "$1"
    fi
else
    # Default: pretty output
    ./tests/bats/bin/bats tests/*.bats
fi

# Check exit code
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ All tests passed!${NC}"
else
    echo ""
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi