import QtQuick
Tile {
    id: t
    accent: "#3fe0c5"
    label: "MEMORY"
    property real used: 0
    property real total: 0
    property real swapUsed: 0
    property real swapTotal: 0
    value: total ? t.gib(used) + " / " + t.gib(total) + " GiB" : ""
    Column {
        width: parent.width
        spacing: 8
        Item {
            width: parent.width; height: 8
            Rectangle { anchors.fill: parent; radius: 4; color: t.accent; opacity: 0.12 }
            Rectangle { height: parent.height; radius: 4; color: t.accent
                        width: parent.width * (t.total ? Math.min(1, t.used / t.total) : 0) }
        }
        Text {
            width: parent.width
            text: (t.total ? Math.round(100 * t.used / t.total) + "% in use" : "")
                  + (t.swapTotal ? "    swap " + t.gib(t.swapUsed) + " / " + t.gib(t.swapTotal) + " GiB" : "")
            color: t.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
        }
    }
}
