import QtQuick
Tile {
    id: t
    accent: "#00ffa8"
    label: "CPU"
    property real usage: 0
    property real temp: 0
    property var cores: []
    value: Math.round(usage) + "%" + (temp > 1 ? "   " + Math.round(temp) + "°C" : "")
    function sample() { graph.push([usage]) }
    Column {
        width: parent.width
        spacing: 8
        Graph { id: graph; width: parent.width; height: 70; colors: [t.accent]; maxes: [100] }
        Row {
            id: row
            width: parent.width; height: 24; spacing: 2
            Repeater {
                model: t.cores.length
                Item {
                    required property int index
                    width: (row.width - (t.cores.length - 1) * row.spacing) / Math.max(1, t.cores.length)
                    height: row.height
                    Rectangle { anchors.fill: parent; color: t.accent; opacity: 0.08 }
                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width
                        height: Math.max(1, parent.height * Math.min(100, t.cores[index] || 0) / 100)
                        color: t.accent; opacity: 0.35 + 0.6 * Math.min(1, (t.cores[index] || 0) / 100)
                    }
                }
            }
        }
    }
}
