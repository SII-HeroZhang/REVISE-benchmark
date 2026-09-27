# Benchmark handoff: reproduce and extend the two workflows

This is the operating guide for a colleague taking over the large-scale
benchmark. All code paths are relative to this repository; all large inputs
and outputs remain under a separate data/work root. The qz data root below
already contains a completed P1CRC run. A new server must first stage the
same inputs and compatible environments.

## 1. Establish the two roots

```bash
export BENCHMARK_ROOT=/inspire/hdd/global_user/zhangyinghao-240107100021/REVISE_benchmark
mkdir -p "$BENCHMARK_ROOT/code"
git clone https://github.com/SII-HeroZhang/REVISE-benchmark.git "$BENCHMARK_ROOT/code/REVISE-benchmark"
export CODE_ROOT="$BENCHMARK_ROOT/code/REVISE-benchmark"
git -C "$CODE_ROOT" rev-parse HEAD
mkdir -p "$BENCHMARK_ROOT/misseg"
```

Save the printed benchmark commit with every analysis. The same commands work
from any working directory once `BENCHMARK_ROOT` and `CODE_ROOT` are set.
The code may also be checked out elsewhere. Existing qz outputs can be
verified without retraining; the full runner skips completed stages.

## 2. Stage data and fixed method revisions

```bash
# Public 10x images and Visium HD files; large downloads are resumable.
bash "$CODE_ROOT/scripts/download_public_data.sh" all

# Five pinned upstream method checkouts and two adapter patches.
bash "$CODE_ROOT/scripts/clone_methods.sh"
cargo build --release --manifest-path \
  "$BENCHMARK_ROOT/misseg/methods/proseg/Cargo.toml"
```

The spot cases are from the released REVISE Sim2Real-ST archive and must be
placed under `$BENCHMARK_ROOT/spot/part{1,2,3}`. Each part needs
`selected_xenium.h5ad`, `real_sc_ref_part.h5ad`, and
`spot_{50,100,150,200}/xenium_spot.h5ad`. The public Xenium H&E image and
alignment CSV downloaded above go at the data root. The independent
`$BENCHMARK_ROOT/misseg/for_mis_seg.zip` contains the annotated
`adata_sc_all_reanno.h5ad`; extract that file into the mis-seg root:

```bash
unzip -n "$BENCHMARK_ROOT/misseg/for_mis_seg.zip" \
  adata_sc_all_reanno.h5ad -d "$BENCHMARK_ROOT/misseg"
```

The old zip's `P1CRC_HD.h5ad` is an 8 µm **bin** matrix. The default
mis-segmentation workflow uses H&E nucleus-derived cells instead. Keep these
protocols separate. Do not commit any archive, raw image, reference,
checkpoint, or generated matrix to this Git repository.

The pinned revisions are REVISE `c83dc97`, iStar `3cb0e53`, TESLA `8c4dcf8`,
Proseg `4caa6f3`, and SPLIT `e880e39`. Full SHA values are in
`scripts/clone_methods.sh`. The iStar patch limits shared-node CPU thread
contention. The Proseg patch corrects Visium HD row/column-to-x/y mapping.
The completed qz REVISE checkout was `01d639f`, which adds an earlier
benchmark handoff on top of `c83dc97`; no upstream model or route files
changed in that commit. A fresh setup pins the model base `c83dc97`.

## 3. Environments and checkpoints

On the tested qz image, these existing executables were used:

| Role | Executable | Main pinned packages |
| --- | --- | --- |
| Spot TESLA/iStar | `$BENCHMARK_ROOT/envs/baselines/bin/python` | Python 3.10, PyTorch 2.5.1, NumPy 1.26.4, AnnData 0.11.4, Scanpy 1.11.5, pyvips 3.1.1; additional versions in the [spot guide](benchmark/spot_sr/README.md) |
| REVISE and common mis-seg steps | `$BENCHMARK_ROOT/envs/revise/bin/python` | Same qz base, POT 0.9.5, Squidpy 1.6.5, scikit-misc 0.5.2 |
| StarDist | `$BENCHMARK_ROOT/misseg/envs/stardist/bin/python` | StarDist and compatible TensorFlow, tifffile, zarr |
| ResolVI | `$BENCHMARK_ROOT/misseg/envs/resolvi/bin/python` | scvi-tools 1.3.3 and PyTorch |
| SPLIT/RCTD | `$BENCHMARK_ROOT/misseg/envs/split/bin/Rscript` | SPLIT 0.3.0 and spacexr 2.2.1 |

These are verified qz environment paths, not a cross-platform lockfile. On a
fresh machine, install each upstream method's declared dependencies and
confirm all five executables import their libraries before a long run.
The existing qz baseline and REVISE venvs inherit `/opt/conda/envs/spacec`.
A compatible qz rebuild of those two environments is documented in the
[spot guide](benchmark/spot_sr/README.md). Keep NumPy 1.26.4 there; an
unconstrained Squidpy install previously upgraded it to an incompatible 2.x.
For SPLIT, install the pinned source after `spacexr` in the R environment,
then verify `library(Matrix); library(spacexr); library(SPLIT)`.

