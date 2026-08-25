import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Detail popup: header with freshness info + actions, then the ranked list of
// currently-free models from the tracker. Read-only view over the service.
Panel {
  id: root
  moduleName: "io.github.argusguardian.freemodels"
  ipcTarget: "io.github.argusguardian.freemodels.panel"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var svc: bar ? (bar.shell ? bar.shell.serviceFor("io.github.argusguardian.freemodels") : null) : null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Depends on svc._agoTick so "Xm ago" refreshes each minute while open.
  readonly property string agoText: {
    if (svc) void svc._agoTick
    return Model.timeAgo(svc ? svc.fetchedAt : 0, Date.now())
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Fresh panels always open at the top of the list.
  onOpenedChanged: {
    if (opened) Qt.callLater(function() { flick.contentY = 0 })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if ((t === "r" || t === "R") && root.svc) root.svc.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
          policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(8)

          // ---- Header: icon + title, freshness line underneath.
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: Model.GLYPH.robot
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Column {
              width: parent.width - Style.space(24)
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: "Free AI Models"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                width: parent.width
                elide: Text.ElideRight
                text: !root.svc ? ""
                  : (root.svc.status === "loading" && !root.svc.hasData)
                    ? "Fetching tracker\u2026"
                    : Model.GLYPH.history + " " + root.svc.total + " tracked \u00B7 updated " + root.agoText
                      + (Model.snapshotClock(root.svc.updatedAt) !== "" ? " \u00B7 snapshot " + Model.snapshotClock(root.svc.updatedAt) : "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ---- Actions
          Row {
            spacing: Style.space(6)

            Button {
              text: Model.GLYPH.refresh + " Refresh"
              foreground: root.fg
              accent: Color.accent
              enabled: !!root.svc && !root.svc.fetchInFlight
              onClicked: if (root.svc) root.svc.refresh()
            }

            Button {
              text: Model.GLYPH.externalLink + " Tracker"
              foreground: root.fg
              accent: Color.accent
              onClicked: if (root.svc) root.svc.openUrl(root.svc.repoUrl)
            }
          }

          // ---- Error banner (cached list still shown below when present)
          Rectangle {
            visible: !!root.svc && root.svc.status === "error"
            width: parent.width
            height: errLabel.implicitHeight + Style.space(12)
            radius: Style.space(6)
            color: Qt.alpha(Color.accent, 0.15)

            Text {
              id: errLabel
              anchors.centerIn: parent
              width: parent.width - Style.space(12)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: !root.svc ? "" : "Update failed: " + (root.svc.errorMsg || "unknown") + " \u00B7 showing cached data"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---- Loading placeholder before first data lands
          Text {
            visible: !!root.svc && !root.svc.hasData && root.svc.status !== "error"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(16)
            bottomPadding: Style.space(16)
            text: Model.GLYPH.robot + "  Waiting for tracker data\u2026"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---- Model rows
          Repeater {
            model: root.svc ? root.svc.models : []

            delegate: Rectangle {
              required property var modelData
              required property int index

              width: column.width
              height: rowCol.implicitHeight + Style.space(14)
              radius: Style.space(6)
              color: rowMa.containsMouse ? Qt.alpha(Color.accent, 0.13) : "transparent"

              MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  if (!root.svc) return
                  if (mouse.button === Qt.RightButton) root.svc.copyModelId(modelData)
                  else root.svc.openModel(modelData)
                }
              }

              Column {
                id: rowCol
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space(8)
                spacing: Style.space(3)

                // Line 1: rank, name, context badge right-aligned
                Item {
                  width: parent.width
                  height: Math.max(nameLabel.implicitHeight, ctxBadge.implicitHeight)

                  Text {
                    id: rankLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "#" + (index + 1)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: nameLabel
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(22)
                    anchors.right: ctxBadge.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    id: ctxBadge
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.GLYPH.memory + " " + modelData.context
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                // Line 2: provider tag, modality glyphs, rate limit
                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: modelData.provider
                    color: Qt.darker(root.fg, 1.25)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: modelData.glyphs
                    color: Color.accent
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: modelData.rateLimit !== "" && modelData.rateLimit !== "varies"
                    text: Model.GLYPH.gauge + " " + modelData.rateLimit
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- Footer hints
          Text {
            visible: !!root.svc && root.svc.hasData
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(2)
            text: Model.GLYPH.copy + " copy id \u00B7 " + Model.GLYPH.externalLink + " open provider"
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
