# P1CRC mis-segmentation benchmark

This workflow runs Proseg, ResolVI, and SPLIT on the same public 10x Genomics
Visium HD Human Colon Cancer P1 section. The pipeline creates a StarDist H&E
nucleus prior, runs Proseg on the full 2 µm binned output, aggregates raw
counts from the same nucleus prior for ResolVI and SPLIT, and validates all
three outputs. It is resumable at each stage.

## Input and output contracts

| Method | Input | Main output | Scope |
| --- | --- | --- | --- |
| Proseg | Full 2 µm bins, Space Ranger coordinates, StarDist H&E nucleus prior | Reassigned cell counts, cell metadata, spatial segmentation | Whole tissue |
| ResolVI | Uncorrected StarDist-aggregated cell counts and coordinates | Latent representation, normalized expression, corrected expected counts | Whole tissue |
| SPLIT | The same raw cell counts and coordinates, plus P1CRC scRNA reference | RCTD assignments and purified counts | Contiguous central sample of 10,000 cells |

These methods change different aspects of the input. Proseg changes cell
assignment; ResolVI models background and misassignment; SPLIT uses a
reference and RCTD to purify counts. Report input/output cell and gene counts
and common-cell comparisons explicitly. ResolVI's corrected counts are
continuous posterior estimates, not observed integer UMIs.

The required reference is `adata_sc_all_reanno.h5ad` from the supplied
`for_mis_seg.zip`. Only cells with `Patient == P1CRC` enter the SPLIT
reference. The old archive's `P1CRC_HD.h5ad` has 507,684 **8 µm bins**, not
507,684 segmented cells; it is a separate legacy input protocol and is not
used by the default full run.

## Data layout

```text
$BENCHMARK_ROOT/misseg/
  raw_p1crc/
    binned_outputs/
    spatial/
    Visium_HD_Human_Colon_Cancer_P1_tissue_image.btf
  adata_sc_all_reanno.h5ad
  methods/proseg/             patched source and release binary
  methods/SPLIT/              pinned R package source
  envs/{stardist,resolvi,split}/
  results/                    generated outputs and stage markers
$BENCHMARK_ROOT/envs/revise/  common Python environment
```

Run `scripts/download_public_data.sh misseg` from the repository to download
the 10x files. Obtain `adata_sc_all_reanno.h5ad` from the original supplied
archive; this repository cannot recreate that annotation or a strict SPLIT
run without it. `scripts/clone_methods.sh` pins Proseg and SPLIT and applies
the Proseg coordinate patch. Build Proseg with the command printed by that
script. Use [HANDOFF.md](../../HANDOFF.md) for environment and server setup.

## Run

```bash
export BENCHMARK_ROOT=/inspire/hdd/global_user/zhangyinghao-240107100021/REVISE_benchmark
export CODE_ROOT="$BENCHMARK_ROOT/code/REVISE-benchmark"

# One command resumes all stages and runs final verification.
GPU=0 PROSEG_THREADS=48 SPLIT_THREADS=16 \
  bash "$CODE_ROOT/benchmark/misseg/run_full_pipeline.sh" all

# An individual failed stage can be rerun after inspecting its log/output.
bash "$CODE_ROOT/benchmark/misseg/run_full_pipeline.sh" verify
```

The full command runs `segment → proseg → aggregate → resolvi →
resolvi_corrected → split_inputs → split → split_h5ad → verify` sequentially.
Completed stages are skipped only when their marker and main output both
exist. Its log is `$BENCHMARK_ROOT/misseg/results/full_pipeline.log`. To force
a stage rerun, remove its `.stage.done` marker **and inspect or move the old
output first**; downstream stages may then need rerunning. The script accepts
each stage name in place of `all`, and `MISSEG_ROOT`, `MISSEG_PYTHON`,
`STARDIST_PYTHON`, `RESOLVI_PYTHON`, `SPLIT_RSCRIPT`, and `PROSEG_BINARY` path
overrides.

The mask covers BTF pixels `x=0..26000, y=11000..38000`, downsampled by 2.
Its adjacent `p1crc_stardist_masks.npy.json` stores the mask-to-micron
transform and must stay with the mask. StarDist uses `prob_thresh=0.01` and
`nms_thresh=0.001`. Raw counts are aggregated up to 5 µm outside each nucleus.
SPLIT samples a contiguous 10,000-cell field, up to 500 reference cells per
type, with seed 42. ResolVI trains for 100 epochs with batch size 256.

The patched Proseg version is commit `4caa6f3` (v3.2.0). Its Visium HD reader
otherwise interchanges full-resolution pixel row and column when assigning
micron x/y, misaligning H&E nuclei. The patch uses column for x and row for y.
SPLIT is commit `e880e39` (v0.3.0); the tested ResolVI implementation is in
scvi-tools 1.3.3.

## Validation and current result

`verify_full.py` writes `results/full_verification.json`, checks matrix
dimensions and spatial coordinates, verifies the Proseg exit code and SPLIT
alignment, samples ResolVI corrected values, and creates Proseg-to-raw cell
and unambiguous gene correspondence tables in `results/common/`. Proseg has
three duplicate gene-symbol groups; the gene table excludes ambiguous names.

The completed qz run on 2026-09-27 produced:

| Stage | Result | Wall time |
| --- | --- | --- |
| Proseg | 226,214 cells × 18,965 genes | 1 h 41 min |
| Raw StarDist aggregation | 200,191 cells × 18,085 genes | 1 min 26 s |
| ResolVI | 199,317 cells × 18,041 genes | 1 h 42 min |
| Corrected-count export | Same ResolVI dimensions | about 1 h 31 min |
| SPLIT, including RCTD | 10,000 input → 8,344 retained cells × 18,071 genes | 3 h 59 min |

RCTD retained 8,344 of 8,876 cells above its default 100-UMI threshold;
the remaining 1,124 input cells were below that threshold. Of retained
cells, 6,080 were singlets, 1,503 certain doublets, and 761 uncertain
doublets. These are run outcomes, not accuracy metrics. The old ARI/NMI/
Moran's I scoring scripts were not in the supplied archive, so those metrics
have not been recomputed here. See [HANDOFF.md](../../HANDOFF.md) before
claiming a performance comparison.

The [official ResolVI tutorial](https://docs.scvi-tools.org/en/latest/tutorials/notebooks/spatial/resolVI_tutorial.html)
describes normalized expression and the corrected `px_rate` posterior used
for the separate corrected-count export.
