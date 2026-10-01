import QtQuick
Tile {
    id: t
    accent: "#00ffa8"
    property string system: ""
    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: t.now = new Date() }
    Column {
        width: parent.width
        spacing: 2
        Text {
            width: parent.width; horizontalAlignment: Text.AlignRight
            text: Qt.formatTime(t.now, "HH:mm")
            color: t.text1; font.family: "JetBrains Mono"; font.weight: Font.Light; font.pixelSize: 58
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignRight
            text: Qt.formatDate(t.now, "dddd  yyyy-MM-dd").toLowerCase()
            color: t.accent; opacity: 0.85; font.family: "JetBrains Mono"; font.pixelSize: 14; font.letterSpacing: 1.5
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
            text: t.system
            color: t.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
        }
    }
}
