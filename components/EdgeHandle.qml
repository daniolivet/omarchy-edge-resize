import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../lib/EdgeGeometry.js" as EdgeGeometry

// The draggable handle over one edge from EdgeGeometry.findEdges.
// Full-screen surface so the handle can follow the cursor anywhere;
// the mask limits input to the gap itself.
PanelWindow {
  id: handle

  required property var modelData   // the edge, as Variants hands it over
  required property var ipc         // the HyprlandBridge
  property bool settling: false     // just released, until the new layout arrives

  signal dragStarted()
  signal dragEnded()

  readonly property var edge: modelData
  readonly property bool vertical: edge.vertical
  readonly property bool active: dragArea.pressed || settling

  readonly property int grab: 5   // extra px on each side of the gap that also grab
  readonly property int resizeThrottleMs: 16
  readonly property int sizeReadbackMs: 33

  // Sizes of window A along the drag axis.
  property real requestedSize: 0   // what the cursor asks for
  property real dispatchedSize: 0  // as of our last dispatch
  property real realSize: 0        // what Hyprland actually gave it

  // Center of the handle along the drag axis: on the real border while dragging.
  readonly property real axisCenter: active ? edge.start + realSize + edge.gapSize / 2 : edge.center

  // Position along the edge, following the cursor and kept inside the edge.
  property real crossPos: edge.crossCenter
  readonly property real crossCenter: {
    const halfPill = Style.space(40)
    const lowest = edge.crossCenter - edge.length / 2 + halfPill
    const highest = edge.crossCenter + edge.length / 2 - halfPill
    return Math.max(lowest, Math.min(highest, crossPos))
  }

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-edge-resize"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  mask: Region { item: hitZone }

  Item {
    id: hitZone

    readonly property real axisStart: handle.edge.center - handle.edge.gapSize / 2 - handle.grab
    readonly property real axisLength: handle.edge.gapSize + handle.grab * 2
    readonly property real crossStart: handle.edge.crossCenter - handle.edge.length / 2

    x: handle.vertical ? axisStart : crossStart
    y: handle.vertical ? crossStart : axisStart
    width: handle.vertical ? axisLength : handle.edge.length
    height: handle.vertical ? handle.edge.length : axisLength

    MouseArea {
      id: dragArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: handle.vertical ? Qt.SplitHCursor : Qt.SplitVCursor

      onPressed: {
        handle.requestedSize = handle.edge.size
        handle.dispatchedSize = handle.edge.size
        handle.realSize = handle.edge.size
        handle.dragStarted()
      }
      onReleased: handle.dragEnded()
      // A lost grab never sends onReleased; without this the drag would never end.
      onCanceled: handle.dragEnded()
      onPositionChanged: (mouse) => {
        if (!pressed) {
          handle.crossPos = hitZone.crossStart + (handle.vertical ? mouse.y : mouse.x)
          return
        }
        const cursor = hitZone.axisStart + (handle.vertical ? mouse.x : mouse.y)
        handle.requestedSize = EdgeGeometry.clampSize(handle.edge, cursor - handle.edge.gapSize / 2 - handle.edge.start)
        if (!resizeThrottle.running) resizeThrottle.start()
      }
    }
  }

  Timer {
    id: resizeThrottle
    interval: handle.resizeThrottleMs
    onTriggered: {
      const delta = Math.round(handle.requestedSize - handle.dispatchedSize)
      if (delta === 0) return
      handle.dispatchedSize += delta
      // A positive delta moves the shared edge right/down whichever of
      // the two windows we resize.
      handle.ipc.resizeWindow(handle.edge.resizeTarget, handle.vertical ? delta : 0, handle.vertical ? 0 : delta)
    }
  }

  // While dragging, read window A's real size back so the handle sits on
  // the actual border, not wherever the cursor went.
  Timer {
    interval: handle.sizeReadbackMs
    repeat: true
    running: handle.active
    onTriggered: {
      const size = handle.ipc.windowSize(handle.edge.leftOrTopWindow)
      if (size) handle.realSize = handle.vertical ? size[0] : size[1]
      handle.ipc.refreshWindows()
    }
  }

  HandlePill {
    vertical: handle.vertical
    hovered: dragArea.containsMouse
    pressed: dragArea.pressed
    axisCenter: handle.axisCenter
    crossCenter: handle.crossCenter
  }

  ShareLabel {
    visible: handle.active
    vertical: handle.vertical
    share: EdgeGeometry.sharePercent(handle.edge, handle.realSize)
    axisCenter: handle.axisCenter
    crossCenter: handle.crossCenter
    gapSize: handle.edge.gapSize
  }
}
