import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: fanPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-fan-monitor"

    readonly property int barBottom: 35
    readonly property int gap: 8

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
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: fanPanel.parseSensors(text) }
    }

    Timer {
        interval: 5000
        running: root.fanMonitorVisible
        repeat: true
        onTriggered: fanPanel.refresh()
    }

    onVisibleChanged: if (visible) fanPanel.refresh()

    property real reveal: root.fanMonitorVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.fanMonitorVisible ? 160 : 120
            easing.type: root.fanMonitorVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.fanMonitorVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.fanMonitorVisible = false }

    Rectangle {
        id: card
        width: 300
        height: col.implicitHeight + 24
        radius: fanPanel.reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.fanMonitorBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
           ? (parent.height - fanPanel.barBottom - fanPanel.gap - height)
           : (fanPanel.barBottom + fanPanel.gap)
        opacity: fanPanel.reveal
        focus: root.fanMonitorVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.fanMonitorVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ── header ──
            Row {
                width: parent.width
                spacing: 8

                Text {
                    text: "󱕘"
                    color: fanPanel.hasDeadFan ? root.sealRaw : root.ink
                    font.family: root.mono
                    font.pixelSize: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    UiText {
                        text: "Fan Monitor"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 13
                        font.bold: true
                    }

                    UiText {
                        text: !fanPanel.loaded ? "Loading…"
                            : fanPanel.hasDeadFan ? "FAN STOPPED"
                            : "All fans OK"
                        color: fanPanel.hasDeadFan ? root.sealRaw : root.green
                        font.family: root.mono
                        font.pixelSize: 10
                    }
                }
            }

            // ── divider ──
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.15) }

            // ── fan speeds ──
            UiText {
                text: "FAN SPEEDS"
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                font.family: root.mono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.8
            }

            Repeater {
                model: fanPanel.fans
                Row {
                    required property var modelData
                    width: parent.width
                    spacing: 8

                    UiText {
                        text: modelData.name
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                        font.family: root.mono
                        font.pixelSize: 11
                        width: 42
                    }

                    UiText {
                        text: modelData.rpm === 0 ? "STOPPED" : modelData.rpm + " RPM"
                        color: modelData.rpm === 0 ? root.sealRaw : root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                        font.bold: modelData.rpm === 0
                    }
                }
            }

            // ── divider ──
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.15) }

            // ── temperatures ──
            UiText {
                text: "TEMPERATURES"
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                font.family: root.mono
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.8
            }

            Repeater {
                model: fanPanel.temps
                Row {
                    required property var modelData
                    width: parent.width
                    spacing: 8

                    readonly property real tempVal: parseFloat(modelData.value)

                    UiText {
                        text: modelData.name
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                        font.family: root.mono
                        font.pixelSize: 11
                        width: 70
                    }

                    UiText {
                        text: modelData.value + "°C"
                        color: parent.tempVal >= 80 ? root.sealRaw
                             : parent.tempVal >= 65 ? root.color03
                             : root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
