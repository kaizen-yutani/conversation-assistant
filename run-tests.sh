#!/bin/bash
# Run OAuth and Connection tests

set -e

echo "========================================="
echo "Building and running OAuth tests..."
echo "========================================="

# Compile the test file
swiftc -o /tmp/oauth_tests \
    -framework Foundation \
    -framework Network \
    Tests/OAuthTests.swift \
    2>&1

if [ $? -eq 0 ]; then
    echo "Compilation successful, running tests..."
    /tmp/oauth_tests
    TEST_RESULT=$?
    rm -f /tmp/oauth_tests
    exit $TEST_RESULT
else
    echo "Compilation failed!"
    exit 1
fi
