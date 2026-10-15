#!/usr/bin/env python3
"""Run the round-33 presentation logic and existing home routing tests without iOS SDKs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="moveliq-readability-") as directory:
    package = Path(directory)
    source = package / "Sources/AgenticKeepKeep"
    tests = package / "Tests/AgenticKeepKeepTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    for path in ["Support/RecordDisplayName.swift", "Support/ReportTextLayout.swift", "Agents/HomeInputRouter.swift"]:
        shutil.copy2(root / "AgenticKeepKeep/Core" / path, source)
    for path in ["DataTests/ReadingPresentationTests.swift", "AgentTests/HomeInputRouterTests.swift"]:
        shutil.copy2(root / "AgenticKeepKeepTests" / path, tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ReadabilityChecks", targets: [
    .target(name: "AgenticKeepKeep"),
    .testTarget(name: "AgenticKeepKeepTests", dependencies: ["AgenticKeepKeep"])
])
''')
    subprocess.run([os.environ.get("SWIFT", "swift"), "test", "--package-path", str(package)], check=True)
