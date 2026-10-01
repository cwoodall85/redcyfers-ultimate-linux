/*
 * The Ultimate widgets' tile: a dark glass card with one accent colour,
 * a small caption row (dot, LABEL, value) and a body. Every tile is sized
 * on Plasma's 16 px desktop grid and shares one width, so tiles dropped
 * next to each other snap flush and read as one stack; the little tabs on
 * the top and bottom edges are where they clip together.
 *
 * Copied into each widget's package at build time (no shared QML module).
 */
import QtQuick

Item {
    id: tile
    property color accent: "#00ffa8"
    property string label: ""
    property string value: ""
    property bool live: false          // pulse the dot (e.g. Claude working)
    default property alias body: content.data
    readonly property color text1: "#dff3e6"
    readonly property color text2: "#7fa593"
    readonly property int pad: 16

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 1
        radius: 12
        color: Qt.rgba(3 / 255, 9 / 255, 8 / 255, 0.80)
        border.width: 1
        border.color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.22)
        // the accent line along the top, like a lit edge
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
            anchors.leftMargin: 14; anchors.rightMargin: 14
            height: 1
            color: tile.accent
            opacity: 0.55
        }
    }
    // clip tabs, centred on the top and bottom edges
    Repeater {
        model: 2
        Rectangle {
            required property int index
            width: 28; height: 4; radius: 2
            x: (tile.width - width) / 2
            y: index === 0 ? -1 : tile.height - 3
            color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.35)
        }
    }

    Row {
        id: caption
        visible: tile.label !== ""
        x: tile.pad; y: 12
        width: tile.width - 2 * tile.pad
        spacing: 8
        Rectangle {
            id: dot
            width: 7; height: 7; radius: 3.5
            anchors.verticalCenter: parent.verticalCenter
            color: tile.accent
            opacity: tile.live ? (blink.on ? 1 : 0.3) : 0.9
            Timer { id: blink; property bool on: true; interval: 600; repeat: true; running: tile.live; onTriggered: on = !on }
        }
        Text {
            id: lab
            text: tile.label
            color: tile.accent
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            font.letterSpacing: 2.5
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            width: caption.width - dot.width - lab.width - 2 * caption.spacing
            horizontalAlignment: Text.AlignRight
            text: tile.value
            color: tile.text1
            elide: Text.ElideLeft
            font.family: "JetBrains Mono"
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Item {
        id: content
        x: tile.pad
        y: caption.visible ? 38 : tile.pad
        width: tile.width - 2 * tile.pad
        height: tile.height - y - 14
    }

    function rate(b) {
        b = Number(b) || 0
        const u = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
        let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i === 0 ? Math.round(b) : b.toFixed(b < 10 ? 1 : 0)) + " " + u[i]
    }
    function gib(b) { return (Number(b) / 1073741824).toFixed(1) }
}
