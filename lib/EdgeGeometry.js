.pragma library

// Each edge: { vertical, a (left/top window), t (window we resize), cx, cy, len, gap }
function computeEdges(clients, wsId) {
  var ws = clients.filter(function (c) {
    return c.mapped && !c.hidden && !c.floating && c.workspace.id === wsId
  })
  if (ws.some(function (c) { return c.fullscreen > 0 })) return []
  // Left/top bounds of the workspace, to tell which windows sit against the screen edge.
  var minX = Math.min.apply(null, ws.map(function (c) { return c.at[0] }))
  var minY = Math.min.apply(null, ws.map(function (c) { return c.at[1] }))
  // Which window to resize so Hyprland moves the shared edge: one whose other
  // side is against the screen edge only has that one edge free to move.
  function pick(a, b, vertical) {
    if ((vertical ? a.at[0] : a.at[1]) <= (vertical ? minX : minY)) return a.address
    return b.address
  }
  var out = []
  for (var i = 0; i < ws.length; i++) {
    for (var j = 0; j < ws.length; j++) {
      if (i === j) continue
      var a = ws[i], b = ws[j]
      var gapX = b.at[0] - (a.at[0] + a.size[0])
      var top = Math.max(a.at[1], b.at[1])
      var bottom = Math.min(a.at[1] + a.size[1], b.at[1] + b.size[1])
      if (gapX > 0 && gapX <= 40 && bottom - top > 60) {
        out.push({ vertical: true, a: a.address, t: pick(a, b, true), ax: a.at[0], ay: a.at[1], aw: a.size[0], ah: a.size[1], bsize: b.size[0],
                   cx: a.at[0] + a.size[0] + gapX / 2, cy: (top + bottom) / 2, len: bottom - top, gap: gapX })
      }
      var gapY = b.at[1] - (a.at[1] + a.size[1])
      var left = Math.max(a.at[0], b.at[0])
      var right = Math.min(a.at[0] + a.size[0], b.at[0] + b.size[0])
      if (gapY > 0 && gapY <= 40 && right - left > 60) {
        out.push({ vertical: false, a: a.address, t: pick(a, b, false), ax: a.at[0], ay: a.at[1], aw: a.size[0], ah: a.size[1], bsize: b.size[1],
                   cx: (left + right) / 2, cy: a.at[1] + a.size[1] + gapY / 2, len: right - left, gap: gapY })
      }
    }
  }
  return out
}
