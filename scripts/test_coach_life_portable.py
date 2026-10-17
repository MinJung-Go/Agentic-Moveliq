#!/usr/bin/env python3
"""Run actual Foundation-only coach policy XCTest; Apple SDK integration is separate."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="moveliq-coach-life-") as directory:
    package = Path(directory)
    source = package / "Sources/AgenticKeepKeep"
    tests = package / "Tests/AgenticKeepKeepTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    shutil.copy2(root / "AgenticKeepKeep/Core/Agents/CoachLifeTypes.swift", source)
    shutil.copy2(root / "AgenticKeepKeepTests/AgentTests/CoachLifePolicyTests.swift", tests)
    shutil.copy2(root / "AgenticKeepKeep/Core/Agents/CoachAutomationPolicy.swift", source)
    shutil.copy2(root / "AgenticKeepKeepTests/AgentTests/CoachAutomationPolicyTests.swift", tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CoachLifeChecks", platforms: [.macOS(.v13)], targets: [
    .target(name: "AgenticKeepKeep"),
    .testTarget(name: "AgenticKeepKeepTests", dependencies: ["AgenticKeepKeep"])
])
''', encoding="utf-8")
    subprocess.run([os.environ.get("SWIFT", "swift"), "test", "--package-path", str(package)], check=True)
