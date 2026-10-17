import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../lib/EdgeGeometry.js" as EdgeGeometry

// Everything that talks to Hyprland: reading the tiled layout, turning off the
// options that get in the way of a live drag, and dispatching the resizes.
// It knows nothing about handles or drags.
Scope {
  id: bridge

  signal layoutRead(var clients, var workspaceId)

  // The drag options as they were before disableDragOptions(), to put them back.
  property bool animationsWere: true
  property bool smartResizingWas: true
  property bool disableRequested: false   // between disableDragOptions() and restoreDragOptions()
  property bool optionsDisabled: false    // the options really are off, so there is something to restore

  function readLayout() {
    if (!layoutReader.running) layoutReader.running = true
  }

  // Animations off so the resize doesn't trail the cursor, and dwindle
  // smart_resizing off so Hyprland always moves window A's right/bottom edge
  // (smart resizing picks the edge from the cursor and can move the wrong side
  // of a middle window). The current values are read first, to restore them.
  function disableDragOptions() {
    disableRequested = true
    if (!optionsDisabled) optionsReader.running = true
  }

  // Only undoes what disableDragOptions() actually changed: a drag released
  // before the current values were read never touched them.
  function restoreDragOptions() {
    disableRequested = false
    if (!optionsDisabled) return
    optionsDisabled = false
    setDragOptions(animationsWere, smartResizingWas)
  }

  // Addresses are bare, without "0x", as EdgeGeometry keeps them.
  function resizeWindow(address, dx, dy) {
    Hyprland.dispatch(`hl.dsp.window.resize({ x = ${dx}, y = ${dy}, relative = true, window = "address:0x${address}" })`)
  }

  // The size Hyprland last reported for a window, as [width, height], or null.
  // It comes from Quickshell's cache: call refreshWindows() to keep it fresh.
  function windowSize(address) {
    const toplevel = Hyprland.toplevels.values.find(candidate => EdgeGeometry.bareAddress(candidate.address) === address)
    return toplevel?.lastIpcObject?.size ?? null
  }

  function refreshWindows() {
    Hyprland.refreshToplevels()
  }

  function setDragOptions(animations, smartResizing) {
    Quickshell.execDetached(["hyprctl", "eval",
      `hl.config({ animations = { enabled = ${animations} }, dwindle = { smart_resizing = ${smartResizing} } })`])
  }

  // getoption answers { "option": ..., "bool": true|false, "set": ... } for boolean options.
  function optionValue(reply) {
    if (typeof reply.bool !== "boolean") throw new Error(`unexpected getoption reply for ${reply.option}`)
    return reply.bool
  }

  Process {
    id: layoutReader
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        const workspace = Hyprland.focusedWorkspace
        if (!workspace) return
        let clients
        try {
          clients = JSON.parse(text)
        } catch (e) {
          console.warn("edge-resize: could not read the layout:", e, text)
          return
        }
        bridge.layoutRead(clients, workspace.id)
      }
    }
  }

  Process {
    id: optionsReader
    // --batch answers each command in turn, separated by a blank line.
    command: ["hyprctl", "-j", "--batch", "getoption animations:enabled; getoption dwindle:smart_resizing"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const [animations, smartResizing] = text.trim().split(/\n\s*\n/).map(reply => JSON.parse(reply))
          bridge.animationsWere = bridge.optionValue(animations)
          bridge.smartResizingWas = bridge.optionValue(smartResizing)
        } catch (e) {
          console.warn("edge-resize: could not read the drag options, will restore both as on:", e, text)
          bridge.animationsWere = true
          bridge.smartResizingWas = true
        }
        if (!bridge.disableRequested) return
        bridge.optionsDisabled = true
        bridge.setDragOptions(false, false)
      }
    }
  }
}
