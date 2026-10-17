#!/usr/bin/env python3
"""Read the single authoritative private-engine pin from XcodeGen's project spec."""
import json
import os
import pathlib
import re
import sys


def inference_dependency(spec=None):
    spec = spec or pathlib.Path(__file__).resolve().parents[2] / "project.yml"
    text = pathlib.Path(spec).read_text(encoding="utf-8")
    block = re.search(r"^  MiloInference:\n((?:    [^\n]*\n)+)", text, re.MULTILINE)
    if not block:
        raise ValueError("Missing MiloInference remote dependency in project.yml")
    fields = dict(re.findall(r"^    (url|revision): (\S+)$", block[1], re.MULTILINE))
    if fields.get("url") != "https://github.com/MinJung-Go/MiloInference.git" or not re.fullmatch(r"[0-9a-f]{40}", fields.get("revision", "")):
        raise ValueError("MiloInference requires the expected private URL and a full fixed commit SHA")
    if "    path:" in block[1]:
        raise ValueError("Local engine copies must not override the remote pin")
    return fields


if __name__ == "__main__":
    pin = inference_dependency()
    if sys.argv[1:] == ["--github-output"]:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write("revision=" + pin["revision"] + "\n")
    else:
        print(json.dumps(pin))
