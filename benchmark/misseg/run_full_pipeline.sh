#!/usr/bin/env bash
# Run or resume the P1CRC mis-segmentation benchmark from a separate code checkout.
set -euo pipefail

DATA_ROOT=$(cd "${BENCHMARK_ROOT:-$PWD}" && pwd -P)
ROOT=${MISSEG_ROOT:-"$DATA_ROOT/misseg"}
SCRIPT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
RESULTS="$ROOT/results"
MASK="$RESULTS/proseg/p1crc_stardist_masks.npy.gz"
PY=${MISSEG_PYTHON:-"$DATA_ROOT/envs/revise/bin/python"}
STARDIST_PYTHON=${STARDIST_PYTHON:-"$ROOT/envs/stardist/bin/python"}
RESOLVI_PYTHON=${RESOLVI_PYTHON:-"$ROOT/envs/resolvi/bin/python"}
SPLIT_RSCRIPT=${SPLIT_RSCRIPT:-"$ROOT/envs/split/bin/Rscript"}
PROSEG_BINARY=${PROSEG_BINARY:-"$ROOT/methods/proseg/target/release/proseg"}
PROSEG_THREADS=${PROSEG_THREADS:-48}
SPLIT_THREADS=${SPLIT_THREADS:-16}
GPU=${GPU:-0}
MODE=${1:-all}

case "$MODE" in
  all|segment|proseg|aggregate|resolvi|resolvi_corrected|split_inputs|split|split_h5ad|verify) ;;
  *) echo "Usage: $0 [all|segment|proseg|aggregate|resolvi|resolvi_corrected|split_inputs|split|split_h5ad|verify]" >&2; exit 2 ;;
esac

mkdir -p "$RESULTS"
exec > >(tee -a "$RESULTS/full_pipeline.log") 2>&1
trap 'status=$?; echo "$(date -Is) FAILED (exit $status) at: $BASH_COMMAND"; exit "$status"' ERR
echo "$(date -Is) Data: $ROOT; code: $SCRIPT; mode: $MODE"

require_file() {
  local path
  for path in "$@"; do
    [[ -e "$path" ]] || { echo "Missing required input: $path" >&2; return 1; }
  done
}

run_stage() {
  local stage=$1 output=$2
  shift 2
  if [[ -e "$RESULTS/.$stage.done" ]]; then
    require_file "$output"
    echo "$(date -Is) SKIP $stage (completed output exists)"
    return
  fi
  echo "$(date -Is) START $stage"
  "$@"
  require_file "$output"
  touch "$RESULTS/.$stage.done"
  echo "$(date -Is) DONE $stage"
}

selected() { [[ "$MODE" == all || "$MODE" == "$1" ]]; }

if selected segment; then
  require_file "$STARDIST_PYTHON" "$ROOT/raw_p1crc/Visium_HD_Human_Colon_Cancer_P1_tissue_image.btf"
  if [[ -s "$MASK" && -s "${MASK%.gz}.json" ]]; then
    echo "$(date -Is) SKIP segment (mask and transform exist)"
  else
    "$STARDIST_PYTHON" "$SCRIPT/segment_p1crc_he.py" \
      --image "$ROOT/raw_p1crc/Visium_HD_Human_Colon_Cancer_P1_tissue_image.btf" \
      --output "$MASK" --microns-per-pixel 0.27380817798463214 \
      --x0 0 --y0 11000 --x1 26000 --y1 38000 \
      --downsample 2 --block-size 2048
    require_file "$MASK" "${MASK%.gz}.json"
  fi
fi

if selected proseg; then
  require_file "$PY" "$PROSEG_BINARY" "$MASK" "${MASK%.gz}.json" "$ROOT/raw_p1crc/binned_outputs"
  run_stage proseg "$RESULTS/proseg/full/counts.mtx.gz" \
    "$PY" "$SCRIPT/run_proseg.py" --binary "$PROSEG_BINARY" \
      --binned-outputs "$ROOT/raw_p1crc/binned_outputs" \
      --mask "$MASK" --output "$RESULTS/proseg/full" --nthreads "$PROSEG_THREADS"
fi

if selected aggregate; then
  require_file "$PY" "$MASK" "${MASK%.gz}.json" "$ROOT/raw_p1crc/binned_outputs"
  run_stage aggregate "$RESULTS/common/star_dist_cells_5um.h5ad" \
    "$PY" "$SCRIPT/aggregate_stardist_cells.py" \
      --binned-outputs "$ROOT/raw_p1crc/binned_outputs" \
      --mask "$MASK" --output "$RESULTS/common/star_dist_cells_5um.h5ad" \
      --max-expansion-um 5
fi

if selected resolvi; then
  require_file "$RESOLVI_PYTHON" "$RESULTS/common/star_dist_cells_5um.h5ad"
  run_stage resolvi "$RESULTS/resolvi/full/resolvi_latent.h5ad" \
    env CUDA_VISIBLE_DEVICES="$GPU" "$RESOLVI_PYTHON" "$SCRIPT/run_resolvi.py" \
      --input "$RESULTS/common/star_dist_cells_5um.h5ad" \
      --output "$RESULTS/resolvi/full" --epochs 100 --batch-size 256
fi

if selected resolvi_corrected; then
  require_file "$RESOLVI_PYTHON" "$RESULTS/resolvi/full/resolvi_latent.h5ad" "$RESULTS/resolvi/full/model"
  run_stage resolvi_corrected "$RESULTS/resolvi/full/resolvi_corrected_counts.h5ad" \
    env CUDA_VISIBLE_DEVICES="$GPU" "$RESOLVI_PYTHON" "$SCRIPT/export_resolvi_corrected.py" \
      --input "$RESULTS/resolvi/full/resolvi_latent.h5ad" \
      --model "$RESULTS/resolvi/full/model" \
      --output "$RESULTS/resolvi/full/resolvi_corrected_counts.h5ad" \
      --block-size 2048 --batch-size 256 --num-samples 3 --seed 42
fi

if selected split_inputs; then
  require_file "$PY" "$ROOT/adata_sc_all_reanno.h5ad" "$RESULTS/common/star_dist_cells_5um.h5ad"
  run_stage split_inputs "$RESULTS/split/full_input/manifest.json" \
    "$PY" "$SCRIPT/prepare_split_inputs.py" \
      --spatial "$RESULTS/common/star_dist_cells_5um.h5ad" \
      --reference "$ROOT/adata_sc_all_reanno.h5ad" \
      --output "$RESULTS/split/full_input" \
      --max-spatial-cells 10000 --max-reference-per-type 500 --seed 42
fi

if selected split; then
  require_file "$SPLIT_RSCRIPT" "$RESULTS/split/full_input/manifest.json"
  run_stage split "$RESULTS/split/full/split_result.rds" \
    "$SPLIT_RSCRIPT" "$SCRIPT/run_split.R" \
      "$RESULTS/split/full_input" "$RESULTS/split/full" "$SPLIT_THREADS"
fi

if selected split_h5ad; then
  require_file "$PY" "$RESULTS/split/full/split_result.rds"
  run_stage split_h5ad "$RESULTS/split/full/split_purified.h5ad" \
    "$PY" "$SCRIPT/convert_split_output.py" \
      --split-output "$RESULTS/split/full" \
      --split-input "$RESULTS/split/full_input" \
      --output "$RESULTS/split/full/split_purified.h5ad"
fi

if selected verify; then
  require_file "$PY"
  "$PY" "$SCRIPT/verify_full.py" --root "$ROOT"
  require_file "$RESULTS/full_verification.json"
  touch "$RESULTS/.verified.done"
fi

echo "$(date -Is) Completed $MODE"
