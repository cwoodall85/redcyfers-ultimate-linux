// Ultimate Network widget: Plasma shell around NetworkFace.qml (which is
// plain QML, so it can be previewed without Plasma). Numbers come from
// KDE's sensor service (ksystemstats), like the System Monitor widgets.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    component S: Sensors.Sensor { updateRateLimit: 1000 }
    S { id: s_down; sensorId: "network/all/download" }
    S { id: s_up; sensorId: "network/all/upload" }
    fullRepresentation: NetworkFace {
        id: face
        Layout.minimumWidth: 256; Layout.minimumHeight: 96
        Layout.preferredWidth: 320; Layout.preferredHeight: 128
        down: Number(s_down.value) || 0; up: Number(s_up.value) || 0
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
            face.sample()
            }
        }
    }
}
