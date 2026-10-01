// Ultimate Claude widget: Plasma shell around ClaudeFace.qml (which is
// plain QML, so it can be previewed without Plasma).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    readonly property string stateCmd: "ultimate-claude-bar state 2>/dev/null || echo '{}'"
    readonly property string historyCmd: "ultimate-claude-bar history 50 2>/dev/null || echo '[]'"
    // kept here, not in the face: the face lives in its own component and
    // the timer and data source can't see into it
    property var run: ({})
    property var history: []
    readonly property bool busy: run.status === "thinking" || run.status === "listening"
    P5Support.DataSource {
        id: shell
        engine: "executable"
        onNewData: (source, data) => {
            try {
                if (source === root.stateCmd) root.run = JSON.parse(data["stdout"] || "{}")
                else root.history = JSON.parse(data["stdout"] || "[]")
            } catch (e) {}
            disconnectSource(source)
        }
    }
    Timer {
        interval: root.busy ? 400 : 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: shell.connectSource(root.stateCmd)
    }
    fullRepresentation: ClaudeFace {
        id: face
        run: root.run
        history: root.history
        Layout.minimumWidth: 256; Layout.minimumHeight: 192
        Layout.preferredWidth: 320; Layout.preferredHeight: 400
        onWantHistory: shell.connectSource(root.historyCmd)
        Component.onCompleted: shell.connectSource(root.historyCmd)
    }
}
