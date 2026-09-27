#!/usr/bin/env bash
# Download public 10x images and Visium HD input into BENCHMARK_ROOT.
# The released REVISE spot archive and scRNA reference must be supplied separately.
set -euo pipefail

DATA_ROOT=$(cd "${BENCHMARK_ROOT:-$PWD}" && pwd -P)
MODE=${1:-all}
case "$MODE" in spot|misseg|all) ;; *) echo "Usage: $0 [spot|misseg|all]" >&2; exit 2 ;; esac

download() {
  local url=$1 dest=$2
  local remote_size local_size
  mkdir -p "$(dirname "$dest")"
  remote_size=$(curl -fsSLI --retry 5 "$url" | awk 'tolower($1)=="content-length:" {gsub("\r", "", $2); size=$2} END {print size}')
  [[ "$remote_size" =~ ^[0-9]+$ ]] || { echo "Cannot determine source size: $url" >&2; return 1; }
  local_size=0
  [[ ! -e "$dest" ]] || local_size=$(wc -c < "$dest" | tr -d '[:space:]')
  if [[ "$local_size" == "$remote_size" ]]; then
    echo "Using existing file: $dest"
    return
  fi
  (( local_size < remote_size )) || { echo "Local file exceeds source size: $dest" >&2; return 1; }
  curl -fL -C - --retry 10 --retry-delay 15 -o "$dest" "$url"
  local_size=$(wc -c < "$dest" | tr -d '[:space:]')
  [[ "$local_size" == "$remote_size" ]] || { echo "Incomplete download: $dest ($local_size/$remote_size bytes)" >&2; return 1; }
}

if [[ "$MODE" == spot || "$MODE" == all ]]; then
  sample=Xenium_V1_Human_Colon_Cancer_P1_CRC_Add_on_FFPE
  base="https://cf.10xgenomics.com/samples/xenium/2.0.0/$sample"
  download "$base/${sample}_he_image.ome.tif" "$DATA_ROOT/${sample}_he_image.ome.tif"
  download "$base/${sample}_he_imagealignment.csv" "$DATA_ROOT/${sample}_he_imagealignment.csv"
fi

if [[ "$MODE" == misseg || "$MODE" == all ]]; then
  sample=Visium_HD_Human_Colon_Cancer_P1
  base="https://cf.10xgenomics.com/samples/spatial-exp/3.0.0/$sample"
  target="$DATA_ROOT/misseg/raw_p1crc"
  for suffix in binned_outputs.tar.gz spatial.tar.gz tissue_image.btf; do
    download "$base/${sample}_${suffix}" "$target/${sample}_${suffix}"
  done
  [[ -s "$target/binned_outputs/square_002um/filtered_feature_bc_matrix.h5" ]] || \
    tar -xzf "$target/${sample}_binned_outputs.tar.gz" -C "$target"
  [[ -s "$target/spatial/tissue_hires_image.png" ]] || \
    tar -xzf "$target/${sample}_spatial.tar.gz" -C "$target"
fi

echo "Public data ready under $DATA_ROOT"
