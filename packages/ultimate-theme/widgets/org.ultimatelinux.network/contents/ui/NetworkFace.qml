import QtQuick
Tile {
    id: t
    accent: "#4fb3ff"
    label: "NETWORK"
    property real down: 0
    property real up: 0
    value: "↓ " + t.rate(down) + "   ↑ " + t.rate(up)
    function sample() { graph.push([down, up]) }
    Graph { id: graph; width: parent.width; height: parent.height; colors: [t.accent, "#b4dcff"] }
}
