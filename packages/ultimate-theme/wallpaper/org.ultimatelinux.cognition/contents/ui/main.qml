// The Plasma wallpaper shell around CognitionView, which does the drawing
// and has no Plasma dependency (so it can be rendered and tested alone).
// It also reads the Claude bar's state (ultimate-claude-bar state), so the
// brain reacts while Claude works. The clock/system readout and Claude's
// answers are the Ultimate widgets now; the old in-wallpaper versions are
// still here behind ShowStats / ShowAnswers (off by default).
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

WallpaperItem {
    id: root

    readonly property bool showClaude: root.configuration.ShowClaude !== false
    // Without GPU acceleration every redraw is done on the CPU (Plasma and
    // KWin both), so the animation slows itself down.
    property bool softwareGL: false
    readonly property string glCmd:
        "busctl --user call org.kde.KWin /KWin org.kde.KWin supportInformation 2>/dev/null"
        + " | grep -qiE 'renderer string: (llvmpipe|softpipe|swrast)' && echo soft || echo hw"
    readonly property string stateCmd: "ultimate-claude-bar state 2>/dev/null || echo '{}'"

    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            if (source === root.glCmd)
                root.softwareGL = (data["stdout"] || "").trim() === "soft"
            else
                try { view.claude = JSON.parse(data["stdout"] || "{}") } catch (e) {}
            disconnectSource(source)
        }
    }
    Timer {   // KWin may not answer the moment the shell starts
        interval: 4000; running: true; onTriggered: shell.connectSource(root.glCmd)
    }

    Timer {
        // Fast while Claude is working, lazy otherwise.
        interval: view.claude.status === "thinking" ? 300 : 1500
        running: root.showClaude && root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.connectSource(root.stateCmd)
    }

    // Live system numbers, for the readout drawn into the wallpaper.
    Loader {
        id: sensors
        active: root.configuration.ShowStats === true
        source: "SystemStats.qml"
    }
    Connections {
        target: sensors.item
        function onStatsChanged() { view.stats = sensors.item.stats }
    }

    CognitionView {
        id: view
        anchors.fill: parent
        fps: Math.min(root.configuration.Fps || 15, root.softwareGL ? 6 : 60)
        brightness: (root.configuration.Brightness || 85) / 100
        showThoughts: root.configuration.ShowThoughts !== false
        fullRes: !root.softwareGL
        showClaude: root.showClaude
        showStats: root.configuration.ShowStats === true
        showAnswers: root.configuration.ShowAnswers === true
        running: root.visible
    }
}
