#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/Model.swift Tests/ModelTests.swift -o .build/ModelTests
.build/ModelTests
