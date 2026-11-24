#!/usr/bin/env bash
# Build against the libraries of an installed Forge 1.20.1 profile, using JDK 17+.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
libs=${1:?usage: build.sh MINECRAFT_LIBRARIES OUTPUT_JAR}
jarfile=${2:?missing output jar}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Restrict classpath to the APIs used by this client-only probe. Load no processors.
classpath=$(find "$libs" -type f \( -name 'forge-1.20.1-47.*-universal.jar' \
    -o -name 'javafmllanguage-1.20.1-47.*.jar' -o -name 'mergetool-*-api.jar' \
    -o -name 'eventbus-6*.jar' -o -name 'slf4j-api-2*.jar' \
    -o -name 'lwjgl-3*.jar' -o -name 'lwjgl-opengl-3*.jar' \) \
    ! -name '*-natives-*' | paste -sd : -)
javac --release 17 -proc:none -cp "$classpath" -d "$work" \
    "$root"/src/main/java/dev/prismacubic/entityprobe/*.java
jar --create --file "$jarfile" -C "$root/../.." LICENSE -C "$root/src/main/resources" . -C "$work" .
