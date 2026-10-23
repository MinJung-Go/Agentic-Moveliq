#!/usr/bin/env python3
"""Run the browser URL regression tests with Foundation, without Apple SDKs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="moveliq-browser-search-") as directory:
    package = Path(directory)
    source = package / "Sources" / "AgenticKeepKeep"
    tests = package / "Tests" / "BrowserSearchTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    for relative in ["Core/LLM/FitnessSearchTopic.swift", "Core/Agents/CoachToolResult.swift",
                     "Core/LocalMilo/LocalBrowserPolicy.swift", "Core/LLM/PublicWebSearch.swift"]:
        shutil.copy2(root / "AgenticKeepKeep" / relative, source)
    shutil.copy2(root / "AgenticKeepKeepTests/AgentTests/LocalBrowserSearchTests.swift", tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BrowserSearchChecks", platforms: [.macOS(.v13)], targets: [
    .target(name: "AgenticKeepKeep"),
    .testTarget(name: "BrowserSearchTests", dependencies: ["AgenticKeepKeep"])
])
''')
    subprocess.run([os.environ.get("SWIFT", "swift"), "test", "--package-path", str(package)], check=True)
