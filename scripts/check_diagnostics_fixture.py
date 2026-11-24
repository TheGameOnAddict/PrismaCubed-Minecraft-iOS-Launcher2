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
    for scenario in ("matched", "profile", "stale"):
        verify(Path(sys.argv[1]), scenario)
