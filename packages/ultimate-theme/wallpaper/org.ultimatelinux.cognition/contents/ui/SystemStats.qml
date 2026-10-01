/*
 * Live numbers for the wallpaper's system readout, from KDE's sensor
 * service (ksystemstats) -- the same source the System Monitor widgets
 * use. Publishes one plain object, `stats`, once a second:
 *   cpu, cores[], temp (0-100 / °C), memUsed, memTotal (bytes),
 *   down, up, read, write (bytes/s), uptime (seconds), os, kernel
 * Only this file needs Plasma; SystemHud draws whatever it is given.
 */
import QtQuick
import QtQml.Models
import org.kde.ksysguard.sensors as Sensors

Item {
    id: src
    property var stats: ({})

    component S: Sensors.Sensor { updateRateLimit: 1000 }

    S { id: cpu;      sensorId: "cpu/all/usage" }
    S { id: temp;     sensorId: "cpu/all/averageTemperature" }
    S { id: count;    sensorId: "cpu/all/cpuCount" }
    S { id: memUsed;  sensorId: "memory/physical/used" }
    S { id: memTotal; sensorId: "memory/physical/total" }
    S { id: down;     sensorId: "network/all/download" }
    S { id: up;       sensorId: "network/all/upload" }
    S { id: rd;       sensorId: "disk/all/read" }
    S { id: wr;       sensorId: "disk/all/write" }
    S { id: uptime;   sensorId: "os/system/uptime" }
    S { id: os;       sensorId: "os/system/name" }
    S { id: kernel;   sensorId: "os/kernel/prettyName" }

    Instantiator {
        id: cores
        model: Math.min(128, Number(count.value) || 0)
        delegate: S { required property int index; sensorId: "cpu/cpu" + index + "/usage" }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const c = []
            for (let i = 0; i < cores.count; i++) {
                const o = cores.objectAt(i)
                c.push(o ? Number(o.value) || 0 : 0)
            }
            src.stats = {
                cpu: Number(cpu.value) || 0, cores: c, temp: Number(temp.value) || 0,
                memUsed: Number(memUsed.value) || 0, memTotal: Number(memTotal.value) || 0,
                down: Number(down.value) || 0, up: Number(up.value) || 0,
                read: Number(rd.value) || 0, write: Number(wr.value) || 0,
                uptime: Number(uptime.value) || 0,
                os: String(os.value || ""), kernel: String(kernel.value || "")
            }
        }
    }
}
