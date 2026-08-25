import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Singleton data engine for the free-models tracker. Loaded once (service
// kind) so every bar surface across monitors shares one fetch, one cache,
// and one refresh cadence. Bar widget and panel are thin readers of this.
Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/omarchy/free-ai-models-cache.json"

  readonly property string dataUrl:
    "https://raw.githubusercontent.com/ClawLabsAI/free-ai-models/main/data/models.json"
  readonly property string repoUrl: "https://github.com/ClawLabsAI/free-ai-models"

  // Refresh every 6h; the upstream tracker itself updates daily.
  readonly property int refreshIntervalMs: 6 * 60 * 60 * 1000

  // ------------------------------------------------------------ runtime state
  property var models: []
  property int total: 0
  property string updatedAt: ""
  property double fetchedAt: 0
  property string status: "loading"   // "loading" | "ok" | "error"
  property string errorMsg: ""

  readonly property bool hasData: models.length > 0
  readonly property string agoLabel: Model.timeAgo(fetchedAt, Date.now())

  function topModel() {
    return hasData ? models[0] : null
  }

  function summaryLine() {
    if (status === "loading") return "Free AI models \u00B7 loading\u2026"
    if (status === "error") return "Free AI models \u00B7 update failed" + (errorMsg !== "" ? " (" + errorMsg + ")" : "")
    return total + " free AI models \u00B7 updated " + Model.timeAgo(fetchedAt, Date.now())
      + (updatedAt !== "" ? " \u00B7 tracker snapshot " + updatedAt : "")
  }

  // ------------------------------------------------------------ fetch
  // Hard cap on bytes accepted from the network per fetch. The tracker
  // payload is ~6 KB; 256 KB is ~40x headroom. curl aborts known-oversize
  // responses (--max-filesize) and `head -c` truncates streamed ones, so
  // the long-lived shell never buffers more than the cap.
  property bool fetchInFlight: false
  readonly property int fetchCapBytes: 262144

  function refresh() {
    if (fetchInFlight) return
    fetchInFlight = true
    status = "loading"
    curlProc.command = ["bash", "-c",
      "set -o pipefail; curl -fsS --proto =https --max-time 15 --max-filesize "
      + root.fetchCapBytes + " " + root.dataUrl + " | head -c " + root.fetchCapBytes]
    curlProc.running = true
  }

  Process {
    id: curlProc

    stdout: StdioCollector {
      onStreamFinished: root.handlePayload(text)
    }

    onExited: function(code) {
      root.fetchInFlight = false
      if (code !== 0 && root.status === "loading") {
        root.status = "error"
        root.errorMsg = "network error " + code
      }
    }
  }

  function handlePayload(text) {
    try {
      var parsed = Model.parsePayload(text)
      models = parsed.models
      total = parsed.total
      updatedAt = parsed.updatedAt
      fetchedAt = Date.now()
      status = "ok"
      errorMsg = ""
      scheduleSave()
    } catch (e) {
      status = "error"
      errorMsg = String(e.message || e)
    }
  }

  // ------------------------------------------------------------ persistence
  // Cache the last good payload so the bar is instant at shell start even
  // before the first network round-trip completes.
  //
  // The cache path is predictable, so reads are guarded: the file must be a
  // regular file (no symlinks/FIFOs), owned by this user, and within the
  // same byte cap as network reads. The guard re-verifies via
  // /proc/self/fd after open (same-descriptor check) to close the stat/open
  // race, and the whole read runs under `timeout` so a pathological file
  // can never stall the shell.
  property bool cacheLoaded: false

  FileView {
    id: cacheFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: cacheReadProc

    stdout: StdioCollector {
      onStreamFinished: root.hydrate(text)
    }

    onExited: {
      // Empty output (missing/guard-rejected cache) must still unblock boot.
      Qt.callLater(function() { if (!root.cacheLoaded) root.hydrate("") })
    }
  }

  function readCache() {
    cacheReadProc.command = ["timeout", "2", "bash", "-c",
      "f=" + JSON.stringify(root.statePath) + "; cap=" + root.fetchCapBytes + "; " +
      "[ ! -L \"$f\" ] && [ -f \"$f\" ] || exit 0; " +
      "[ \"$(stat -c %F \"$f\")\" = \"regular file\" ] || exit 0; " +
      "[ \"$(stat -c %u \"$f\")\" = \"$(id -u)\" ] || exit 0; " +
      "[ \"$(stat -c %s \"$f\")\" -le \"$cap\" ] || exit 0; " +
      "exec 3<\"$f\"; " +
      "[ \"$(stat -c %F -L /proc/self/fd/3)\" = \"regular file\" ] || exit 0; " +
      "[ \"$(stat -c %u -L /proc/self/fd/3)\" = \"$(id -u)\" ] || exit 0; " +
      "[ \"$(stat -c %s -L /proc/self/fd/3)\" -le \"$cap\" ] || exit 0; " +
      "cat <&3"]
    cacheReadProc.running = true
  }

  Timer {
    id: saveTimer
    interval: 200
    repeat: false
    onTriggered: root.flush()
  }

  function scheduleSave() {
    cacheLoaded = true
    saveTimer.restart()
  }

  function hydrate(raw) {
    if (cacheLoaded) return
    var data = {}
    try { data = JSON.parse(raw || "{}") } catch (e) { data = {} }
    if (Array.isArray(data.models) && data.models.length > 0) {
      models = data.models
      total = Number(data.total) > 0 ? Number(data.total) : data.models.length
      updatedAt = typeof data.updatedAt === "string" ? data.updatedAt : ""
      fetchedAt = Number(data.fetchedAt) || 0
      errorMsg = ""
      // Show cached data immediately; the refresh below replaces it.
      status = "ok"
    } else {
      status = "loading"
    }
    cacheLoaded = true
    Qt.callLater(root.refresh)
  }

  function flush() {
    cacheFile.setText(JSON.stringify({
      version: 1,
      models: models,
      total: total,
      updatedAt: updatedAt,
      fetchedAt: fetchedAt
    }) + "\n")
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.home + "/.local/state/omarchy"]
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(root.readCache)
  }

  // ------------------------------------------------------------ cadence
  Timer {
    id: refresher
    interval: root.refreshIntervalMs
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  // Minute tick keeps the panel's "updated Xm ago" label honest.
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.agoTick()
  }

  property int _agoTick: 0
  function agoTick() { _agoTick++ }

  // ------------------------------------------------------------ actions
  function openUrl(url) {
    if (typeof url !== "string" || url === "") return
    Quickshell.execDetached(["xdg-open", url])
  }

  function openModel(entry) {
    if (!entry || typeof entry.url !== "string") return
    openUrl(entry.url)
  }

  function copyModelId(entry) {
    if (!entry || entry.id === "") return
    Quickshell.execDetached(["wl-copy", entry.id])
    notify("Free AI Models", "Copied " + entry.id)
  }

  function notify(title, body) {
    Quickshell.execDetached([
      omarchyPath + "/bin/omarchy-notification-send",
      title,
      body,
      "-g", "\uD83E\uDD16"
    ])
  }

  // ------------------------------------------------------------ IPC
  IpcHandler {
    target: "io.github.argusguardian.freemodels"

    function refresh(): string { root.refresh(); return "ok" }
    function openPanel(): string {
      if (root.shell) root.shell.summon("io.github.argusguardian.freemodels", {})
      return "ok"
    }
    function status(): string {
      return JSON.stringify({
        status: root.status,
        total: root.total,
        updatedAt: root.updatedAt,
        fetchedAt: Math.round(root.fetchedAt),
        error: root.errorMsg
      })
    }
  }
}
