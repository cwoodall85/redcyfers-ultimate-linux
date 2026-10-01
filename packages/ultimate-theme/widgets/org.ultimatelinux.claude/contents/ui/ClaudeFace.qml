import QtQuick
import QtQuick.Controls as QQC2
Tile {
    id: t
    accent: "#ff8f6b"
    label: "CLAUDE"
    // run: the Claude bar's current state; history: earlier answers, oldest first
    property var run: ({})
    property var history: []
    property int page: -1              // -1 = the current run, else an index into history
    signal wantHistory()
    readonly property var shown: page < 0 ? run : (history[page] || {})
    live: run.status === "thinking" || run.status === "listening"
    value: page >= 0 ? (page + 1) + " / " + history.length
         : run.status === "thinking" ? ((run.steps || []).length ? "▸ " + run.steps[run.steps.length - 1].name + "()" : "thinking…")
         : run.status === "done" ? "answered" : run.status || "idle"
    Column {
        anchors.fill: parent
        spacing: 8
        Text {
            width: parent.width
            text: t.shown.prompt ? "› " + t.shown.prompt : "Ask with Meta+Space. Answers stay here: scroll, or page back with ◀."
            color: t.shown.prompt ? "#ffc7b3" : t.text2
            font.family: "Inter"; font.pixelSize: 13; font.italic: !!t.shown.prompt
            wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
        }
        Rectangle { width: parent.width; height: 1; color: t.accent; opacity: 0.18 }
        QQC2.ScrollView {
            id: scroll
            width: parent.width
            height: parent.height - y - nav.height - parent.spacing
            clip: true
            contentWidth: availableWidth
            TextEdit {
                width: scroll.availableWidth
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.MarkdownText
                color: t.shown.error ? "#ff9fb0" : t.text1
                selectionColor: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.4)
                font.family: "Inter"; font.pixelSize: 13
                text: t.shown.error ? "⚠ " + t.shown.error : (t.shown.text || "")
            }
        }
        Row {
            id: nav
            spacing: 6
            height: 24
            component Btn: Rectangle {
                property string label
                signal clicked()
                width: Math.max(28, lbl.implicitWidth + 16); height: 22; radius: 6
                color: ma.containsMouse ? Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.05)
                border.width: 1; border.color: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.25)
                Text { id: lbl; anchors.centerIn: parent; text: parent.label; color: t.text1; font.family: "JetBrains Mono"; font.pixelSize: 11 }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
            }
            Btn { label: "◀"; onClicked: { t.wantHistory(); t.page = t.page < 0 ? t.history.length - 1 : Math.max(0, t.page - 1) } }
            Btn { label: "▶"; onClicked: t.page = (t.page < 0 || t.page >= t.history.length - 1) ? -1 : t.page + 1 }
            Btn { label: "now"; visible: t.page >= 0; onClicked: t.page = -1 }
        }
    }
    // a new question brings the tile back to the current run
    property string lastRun: ""
    onRunChanged: if (run.id && run.id !== lastRun) { lastRun = run.id; page = -1 }
}
