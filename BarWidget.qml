import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill: robot glyph + live count of free AI models. Left click opens the
// list panel, middle click forces a refresh, right click notifies the current
// top-ranked model. All data comes from the shared service singleton.
BarWidget {
  id: root
  moduleName: "io.github.argusguardian.freemodels"

  readonly property var svc: bar ? (bar.shell ? bar.shell.serviceFor("io.github.argusguardian.freemodels") : null) : null

  function barText() {
    if (!svc) return Model.GLYPH.robot
    if (svc.status === "loading" && !svc.hasData) return Model.GLYPH.robot + " \u2026"
    return Model.GLYPH.robot + " " + svc.total
  }
  readonly property string displayText: barText()

  function tooltipText() {
    if (!svc) return "Free AI Models"
    var top = svc.topModel()
    var line = "Free AI models: " + svc.total + " \u00B7 updated " + Model.timeAgo(svc.fetchedAt, Date.now())
    if (top) line += "\nTop: " + top.name + " (" + top.context + ")"
    line += "\nClick: list \u00B7 Middle: refresh \u00B7 Right: top model"
    return line
  }

  // ---- Panel lifecycle contract expected by the bar's popout coordinator.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.argusguardian.freemodels.widget"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipText()

    onPressed: function(b) {
      if (!root.svc) return
      if (b === Qt.RightButton) {
        var top = root.svc.topModel()
        root.svc.notify("Free AI Models", top ? ("Top free model: " + top.name + " (" + top.context + ")") : root.svc.summaryLine())
      }
      else if (b === Qt.MiddleButton) root.svc.refresh()
      else root.togglePanel()
    }
  }
}
