import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Bar toggle for "closing the lid must not suspend".
//
// The mechanism is a logind inhibitor lock rather than a HandleLidSwitch
// setting in logind.conf: taking `handle-lid-switch` is allowed for the active
// session (allow_active=yes on org.freedesktop.login1.inhibit-handle-lid-switch),
// so toggling costs no root and no polkit prompt. The lock lives exactly as
// long as the child process, so "off" is just letting it die.
BarWidget {
  id: root
  moduleName: "io.github.michalpomykacz.lid-awake"

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
  readonly property string statePath: stateDir + "/lid-awake"
  property bool lidAwake: false
  property string pendingWrite: ""

  // Every instance of the neighbouring indicator cluster. Reading it through
  // `moduleWidgets` keeps this a live binding: the bar rebuilds `moduleSlots`
  // whenever a widget appears or goes away, so the lookup re-runs on its own.
  readonly property var indicatorClusters: bar && typeof bar.moduleWidgets === "function"
    ? bar.moduleWidgets("omarchy.indicators")
    : []

  // Any cluster counts, not the one on this widget's own screen, so
  // on a multi-monitor bar hovering one screen's cluster also reveals this
  // icon on the other. Filter by screen if that ever grates.
  readonly property bool clusterRevealed: {
    var clusters = root.indicatorClusters
    for (var i = 0; i < clusters.length; i++) {
      if (clusters[i] && clusters[i].revealInactiveIndicators) return true
    }
    return false
  }

  readonly property bool slotOpen: root.lidAwake || revealProxy.revealInactiveIndicators

  // Collapse the slot rather than just going transparent. The cluster does the
  // same for its own inactive block; leaving the width in place would park a
  // permanent blank gap next to it.
  implicitWidth: root.vertical || root.slotOpen ? indicator.implicitWidth : 0
  implicitHeight: !root.vertical || root.slotOpen ? indicator.implicitHeight : 0
  clip: true

  // A bar surface exists per monitor, so this widget is instantiated more than
  // once and every copy has to agree. `broadcast` reaches all of them; the
  // caller decides the absolute value first so the surfaces cannot drift the
  // way a per-instance `!lidAwake` would.
  function setAwake(value) {
    root.broadcast(value ? "enableAwake" : "disableAwake")
    root.persist(value ? "awake" : "suspend")
    return value ? "awake" : "suspend"
  }

  function enableAwake() { root.lidAwake = true }
  function disableAwake() { root.lidAwake = false }

  // Writes go through a subprocess, not FileView.setText: each surface owns a
  // separate FileView with its own cached copy of the file, and setText drops a
  // write whose value already matches that cache. Whichever surface was not
  // clicked keeps a stale cache, so toggling on from one monitor and off from
  // another silently left `awake` on disk under an interface reporting `off` —
  // and the next shell start honoured the disk. A subprocess has no cache to
  // disagree with.
  function persist(value) {
    root.pendingWrite = value
    if (!stateWriter.running) root.flushWrite()
  }

  // One queued value, last write wins. Retargeting a Process while it runs
  // loses the write, and two quick clicks must not land out of order.
  function flushWrite() {
    if (root.pendingWrite === "") return

    var value = root.pendingWrite
    root.pendingWrite = ""
    stateWriter.command = ["bash", "-c", 'printf \'%s\\n\' "$2" > "$1"', "lid-awake", root.statePath, value]
    stateWriter.running = true
  }

  BarIndicator {
    id: indicator
    anchors.centerIn: parent

    // Everything themed hangs off the host bar: the glyph colour is
    // `bar.barForeground`, the font is `bar.fontFamily`, and the tooltip is the
    // bar's shared popup. Left unset it silently falls back to the static
    // Color/Style defaults, which is why it rendered in a different colour from
    // every neighbouring icon.
    bar: root.bar

    active: root.lidAwake
    activeText: "󰌢"
    activeTooltipText: "Lid close ignored"
    inactiveTooltipText: "Suspends on lid close"
    indicatorHost: revealProxy
    // Keeps the cluster's reveal alive while the pointer travels off it and
    // onto this icon, which sits outside the cluster's own hover area.
    maintainIndicatorReveal: true

    onPressed: function() { root.setAwake(!root.lidAwake) }
  }

  // BarIndicator hides itself and stops accepting clicks while inactive unless
  // its host reports the inactive block as revealed. Inside omarchy.indicators
  // that host is the cluster; standing outside it, this proxy forwards the
  // cluster's reveal so the icon appears and disappears in step with the
  // neighbours instead of sitting there permanently dimmed.
  QtObject {
    id: revealProxy

    // No cluster in the bar means there is nothing to hover, and a hidden
    // indicator would be a toggle nobody could switch back on. Stay visible.
    property bool revealInactiveIndicators: root.indicatorClusters.length === 0 || root.clusterRevealed

    function setIndicatorItemHovered(hovered) {
      var clusters = root.indicatorClusters
      for (var i = 0; i < clusters.length; i++) {
        if (clusters[i] && clusters[i].setIndicatorItemHovered) clusters[i].setIndicatorItemHovered(hovered)
      }
    }
  }

  // One inhibitor per bar surface. They are additive and all die together on
  // toggle-off, so the behaviour is right; it just shows N identical rows in
  // `systemd-inhibit --list`. Move the lock into a service plugin if the
  // duplicate rows ever matter.
  Process {
    id: inhibitor
    running: root.lidAwake
    command: [
      "systemd-inhibit",
      "--what=handle-lid-switch",
      "--who=Lid awake",
      "--why=Lid close ignored by request",
      "--mode=block",
      "sleep", "infinity"
    ]

    // `sleep infinity` only ends because the toggle went off, or because
    // something went wrong — logind unavailable, or the lock refused because
    // the session is no longer active. In the second case the indicator would
    // otherwise keep promising protection that nothing holds, so drop the
    // toggle and say why.
    //
    // A failure here is treated as total rather than per-surface: one held lock
    // is enough to inhibit the lid, but every cause is session-wide, so a
    // surface failing alone is not a case worth modelling.
    onExited: function(exitCode, exitStatus) {
      if (!root.lidAwake) return

      console.warn("lid-awake: inhibitor exited unexpectedly (code " + exitCode
        + ", status " + exitStatus + "); lid close will suspend again")
      root.setAwake(false)
    }
  }

  Process {
    id: stateWriter
    onExited: root.flushWrite()
  }

  Process {
    id: ensureStateDir
    command: ["mkdir", "-p", root.stateDir]
    onExited: stateFile.reload()
  }

  // Read-only: hydration at startup. Writes deliberately do not go through
  // here — see `persist`.
  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: root.lidAwake = text().trim() === "awake"
    // First run: no file yet, which means the laptop should still suspend.
    onLoadFailed: root.lidAwake = false
  }

  IpcHandler {
    // Only one handler wins this target across the per-monitor instances, and
    // that is enough: it broadcasts to the rest.
    target: "lid"

    function status(): string { return root.lidAwake ? "awake" : "suspend" }
    function toggle(): string { return root.setAwake(!root.lidAwake) }
    function on(): string { return root.setAwake(true) }
    function off(): string { return root.setAwake(false) }
  }

  Component.onCompleted: ensureStateDir.running = true
}
