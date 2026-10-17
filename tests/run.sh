#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node "$project_dir/tests/geometry.test.js"
bash -n "$project_dir/tests/run.sh" "$project_dir/tests/capture-fixture.sh"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$project_dir"
fi
