#!/bin/bash
# Test runner for pyworks.nvim
# Runs all tests using Plenary.nvim

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Pyworks.nvim Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if nvim is available
if ! command -v nvim &> /dev/null; then
    echo "❌ Error: nvim not found in PATH"
    exit 1
fi

echo "✓ Neovim version:"
nvim --version | head -n 1

# Check if plenary is installed
PLENARY_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/plenary.nvim"
if [ ! -d "$PLENARY_PATH" ]; then
    PLENARY_PATH="$HOME/.local/share/nvim/site/pack/vendor/start/plenary.nvim"
fi

if [ ! -d "$PLENARY_PATH" ]; then
    echo ""
    echo "❌ Error: plenary.nvim not found"
    echo "   Install with: git clone https://github.com/nvim-lua/plenary.nvim $PLENARY_PATH"
    exit 1
fi

echo "✓ Plenary found at: $PLENARY_PATH"
echo ""

# Parse arguments
TEST_FILE=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -f|--file)
            TEST_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose     Show detailed output"
            echo "  -f, --file FILE   Run specific test file"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                          # Run all tests"
            echo "  $0 -f utils_spec.lua        # Run specific test"
            echo "  $0 -v                       # Run with verbose output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Run tests
if [ -n "$TEST_FILE" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running: $TEST_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    nvim --headless \
        -u tests/minimal_init.lua \
        -c "PlenaryBustedFile tests/$TEST_FILE" \
        -c "qa!"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running all tests in tests/"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    nvim --headless \
        -u tests/minimal_init.lua \
        -c "lua require('plenary.test_harness').test_directory('tests/', {minimal_init = 'tests/minimal_init.lua'})" \
        -c "qa!"
fi

EXIT_CODE=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✅ All tests passed!"
else
    echo "  ❌ Some tests failed (exit code: $EXIT_CODE)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $EXIT_CODE
