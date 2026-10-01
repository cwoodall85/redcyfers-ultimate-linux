/*
 * The Ultimate splash: what you see between logging in and the desktop.
 *
 * The Cognition network (the wallpaper's own view, copied in beside this
 * file at build time) runs behind the Ultimate Linux mark; a row of linked
 * nodes lights up as Plasma reports each loading stage, and the whole
 * thing fades out onto the same network on the desktop, so the handover
 * looks like the network settling rather than a cut.
 *
 * ksplashqml sets `stage` as startup progresses (about 1..6); stage 6 is
 * the desktop being ready.
 */
import QtQuick
import QtQuick.Shapes

Rectangle {
    id: root
    color: "#030605"

    property int stage
    readonly property int stages: 6
    readonly property var labels: ["", "waking the network", "starting the window manager",
                                   "loading your settings", "starting services",
                                   "building the desktop", "ready"]

    CognitionView {
        anchors.fill: parent
        fps: 24
        brightness: 0.9
        showThoughts: true
        showClaude: false
        showStats: false
    }

    // A pool of darkness behind the mark, so it reads over the network.
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.width / 2; centerY: root.height / 2
                focalX: centerX; focalY: centerY
                centerRadius: Math.min(root.width, root.height) * 0.55
                focalRadius: 0
                GradientStop { position: 0.0; color: "#f0030605" }
                GradientStop { position: 0.5; color: "#a0030605" }
                GradientStop { position: 1.0; color: "#00030605" }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -height * 0.08
            spacing: 26

            Image {
                id: mark
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property int size: Math.round(Math.min(root.width, root.height) * 0.2)
                source: "images/ultimate-linux-mark.svg"
                sourceSize.width: size
                sourceSize.height: size
                width: size
                height: size
                // a slow breath, in step with the network
                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 1.035; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.035; to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
                }
            }

            // the name: a small "RedCyfer's" above the spaced title
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(mark.size * 0.03)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "REDCYFER'S"
                    color: "#99b8a3"
                    font.family: "Inter"
                    font.pixelSize: Math.round(mark.size * 0.085)
                    font.letterSpacing: Math.round(mark.size * 0.085 * 0.5)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "ULTIMATE LINUX"
                    color: "#cfe8d6"
                    font.family: "Inter"
                    font.pixelSize: Math.round(mark.size * 0.17)
                    font.weight: Font.Light
                    font.letterSpacing: Math.round(mark.size * 0.17 * 0.45)
                }
            }

            // Progress: linked nodes, lit one per stage.
            Item {
                id: progress
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property int gap: Math.round(mark.size * 0.22)
                readonly property int dot: Math.round(mark.size * 0.055)
                width: gap * (root.stages - 1) + dot * 2
                height: dot * 3

                Repeater {
                    model: root.stages - 1
                    Rectangle {
                        x: progress.dot + index * progress.gap
                        y: progress.height / 2 - height / 2
                        width: progress.gap
                        height: Math.max(2, Math.round(progress.dot * 0.3))
                        radius: height / 2
                        color: index + 1 < root.stage ? "#00c77a" : "#16221c"
                        Behavior on color { ColorAnimation { duration: 400 } }
                    }
                }
                Repeater {
                    model: root.stages
                    Rectangle {
                        readonly property bool lit: index < root.stage
                        readonly property bool current: index === root.stage - 1
                        x: progress.dot + index * progress.gap - width / 2
                        y: progress.height / 2 - height / 2
                        width: progress.dot * (current ? 2.4 : 2)
                        height: width
                        radius: width / 2
                        color: lit ? "#00ff9c" : "#16221c"
                        border.color: lit ? "#3dffb2" : "#22322a"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 400 } }
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.labels[Math.max(0, Math.min(root.stage, root.stages))] || ""
                color: "#6f8a7a"
                font.family: "JetBrains Mono"
                font.pixelSize: Math.round(mark.size * 0.1)
            }
        }
    }

    onStageChanged: {
        if (stage >= 1 && content.opacity === 0)
            fadeIn.running = true
    }

    OpacityAnimator {
        id: fadeIn
        target: content
        from: 0
        to: 1
        duration: 700
        easing.type: Easing.OutQuad
    }
}
