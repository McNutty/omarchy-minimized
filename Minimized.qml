import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Windows minimized from a workspace live on the hidden Hyprland workspace
// "special:min-<id>" (the Super+M binding puts them there). This widget shows
// the ones belonging to the workspace its own monitor is displaying; clicking
// an icon moves that window back and focuses it. Hyprland holds all the state,
// so a shell restart or plugin reload loses nothing.
BarWidget {
  id: root
  moduleName: "thord.minimized"

  readonly property string prefix: "special:min-"

  // One bar surface exists per monitor; resolve the one this instance is on.
  readonly property string screenName:
    root.QsWindow && root.QsWindow.window && root.QsWindow.window.screen
      ? String(root.QsWindow.window.screen.name || "") : ""

  readonly property var thisMonitor: {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (String(mons[i].name) === root.screenName) return mons[i]
    }
    return null
  }

  readonly property int activeWsId:
    thisMonitor && thisMonitor.activeWorkspace ? thisMonitor.activeWorkspace.id
      : (Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1)

  readonly property var minimizedWorkspace: {
    var name = root.prefix + root.activeWsId
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name) === name) return values[i]
    }
    return null
  }

  readonly property var windows: minimizedWorkspace ? minimizedWorkspace.toplevels.values : []

  // class/initialClass come from lastIpcObject, which is only filled in after a
  // refresh, so refresh whenever a window lands on or leaves a min workspace.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name)
      if (name.indexOf("movewindow") === 0 || name.indexOf("openwindow") === 0 || name.indexOf("windowtitle") === 0)
        Hyprland.refreshToplevels()
    }
  }

  function normalize(value) {
    var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    return s.slice(-8) === ".desktop" ? s.slice(0, -8) : s
  }

  // Desktop entry for a window: exact id, StartupWMClass or name first. Chromium
  // web apps (class "chrome-<domain>__<path>-Default") match the entry whose Exec
  // opens that domain; requiring "://<domain>" avoids loose word matches.
  function entryFor(top) {
    var ipc = top && top.lastIpcObject ? top.lastIpcObject : {}
    var appId = top && top.wayland ? top.wayland.appId : ""
    var candidates = [normalize(appId), normalize(ipc.class), normalize(ipc.initialClass)]
      .filter(function(c, i, all) { return c !== "" && all.indexOf(c) === i })
    var entries = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var fields = ["id", "startupClass", "name"]

    for (var f = 0; f < fields.length; f++) {
      for (var c = 0; c < candidates.length; c++) {
        for (var e = 0; e < entries.length; e++) {
          if (entries[e] && !entries[e].noDisplay && normalize(entries[e][fields[f]]) === candidates[c])
            return { entry: entries[e], fallback: candidates[0] || "" }
        }
      }
    }

    for (var w = 0; w < candidates.length; w++) {
      var m = candidates[w].match(/^(?:chrome|chromium|brave|msedge)-([^_]+)__/)
      if (!m) continue
      var needle = "://" + m[1]
      for (var k = 0; k < entries.length; k++) {
        var exec = String(entries[k] && (entries[k].execString || entries[k].exec) || "").toLowerCase()
        if (exec.indexOf(needle) !== -1) return { entry: entries[k], fallback: candidates[0] }
      }
    }

    return { entry: null, fallback: candidates[0] || "" }
  }

  function iconFor(top) {
    var found = entryFor(top)
    var name = found.entry ? String(found.entry.icon || "") : found.fallback
    var lib = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    var source = lib && typeof lib.iconSource === "function" ? String(lib.iconSource(name) || "") : ""
    if (!source && name) source = Quickshell.iconPath(name, true)
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  function restore(top) {
    if (!root.bar || !top || root.activeWsId < 1) return
    var addr = String(top.address || "")
    if (addr.indexOf("0x") !== 0) addr = "0x" + addr
    var move = "hl.dsp.window.move({ window = \"address:" + addr + "\", workspace = \"" + root.activeWsId + "\" })"
    var focus = "hl.dsp.focus({ window = \"address:" + addr + "\" })"
    root.bar.run("hyprctl dispatch " + Util.shellQuote(move) + " && hyprctl dispatch " + Util.shellQuote(focus))
  }

  readonly property real trailingGap: root.vertical || root.windows.length === 0 ? 0 : Style.spaceReal(1.5)

  visible: root.windows.length > 0
  implicitWidth: visible ? grid.implicitWidth + trailingGap : 0
  implicitHeight: visible ? grid.implicitHeight : 0

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.windows.length)
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.windows

      BarIconButton {
        id: button
        required property var modelData

        bar: root.bar
        fixedWidth: root.vertical ? root.barSize : Style.bar.iconSlot
        fixedHeight: root.barSize
        tooltipText: String(button.modelData.title || "") + "\nClick to restore"
        useActiveColor: false
        iconComponent: Component {
          Image {
            source: root.iconFor(button.modelData)
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Math.round(Style.bar.iconCanvas * Screen.devicePixelRatio)
            sourceSize.height: Math.round(Style.bar.iconCanvas * Screen.devicePixelRatio)
            asynchronous: true
          }
        }
        onPressed: function() { root.restore(button.modelData) }
      }
    }
  }
}
