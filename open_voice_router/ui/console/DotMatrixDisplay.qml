// DotMatrixDisplay.qml — Multi-State LED Matrix Display
// States: intro (GRAIN reveal) | glitch | fireworks | ripple
import QtQuick 2.15

Item {
    id: root

    // Public API: "auto" | "intro" | "glitch" | "fireworks" | "ripple"
    property string displayState: "auto"

    property int   dotSize:  3
    property int   dotGap:   2
    property color dotColor: "#FF5D1E"

    // ── Internal ────────────────────────────────────────────────────────
    property int    _frame:      0
    property int    _stateFrame: 0
    property int    _stateIdx:   0
    property string _curState:   "intro"

    readonly property var _states:    ["intro", "glitch", "fireworks", "ripple"]
    readonly property var _durations: [130,      60,       70,          80     ]
    property var _matrix: null
    property var _cachedGrainDots: null

    onColsChanged: _initData()
    onRowsChanged: _initData()

    Component.onCompleted: _initData()

    function _initData() {
        if (cols > 0 && rows > 0) {
            _matrix = new Float32Array(cols * rows)
            _cachedGrainDots = _buildGrainDots()
        }
    }


    property int  cols:   Math.floor(width  / (dotSize + dotGap))
    property int  rows:   Math.floor(height / (dotSize + dotGap))
    property real startX: (width  - cols * (dotSize + dotGap)) / 2
    property real startY: (height - rows * (dotSize + dotGap)) / 2
    property real dotR:   dotSize / 2

    // ── 5×7 bitmap font for GRAIN ────────────────────────────────────────
    readonly property var _font5x7: ({
        "G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0E],
        "R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        "A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "N": [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11]
    })

    function _buildGrainDots() {
        var text    = "GRAIN"
        var charW   = 5, charH = 7, charGap = 2
        var totalW  = text.length * charW + (text.length - 1) * charGap
        var offX    = Math.floor((root.cols - totalW) / 2)
        var offY    = Math.floor((root.rows - charH)  / 2)
        var dots    = []
        for (var ci = 0; ci < text.length; ci++) {
            var bitmap = root._font5x7[text[ci]]
            if (!bitmap) continue
            for (var row = 0; row < charH; row++) {
                var mask = bitmap[row]
                for (var bit = 0; bit < charW; bit++) {
                    if (mask & (1 << (charW - 1 - bit))) {
                        dots.push({ col: offX + ci * (charW + charGap) + bit,
                                    row: offY + row })
                    }
                }
            }
        }
        return dots
    }

    // ── Layer 1 — Unlit background dots (GPU-cached) ───────────────────
    Canvas {
        id: bgCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        Connections {
            target: root
            function onColsChanged() { bgCanvas.requestPaint() }
            function onRowsChanged() { bgCanvas.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var C = root.cols, R = root.rows
            if (C <= 0 || R <= 0) return
            var step = root.dotSize + root.dotGap, r = root.dotR
            ctx.fillStyle = Qt.rgba(1.0, 0.365, 0.118, 0.07)
            ctx.beginPath()
            for (var row = 0; row < R; row++) {
                for (var col = 0; col < C; col++) {
                    var px = root.startX + col * step; var py = root.startY + row * step; ctx.fillRect(px, py, root.dotSize, root.dotSize);
                }
            }
            ctx.fill()
        }
    }

    // ── Layer 2 — Animated foreground ──────────────────────────────────
    Canvas {
        id: fgCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        Timer {
            interval: 80
            running:  root.visible
            repeat:   true
            onTriggered: {
                root._frame++
                root._stateFrame++
                if (root.displayState === "auto") {
                    var dur = root._durations[root._stateIdx]
                    if (root._stateFrame >= dur) {
                        root._stateIdx   = (root._stateIdx + 1) % root._states.length
                        root._curState   = root._states[root._stateIdx]
                        root._stateFrame = 0
                    }
                }
                fgCanvas.requestPaint()
            }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var C = root.cols, R = root.rows
            if (C <= 0 || R <= 0) return
            var step = root.dotSize + root.dotGap
            var r    = root.dotR
            var t    = root._stateFrame
            var cx0  = Math.floor(C / 2)
            var cy0  = Math.floor(R / 2)
            var state = (root.displayState === "auto") ? root._curState : root.displayState

            var matrix = root._matrix;
            if (!matrix) return;
            matrix.fill(0.0);
            var i, j;

            // ══════════════════════════════════════════════════════════
            // STATE: INTRO — four-phase cinematic GRAIN reveal
            //  Phase 0 (t  0-29): GRAIN RAIN   — dots fall like seeds
            //  Phase 1 (t 30-69): CRYSTALLISE  — cloud snaps into word
            //  Phase 2 (t 70-99): HOLD + BREATHE — word glows warmly
            //  Phase 3 (t 100-129): DISPERSE   — letters scatter away
            // ══════════════════════════════════════════════════════════
            if (state === "intro") {
                var grainDots = root._cachedGrainDots
                var numDots   = grainDots.length
                var P0 = 30, P1 = 70, P2 = 100

                if (t < P0) {
                    // ── GRAIN RAIN ────────────────────────────────────
                    var density    = t / P0
                    var activeCols = Math.floor(density * C + 2)
                    for (j = 0; j < Math.min(activeCols, C); j++) {
                        var colSeed = (j * 7919 + 1013) % 997
                        var spd     = 0.5 + (colSeed % 5) * 0.18
                        var sOff    = colSeed % R
                        var head    = Math.floor((t * spd + sOff) % (R + 4)) - 4
                        var trail   = 4
                        for (var dot = 0; dot < trail; dot++) {
                            var drow = head + dot
                            if (drow >= 0 && drow < R) {
                                var bright = (dot === trail - 1) ? 0.95 : (dot / trail) * 0.55
                                matrix[(drow) * C + (j)] = Math.max(matrix[(drow) * C + (j)], bright)
                            }
                        }
                        if (t > 5) {
                            for (var sr = 0; sr < R; sr++) {
                                var spSeed = (j * 1009 + sr * 6271 + t * 37) % 997
                                if (spSeed < 0) spSeed += 997
                                if (spSeed < 55) matrix[(sr) * C + (j)] = Math.max(matrix[(sr) * C + (j)], 0.28)
                            }
                        }
                    }

                } else if (t < P1) {
                    // ── CRYSTALLISE ───────────────────────────────────
                    var prog = (t - P0) / (P1 - P0)
                    // Noise fades out
                    var noiseFade = 1.0 - prog
                    for (i = 0; i < R; i++) {
                        for (j = 0; j < C; j++) {
                            var nSeed = ((i * 2654435761 + j * 40503 + 99) >>> 0) % 1000
                            if (nSeed < 120)
                                matrix[(i) * C + (j)] = Math.max(matrix[(i) * C + (j)], noiseFade * (0.15 + (nSeed % 10) * 0.02))
                        }
                    }
                    // Glyph dots emerge staggered left→right
                    for (var gi = 0; gi < numDots; gi++) {
                        var thresh  = gi / numDots
                        var dProg   = Math.min(1.0, Math.max(0, (prog - thresh * 0.6) / 0.4) * 2.5)
                        var gr = grainDots[gi].row, gc = grainDots[gi].col
                        if (gr >= 0 && gr < R && gc >= 0 && gc < C) {
                            var flicker = (dProg > 0.3 && dProg < 0.7)
                                ? (((gi * 1009 + t * 337) % 3) === 0 ? 0.4 : dProg)
                                : dProg
                            matrix[(gr) * C + (gc)] = Math.max(matrix[(gr) * C + (gc)], flicker)
                        }
                    }

                } else if (t < P2) {
                    // ── HOLD + BREATHE ────────────────────────────────
                    var breathe = (Math.sin((t - P2) * 0.22) + 1.0) * 0.5
                    for (var gi2 = 0; gi2 < numDots; gi2++) {
                        var gr2 = grainDots[gi2].row, gc2 = grainDots[gi2].col
                        if (gr2 < 0 || gr2 >= R || gc2 < 0 || gc2 >= C) continue
                        matrix[(gr2) * C + (gc2)] = 1.0
                        var fringe = 0.12 + breathe * 0.22
                        for (var di = -1; di <= 1; di++) {
                            for (var dj = -1; dj <= 1; dj++) {
                                if (di === 0 && dj === 0) continue
                                var ni = gr2 + di, nj = gc2 + dj
                                if (ni >= 0 && ni < R && nj >= 0 && nj < C)
                                    matrix[(ni) * C + (nj)] = Math.max(matrix[(ni) * C + (nj)], fringe)
                            }
                        }
                    }

                } else {
                    // ── DISPERSE ──────────────────────────────────────
                    var dispProg = (t - P2) / (root._durations[0] - P2)
                    var dispEase = dispProg * dispProg
                    var maxTravel = Math.max(C, R) * 0.6
                    var centX = 0, centY = 0
                    for (var gi3 = 0; gi3 < numDots; gi3++) {
                        centX += grainDots[gi3].col
                        centY += grainDots[gi3].row
                    }
                    centX /= numDots; centY /= numDots
                    for (var gi4 = 0; gi4 < numDots; gi4++) {
                        var gr4 = grainDots[gi4].row, gc4 = grainDots[gi4].col
                        var vx = gc4 - centX, vy = gr4 - centY
                        var vLen = Math.sqrt(vx * vx + vy * vy) + 0.001
                        vx /= vLen; vy /= vLen
                        var jSeed  = (gi4 * 1009 + 31) % 997
                        var jAngle = (jSeed / 997) * 0.8 - 0.4
                        var jx = vx * Math.cos(jAngle) - vy * Math.sin(jAngle)
                        var jy = vx * Math.sin(jAngle) + vy * Math.cos(jAngle)
                        var travel = dispEase * maxTravel
                        var nr = Math.round(gr4 + jy * travel)
                        var nc = Math.round(gc4 + jx * travel)
                        var fade = Math.max(0, 1.0 - dispEase * 1.3)
                        if (nr >= 0 && nr < R && nc >= 0 && nc < C && fade > 0.05)
                            matrix[(nr) * C + (nc)] = Math.max(matrix[(nr) * C + (nc)], fade)
                    }
                }

                // ── Contextual glow ───────────────────────────────────
                var glowPx = 0
                if (t >= P1 && t < P2) {
                    var breathe2 = (Math.sin((t - P2) * 0.22) + 1.0) * 0.5
                    glowPx = 4 + breathe2 * 10
                } else if (t >= P0 && t < P1) {
                    glowPx = 6
                }

                // ── Render (dim pass + bright pass) ───────────────────
                var dc = root.dotColor
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        var bv = matrix[(i) * C + (j)]
                        if (bv >= 0.05 && bv < 0.8) {
                            ctx.fillStyle = Qt.rgba(dc.r, dc.g, dc.b, bv)
                            var pxa = root.startX + j * step; var pya = root.startY + i * step; ctx.fillRect(pxa, pya, root.dotSize, root.dotSize);
                        }
                    }
                }
                ctx.fillStyle  = root.dotColor
                ctx.beginPath()
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        if (matrix[(i) * C + (j)] >= 0.8) {
                            var pxb = root.startX + j * step; var pyb = root.startY + i * step; ctx.fillRect(pxb, pyb, root.dotSize, root.dotSize);
                        }
                    }
                }
                ctx.fill()
            }

            // ══════════════════════════════════════════════════════════
            // STATE: GLITCH
            // ══════════════════════════════════════════════════════════
            else if (state === "glitch") {
                var bandH = Math.floor(R * 0.18)
                var bandY = Math.floor((t * 1.8) % (R + bandH)) - bandH
                for (i = bandY; i < bandY + bandH; i++) {
                    if (i < 0 || i >= R) continue
                    for (j = 0; j < C; j++) {
                        var sg = (i * 374761393 + j * 668265263 + t * 1234567) % 997
                        if (sg < 0) sg += 997
                        matrix[(i) * C + (j)] = (sg < 600) ? 1.0 : 0.0
                    }
                }
                for (var bg = 0; bg < 4; bg++) {
                    var tbg  = Math.floor(t / 3)
                    var bSg  = ((bg * 1009 + tbg * 6271) % 997 + 997) % 997
                    var brg  = Math.floor((bSg * 37) % R)
                    var bcg  = Math.floor((bSg * 71) % C)
                    var bhg  = 2 + Math.floor((bSg * 13) % 4)
                    var bwg  = 3 + Math.floor((bSg * 23) % Math.floor(C * 0.3))
                    for (i = brg; i < brg + bhg && i < R; i++)
                        for (j = bcg; j < bcg + bwg && j < C; j++) matrix[(i) * C + (j)] = 1.0
                }
                var tcg = Math.floor(t / 5)
                var tc1 = ((tcg * 337 + 191) % C + C) % C
                var tc2 = ((tcg * 521 + 83)  % C + C) % C
                if (t % 5 < 3) {
                    for (i = 0; i < R; i++) { matrix[(i) * C + (tc1)] = 1.0; matrix[(i) * C + (tc2)] = 1.0 }
                }
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        var nsg = ((i * 2654435761 + j * 40503 + t * 16807) >>> 0) % 1000
                        if (nsg < 40) matrix[(i) * C + (j)] = 1.0
                    }
                }
                ctx.fillStyle = root.dotColor
                ctx.beginPath()
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        if (matrix[(i) * C + (j)] >= 0.8) {
                            var pxg = root.startX + j * step; var pyg = root.startY + i * step; ctx.fillRect(pxg, pyg, root.dotSize, root.dotSize)
                        }
                    }
                }
                ctx.fill()
            }

            // ══════════════════════════════════════════════════════════
            // STATE: FIREWORKS
            // ══════════════════════════════════════════════════════════
            else if (state === "fireworks") {
                var shellP = 22
                for (var sf = 0; sf < 3; sf++) {
                    var soF  = sf * Math.floor(shellP * 0.65)
                    var ltF  = (t + soF) % shellP
                    var cyF  = Math.floor((t + soF) / shellP)
                    var bxF  = cx0 + Math.floor(((cyF * 1009 + sf * 337) % (C * 0.6)) - C * 0.3)
                    var byF  = cy0 - Math.floor(2 + ((cyF * 761 + sf * 193) % (R * 0.35)))
                    bxF = Math.max(2, Math.min(C - 3, bxF))
                    byF = Math.max(2, Math.min(R - 3, byF))
                    if (ltF < 12) {
                        var prF  = ltF / 12
                        var ttF  = Math.floor(R - 1 - prF * (R - 1 - byF))
                        for (i = ttF; i < R; i++)
                            if (i >= 0 && i < R && bxF >= 0 && bxF < C)
                                matrix[(i) * C + (bxF)] = (i === ttF) ? 1.0 : 0.5
                    } else {
                        var agF = ltF - 12
                        for (var armF = 0; armF < 12; armF++) {
                            var aaF = (armF / 12) * Math.PI * 2
                            for (var spF = 0; spF <= 5; spF++) {
                                var saF = agF - Math.floor(spF * 0.6)
                                if (saF < 0) continue
                                var siF = Math.round(byF + Math.sin(aaF) * (saF * 1.5 + spF * 0.4))
                                var sjF = Math.round(bxF + Math.cos(aaF) * (saF * 1.5 + spF * 0.4))
                                if (siF >= 0 && siF < R && sjF >= 0 && sjF < C)
                                    matrix[(siF) * C + (sjF)] = Math.max(matrix[(siF) * C + (sjF)],
                                        Math.max(0, 1.0 - saF * 0.11 - spF * 0.08))
                            }
                        }
                        if (agF < 3) {
                            var frF = 3 - agF
                            for (i = byF - frF; i <= byF + frF; i++)
                                for (j = bxF - frF; j <= bxF + frF; j++)
                                    if (i >= 0 && i < R && j >= 0 && j < C)
                                        matrix[(i) * C + (j)] = Math.max(matrix[(i) * C + (j)], 1.0 - agF * 0.3)
                        }
                    }
                }
                ctx.fillStyle = root.dotColor
                ctx.beginPath()
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        if (matrix[(i) * C + (j)] >= 0.8) {
                            var pxf = root.startX + j * step; var pyf = root.startY + i * step; ctx.fillRect(pxf, pyf, root.dotSize, root.dotSize)
                        }
                    }
                }
                ctx.fill()
                var dcf = root.dotColor
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        var bvf = matrix[(i) * C + (j)]
                        if (bvf >= 0.2 && bvf < 0.8) {
                            ctx.fillStyle = Qt.rgba(dcf.r, dcf.g, dcf.b, bvf)
                            ctx.beginPath()
                            var pxf2 = root.startX + j * step; var pyf2 = root.startY + i * step; ctx.fillRect(pxf2, pyf2, root.dotSize, root.dotSize)
                            ctx.fill()
                        }
                    }
                }
            }

            // ══════════════════════════════════════════════════════════
            // STATE: RIPPLE
            // ══════════════════════════════════════════════════════════
            else if (state === "ripple") {
                var driftT = Math.floor(t / 30)
                for (var src = 0; src < 3; src++) {
                    var sxr = cx0 + Math.floor(((driftT * 337 + src * 719) % (C * 0.7)) - C * 0.35)
                    var syr = cy0 + Math.floor(((driftT * 521 + src * 293) % (R * 0.7)) - R * 0.35)
                    sxr = Math.max(1, Math.min(C - 2, sxr))
                    syr = Math.max(1, Math.min(R - 2, syr))
                    var phOff = src * 7
                    for (i = 0; i < R; i++) {
                        for (j = 0; j < C; j++) {
                            var rdx = j - sxr, rdy = i - syr
                            var dr  = Math.sqrt(rdx * rdx + rdy * rdy)
                            var wr  = Math.sin(dr * 0.8 - (t + phOff) * 0.35)
                            var ar  = Math.max(0, 1.0 - dr / (Math.max(C, R) * 0.7))
                            matrix[(i) * C + (j)] += wr * ar
                        }
                    }
                }
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        var vr = matrix[(i) * C + (j)]
                        matrix[(i) * C + (j)] = (vr > 0.55) ? Math.min(1.0, (vr - 0.55) * 2.5) : 0.0
                    }
                }
                ctx.fillStyle = root.dotColor
                ctx.beginPath()
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        if (matrix[(i) * C + (j)] >= 0.8) {
                            var pxr = root.startX + j * step; var pyr = root.startY + i * step; ctx.fillRect(pxr, pyr, root.dotSize, root.dotSize)
                        }
                    }
                }
                ctx.fill()
                var dcr = root.dotColor
                for (i = 0; i < R; i++) {
                    for (j = 0; j < C; j++) {
                        var bvr = matrix[(i) * C + (j)]
                        if (bvr >= 0.2 && bvr < 0.8) {
                            ctx.fillStyle = Qt.rgba(dcr.r, dcr.g, dcr.b, bvr)
                            ctx.beginPath()
                            var pxr2 = root.startX + j * step; var pyr2 = root.startY + i * step; ctx.fillRect(pxr2, pyr2, root.dotSize, root.dotSize)
                            ctx.fill()
                        }
                    }
                }
            }
        }
    }
}
