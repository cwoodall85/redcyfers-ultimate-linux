import QtQuick
Tile {
    id: t
    accent: "#f5c542"
    label: "DISK"
    property real read: 0
    property real write: 0
    property real rootUsed: 0
    property real rootTotal: 0
    value: "r " + t.rate(read) + "   w " + t.rate(write)
    function sample() { graph.push([read, write]) }
    Column {
        width: parent.width
        spacing: 8
        Graph { id: graph; width: parent.width; height: 56; colors: [t.accent, "#ffe7a3"] }
        Text {
            width: parent.width
            visible: t.rootTotal > 0
            text: "/  " + t.gib(t.rootUsed) + " of " + t.gib(t.rootTotal) + " GiB used"
            color: t.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
        }
    }
}
