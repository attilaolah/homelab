#!/bin/sh

set -eu

if [ "$#" -lt 3 ]; then
  printf '%s\n' 'Usage: firmware.sh out firmware_inventory firmware_source...' >&2
  exit 2
fi

output=$1
firmware_inventory=$2
shift 2

if [ ! -f "$firmware_inventory" ]; then
  printf 'Firmware inventory is not a regular file: %s\n' "$firmware_inventory" >&2
  exit 2
fi

for firmware_source in "$@"; do
  firmware_root=$firmware_source/lib/firmware
  if [ ! -d "$firmware_root" ]; then
    printf 'Firmware source directory does not exist: %s\n' "$firmware_root" >&2
    exit 2
  fi
done

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

  target_file=$output/lib/firmware/$firmware_path

  for firmware_source in "$@"; do
    firmware_root=$firmware_source/lib/firmware
    source_file=$firmware_root/$firmware_path
    if [ -f "$source_file" ]; then
      mkdir -p "$(dirname "$target_file")"
      cp "$source_file" "$target_file"
      chmod 0444 "$target_file"
      break
    elif [ -f "$source_file.zst" ]; then
      mkdir -p "$(dirname "$target_file")"
      zstd --decompress --stdout -- "$source_file.zst" > "$target_file"
      chmod 0444 "$target_file"
      break
    fi
  done
done < "$firmware_inventory"
