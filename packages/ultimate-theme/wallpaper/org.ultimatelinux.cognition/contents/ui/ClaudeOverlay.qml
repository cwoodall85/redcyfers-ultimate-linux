/*
 * Claude's work, drawn over the desktop wallpaper: the question, each tool
 * as it runs, and the answer typing out, on a dark translucent panel with
 * a soft shadow. The shadow is layered rectangles, not a shader effect, so
 * it renders the same on software graphics and in virtual machines.
 *
 * It appears when a run starts and stays until the run is dismissed in
 * the Claude bar (Esc or ✕) or a new question replaces it: a timed fade
 * took long answers away before they were read.
 */
import QtQuick

Item {
    id: panel

    property var state_: ({})
    property bool enabled_: true
    property int maxHeight: 600
    readonly property string status: state_.status || ""
    readonly property var steps: state_.steps || []
    readonly property string answer: state_.error ? "⚠ " + state_.error : (state_.text || "")
    readonly property bool shown: enabled_ && !!state_.id

    height: Math.min(content.implicitHeight + 40, maxHeight)
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300 } }   // brief: on show/hide only

    // Typewriter: reveal the answer a few characters per frame.
    property int revealed: 0
    property string lastAnswer: ""
    onAnswerChanged: {
        if (!answer.startsWith(lastAnswer.slice(0, 20)))
            revealed = 0
        lastAnswer = answer
    }
    // Coarse steps on purpose: every step redraws the whole wallpaper.
    Timer {
        interval: 80
        running: panel.shown && panel.revealed < panel.answer.length
        repeat: true
        onTriggered: panel.revealed = Math.min(panel.answer.length, panel.revealed + 28)
    }

    // Soft shadow: widening, fading rectangles behind the panel.
    Repeater {
        model: 7
        Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: -(index + 1) * 4
            anchors.topMargin: -(index + 1) * 4 + 8
            anchors.bottomMargin: -(index + 1) * 4 - 8
            radius: 16 + (index + 1) * 4
            color: "black"
            opacity: 0.07
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.rgba(3 / 255, 9 / 255, 7 / 255, 0.74)
        border.width: 1
        border.color: Qt.rgba(0, 1, 156 / 255, 0.22)
    }

    Column {
        id: content
        x: 22; y: 20
        width: parent.width - 44
        spacing: 10
        clip: true

        Row {
            spacing: 10
            Rectangle {
                width: 10; height: 10; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: panel.status === "error" ? "#ff4d6d" : "#00ff9c"
                // Blinks on a slow timer rather than a 60 fps animation.
                opacity: panel.status === "thinking" ? (blink.on ? 1 : 0.3) : 1
                Timer {
                    id: blink
                    property bool on: true
                    interval: 600
                    repeat: true
                    running: panel.status === "thinking" && panel.shown
                    onTriggered: on = !on
                }
            }
            Text {
                text: "Claude"
                color: "#cfe8d6"
                font.family: "Inter"
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                anchors.baseline: parent.children[1].baseline
                text: panel.status === "thinking" ? "working…"
                    : panel.status === "done" ? (panel.steps.length + " steps")
                    : panel.status
                color: "#6f8a7a"
                font.family: "JetBrains Mono"
                font.pixelSize: 12
            }
        }

        Text {
            width: parent.width
            text: "› " + (panel.state_.prompt || "")
            color: "#8fb3a2"
            font.family: "Inter"
            font.pixelSize: 14
            font.italic: true
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Column {
            width: parent.width
            spacing: 3
            visible: panel.steps.length > 0
            Repeater {
                model: panel.steps.slice(-8)
                Text {
                    required property var modelData
                    required property int index
                    width: parent.width
                    elide: Text.ElideRight
                    text: "▸ " + modelData.name + "(" + (modelData.args || "") + ")"
                    color: "#00e68a"
                    opacity: 0.85
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                }
            }
        }

        Rectangle {
            width: parent.width; height: 1
            color: Qt.rgba(0, 1, 156 / 255, 0.15)
            visible: panel.answer.length > 0
        }

        Text {
            width: parent.width
            visible: panel.answer.length > 0
            text: panel.answer.slice(0, panel.revealed)
            textFormat: Text.MarkdownText
            wrapMode: Text.Wrap
            color: panel.state_.error ? "#ff9fb0" : "#e4f5ea"
            linkColor: "#3fe0c5"
            font.family: "Inter"
            font.pixelSize: 15
            lineHeight: 1.18
        }
    }
}
