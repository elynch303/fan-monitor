import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.fan-monitor"
  ipcTarget: "local.fan-monitor"

  property var fans: []
  property var temps: []
  property bool loaded: false

  readonly property bool hasDeadFan: {
    var f = fans
    for (var i = 0; i < f.length; i++) { if (f[i].rpm === 0) return true }
    return false
  }

  function refresh() {
    if (!sensorsProc.running) sensorsProc.running = true
  }

  function parseSensors(raw) {
    try {
      var data = JSON.parse(raw)
      var newFans = []
      var newTemps = []
      var chips = Object.keys(data)

      for (var ci = 0; ci < chips.length; ci++) {
        var chip = chips[ci]
        var chipData = data[chip]
        if (typeof chipData !== "object" || chipData === null) continue
        var skeys = Object.keys(chipData)

        if (chip.indexOf("it8689") !== -1 || chip.indexOf("it87") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue

            if (sname.indexOf("fan") === 0) {
              var fk = sname + "_input"
              if (sval.hasOwnProperty(fk))
                newFans.push({ name: sname, rpm: Math.round(sval[fk]) })
            } else if (sname.indexOf("temp") === 0) {
              var tk = sname + "_input"
              if (sval.hasOwnProperty(tk)) {
                var t = sval[tk]
                if (t > -50 && t < 120)
                  newTemps.push({ name: "Board " + sname.replace("temp", ""), value: t.toFixed(1) })
              }
            }
          }
        } else if (chip.indexOf("coretemp") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            if (sname !== "Package id 0") continue
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue
            var vkeys = Object.keys(sval)
            for (var ki = 0; ki < vkeys.length; ki++) {
              if (vkeys[ki].indexOf("_input") !== -1) {
                newTemps.unshift({ name: "CPU", value: sval[vkeys[ki]].toFixed(1) })
                break
              }
            }
          }
        } else if (chip.indexOf("nvme") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            if (sname !== "Composite") continue
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue
            var vkeys = Object.keys(sval)
            for (var ki = 0; ki < vkeys.length; ki++) {
              if (vkeys[ki].indexOf("_input") !== -1) {
                var t = sval[vkeys[ki]]
                if (t > -50 && t < 100)
                  newTemps.push({ name: "NVMe " + chip.slice(-4), value: t.toFixed(1) })
                break
              }
            }
          }
        }
      }

      fans = newFans
      temps = newTemps
      loaded = true
    } catch (e) {
      console.warn("fan-monitor: parse error:", e)
    }
  }

  Process {
    id: sensorsProc
    command: ["sensors", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseSensors(text) }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  onOpenedChanged: if (opened) root.refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱕘"
    active: root.hasDeadFan
    tooltipText: root.hasDeadFan ? "Fan warning" : "Fans & temps"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: kpanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: kpanel.fittedContentWidth(Style.space(300))
    contentHeight: kpanel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: "󱕘"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          }

          Column {
            id: heroLabels
            anchors {
              left: heroIcon.right; leftMargin: Style.space(14)
              verticalCenter: parent.verticalCenter
            }
            spacing: Style.space(2)

            Text {
              text: "Fan Monitor"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: !root.loaded ? "LOADING…"
                  : root.hasDeadFan ? "FAN STOPPED"
                  : "ALL FANS OK"
              color: root.hasDeadFan ? "#f7768e" : Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "FAN SPEEDS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.fans
            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.name
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: Style.space(48)
              }

              Text {
                text: modelData.rpm === 0 ? "STOPPED" : modelData.rpm + " RPM"
                color: modelData.rpm === 0 ? "#f7768e" : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: modelData.rpm === 0
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "TEMPERATURES"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.temps
            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: modelData.name
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                width: Style.space(72)
              }

              Text {
                readonly property real tempVal: parseFloat(modelData.value)
                text: modelData.value + "°C"
                color: tempVal >= 80 ? "#f7768e" : tempVal >= 65 ? "#e0af68" : root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