iStar also requires the official HIPT `vit256_small_dino.pth` and
`vit4k_xs_dino.pth` under `$BENCHMARK_ROOT/methods/istar/checkpoints/`.
Their tested SHA-256 values and the [HIPT source](https://github.com/mahmoodlab/HIPT)
are recorded in the spot guide. The original iStar Box links were unavailable
for the completed run.

## 4. Execute spot super-resolution

```bash
bash "$CODE_ROOT/benchmark/spot_sr/run_all.sh" prepare
bash "$CODE_ROOT/benchmark/spot_sr/run_all.sh" tesla
GPU=0 bash "$CODE_ROOT/benchmark/spot_sr/run_all.sh" istar

"$BENCHMARK_ROOT/envs/baselines/bin/python" \
  "$CODE_ROOT/benchmark/spot_sr/summarize.py" \
  --prepared "$BENCHMARK_ROOT/prepared" \
  --output "$BENCHMARK_ROOT/results/baselines_summary.csv"
"$BENCHMARK_ROOT/envs/baselines/bin/python" \
  "$CODE_ROOT/benchmark/spot_sr/validate_results.py" \
  --prepared "$BENCHMARK_ROOT/prepared" \
  --output "$BENCHMARK_ROOT/results/validation.json"
```

For a failed case, use `PARTS=part2 SIZES=200` before a runner command;
valid completed cases are skipped. The standard matrix is 3 regions × 4
spot sizes × 2 baselines, 324 genes per case. TESLA/iStar use pseudo-spot
counts and H&E. Held-out Xenium expression is used for scoring; cell
coordinates also define the image crop and prediction sampling positions.
Inspect each new sample's `prepared/<part>/he-raw.jpg` and transform metadata
for correct image alignment before interpreting scores.

REVISE's upstream route needs the **original** full reference and PM prior
for an exact input reproduction. The released spot subset lacked both. If
only a runtime and code-path pilot is needed, construct and clearly label
adapted inputs:

```bash
"$BENCHMARK_ROOT/envs/revise/bin/python" \
  "$CODE_ROOT/benchmark/spot_sr/prepare_revise_reference.py" \
  --spot-root "$BENCHMARK_ROOT/spot"
"$BENCHMARK_ROOT/envs/revise/bin/python" \
  "$CODE_ROOT/benchmark/spot_sr/prepare_revise_pm.py" \
  --spot-root "$BENCHMARK_ROOT/spot" --seed 0
PARTS='part1 part2 part3' bash "$CODE_ROOT/benchmark/spot_sr/run_revise.sh"
```

The PM helper refuses to overwrite an existing prior without `--force`.
The adapted route was tested for two single cases and all four `part2` sizes;
it is not the paper's exact input set. See the spot guide for metric
definitions, detailed runtime boundaries, and existing summary CSVs.

## 5. Execute mis-segmentation

```bash
GPU=0 PROSEG_THREADS=48 SPLIT_THREADS=16 \
  bash "$CODE_ROOT/benchmark/misseg/run_full_pipeline.sh" all

# Read-only verification after an existing full run:
bash "$CODE_ROOT/benchmark/misseg/run_full_pipeline.sh" verify
```

The pipeline runs StarDist, Proseg, raw nucleus-cell aggregation, ResolVI,
corrected-count export, SPLIT input preparation, RCTD/SPLIT, AnnData
conversion, and verification. Results and completion markers are under
`$BENCHMARK_ROOT/misseg/results/`; logs go to `full_pipeline.log`.
The current script is sequential. The original qz run exported ResolVI
corrected counts alongside SPLIT, so its elapsed wall time is shorter than
a sequential sum. Each stage can be invoked by name for troubleshooting.

The final report is `results/full_verification.json`. Inspect it together
with `results/common/proseg_cell_correspondence.parquet` and
`proseg_gene_correspondence.parquet` before a shared-cell/gene comparison.
The completed qz run produced 226,214 Proseg cells, 199,317 ResolVI cells,
and 8,344 SPLIT cells from 10,000 sampled inputs. The methods have different
input and output contracts; keep their coverage counts next to any metric.

## 6. What remains before a large-scale performance paper

The spot baselines are scored and their 24 small-case artifacts validated.
The mis-segmentation **method outputs** are validated, but the historical
ARI/NMI/Moran's I evaluation code was absent from `for_mis_seg.zip`. Recreate
and review a shared scoring protocol before reporting those performance
numbers. In particular, define cell correspondence, gene intersection,
cell-type ground truth, spatial graph, and any 10,000-cell sampling rule.

For each new sample, save an input manifest with sample ID, data origin,
image scale/alignment, reference choice, gene panel, cell selection rule,
method commits, benchmark commit, random seeds, hardware, CPU/GPU thread
limits, output dimensions, and file checksums. Record preprocessing,
shared image-feature extraction, model runtime, and scoring separately.
Do not combine TESLA/iStar and adapted REVISE timing into a single speed
ranking without explaining their different inputs and measurement windows.
