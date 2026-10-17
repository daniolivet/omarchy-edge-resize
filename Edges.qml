import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Each edge: { vertical, a (left/top window), t (window we resize), cx, cy, len, gap }
  property var edges: []

  readonly property int span: 160
  readonly property real minShare: 0.25   // smallest share either window can get

  function refresh() {
    if (!poll.running) poll.running = true
  }

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

  Process {
    id: poll
    command: ["sh", "-c", "echo \"{\\\"c\\\":$(hyprctl -j clients),\\\"w\\\":$(hyprctl -j activeworkspace)}\""]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          // Don't rebuild the handles while one is being dragged.
          if (root.dragging) return
          var next = root.computeEdges(d.c, d.w.id)
          if (JSON.stringify(next) !== JSON.stringify(root.edges)) root.edges = next
          root.settlingWin = null
        } catch (e) {}
      }
    }
  }

  property bool dragging: false
  property var settlingWin: null   // the handle that was just released, until the new layout arrives
  property bool animationsWere: true
  property bool smartResizingWas: true
  readonly property int grab: 5   // extra px on each side of the gap that also grab

  // While dragging: animations off so the resize doesn't trail the cursor, and
  // dwindle smart_resizing off so Hyprland always moves window A's right/bottom
  // edge (smart resizing picks the edge from the cursor and can move the wrong
  // side of a middle window).
  function beginDrag() {
    dragging = true
    animProbe.running = true
  }
  function endDrag(w) {
    dragging = false
    settlingWin = w
    settleGuard.restart()
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ animations = { enabled = " + animationsWere
      + " }, dwindle = { smart_resizing = " + smartResizingWas + " } })"])
    settle.restart()
  }

  Process {
    id: animProbe
    command: ["sh", "-c", "echo \"[$(hyprctl -j getoption animations:enabled),$(hyprctl -j getoption dwindle:smart_resizing)]\""]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var o = JSON.parse(text)
          root.animationsWere = o[0].int === 1
          root.smartResizingWas = o[1].int === 1
        } catch (e) {
          root.animationsWere = true
          root.smartResizingWas = true
        }
        if (root.dragging)
          Quickshell.execDetached(["hyprctl", "eval", "hl.config({ animations = { enabled = false }, dwindle = { smart_resizing = false } })"])
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { debounce.restart() }
  }
  Timer { id: debounce; interval: 60; onTriggered: root.refresh() }
  Timer { id: settle; interval: 150; onTriggered: root.refresh() }
  // Never leave a released handle hanging if the layout read fails.
  Timer { id: settleGuard; interval: 800; onTriggered: root.settlingWin = null }

  Variants {
    model: root.edges

    PanelWindow {
      id: win
      required property var modelData
      readonly property bool vertical: modelData.vertical

      // Full-screen surface so the handle can follow the cursor anywhere;
      // the mask limits input to the gap itself.
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-edge-resize"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region { item: hit }

      property real target: 0     // requested size of window A along the drag axis
      property real realSize: 0   // size Hyprland actually gave window A
      property real pending: -1
      property real sent: 0       // size of window A as of our last dispatch

      readonly property bool settling: root.settlingWin === win

      // Center of the handle along the drag axis, following the cursor while dragging.
      readonly property real axisCenter: {
        if (!area.pressed && !win.settling) return vertical ? modelData.cx : modelData.cy
        var start = vertical ? modelData.ax : modelData.ay
        return start + realSize + modelData.gap / 2
      }

      // Position along the edge, following the cursor and kept inside the edge.
      property real crossPos: vertical ? modelData.cy : modelData.cx
      readonly property real crossCenter: {
        var half = Style.space(40)
        var lo = (vertical ? modelData.cy : modelData.cx) - modelData.len / 2 + half
        var hi = (vertical ? modelData.cy : modelData.cx) + modelData.len / 2 - half
        return Math.max(lo, Math.min(hi, crossPos))
      }

      Item {
        id: hit
        x: win.vertical ? win.modelData.cx - win.modelData.gap / 2 - root.grab : win.modelData.cx - win.modelData.len / 2
        y: win.vertical ? win.modelData.cy - win.modelData.len / 2 : win.modelData.cy - win.modelData.gap / 2 - root.grab
        width: win.vertical ? win.modelData.gap + root.grab * 2 : win.modelData.len
        height: win.vertical ? win.modelData.len : win.modelData.gap + root.grab * 2

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: win.vertical ? Qt.SplitHCursor : Qt.SplitVCursor

          onPressed: (m) => {
            var m2 = win.modelData
            win.target = win.vertical ? m2.aw : m2.ah
            win.realSize = win.target
            win.sent = win.target
            root.beginDrag()
          }
          onReleased: root.endDrag(win)
          onPositionChanged: (m) => {
            if (!pressed) {
              win.crossPos = win.vertical ? hit.y + m.y : hit.x + m.x
              return
            }
            var m2 = win.modelData
            var screenPos = win.vertical ? hit.x + m.x : hit.y + m.y
            var start = win.vertical ? m2.ax : m2.ay
            var total = (win.vertical ? m2.aw : m2.ah) + m2.bsize
            var minSize = total * root.minShare
            win.target = Math.max(minSize, Math.min(total - minSize, screenPos - m2.gap / 2 - start))
            win.pending = win.target
            if (!flush.running) flush.start()
          }
        }
      }

      Timer {
        id: flush
        interval: 16
        onTriggered: {
          if (win.pending < 0) return
          var m = win.modelData
          var delta = Math.round(win.pending - win.sent)
          win.pending = -1
          if (delta === 0) return
          win.sent += delta
          // A positive delta moves the shared edge right/down whichever of
          // the two windows we resize.
          var x = win.vertical ? delta : 0
          var y = win.vertical ? 0 : delta
          Hyprland.dispatch("hl.dsp.window.resize({ x = " + x + ", y = " + y + ", relative = true, window = \"address:" + m.t + "\" })")
        }
      }

      // While dragging, read window A's real size back so the handle sits on
      // the actual border, not wherever the cursor went.
      Timer {
        interval: 33
        repeat: true
        running: area.pressed || win.settling
        onTriggered: {
          var list = Hyprland.toplevels.values
          for (var i = 0; i < list.length; i++) {
            var t = list[i]
            if (t.address !== win.modelData.a && "0x" + t.address !== win.modelData.a) continue
            var o = t.lastIpcObject
            if (o && o.size) win.realSize = win.vertical ? o.size[0] : o.size[1]
            break
          }
          Hyprland.refreshToplevels()
        }
      }

      // The handle: a pill centered on the gap, visible on hover or drag.
      Rectangle {
        readonly property bool active: area.containsMouse || area.pressed
        width: win.vertical ? Style.space(area.pressed ? 8 : 6) : Style.space(80)
        height: win.vertical ? Style.space(80) : Style.space(area.pressed ? 8 : 6)
        radius: Math.min(width, height) / 2
        color: Color.accent
        opacity: active ? 0.95 : 0
        x: win.vertical ? win.axisCenter - width / 2 : win.crossCenter - width / 2
        y: win.vertical ? win.crossCenter - height / 2 : win.axisCenter - height / 2
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      // Live share of each window while dragging: side by side for a vertical
      // edge, stacked top/bottom for a horizontal one, next to the pill.
      Rectangle {
        visible: area.pressed || win.settling
        width: label.implicitWidth + Style.space(24)
        height: label.implicitHeight + Style.space(14)
        radius: Math.max(Style.cornerRadius, Style.space(8))
        color: Util.alpha(Color.background, 0.97)
        border.color: Color.accent
        border.width: Math.max(1, Style.space(2))
        x: win.vertical ? win.axisCenter + win.modelData.gap / 2 + Style.space(10) : win.crossCenter + Style.space(50)
        y: win.vertical ? win.crossCenter - height / 2 : win.axisCenter - height / 2
        Text {
          id: label
          anchors.centerIn: parent
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.StyledText
          font.weight: Font.DemiBold
          lineHeight: 1.1
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          color: Color.popups.text
          text: {
            var m = win.modelData
            var total = (win.vertical ? m.aw : m.ah) + m.bsize
            var a = Math.round(win.realSize / total * 100)
            var sep = "<font color=\"" + Color.accent + "\">·</font>"
            return win.vertical ? a + "%&nbsp;&nbsp;" + sep + "&nbsp;&nbsp;" + (100 - a) + "%"
                                : a + "%<br>" + sep + "<br>" + (100 - a) + "%"
          }
        }
      }
    }
  }
}
