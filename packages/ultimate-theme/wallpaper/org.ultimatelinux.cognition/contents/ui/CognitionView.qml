/*
 * Cognition -- the Ultimate Linux wallpaper: an AI brain, thinking.
 *
 * A brain in profile (frontal lobe to the left), made of a neural mesh:
 * a few hundred nodes filling its outline, each wired to its nearest
 * neighbours, with faint folds (sulci) inside. Circuit traces run in from
 * the edges of the screen -- data arriving -- and each pulse that reaches
 * the brain sets off a chain of signals hopping node to node. Nodes flare
 * where a signal lands; now and then a fragment of machine thought
 * surfaces beside one.
 *
 * When Claude is working (the Claude bar's state), the brain speeds up and
 * its signals turn Claude's warm coral; every tool it runs sends a ripple
 * across one lobe and surfaces the tool's name there.
 *
 * Drawn for cost, as before. Qt's Canvas rasterises on the CPU and uploads
 * its whole image every frame, so:
 *   lattice  -- glow, silhouette, folds, traces, resting mesh: painted once
 *               per layout;
 *   activity -- hot edges, flaring nodes, pulses: redrawn each frame, at
 *               full resolution with GPU acceleration, else at half
 *               resolution (a quarter of the pixels), scaled up;
 *   fragments -- ordinary Text items whose fades step on the same timer.
 * All motion advances on the one timer below: a 60 fps animation anywhere
 * would redraw the whole desktop at 60 fps.
 */
import QtQuick

