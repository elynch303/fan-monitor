import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property var fans: []

    readonly property bool hasDeadFan: {
        var f = fans
        for (var i = 0; i < f.length; i++) { if (f[i].rpm === 0) return true }
        return false
    }

    function refresh() {
        if (!sensorsProc.running) sensorsProc.running = true
    }

    function parseFans(raw) {
        try {
            var data = JSON.parse(raw)
            var newFans = []
            var chips = Object.keys(data)
            for (var ci = 0; ci < chips.length; ci++) {
                var chip = chips[ci]
                if (chip.indexOf("it8689") === -1 && chip.indexOf("it87") === -1) continue
                var chipData = data[chip]
                var skeys = Object.keys(chipData)
                for (var si = 0; si < skeys.length; si++) {
                    var sname = skeys[si]
                    if (sname.indexOf("fan") !== 0) continue
                    var sval = chipData[sname]
                    if (typeof sval !== "object" || sval === null) continue
                    var k = sname + "_input"
                    if (sval.hasOwnProperty(k))
                        newFans.push({ name: sname, rpm: Math.round(sval[k]) })
                }
            }
            fans = newFans
        } catch (e) {}
    }

    Process {
        id: sensorsProc
        command: ["sensors", "-j"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: rootMod.parseFans(text) }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: rootMod.refresh()
    }

    readonly property string tooltipText: {
        var f = fans
        if (f.length === 0) return "Fans & temps"
        var parts = []
        for (var i = 0; i < f.length; i++)
            parts.push(f[i].name + ": " + (f[i].rpm === 0 ? "STOPPED" : f[i].rpm + " RPM"))
        return parts.join("  ·  ")
    }

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 28

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(row.implicitWidth) + 18
        height: root.pillH
        radius: root.pillRadius
        color: root.pill
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󱕘"
            color: rootMod.hasDeadFan ? root.sealRaw : root.ink
            font.family: root.mono
            font.pixelSize: 13
            renderType: Text.NativeRendering
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited:  tip.hide()
        onClicked: { tip.hide(); root.fanMonitorVisible = !root.fanMonitorVisible }
    }
}
