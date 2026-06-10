#!/bin/bash
# Run the core package test suite.
set -euo pipefail
cd "$(dirname "$0")/../Core"
swift test
