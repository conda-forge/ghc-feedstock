#!/usr/bin/env bash
set -x

# Test script to investigate linker flag issues
# This should be run in the test environment

echo "=== Test 1: Default GHC (with all linker flags) ==="
ghc hello.hs -o hello-default
./hello-default && echo "SUCCESS" || echo "FAILED with exit code $?"

echo ""
echo "=== Test 2: Without -undefined dynamic_lookup ==="
ghc hello.hs -o hello-no-dynamic-lookup \
  -optl-Wl,-undefined,error
./hello-no-dynamic-lookup && echo "SUCCESS" || echo "FAILED with exit code $?"

echo ""
echo "=== Test 3: Without -dead_strip ==="
ghc hello.hs -o hello-no-dead-strip \
  -optl-Wl,-no_dead_strip
./hello-no-dead-strip && echo "SUCCESS" || echo "FAILED with exit code $?"

echo ""
echo "=== Test 4: Without both dangerous flags ==="
ghc hello.hs -o hello-safe \
  -optl-Wl,-undefined,error \
  -optl-Wl,-no_dead_strip
./hello-safe && echo "SUCCESS" || echo "FAILED with exit code $?"

echo ""
echo "=== Test 5: With verbose linker output ==="
ghc -v hello.hs -o hello-verbose 2>&1 | tee linker-verbose.log
./hello-verbose && echo "SUCCESS" || echo "FAILED with exit code $?"

echo ""
echo "=== Test 6: Check for undefined symbols ==="
nm -u hello-default | head -20
echo "Count of undefined symbols:"
nm -u hello-default | wc -l
