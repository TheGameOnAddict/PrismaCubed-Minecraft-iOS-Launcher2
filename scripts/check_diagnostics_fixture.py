"""Independently unpack the ZIPs written by the simulator's real exporter."""
import json
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile


def verify(directory, scenario):
    with ZipFile(directory / f"fixture-{scenario}.zip") as archive:
        assert archive.testzip() is None, "ZIP CRC mismatch"
        entries = {}
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            assert not path.is_absolute() and ".." not in path.parts
            if not entry.is_dir() and path.name != ".DS_Store":
                assert path.name not in entries, f"Ambiguous member {path.name}"
                entries[path.name] = archive.read(entry)
    manifest = json.loads(entries["manifest.json"])
    assert manifest["profile"] == "example"
    assert set(manifest["included"]) == entries.keys() - {"manifest.json"}
    assert "hs_err_pid99999.log" not in entries and "level.dat" not in entries
    if scenario.startswith("mobilegl"):
        if scenario == "mobilegl":
            driver = entries["mobilegl.log"]
            assert b"Initializing MobileGL" in driver and b"Renderer Name: Magma" in driver
            assert b"renderer-canary" not in driver
            assert b"middle omitted for export" in driver and b"repeated warning/error" in driver
            assert 1 <= driver.count(b"VK_ERROR_DEVICE_LOST") <= 8
            assert driver.rstrip().endswith(b"final fence operation") and len(driver) < 4096
        else:
            assert "mobilegl.log" not in entries and "mobilegl.log" in manifest["unavailable"]
        print(f"{scenario}: verified renderer log association and excerpt")
        return
    if scenario.startswith("early"):
        assert "game-latest.log" in manifest["unavailable"] and "game-latest.log" not in entries
        assert "hs_err_pid12260.log" not in entries and "hs_err_pid12260.log" not in manifest["unavailable"]
        assert b"matching-launcher-snapshot" in entries["launcher.log"] and b"wrong-restart-log" not in entries["launcher.log"]
        assert b"category: java_exception" in entries["crash-report.txt"]
        trace = entries["fatal-trace.txt"]
        assert b"matching-trace" in trace and trace.count(b"Amethyst fatal trace") == 1
        assert b"previous-run-canary" not in trace and b"following-run-canary" not in trace
        if scenario == "early-profile":
            assert manifest["crashMatch"] == "launcher snapshot run ID"
        print(f"{scenario}: verified early exit diagnostics")
        return
    assert b"zink" in entries["game-latest.log"] and b"private-test" not in entries["game-latest.log"]
    assert b"secret-test" not in entries["launcher.log"]
    profile = json.loads(entries["profile.json"])
    assert str(profile["options"]["renderDistance"]) == "8"
    for private_setting in (b"setting-canary", b"shader-canary"):
        assert private_setting not in entries["profile.json"]
    assert b"hs_err_pid10981.log" in entries["launcher.log"]
    assert b"hs_err_pid10981.log" in entries["crash-report.txt"]
    if scenario == "profile":
        assert "timestamp" in manifest["crashMatch"]
    if scenario != "stale":
        assert json.loads(entries["performance.json"])["profile"] == "example"
        excerpt = entries["hs_err_pid10981.log"]
        for marker in (b"fatal error", b"SIGSEGV", b"Native frames", b"libMobileGL.dylib"):
            assert marker in excerpt, marker
        for secret in (b"Registers:", b"Command Line:", b"raw-register-fixture", b"private-fixture-value"):
            assert secret not in excerpt, secret
    else:
        for name in ("performance.json", "hs_err_pid10981.log"):
            assert name not in entries and name in manifest["unavailable"], name
    print(f"{scenario}: verified {len(entries)} diagnostics files")


if __name__ == "__main__":
    for scenario in ("matched", "profile", "stale", "early", "early-profile", "mobilegl", "mobilegl-other-run", "mobilegl-stale"):
        verify(Path(sys.argv[1]), scenario)
