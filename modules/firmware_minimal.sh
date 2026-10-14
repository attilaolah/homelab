#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
  printf '%s\n' 'Usage: firmware_minimal.sh FIRMWARE_INVENTORY LINUX_FIRMWARE OUT' >&2
  exit 2
fi

firmware_inventory=$1
linux_firmware=$2
output=$3

if [ ! -f "$firmware_inventory" ]; then
  printf 'Firmware inventory is not a regular file: %s\n' "$firmware_inventory" >&2
  exit 2
fi

firmware_root=$linux_firmware/lib/firmware
if [ ! -d "$firmware_root" ]; then
  printf 'Linux firmware directory does not exist: %s\n' "$firmware_root" >&2
  exit 2
fi

if [ -z "$output" ]; then
  printf '%s\n' 'Output path must not be empty' >&2
  exit 2
fi

mkdir -p "$output/lib/firmware"

while IFS= read -r firmware_path || [ -n "$firmware_path" ]; do
  [ -n "$firmware_path" ] || continue

  case "$firmware_path" in
    /* | .. | ../* | */.. | */../*)
      printf 'Unsafe firmware inventory path: %s\n' "$firmware_path" >&2
      exit 1
      ;;
  esac

  source_file=$firmware_root/$firmware_path
  target_file=$output/lib/firmware/$firmware_path
  if [ -f "$source_file" ]; then
    mkdir -p "$(dirname "$target_file")"
    cp "$source_file" "$target_file"
    chmod 0444 "$target_file"
  elif [ -f "$source_file.zst" ]; then
    mkdir -p "$(dirname "$target_file")"
    zstd --decompress --stdout -- "$source_file.zst" > "$target_file"
    chmod 0444 "$target_file"
  fi
done < "$firmware_inventory"
