#!/bin/bash
docker_build_mount="$(realpath "$(dirname "$0")"/build)"
app_dir="$(realpath "$docker_build_mount"/../../../..)"
exiftool_dir="$app_dir"/vendor/exiftool/exiftool
DOCKER_BIN="${DOCKER:-docker}"

"$DOCKER_BIN" run --workdir /build --rm -v "$docker_build_mount":/build i386/alpine:3.9 ./build-perl.sh

if [ -e "$docker_build_mount"/exiftool.bin ];then
  if command -v chown >/dev/null 2>&1; then chown "$(id -u)":"$(id -g)" "$docker_build_mount"/exiftool.bin || true; fi

  chmod +x "$docker_build_mount"/exiftool.bin
  if [ -e "$exiftool_dir"/exiftool.bin ];then
    rm "$exiftool_dir"/exiftool.bin
  fi

  mv "$docker_build_mount"/exiftool.bin "$exiftool_dir"/
fi
