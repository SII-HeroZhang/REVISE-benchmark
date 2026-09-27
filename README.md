# REVISE-benchmark

Reproducible adapters and handoff material for two benchmarks associated with
[REVISE](https://github.com/wuys13/REVISE): spot super-resolution and
mis-segmentation correction. This repository contains runnable code, fixed
upstream revisions, validation scripts, and small result summaries. It does
not redistribute 10x data, the supplied scRNA reference, model checkpoints,
or cell-level predictions.

| Workflow | Dataset and methods | Entry point | Status |
| --- | --- | --- | --- |
| [Spot super-resolution](benchmark/spot_sr/README.md) | P1CRC Sim2Real-ST, 3 regions × 4 spot sizes; TESLA, iStar, adapted REVISE | `benchmark/spot_sr/run_all.sh` | TESLA and iStar: 24/24 runs validated; REVISE: adapted pilot only |
| [Mis-segmentation](benchmark/misseg/README.md) | Visium HD Human Colon Cancer P1; Proseg, ResolVI, SPLIT | `benchmark/misseg/run_full_pipeline.sh` | Full three-method run and artifact validation completed on qz |

The [handoff guide](HANDOFF.md) gives the exact server paths, download and
setup commands, run order, expected outputs, and limits of the current
results. Start there when transferring the benchmark to another person.

## Quick start on qz

```bash
export BENCHMARK_ROOT=/inspire/hdd/global_user/zhangyinghao-240107100021/REVISE_benchmark
mkdir -p "$BENCHMARK_ROOT/code"
git clone https://github.com/SII-HeroZhang/REVISE-benchmark.git "$BENCHMARK_ROOT/code/REVISE-benchmark"
export CODE_ROOT="$BENCHMARK_ROOT/code/REVISE-benchmark"

# Inspect and prepare inputs as described in HANDOFF.md, then:
bash "$CODE_ROOT/benchmark/spot_sr/run_all.sh" prepare
bash "$CODE_ROOT/benchmark/spot_sr/run_all.sh" tesla
GPU=0 bash "$CODE_ROOT/benchmark/spot_sr/run_all.sh" istar
bash "$CODE_ROOT/benchmark/misseg/run_full_pipeline.sh" all
```

`BENCHMARK_ROOT` is the data and output directory. `CODE_ROOT` is this Git
checkout. Every workflow accepts path overrides; both can be moved to other
machines without editing source paths.

## Scientific interpretation

The workflows are separate experiments. Spot super-resolution is scored
against held-out Xenium cell expression. Mis-segmentation currently has
verified output matrices and cell correspondence tables, but the historical
ARI, NMI, and Moran's I evaluation implementation was not available in the
supplied archive. The current mis-segmentation run is therefore a method
reproduction and output audit, **not** a reconstructed performance ranking.

The two spot baselines consume image and spot counts. The adapted REVISE
route additionally uses cell locations and spot membership, and its missing
full reference and prior were reconstructed. Report its pilot separately
from a strict reproduction of the published benchmark.

## Repository layout

```text
benchmark/spot_sr/      input conversion, TESLA/iStar/REVISE runs, scoring
benchmark/misseg/       StarDist, Proseg, ResolVI, SPLIT, output verification
scripts/                public data download and pinned upstream checkouts
HANDOFF.md              complete English transfer guide
LICENSE                 MIT license, preserving the original REVISE notice
```
