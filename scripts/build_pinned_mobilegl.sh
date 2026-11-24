#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
output=${1:?usage: build_pinned_mobilegl.sh OUTPUT_DIR MAKE JOBS}
make_command=${2:?missing GNU Make}
jobs=${3:?missing job count}
mkdir -p "$output"
output=$(cd "$output" && pwd)
build=$(mktemp -d "$output/build.XXXXXXXX")
trap 'rm -rf "$build"' EXIT

# This is the launcher commit reported by the shipped driver's GL_VERSION.
# The upstream renderer sources and the iOS-specific compiler fixes live together.
pinned=874b9e8af7b74f886e97456ac2b82dce59baf406
asio_pin=8806a6803cde7054c3049d3666d3ec36786568c5
export GIT_LFS_SKIP_SMUDGE=1
source_dir="$build/launcher"
git init --quiet "$source_dir"
git -C "$source_dir" remote add origin https://github.com/herbrine8403/Amethyst-iOS-MyRemastered.git
git -C "$source_dir" sparse-checkout set --no-cone \
    /Makefile /Natives/external/MobileGL/ /Natives/patch_mobilegl_ios.py /Natives/patch_mobilegl_glslang.py
git -C "$source_dir" fetch --quiet --filter=blob:none --depth=1 origin "$pinned"
git -C "$source_dir" checkout --quiet --detach "$pinned"
git -C "$source_dir" apply "$repo/patches/mobilegl-ordered-texture-updates.patch"

asio="$source_dir/Natives/external/MobileGL/3rdparty/asio"
git init --quiet "$asio"
git -C "$asio" fetch --quiet --depth=1 https://github.com/chriskohlhoff/asio.git "$asio_pin"
git -C "$asio" checkout --quiet --detach "$asio_pin"
test -f "$asio/include/asio/post.hpp"

# Let the pinned recipe use exactly the MoltenVK binary going into this IPA.
mkdir -p "$source_dir/Natives/resources/Frameworks"
ln -s "$repo/Natives/resources/Frameworks/libMoltenVK.dylib" "$source_dir/Natives/resources/Frameworks/libMoltenVK.dylib"
# Upstream shipped its Debug configuration (release optimizations are enabled
# there too). Release hides symbols and changes the driver's exported ABI.
# Run the unmodified upstream driver target without the unrelated app's global
# prerequisites (ldid, JDK 8, wget and the rest of the Minecraft build).
python3 - "$source_dir/Makefile" "$build/driver.mk" <<'PYMAKE'
from pathlib import Path
import re, sys
original = Path(sys.argv[1]).read_text()
body = re.search(r"(?ms)^dep_mobilegl_build:\n(.*?)(?=^[A-Za-z_][A-Za-z0-9_]*:)", original)
if not body:
    raise RuntimeError("Pinned renderer recipe missing")
Path(sys.argv[2]).write_text("SHELL := /bin/bash\n" + body.group())
PYMAKE
"$make_command" -f "$build/driver.mk" -C "$source_dir" dep_mobilegl_build JOBS="$jobs" \
    WORKINGDIR="$build/output" SOURCEDIR="$source_dir" CMAKE_BUILD_TYPE=Debug \
    MOBILEGL_SOURCE_DIR="$source_dir/Natives/external/MobileGL" \
    MOLTENVK_LIBRARY="$source_dir/Natives/resources/Frameworks/libMoltenVK.dylib" \
    SDKPATH="$(xcrun --sdk iphoneos --show-sdk-path)"

driver="$build/output/libMobileGL.dylib"
lipo "$driver" -verify_arch arm64
otool -L "$driver" > "$build/linkage.txt"
grep -F '@rpath/libMoltenVK.dylib' "$build/linkage.txt" >/dev/null
python3 - "$driver" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
for stamp in (b"GIT@874b9e8", b"Ordered texture upload deferred: an earlier draw is still pending"):
    if stamp not in data:
        raise SystemExit(f"Missing MobileGL build identifier: {stamp!r}")
PY
mv "$driver" "$output/libMobileGL.dylib"
