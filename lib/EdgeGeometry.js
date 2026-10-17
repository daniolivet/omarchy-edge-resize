.pragma library

// Shared edges between the tiled windows of a workspace.

const MAX_GAP = 40      // widest gap between two windows that still counts as a shared edge (px)
const MIN_OVERLAP = 60  // how much the two windows must overlap along the edge (px)
const MIN_SHARE = 0.25  // smallest share either window can be dragged down to
const AXES = [0, 1]     // 0: vertical edge, dragged along x; 1: horizontal edge, dragged along y

// Each edge, with every length measured along the drag axis unless it says otherwise:
// {
//   vertical,         // the edge runs top to bottom, so it is dragged along x
//   leftOrTopWindow,  // address of window A, the one before the gap
//   resizeTarget,     // address of the window to resize so Hyprland moves the edge
//   start, size,      // where window A starts and how big it is
//   total,            // size of both windows together
//   minSize,          // smallest size either window can be dragged down to
//   gapSize, center,  // the gap between the windows and its center
//   crossCenter,      // center of the edge along the edge itself
//   length,           // length of the edge (how much the two windows overlap)
// }
// Addresses are bare, without "0x": see bareAddress.
function findEdges(clients, workspaceId) {
  const windows = clients.filter(client =>
    client.mapped && !client.hidden && !client.floating && client.workspace.id === workspaceId)
  if (windows.some(window => window.fullscreen > 0)) return []
  // Left/top bounds of the workspace, to tell which windows sit against the screen edge.
  const workspaceStart = AXES.map(axis => Math.min(...windows.map(window => window.at[axis])))
  return uniquePairs(windows)
    .reduce((edges, [first, second]) => edges.concat(AXES.map(axis => edgeBetween(first, second, axis, workspaceStart))), [])
    .filter(Boolean)
}

// Plain JSON is enough: findEdges always builds the same keys in the same order.
function edgesEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

// The size window A ends up with when the cursor asks for `requested`,
// leaving each window at least its minimum share.
function clampSize(edge, requested) {
  return Math.max(edge.minSize, Math.min(edge.total - edge.minSize, requested))
}

// Share of window A, in whole percent, when it measures `size`.
function sharePercent(edge, size) {
  return Math.round(size / edge.total * 100)
}

// hyprctl reports addresses as "0x…" and Quickshell's toplevels without the
// prefix; edges keep them bare so a plain === compares them.
function bareAddress(address) {
  return address.replace(/^0x/, "")
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

  const total = a.size[axis] + b.size[axis]
  return {
    vertical: axis === 0,
    leftOrTopWindow: bareAddress(a.address),
    resizeTarget: bareAddress(resizeTargetFor(a, b, axis, workspaceStart)),
    start: a.at[axis],
    size: a.size[axis],
    total,
    minSize: total * MIN_SHARE,
    gapSize: gap,
    center: a.at[axis] + a.size[axis] + gap / 2,
    crossCenter: (overlapStart + overlapEnd) / 2,
    length: overlap,
  }
}

// Which window to resize so Hyprland moves the shared edge: one whose other
// side is against the screen edge only has that one edge free to move.
function resizeTargetFor(a, b, axis, workspaceStart) {
  return a.at[axis] <= workspaceStart[axis] ? a.address : b.address
}
