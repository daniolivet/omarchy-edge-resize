import QtQuick
import Quickshell
import Quickshell.Hyprland
import "components"
import "services"
import "lib/EdgeGeometry.js" as EdgeGeometry

// Entry point: keeps the edges of the focused workspace up to date and puts a
// draggable handle on each one.
Item {
  id: root

  // Built by EdgeGeometry.findEdges; see there for the shape of each edge.
  property var edges: []
  property bool dragging: false
  property var settlingHandle: null   // the handle that was just released, until the new layout arrives

  // How often the layout is read again: as a fallback, after Hyprland events
  // (debounced), and once the windows have settled after a drag.
  readonly property int pollIntervalMs: 1000
  readonly property int eventDebounceMs: 60
  readonly property int postDragRefreshMs: 150
  // Never leave a released handle hanging if the layout read fails.
  readonly property int settleTimeoutMs: 800

  function beginDrag() {
    dragging = true
    bridge.disableDragOptions()
  }
  function endDrag(handle) {
    dragging = false
    settlingHandle = handle
    settleTimeout.restart()
    bridge.restoreDragOptions()
    postDragRefresh.restart()
  }

  HyprlandBridge {
    id: bridge
    onLayoutRead: (clients, workspaceId) => {
      // Don't rebuild the handles while one is being dragged.
      if (root.dragging) return
      const next = EdgeGeometry.findEdges(clients, workspaceId)
      if (!EdgeGeometry.edgesEqual(next, root.edges)) root.edges = next
      root.settlingHandle = null
    }
  }

  Timer {
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: bridge.readLayout()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { eventDebounce.restart() }
  }
  Timer { id: eventDebounce; interval: root.eventDebounceMs; onTriggered: bridge.readLayout() }
  Timer { id: postDragRefresh; interval: root.postDragRefreshMs; onTriggered: bridge.readLayout() }
  Timer { id: settleTimeout; interval: root.settleTimeoutMs; onTriggered: root.settlingHandle = null }

  Variants {
    model: root.edges

    EdgeHandle {
      id: edgeHandle
      ipc: bridge
      settling: root.settlingHandle === edgeHandle
      onDragStarted: root.beginDrag()
      onDragEnded: root.endDrag(edgeHandle)
    }
  }
}
