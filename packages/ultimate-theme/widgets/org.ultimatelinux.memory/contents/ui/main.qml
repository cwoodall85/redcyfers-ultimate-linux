// Ultimate Memory widget: Plasma shell around MemoryFace.qml (which is
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
    S { id: s_used; sensorId: "memory/physical/used" }
    S { id: s_total; sensorId: "memory/physical/total" }
    S { id: s_sused; sensorId: "memory/swap/used" }
    S { id: s_stotal; sensorId: "memory/swap/total" }
    fullRepresentation: MemoryFace {
        id: face
        Layout.minimumWidth: 256; Layout.minimumHeight: 96
        Layout.preferredWidth: 320; Layout.preferredHeight: 96
        used: Number(s_used.value) || 0; total: Number(s_total.value) || 0; swapUsed: Number(s_sused.value) || 0; swapTotal: Number(s_stotal.value) || 0
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
            ;
            }
        }
    }
}
