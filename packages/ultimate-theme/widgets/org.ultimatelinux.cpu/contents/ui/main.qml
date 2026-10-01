// Ultimate CPU widget: Plasma shell around CpuFace.qml (which is
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
    S { id: s_cpu; sensorId: "cpu/all/usage" }
    S { id: s_temp; sensorId: "cpu/all/averageTemperature" }
    S { id: s_count; sensorId: "cpu/all/cpuCount" }
    Instantiator {
        id: s_cores
        model: Math.min(128, Number(s_count.value) || 0)
        delegate: S { required property int index; sensorId: "cpu/cpu" + index + "/usage" }
    }
    fullRepresentation: CpuFace {
        id: face
        Layout.minimumWidth: 256; Layout.minimumHeight: 96
        Layout.preferredWidth: 320; Layout.preferredHeight: 176
        usage: Number(s_cpu.value) || 0; temp: Number(s_temp.value) || 0
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
            const c = []
            for (let i = 0; i < s_cores.count; i++) { const o = s_cores.objectAt(i); c.push(o ? Number(o.value) || 0 : 0) }
            face.cores = c
            face.sample()
            }
        }
    }
}
