.pragma library

// Shared edges between the tiled windows of a workspace.

const MAX_GAP = 40      // widest gap between two windows that still counts as a shared edge (px)
const MIN_OVERLAP = 60  // how much the two windows must overlap along the edge (px)
const AXES = [0, 1]     // 0: vertical edge, dragged along x; 1: horizontal edge, dragged along y

// Each edge: { vertical, a (left/top window), t (window we resize), ax, ay, aw, ah (window a),
//              bsize (window b along the drag axis), cx, cy (center of the gap), len, gap }
function findEdges(clients, workspaceId) {
  const windows = clients.filter(c => c.mapped && !c.hidden && !c.floating && c.workspace.id === workspaceId)
  if (windows.some(c => c.fullscreen > 0)) return []
  // Left/top bounds of the workspace, to tell which windows sit against the screen edge.
  const workspaceStart = AXES.map(axis => Math.min(...windows.map(c => c.at[axis])))
  return uniquePairs(windows)
    .reduce((edges, [first, second]) => edges.concat(AXES.map(axis => edgeBetween(first, second, axis, workspaceStart))), [])
    .filter(Boolean)
}

// Plain JSON is enough: findEdges always builds the same keys in the same order.
function edgesEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

// Every unordered pair once: [w0, w1], [w0, w2], …, [w1, w2], …
function uniquePairs(list) {
  return list.reduce((pairs, first, i) => pairs.concat(list.slice(i + 1).map(second => [first, second])), [])
}

// The edge between two windows along one axis, or null if they don't share one.
function edgeBetween(first, second, axis, workspaceStart) {
  const cross = 1 - axis
  // Only the window that starts first can have the other one after its far side.
  const [a, b] = first.at[axis] <= second.at[axis] ? [first, second] : [second, first]
  const gap = b.at[axis] - (a.at[axis] + a.size[axis])
  const overlapStart = Math.max(a.at[cross], b.at[cross])
  const overlapEnd = Math.min(a.at[cross] + a.size[cross], b.at[cross] + b.size[cross])
  const overlap = overlapEnd - overlapStart
  if (gap <= 0 || gap > MAX_GAP || overlap <= MIN_OVERLAP) return null

  const vertical = axis === 0
  const gapCenter = a.at[axis] + a.size[axis] + gap / 2
  const overlapCenter = (overlapStart + overlapEnd) / 2
  return {
    vertical,
    a: a.address,
    t: resizeTargetFor(a, b, axis, workspaceStart),
    ax: a.at[0], ay: a.at[1], aw: a.size[0], ah: a.size[1],
    bsize: b.size[axis],
    cx: vertical ? gapCenter : overlapCenter,
    cy: vertical ? overlapCenter : gapCenter,
    len: overlap,
    gap,
  }
}

// Which window to resize so Hyprland moves the shared edge: one whose other
// side is against the screen edge only has that one edge free to move.
function resizeTargetFor(a, b, axis, workspaceStart) {
  return a.at[axis] <= workspaceStart[axis] ? a.address : b.address
}
