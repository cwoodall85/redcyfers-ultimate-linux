// Ultimate Clock widget: Plasma shell around ClockFace.qml (which is
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
    S { id: s_os; sensorId: "os/system/name" }
    S { id: s_kernel; sensorId: "os/kernel/prettyName" }
    S { id: s_uptime; sensorId: "os/system/uptime" }
    function duration(s) {
        s = Math.floor(Number(s) || 0)
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
    }
    fullRepresentation: ClockFace {
        id: face
        Layout.minimumWidth: 256; Layout.minimumHeight: 96
        Layout.preferredWidth: 320; Layout.preferredHeight: 144
        system: [String(s_kernel.value || "").replace(/^Linux\s+/, ""), s_uptime.value ? "up " + root.duration(s_uptime.value) : ""].filter(x => x).join("  ·  ")
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
            ;
            }
        }
    }
}
