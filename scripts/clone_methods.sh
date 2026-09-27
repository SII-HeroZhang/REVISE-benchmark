#!/usr/bin/env bash
# Clone tested upstream revisions into the benchmark data/work directory.
set -euo pipefail

DATA_ROOT=$(cd "${BENCHMARK_ROOT:-$PWD}" && pwd -P)
MISSEG_ROOT=${MISSEG_ROOT:-"$DATA_ROOT/misseg"}
CODE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$DATA_ROOT/methods" "$MISSEG_ROOT/methods"

clone_at() {
  local url=$1 target=$2 commit=$3
  if [[ ! -d "$target/.git" ]]; then
    git clone "$url" "$target"
  fi
  if [[ "$(git -C "$target" rev-parse HEAD)" != "$commit" ]]; then
    git -C "$target" fetch origin "$commit"
    git -C "$target" checkout --detach "$commit"
  fi
  echo "$target: $(git -C "$target" rev-parse HEAD)"
}

apply_once() {
  local target=$1 patch=$2
  if git -C "$target" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "Patch already applied: $patch"
  else
    git -C "$target" apply --check "$patch"
    git -C "$target" apply "$patch"
    echo "Applied patch: $patch"
  fi
}

clone_at https://github.com/wuys13/REVISE.git "$DATA_ROOT/methods/REVISE" c83dc97d25b6d513b59cc301255e5bdc7e9c7cd9
clone_at https://github.com/daviddaiweizhang/istar.git "$DATA_ROOT/methods/istar" 3cb0e5352a86df337f41c5841d0808da0003457b
clone_at https://github.com/jianhuupenn/TESLA.git "$DATA_ROOT/methods/TESLA" 8c4dcf896497dd4a34a6e720f03ec68c1502d571
clone_at https://github.com/dcjones/proseg.git "$MISSEG_ROOT/methods/proseg" 4caa6f33d13133374f66b20ec5775f0c027806be
clone_at https://github.com/bdsc-tds/SPLIT.git "$MISSEG_ROOT/methods/SPLIT" e880e39c03a7036e11c9867701c76fdb26acc14c

apply_once "$DATA_ROOT/methods/istar" "$CODE_ROOT/benchmark/spot_sr/istar_thread_limit.patch"
apply_once "$MISSEG_ROOT/methods/proseg" "$CODE_ROOT/benchmark/misseg/proseg-coordinate-fix.patch"
echo "Build Proseg with: cargo build --release --manifest-path \"$MISSEG_ROOT/methods/proseg/Cargo.toml\""