Item {
    id: view

    property int fps: 15
    property real brightness: 0.85
    property bool showThoughts: true
    // Draw the moving layer at full resolution; false = half resolution,
    // scaled up (a quarter of the pixels), for machines without GPU acceleration.
    property bool fullRes: true
    property bool running: true
    property bool showClaude: true      // react to Claude working
    property bool showAnswers: false    // draw Claude's answer panel over the wallpaper
    property bool showStats: false      // the old readout; the Ultimate widgets replace it
    property var stats: ({})
    readonly property int hudWidth: showStats ? Math.max(280, Math.min(340, Math.round(width * 0.2))) : 0
    readonly property int topInset: 56     // below the Claude bar panel
    // The Claude bar's state: {id, prompt, status, steps, text, error, ...}
    property var claude: ({})
    readonly property bool thinking: showClaude && claude.status === "thinking"
    property int seenSteps: 0

    readonly property color mint: "#00ffa8"
    readonly property color coral: "#ff8f6b"     // Claude at work

    onClaudeChanged: {
        const steps = (claude && claude.steps) || []
        if (steps.length < seenSteps)
            seenSteps = 0
        for (let i = seenSteps; i < steps.length; i++)
            net.surface(steps[i].name + "()")
        seenSteps = steps.length
    }

    readonly property var thoughts: [
        "attn = softmax(Q·Kᵀ / √d)", "h₁₂ ← gelu(W·x + b)", "embed(\"why\") ∈ ℝ⁴⁰⁹⁶",
        "p(next | ctx) = 0.873", "∇L → 3.1e-4", "plan → act → observe",
        "recall(ctx, k=8)", "think { hypothesis₃ }", "token[4127] = \"reason\"",
        "score = ⟨q, k⟩", "layer 31 / head 7", "if uncertain: ask()",
        "memory.write(fact)", "chain = [obs, infer, check]", "Σ wᵢxᵢ", "argmax logits",
        "context: 1M", "loss ↓ 0.0112", "tool_use: search()", "verify(answer)",
        "weights ≈ 10¹¹", "residual += Δh", "latent ⊕ prompt", "self.reflect()"
    ]

    Rectangle {
        anchors.fill: parent
        color: "#020504"
    }

    // ---- the model: shape, nodes, edges, traces, signals; no drawing here --
    QtObject {
        id: net

        // The brain in a unit box (x 0..1 left to right, y 0..1 top to
        // bottom), as overlapping lobes: [cx, cy, rx, ry, rotation, name].
        readonly property var lobes: [
            [0.50, 0.38, 0.38, 0.27, 0.00, "cerebrum"],
            [0.25, 0.43, 0.21, 0.24, -0.30, "frontal"],
            [0.55, 0.25, 0.30, 0.16, 0.06, "parietal"],
            [0.81, 0.40, 0.15, 0.19, 0.30, "occipital"],
            [0.47, 0.58, 0.25, 0.115, 0.16, "temporal"],
            [0.745, 0.685, 0.14, 0.095, 0.16, "cerebellum"],
            [0.60, 0.79, 0.045, 0.13, -0.30, "stem"]
        ]
        property var box: ({ x: 0, y: 0, w: 0, h: 0 })
        property var nodes: []     // {x, y, lobe, act, hue}
        property var edges: []     // {a, b, heat, hue}
        property var nbr: []       // node -> [edge index]
        property var traces: []    // {pts: [[x,y]...], len, node}
        property var sulci: []     // gyri: meandering folds, [[x,y]...]
        property var strata: []    // the cerebellum's fine parallel folds
        property var rims: []      // outline segments [x1,y1,x2,y2]
        property var pulses: []    // edge pulses {e, from, t, speed, hops, hue}
        property var packets: []   // trace pulses {tr, d, speed, hue}
        property var ripples: []   // {x, y, t0, hue}
        property var labels: []
        property real clock: 0
        property int nextLabel: 0
        readonly property real w: view.width
        readonly property real h: view.height

        function inLobe(L, u, v) {
            const c = Math.cos(-L[4]), s = Math.sin(-L[4])
            const dx = u - L[0], dy = v - L[1]
            const x = dx * c - dy * s, y = dx * s + dy * c
            return (x * x) / (L[2] * L[2]) + (y * y) / (L[3] * L[3]) <= 1
        }
        function lobeAt(u, v) {
            for (let i = 0; i < lobes.length; i++)
                if (inLobe(lobes[i], u, v)) return i
            return -1
        }
        function toScreen(u, v) { return [box.x + u * box.w, box.y + v * box.h] }

        function build() {
            if (w <= 0 || h <= 0)
                return
            // The brain fills ~64% of the height, a little right of centre
            // (the desktop's icons and widgets live on the left and right).
            let bh = h * 0.64, bw = bh / 0.8
            if (bw > w * 0.66) { bw = w * 0.66; bh = bw * 0.8 }
            box = { x: (w - bw) / 2 + w * 0.02, y: (h - bh) / 2 + h * 0.03, w: bw, h: bh }

            // Nodes: a jittered grid, kept where it falls inside a lobe.
            const ns = [], cols = 30, rows = 24
            for (let r = 0; r < rows; r++) {
                for (let c = 0; c < cols; c++) {
                    const u = (c + 0.5 + (Math.random() - 0.5) * 0.8) / cols
                    const v = (r + 0.5 + (Math.random() - 0.5) * 0.8) / rows
                    const lobe = lobeAt(u, v)
                    if (lobe < 0 || Math.random() < 0.08)
                        continue
                    const p = toScreen(u, v)
                    ns.push({ x: p[0], y: p[1], u: u, v: v, lobe: lobe, act: 0, hue: 0 })
                }
            }
            // Edges: each node to its nearest few.
            const es = [], nb = ns.map(() => []), seen = {}
            const reach = box.w / cols * 1.75
            for (let i = 0; i < ns.length; i++) {
                const near = []
                for (let j = 0; j < ns.length; j++) {
                    if (i === j) continue
                    const d = Math.hypot(ns[i].x - ns[j].x, ns[i].y - ns[j].y)
                    if (d < reach) near.push([d, j])
                }
                near.sort((p, q) => p[0] - q[0])
                for (const [, j] of near.slice(0, 2 + Math.floor(Math.random() * 3))) {
                    const k = i < j ? i + "-" + j : j + "-" + i
                    if (seen[k]) continue
                    seen[k] = true
                    nb[i].push(es.length); nb[j].push(es.length)
                    es.push({ a: i, b: j, heat: 0, hue: 0 })
                }
            }
            // Folds (gyri): short meandering curves that wander the cerebrum
            // without leaving it, like the surface of a real brain.
            const inCere = (u, v) => { for (let i = 0; i < 5; i++) if (inLobe(lobes[i], u, v)) return true; return false }
            const sl = []
            for (let k = 0; k < 70; k++) {
                let u, v, tries = 0
                do { u = 0.05 + Math.random() * 0.9; v = 0.08 + Math.random() * 0.62; tries++ }
                while ((!inCere(u, v) || lobeAt(u, v) === 5) && tries < 50)
                let ang = Math.random() * 6.2832, turn = 0
                const pts = [toScreen(u, v)], n = 14 + Math.floor(Math.random() * 26), stepU = 0.011
                for (let i = 0; i < n; i++) {
                    turn = turn * 0.7 + (Math.random() - 0.5) * 0.9
                    ang += turn
                    const nu = u + Math.cos(ang) * stepU, nv = v + Math.sin(ang) * stepU * 1.25
                    if (!inCere(nu, nv) || inLobe(lobes[5], nu, nv)) { ang += 2.2; continue }
                    u = nu; v = nv
                    pts.push(toScreen(u, v))
                }
                if (pts.length > 5) sl.push(pts)
            }
            // The lateral fissure: the long fold above the temporal lobe.
            const lat = []
            for (let i = 0; i <= 40; i++) {
                const u = 0.20 + i / 40 * 0.50
                lat.push(toScreen(u, 0.50 - (u - 0.20) * 0.10 + Math.sin(u * 13) * 0.01))
            }
            sl.push(lat)
            // Cerebellum: fine parallel arcs.
            const L5 = lobes[5], st = []
            for (let k = -6; k <= 6; k++) {
                const pts = []
                for (let i = 0; i <= 30; i++) {
                    const t = -1 + i / 15
                    const x = t * L5[2] * 1.1, y = k / 6.5 * L5[3] + (1 - t * t) * 0.012
                    const c = Math.cos(L5[4]), sn = Math.sin(L5[4])
                    pts.push(toScreen(L5[0] + x * c - y * sn, L5[1] + x * sn + y * c))
                }
                st.push(pts)
            }
            // Outline: marching squares over a smooth field (how far inside the
            // nearest lobe a point is), with the crossing interpolated, so the
            // rim is a clean curve. Cerebrum and hindbrain (cerebellum + stem)
            // are traced separately so the notch between them shows.
            const field = (u, v, from, to) => {
                let best = -9
                for (let i = from; i <= to; i++) {
                    const L = lobes[i], c = Math.cos(-L[4]), sn = Math.sin(-L[4])
                    const dx = u - L[0], dy = v - L[1]
                    const x = dx * c - dy * sn, y = dx * sn + dy * c
                    best = Math.max(best, 1 - (x * x) / (L[2] * L[2]) - (y * y) / (L[3] * L[3]))
                }
                return best
            }
            const rimSegs = []
            const G = 220, GH = 176
            const traceField = (f) => {
                const m = []
                for (let j = 0; j <= GH; j++) { m.push([]); for (let i = 0; i <= G; i++) m[j].push(f(i / G, j / GH)) }
                const cross = (i1, j1, i2, j2) => {
                    const a = m[j1][i1], b = m[j2][i2], t = a / (a - b)
                    return toScreen((i1 + (i2 - i1) * t) / G, (j1 + (j2 - j1) * t) / GH)
                }
                for (let j = 0; j < GH; j++) for (let i = 0; i < G; i++) {
                    const pts = []
                    if ((m[j][i] > 0) !== (m[j][i + 1] > 0)) pts.push(cross(i, j, i + 1, j))
                    if ((m[j][i + 1] > 0) !== (m[j + 1][i + 1] > 0)) pts.push(cross(i + 1, j, i + 1, j + 1))
                    if ((m[j + 1][i + 1] > 0) !== (m[j + 1][i] > 0)) pts.push(cross(i + 1, j + 1, i, j + 1))
                    if ((m[j + 1][i] > 0) !== (m[j][i] > 0)) pts.push(cross(i, j + 1, i, j))
                    for (let q = 0; q + 1 < pts.length; q += 2)
                        rimSegs.push([pts[q][0], pts[q][1], pts[q + 1][0], pts[q + 1][1]])
                }
            }
            traceField((u, v) => field(u, v, 0, 4))
            traceField((u, v) => Math.min(field(u, v, 5, 6), -field(u, v, 0, 4)))
            // Traces: data lines from the screen edges into nodes on the rim.
            const trs = []
            const rim = ns.map((n, i) => [i, nb[i].length]).filter(p => p[1] <= 3).map(p => p[0])
            const wanted = 10
            for (let k = 0; k < wanted && rim.length; k++) {
                const i = rim.splice(Math.floor(Math.random() * rim.length), 1)[0]
                const n = ns[i]
                const cx = box.x + box.w / 2, cy = box.y + box.h / 2
                const pts = [[n.x, n.y]]
                // leave the brain away from its centre, then bend to the edge: 45° then straight
                const goLeft = n.x < cx, goDown = n.y > cy + box.h * 0.1
                const run = box.w * (0.05 + Math.random() * 0.08)
                if (goDown && Math.random() < 0.6) {
                    const x1 = n.x + (goLeft ? -run : run) * 0.5, y1 = n.y + run
                    pts.push([x1, y1]); pts.push([x1, h + 4])
                } else {
                    const x1 = n.x + (goLeft ? -run : run), y1 = n.y + (n.y < cy ? -run : run) * 0.5
                    pts.push([x1, y1]); pts.push([goLeft ? -4 : w + 4, y1])
                }
                let len = 0
                for (let q = 1; q < pts.length; q++) len += Math.hypot(pts[q][0] - pts[q - 1][0], pts[q][1] - pts[q - 1][1])
                trs.push({ pts: pts.reverse(), len: len, node: i })   // edge of screen -> brain
            }
            nodes = ns; edges = es; nbr = nb; traces = trs; sulci = sl; strata = st; rims = rimSegs
            pulses = []; packets = []; ripples = []; labels = []; fragments.clear()
            lattice.requestPaint()
        }

        function outline(ctx) {      // the union of the lobes, as one path
            ctx.beginPath()
            for (const L of lobes) {
                const c = toScreen(L[0], L[1])
                ctx.save()
                ctx.translate(c[0], c[1]); ctx.rotate(L[4]); ctx.scale(L[2] * box.w, L[3] * box.h)
                ctx.moveTo(1, 0); ctx.arc(0, 0, 1, 0, 6.2832)
                ctx.restore()
            }
        }

        function tracePoint(tr, d) {
            let left = d
            for (let q = 1; q < tr.pts.length; q++) {
                const a = tr.pts[q - 1], b = tr.pts[q]
                const seg = Math.hypot(b[0] - a[0], b[1] - a[1])
                if (left <= seg) { const k = seg ? left / seg : 0; return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k] }
                left -= seg
            }
            return tr.pts[tr.pts.length - 1]
        }

        function fire(node, hops, hue) {
            const choices = nbr[node]
            if (!choices || !choices.length || hops <= 0)
                return
            const e = choices[Math.floor(Math.random() * choices.length)]
            pulses.push({ e: e, from: node, t: 0, speed: 1.6 + Math.random() * 1.4, hops: hops, hue: hue })
        }

        function textWidth(text) { return text.length * Math.max(12, h / 70) * 0.62 }
        function crowded(x, y, text) {
            const tw = textWidth(text)
            if (x < 8 || x + tw > w - (view.showStats ? view.hudWidth + w * 0.035 + 40 : 12))
                return true
            return labels.some(l => Math.abs(l.y - y) < h / 30 && x < l.x + textWidth(l.text) && l.x < x + tw)
        }
        function fresh() {
            const shown = labels.map(l => l.text)
            const left = view.thoughts.filter(t => shown.indexOf(t) < 0)
            return left.length ? left[Math.floor(Math.random() * left.length)] : ""
        }
        function addLabel(text, x, y, kind, life) {
            const id = nextLabel++
            labels.push({ id: id, text: text, x: x, y: y, dim: kind === "dim", born: clock, life: life, until: clock + life })
            fragments.append({ lid: id, words: text, px: x, py: y, kind: kind, fade: 0 })
        }
        function fadeLabels() {
            for (let i = fragments.count - 1; i >= 0; i--) {
                const f = fragments.get(i)
                const l = labels.find(x => x.id === f.lid)
                if (!l) { fragments.remove(i); continue }
                const age = clock - l.born
                const k = Math.max(0, Math.min(1, age / 0.6, (l.life - age) / 0.9))
                if (Math.abs(k - f.fade) > 0.01)
                    fragments.setProperty(i, "fade", k)
            }
        }

        // A tool Claude just ran: a ripple across one lobe, and its name there.
        function surface(text) {
            if (!nodes.length)
                return
            const n = nodes[Math.floor(Math.random() * nodes.length)]
            ripples.push({ x: n.x, y: n.y, t0: clock, hue: 1 })
            for (let k = 0; k < 4; k++) fire(nodes.indexOf(n), 7, 1)
            const tx = n.x + 14, ty = n.y - 16
            addLabel(text, Math.min(tx, w - textWidth(text) - 16), ty, "claude", 6)
        }

        function step(dt) {
            clock += dt
            labels = labels.filter(l => l.until > clock)
            const hue = view.thinking ? 1 : 0
            const load = Math.min(1, (Number(view.stats.cpu) || 0) / 100)
            const busy = (view.thinking ? 3.2 : 1) * (1 + load)

            // Background murmur: dim fragments drifting around the brain.
            if (view.showThoughts && labels.filter(l => l.dim).length < 7 && Math.random() < dt * 0.7) {
                const text = fresh()
                const side = Math.random() < 0.5
                const x = side ? box.x - textWidth(text) - w * 0.02 - Math.random() * w * 0.08
                               : box.x + box.w + w * 0.02 + Math.random() * w * 0.06
                const y = box.y + Math.random() * box.h
                if (text && !crowded(x, y, text))
                    addLabel(text, x, y, "dim", 6 + Math.random() * 6)
            }
            // Data arriving: packets run in along the traces.
            if (traces.length && packets.length < 5 * busy && Math.random() < dt * 1.1 * busy)
                packets.push({ tr: Math.floor(Math.random() * traces.length), d: 0,
                               speed: box.w * (0.35 + Math.random() * 0.3), hue: hue })
            // ...and spontaneous activity inside.
            if (nodes.length && pulses.length < 26 * busy && Math.random() < dt * 2.2 * busy)
                fire(Math.floor(Math.random() * nodes.length), 4 + Math.floor(Math.random() * 5), hue)

            const livePk = []
            for (const p of packets) {
                p.d += dt * p.speed
                if (p.d >= traces[p.tr].len) {
                    const node = traces[p.tr].node
                    nodes[node].act = 1; nodes[node].hue = p.hue
                    for (let k = 0; k < 2; k++) fire(node, 6 + Math.floor(Math.random() * 4), p.hue)
                } else livePk.push(p)
            }
            packets = livePk

            const alive = []
            for (const p of pulses) {
                p.t += dt * p.speed
                const e = edges[p.e]
                e.heat = 1; e.hue = p.hue
                if (p.t >= 1) {
                    const to = e.a === p.from ? e.b : e.a
                    const n = nodes[to]
                    n.act = 1; n.hue = p.hue
                    if (view.showThoughts && labels.filter(l => !l.dim).length < 4 && Math.random() < 0.025) {
                        const text = fresh()
                        if (text && !crowded(n.x + 14, n.y - 16, text))
                            addLabel(text, n.x + 14, n.y - 16, "bright", 3 + Math.random() * 2)
                    }
                    fire(to, p.hops - 1, p.hue)
                } else alive.push(p)
            }
            pulses = alive

            // Ripples: a ring spreading from a point, lighting what it passes.
            const band = box.w * 0.035, speed = box.w * 0.45
            ripples = ripples.filter(r => clock - r.t0 < 1.4)
            for (const r of ripples) {
                const rad = (clock - r.t0) * speed
                for (const n of nodes) {
                    const d = Math.hypot(n.x - r.x, n.y - r.y)
                    if (Math.abs(d - rad) < band && n.act < 0.85) { n.act = 0.85; n.hue = r.hue }
                }
            }

            const na = Math.pow(0.2, dt), ea = Math.pow(0.3, dt)
            for (const n of nodes) n.act *= na
            for (const e of edges) e.heat *= ea
            fadeLabels()
        }
    }
    onWidthChanged: net.build()
    onHeightChanged: net.build()
    Component.onCompleted: net.build()

    function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a.toFixed(3) + ")" }
    function hueColor(hue) { return hue ? view.coral : view.mint }

    // ---- lattice: painted once per layout -------------------------------
    Canvas {
        id: lattice
        anchors.fill: parent
        opacity: view.brightness
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const B = net.box
            if (!B.w) return
            const cx = B.x + B.w * 0.5, cy = B.y + B.h * 0.45
            // aura
            let g = ctx.createRadialGradient(cx, cy, 0, cx, cy, B.w * 0.85)
            g.addColorStop(0, "rgba(0, 90, 70, 0.42)")
            g.addColorStop(0.55, "rgba(0, 40, 34, 0.18)")
            g.addColorStop(1, "rgba(0, 0, 0, 0)")
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
            // traces (under the brain)
            ctx.lineWidth = 1.2
            ctx.strokeStyle = "rgba(20, 120, 96, 0.30)"
            for (const tr of net.traces) {
                ctx.beginPath(); ctx.moveTo(tr.pts[0][0], tr.pts[0][1])
                for (const p of tr.pts) ctx.lineTo(p[0], p[1])
                ctx.stroke()
                const end = tr.pts[tr.pts.length - 2]
                ctx.fillStyle = "rgba(40, 170, 136, 0.55)"
                ctx.fillRect(end[0] - 2, end[1] - 2, 4, 4)       // the solder pad at the bend
            }
            // silhouette: a soft fill inside the outline
            net.outline(ctx)
            g = ctx.createRadialGradient(cx, cy, 0, cx, cy, B.w * 0.55)
            g.addColorStop(0, "rgba(0, 70, 56, 0.34)")
            g.addColorStop(1, "rgba(0, 30, 26, 0.22)")
            ctx.fillStyle = g
            ctx.fill()
            // folds
            ctx.lineCap = "round"; ctx.lineJoin = "round"
            for (const [lw, a] of [[4, 0.05], [1.5, 0.20]]) {
                ctx.lineWidth = lw
                ctx.strokeStyle = "rgba(40, 190, 150, " + a + ")"
                for (const s of net.sulci) {
                    ctx.beginPath(); ctx.moveTo(s[0][0], s[0][1])
                    for (const p of s) ctx.lineTo(p[0], p[1])
                    ctx.stroke()
                }
            }
            // cerebellum, clipped to itself
            ctx.save()
            ctx.beginPath()
            const L5 = net.lobes[5], c5 = net.toScreen(L5[0], L5[1])
            ctx.translate(c5[0], c5[1]); ctx.rotate(L5[4]); ctx.scale(L5[2] * B.w, L5[3] * B.h)
            ctx.arc(0, 0, 1, 0, 6.2832)
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clip()
            ctx.lineWidth = 1.2
            ctx.strokeStyle = "rgba(40, 190, 150, 0.22)"
            for (const s of net.strata) {
                ctx.beginPath(); ctx.moveTo(s[0][0], s[0][1])
                for (const p of s) ctx.lineTo(p[0], p[1])
                ctx.stroke()
            }
            ctx.restore()
            // rim: a soft glow, then a fine bright line
            for (const [lw, a] of [[7, 0.06], [3, 0.12], [1.3, 0.55]]) {
                ctx.lineWidth = lw
                ctx.strokeStyle = "rgba(60, 230, 180, " + a + ")"
                ctx.beginPath()
                for (const r of net.rims) { ctx.moveTo(r[0], r[1]); ctx.lineTo(r[2], r[3]) }
                ctx.stroke()
            }
            // resting mesh
            const N = net.nodes
            ctx.lineWidth = 0.9
            ctx.strokeStyle = "rgba(24, 130, 104, 0.30)"
            ctx.beginPath()
            for (const e of net.edges) { ctx.moveTo(N[e.a].x, N[e.a].y); ctx.lineTo(N[e.b].x, N[e.b].y) }
            ctx.stroke()
            ctx.fillStyle = "rgba(60, 170, 140, 0.75)"
            for (const n of N) { ctx.beginPath(); ctx.arc(n.x, n.y, 1.9, 0, 6.2832); ctx.fill() }
        }
    }

    // ---- activity: redrawn every frame at half resolution ----------------
    Canvas {
        id: activity
        readonly property int div: view.fullRes ? 1 : 2
        width: Math.ceil(parent.width / div)
        height: Math.ceil(parent.height / div)
        scale: div
        transformOrigin: Item.TopLeft
        opacity: view.brightness
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)
            ctx.scale(1 / div, 1 / div)
            const N = net.nodes
            if (!N.length) return
            // Claude at work: a warm glow breathing inside the brain.
            if (view.thinking) {
                const B = net.box, k = 0.5 + 0.5 * Math.sin(net.clock * 2.4)
                const g = ctx.createRadialGradient(B.x + B.w * 0.42, B.y + B.h * 0.42, 0, B.x + B.w * 0.42, B.y + B.h * 0.42, B.w * 0.5)
                g.addColorStop(0, view.rgba(view.coral, 0.10 + k * 0.08))
                g.addColorStop(1, "rgba(0,0,0,0)")
                ctx.fillStyle = g
                ctx.fillRect(B.x, B.y, B.w, B.h)
            }
            ctx.lineWidth = 1.8
            for (const e of net.edges) {
                if (e.heat < 0.04) continue
                ctx.strokeStyle = view.rgba(view.hueColor(e.hue), e.heat * 0.8)
                ctx.beginPath(); ctx.moveTo(N[e.a].x, N[e.a].y); ctx.lineTo(N[e.b].x, N[e.b].y); ctx.stroke()
            }
            for (const n of N) {
                const a = n.act
                if (a <= 0.05) continue
                const c = view.hueColor(n.hue), r = 1.9 + a * 3
                ctx.fillStyle = view.rgba(c, a * 0.22)
                ctx.beginPath(); ctx.arc(n.x, n.y, r * 3.4, 0, 6.2832); ctx.fill()
                ctx.fillStyle = n.hue ? view.rgba(Qt.lighter(c, 1.3), 0.5 + a * 0.5) : "rgba(200, 255, 232, " + (0.45 + a * 0.55).toFixed(3) + ")"
                ctx.beginPath(); ctx.arc(n.x, n.y, r, 0, 6.2832); ctx.fill()
            }
            for (const p of net.pulses) {
                const e = net.edges[p.e], A = N[p.from], Bn = N[e.a === p.from ? e.b : e.a]
                const x = A.x + (Bn.x - A.x) * p.t, y = A.y + (Bn.y - A.y) * p.t
                ctx.fillStyle = view.rgba(view.hueColor(p.hue), 0.28)
                ctx.beginPath(); ctx.arc(x, y, 6, 0, 6.2832); ctx.fill()
                ctx.fillStyle = p.hue ? "#fff1ea" : "#e6fff3"
                ctx.beginPath(); ctx.arc(x, y, 2.3, 0, 6.2832); ctx.fill()
            }
            for (const p of net.packets) {
                const tr = net.traces[p.tr], q = net.tracePoint(tr, p.d)
                const tail = net.tracePoint(tr, Math.max(0, p.d - net.box.w * 0.06))
                const g = ctx.createLinearGradient(tail[0], tail[1], q[0], q[1])
                g.addColorStop(0, "rgba(0,0,0,0)")
                g.addColorStop(1, view.rgba(view.hueColor(p.hue), 0.9))
                ctx.strokeStyle = g; ctx.lineWidth = 2.4
                ctx.beginPath(); ctx.moveTo(tail[0], tail[1]); ctx.lineTo(q[0], q[1]); ctx.stroke()
                ctx.fillStyle = p.hue ? "#fff1ea" : "#e6fff3"
                ctx.beginPath(); ctx.arc(q[0], q[1], 2.4, 0, 6.2832); ctx.fill()
            }
        }
    }

    Timer {
        interval: Math.round(1000 / Math.max(5, Math.min(60, view.fps)))
        repeat: true
        running: view.running
        onTriggered: {
            net.step(interval / 1000)
            activity.requestPaint()
        }
    }

    // ---- fragments ------------------------------------------------------
    ListModel { id: fragments }
    Repeater {
        model: fragments
        delegate: Text {
            required property int lid
            required property string words
            required property real px
            required property real py
            required property string kind
            required property real fade
            text: words
            x: px
            y: py - height
            visible: fade > 0 && (view.showThoughts || kind === "claude")
            opacity: fade * view.brightness * (kind === "claude" ? 1 : kind === "dim" ? 0.5 : 0.85)
            font.family: "JetBrains Mono"
            font.pixelSize: Math.round(Math.max(12, view.height / 72))
            color: kind === "claude" ? "#ffd6c6" : kind === "dim" ? "#3c8c76" : "#8cf5d2"
        }
    }

    // ---- optional overlays (off by default: the Ultimate widgets do this) --
    Rectangle {
        visible: view.showStats
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: view.hudWidth + Math.round(parent.width * 0.035) + 220
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.55; color: Qt.rgba(1 / 255, 4 / 255, 3 / 255, 0.38) }
            GradientStop { position: 1.0; color: Qt.rgba(1 / 255, 4 / 255, 3 / 255, 0.55) }
        }
    }
    SystemHud {
        visible: view.showStats
        width: view.hudWidth
        anchors.right: parent.right
        anchors.rightMargin: Math.round(parent.width * 0.035)
        y: view.topInset + 24
        stats: view.stats
    }
    ClaudeOverlay {
        x: Math.max(140, Math.round(parent.width * 0.06))
        y: view.topInset + 24
        width: Math.min(760, Math.round(parent.width * 0.45),
                        parent.width - x - view.hudWidth - Math.round(parent.width * 0.035) - 64)
        maxHeight: Math.round(parent.height * 0.74)
        state_: view.claude
        enabled_: view.showAnswers
    }
}
