#!/usr/bin/env python3
"""Run production Foundation knowledge/learning logic. SwiftUI/SwiftData require Apple CI."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="moveliq-personal-knowledge-") as directory:
    package = Path(directory)
    source = package / "Sources/AgenticKeepKeep"
    tests = package / "Tests/AgenticKeepKeepTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    for path in ["Core/Agents/PersonalKnowledge.swift", "Core/Agents/PersonalLearningAgent.swift",
                 "Core/LLM/LLMClient.swift", "Core/LLM/LLMTypes.swift", "Core/LLM/JSONValue.swift"]:
        shutil.copy2(root / "AgenticKeepKeep" / path, source)
    shutil.copy2(root / "AgenticKeepKeepTests/AgentTests/PersonalKnowledgeTests.swift", tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PersonalKnowledgeChecks", targets: [
    .target(name: "AgenticKeepKeep"),
    .testTarget(name: "AgenticKeepKeepTests", dependencies: ["AgenticKeepKeep"])
])
''', encoding="utf-8")
    subprocess.run([os.environ.get("SWIFT", "swift"), "test", "--package-path", str(package)], check=True)
