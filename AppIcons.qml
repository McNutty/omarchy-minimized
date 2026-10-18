import QtQuick
import Quickshell
import Quickshell.Hyprland

// Icon lookup shared by the open-windows and minimized icons. One instance
// lives in Workspaces.qml; both parts call iconFor(toplevel).
//
// The matching from window to desktop entry is adapted from Spaces by Tornike
// Gomareli (github.com/tornikegomareli/omarchy-spaces, MIT): app id candidates
// including the tail of a reverse-DNS id, Quickshell's heuristic lookup,
// Chromium-family web apps by host, and windows the shell itself hosts (all
// "org.quickshell") told apart by title. The icon file itself comes from the
// shell's app library, which keeps its own index of app icons.
QtObject {
  id: root

  property QtObject bar: null

  property var cache: ({})
  property int revision: 0

  function appIdOf(top) {
    if (top && top.wayland && top.wayland.appId) return String(top.wayland.appId)
    var ipc = top && top.lastIpcObject ? top.lastIpcObject : {}
    return String(ipc["class"] || ipc.initialClass || "")
  }

  function appIdCandidates(appId) {
    var id = String(appId || "")
    if (id === "") return []
    var out = [id]
    function add(v) { if (v && out.indexOf(v) === -1) out.push(v) }
    add(id.toLowerCase())
    if (id.toLowerCase().slice(-8) === ".desktop") add(id.slice(0, -8))
    var dot = id.lastIndexOf(".")
    if (dot > 0 && dot < id.length - 1) {
      add(id.slice(dot + 1))
      add(id.slice(dot + 1).toLowerCase())
    }
    return out
  }

  // Chromium-family --app windows use classes like
  // "chrome-web.whatsapp.com__-Default" or "brave-app.hey.com__-Profile_1".
  function webAppHost(appId) {
    var m = /^(?:chrome|chromium|brave|msedge|vivaldi|helium|opera)-([^_]+?)(?:__|_).*-(?:Default|Profile_\d+)$/i.exec(String(appId || ""))
    return m ? m[1] : ""
  }

  function findDesktopEntry(appId) {
    if (!appId) return null
    var candidates = root.appIdCandidates(appId)
    for (var c = 0; c < candidates.length; c++) {
      var byId = DesktopEntries.byId(candidates[c])
      if (byId) return byId
    }
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry

    var host = root.webAppHost(appId)
    if (host === "") return null
    var apps = DesktopEntries.applications.values
    for (var i = 0; i < apps.length; i++) {
      var exec = String(apps[i].execString || "")
      if (exec.indexOf("//" + host) !== -1) return apps[i]
    }
    return null
  }

  function iconUrl(name) {
    var lib = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    if (lib && typeof lib.iconSource === "function") return String(lib.iconSource(name) || "")
    return Quickshell.iconPath(String(name || "") || "application-x-executable", true)
  }

  // Cached per app id; windows the shell hosts cache per title instead, since
  // the title, not the id, names the app inside (e.g. "Omamail").
  function iconFor(top) {
    root.revision
    var appId = root.appIdOf(top)
    var title = String(top && top.title || "")
    var key = appId.toLowerCase()
    var shellHosted = key === "org.quickshell" && title !== ""
    var cacheKey = shellHosted ? key + "\u0000" + title.toLowerCase() : key
    var cached = root.cache[cacheKey]
    if (cached) return cached

    var entry = root.findDesktopEntry(appId)
    if (shellHosted) {
      var titled = root.findDesktopEntry(title)
      if (titled && !titled.noDisplay) entry = titled
    }
    var source = root.iconUrl(entry && entry.icon ? entry.icon : appId)
    if (appId !== "") root.cache[cacheKey] = source
    return source
  }

  function invalidate() {
    root.cache = ({})
    root.revision++
  }

  property Connections entriesWatch: Connections {
    target: DesktopEntries
    function onApplicationsChanged() { debounce.restart() }
  }

  property Timer debounce: Timer {
    id: debounce
    interval: 1500
    onTriggered: root.invalidate()
  }

  Component.onCompleted: DesktopEntries.applications.values
}
