// Ultimate Disk widget: Plasma shell around DiskFace.qml (which is
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
    S { id: s_rd; sensorId: "disk/all/read" }
    S { id: s_wr; sensorId: "disk/all/write" }
    S { id: s_rootUsed; sensorId: "disk/all/used" }
    S { id: s_rootTotal; sensorId: "disk/all/total" }
    fullRepresentation: DiskFace {
        id: face
        Layout.minimumWidth: 256; Layout.minimumHeight: 96
        Layout.preferredWidth: 320; Layout.preferredHeight: 144
        read: Number(s_rd.value) || 0; write: Number(s_wr.value) || 0; rootUsed: Number(s_rootUsed.value) || 0; rootTotal: Number(s_rootTotal.value) || 0
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
            face.sample()
            }
        }
    }
}
