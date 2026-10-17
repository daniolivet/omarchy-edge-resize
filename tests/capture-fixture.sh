#!/usr/bin/env bash
# Guarda el layout de un workspace como fixture para los tests de geometría.
# Uso: tests/capture-fixture.sh <nombre> [workspace]   (por defecto, el activo)
set -euo pipefail

name=${1:?uso: $0 <nombre> [workspace]}
workspace=${2:-$(hyprctl -j activeworkspace | node -e 'console.log(JSON.parse(require("fs").readFileSync(0)).id)')}
out="$(dirname -- "${BASH_SOURCE[0]}")/fixtures/$name.json"

# Solo los campos que lee computeEdges: sin títulos ni clases de ventana.
node -e '
  const [clients, workspaceId] = process.argv.slice(1).map(JSON.parse)
  const keep = (c) => ({
    address: c.address, at: c.at, size: c.size, mapped: c.mapped, hidden: c.hidden,
    floating: c.floating, fullscreen: c.fullscreen, workspace: { id: c.workspace.id },
  })
  console.log(JSON.stringify({ workspaceId, clients: clients.map(keep) }, null, 2))
' "$(hyprctl -j clients)" "$workspace" > "$out"

echo "guardado: $out"
