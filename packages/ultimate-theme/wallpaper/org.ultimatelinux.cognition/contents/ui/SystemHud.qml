/*
 * The system readout, drawn straight onto the wallpaper: no boxes, no
 * backgrounds, just type and fine glowing graphs in a slim column on the
 * right. (The view shades that side of the screen so it stays readable.) Clock and system line,
 * then CPU (history + per-core), memory, network and disk.
 *
 * Takes `stats` (see SystemStats.qml) and keeps its own short history for
 * the graphs. No Plasma imports, so it can be rendered and tested alone.
 *
 * Nothing here animates: values change once a second, in one step. A
 * smooth 60 fps slide would make the whole wallpaper redraw at 60 fps.
 */
import QtQuick

Item {
    id: hud

    property var stats: ({})
    readonly property int samples: 60
    property var hist: ({ cpu: [], down: [], up: [], read: [], write: [] })

    readonly property color mint: "#00ff9c"
    readonly property color teal: "#3fe0c5"
    readonly property color amber: "#f5c542"
    readonly property color text1: "#dff3e6"
    readonly property color text2: "#7fa593"

    onStatsChanged: {
        if (stats.cpu === undefined)
            return
        const h = hist
        for (const k of ["cpu", "down", "up", "read", "write"]) {
            h[k].push(Number(stats[k]) || 0)
            if (h[k].length > samples)
                h[k].shift()
        }
        hist = h
        for (const g of [cpuGraph, netGraph, diskGraph])
            g.requestPaint()
    }

    function rate(b) {
        b = Number(b) || 0
        const u = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
        let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i === 0 ? Math.round(b) : b.toFixed(b < 10 ? 1 : 0)) + " " + u[i]
    }
    function bytes(b) {
        return (Number(b) / 1073741824).toFixed(1)
    }
    function duration(s) {
        s = Math.floor(Number(s) || 0)
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
    }

    component Caption: Row {
        property alias label: l.text
        property alias value: v.text
        width: parent.width
        Text {
            id: l
            width: parent.width / 2
            color: hud.mint
            opacity: 0.8
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            font.letterSpacing: 2.5
        }
        Text {
            id: v
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            color: hud.text1
            font.family: "JetBrains Mono"
            font.pixelSize: 13
        }
    }

    // A sparkline of one or two series, with a soft glow and a fading fill.
    component Graph: Canvas {
        id: g
        property var series: []          // [{data: [], color, max}]
        width: parent.width
        height: 46
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "rgba(0, 255, 156, 0.08)"
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, height - 0.5); ctx.lineTo(width, height - 0.5); ctx.stroke()
            for (const s of series) {
                const d = s.data || []
                if (d.length < 2)
                    continue
                const max = Math.max(s.max || 0, ...d, 1)
                const step = width / (hud.samples - 1)
                const x0 = width - (d.length - 1) * step
                const pts = d.map((v, i) => [x0 + i * step, height - 3 - (v / max) * (height - 8)])
                // fill
                const grad = ctx.createLinearGradient(0, 0, 0, height)
                grad.addColorStop(0, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.22))
                grad.addColorStop(1, Qt.rgba(s.color.r, s.color.g, s.color.b, 0))
                ctx.fillStyle = grad
                ctx.beginPath(); ctx.moveTo(pts[0][0], height)
                for (const p of pts) ctx.lineTo(p[0], p[1])
                ctx.lineTo(pts[pts.length - 1][0], height); ctx.closePath(); ctx.fill()
                // glow, then the line
                for (const [w, a] of [[5, 0.12], [1.6, 0.95]]) {
                    ctx.lineWidth = w
                    ctx.strokeStyle = Qt.rgba(s.color.r, s.color.g, s.color.b, a)
                    ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
                    for (const p of pts) ctx.lineTo(p[0], p[1])
                    ctx.stroke()
                }
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 7

        // ---- clock
        Text {
            id: clock
            width: parent.width
            horizontalAlignment: Text.AlignRight
            color: hud.text1
            font.family: "JetBrains Mono"
            font.weight: Font.Light
            font.pixelSize: 64
            property var now: new Date()
            text: Qt.formatTime(now, "HH:mm")
            Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            color: hud.mint
            opacity: 0.85
            font.family: "JetBrains Mono"
            font.pixelSize: 15
            font.letterSpacing: 1.5
            text: Qt.formatDate(clock.now, "dddd  yyyy-MM-dd").toLowerCase()
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            color: hud.text2
            elide: Text.ElideLeft
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            text: [hud.stats.os, (hud.stats.kernel || "").replace(/^Linux\s+/, ""),
                   hud.stats.uptime ? "up " + hud.duration(hud.stats.uptime) : ""]
                  .filter(x => x).join("  ·  ")
        }
        Item { width: 1; height: 22 }

        // ---- CPU
        Caption {
            label: "CPU"
            value: Math.round(hud.stats.cpu || 0) + "%" + (hud.stats.temp > 1 ? "   " + Math.round(hud.stats.temp) + "°C" : "")
        }
        Graph {
            id: cpuGraph
            series: [{ data: hud.hist.cpu, color: hud.mint, max: 100 }]
        }
        Row {
            id: coresRow
            width: parent.width
            height: 22
            spacing: 2
            readonly property var cores: hud.stats.cores || []
            Repeater {
                model: coresRow.cores.length
                Item {
                    required property int index
                    width: (coresRow.width - (coresRow.cores.length - 1) * coresRow.spacing) / Math.max(1, coresRow.cores.length)
                    height: coresRow.height
                    Rectangle { anchors.fill: parent; color: hud.mint; opacity: 0.08 }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(1, parent.height * Math.min(100, coresRow.cores[index] || 0) / 100)
                        color: Qt.tint(hud.mint, Qt.rgba(hud.teal.r, hud.teal.g, hud.teal.b, 1 - (coresRow.cores[index] || 0) / 100))
                        opacity: 0.85
                    }
                }
            }
        }
        Item { width: 1; height: 16 }

        // ---- memory
        Caption {
            label: "MEMORY"
            value: hud.stats.memTotal ? hud.bytes(hud.stats.memUsed) + " / " + hud.bytes(hud.stats.memTotal) + " GiB" : ""
        }
        Item {
            width: parent.width
            height: 4
            Rectangle { anchors.fill: parent; radius: 2; color: hud.mint; opacity: 0.12 }
            Rectangle {
                height: parent.height
                radius: 2
                width: parent.width * (hud.stats.memTotal ? Math.min(1, hud.stats.memUsed / hud.stats.memTotal) : 0)
                color: hud.mint
            }
        }
        Item { width: 1; height: 16 }

        // ---- network
        Caption {
            label: "NETWORK"
            value: "↓ " + hud.rate(hud.stats.down) + "   ↑ " + hud.rate(hud.stats.up)
        }
        Graph {
            id: netGraph
            series: [{ data: hud.hist.down, color: hud.teal }, { data: hud.hist.up, color: hud.mint }]
        }
        Item { width: 1; height: 16 }

        // ---- disk
        Caption {
            label: "DISK"
            value: "r " + hud.rate(hud.stats.read) + "   w " + hud.rate(hud.stats.write)
        }
        Graph {
            id: diskGraph
            series: [{ data: hud.hist.read, color: hud.teal }, { data: hud.hist.write, color: hud.amber }]
        }
    }

    height: col.implicitHeight
}
