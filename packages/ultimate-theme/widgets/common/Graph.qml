/*
 * A sparkline of one or more series with a soft glow and a fading fill.
 * push(values) once per sample; it keeps its own history.
 */
import QtQuick

Canvas {
    id: g
    property var colors: ["#00ffa8"]
    property var maxes: []            // per series; 0 = scale to the data
    property int samples: 60
    property var hist: []
    renderStrategy: Canvas.Cooperative

    function push(values) {
        const h = hist
        for (let i = 0; i < values.length; i++) {
            if (!h[i]) h[i] = []
            h[i].push(Number(values[i]) || 0)
            if (h[i].length > samples) h[i].shift()
        }
        hist = h
        requestPaint()
    }
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = "rgba(255, 255, 255, 0.06)"
        ctx.lineWidth = 1
        ctx.beginPath(); ctx.moveTo(0, height - 0.5); ctx.lineTo(width, height - 0.5); ctx.stroke()
        for (let s = 0; s < hist.length; s++) {
            const d = hist[s] || []
            if (d.length < 2) continue
            const c = Qt.color(colors[s % colors.length])
            const max = Math.max(maxes[s] || 0, ...d, 1)
            const step = width / (samples - 1)
            const x0 = width - (d.length - 1) * step
            const pts = d.map((v, i) => [x0 + i * step, height - 3 - (v / max) * (height - 8)])
            const grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.22))
            grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0))
            ctx.fillStyle = grad
            ctx.beginPath(); ctx.moveTo(pts[0][0], height)
            for (const p of pts) ctx.lineTo(p[0], p[1])
            ctx.lineTo(pts[pts.length - 1][0], height); ctx.closePath(); ctx.fill()
            for (const [w, a] of [[5, 0.12], [1.6, 0.95]]) {
                ctx.lineWidth = w
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, a)
                ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
                for (const p of pts) ctx.lineTo(p[0], p[1])
                ctx.stroke()
            }
        }
    }
}
