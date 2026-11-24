"""Read the XML entitlement slot in a thin arm64 iOS Mach-O code signature."""
from pathlib import Path
import plistlib
import struct
import sys

image = Path(sys.argv[1]).read_bytes()
magic, arch, _, _, commands = struct.unpack_from("<5I", image)
assert (magic, arch) == (0xfeedfacf, 0x0100000c)
offset = 32
for _ in range(commands):
    command, size = struct.unpack_from("<II", image, offset)
    if command == 0x1d:
        start, length = struct.unpack_from("<II", image, offset + 8)
        signature = image[start:start+length]
        header, _, count = struct.unpack_from(">III", signature)
        assert header == 0xfade0cc0
        for i in range(count):
            slot, blob = struct.unpack_from(">II", signature, 12+8*i)
            if slot == 5:
                kind, length = struct.unpack_from(">II", signature, blob)
                assert kind == 0xfade7171
                entitlements = plistlib.loads(signature[blob+8:blob+length])
                assert entitlements and 'application-identifier' in entitlements
                Path(sys.argv[2]).write_bytes(plistlib.dumps(entitlements))
                sys.exit(0)
    offset += size
raise ValueError("missing XML entitlement slot")
