#!/usr/bin/env python3
"""Replay an interrupted and a completed capture using a real JVM and its thread MXBean."""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def executable(name):
    if os.environ.get("JAVA_HOME"):
        return str(Path(os.environ["JAVA_HOME"]) / "bin" / name)
    return shutil.which(name) or name

with tempfile.TemporaryDirectory() as temp:
    out = Path(temp)
    subprocess.run([executable("javac"), "-source", "8", "-target", "8", "-d", str(out),
                    str(root / "JavaApp/src/launcher/net/kdt/pojavlaunch/CaptureSampler.java"),
                    str(root / "tests/java/net/kdt/pojavlaunch/CaptureSamplerTest.java")], check=True)
    for mode, status in [("complete", "completed"), ("interrupt", "interrupted")]:
        marker = out / mode
        subprocess.run([executable("java"), "-ea", "-cp", str(out),
                        "net.kdt.pojavlaunch.CaptureSamplerTest", str(marker), mode], check=True, timeout=15)
        report = json.loads(Path(str(marker) + ".json").read_text())
        assert report["status"] == status
        samples = report["samples"]
        assert 0 < len(samples) == report["rounds"] <= 1200
        assert any("render/other" in s["work"] for s in samples)
        assert all(report["captureStartEpochMs"] <= s["atMs"] <= report["captureStartEpochMs"] + 60100 for s in samples)
print("Java work sampler classification, bounded capture and interruption passed.")
