// DotMatrixDisplay.qml — Static "GRAIN//" LED dot-matrix logo
//
// Renders the GRAIN// wordmark as a dense field of round LED dots. The word is
// rasterised from a real heavy font onto a fine dot grid: every dot that falls
// inside a glyph lights warm-orange with a soft glow, the rest stay faint, and
// the whole field fades toward the panel edges. Because the letters come from a
// real bold typeface (not a 1-dot stroke font) the strokes are several dots
// thick, giving solid, properly-shaped letters — and the two slashes render in
// the same typeface so "//" matches the GRAIN look exactly. No animation.
import QtQuick 2.15

Item {
    id: root

    property color dotColor: "#FF8A1E"   // warm LED amber

    // Dot pitch is tied to height so the dot density is consistent regardless
    // of panel width — roughly 34 dot-rows tall.
    readonly property real _step: Math.max(3.0, height / 34)
    readonly property real _dotR: _step * 0.36

    onWidthChanged:  canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        Component.onCompleted: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            var W = width, H = height
            if (W <= 0 || H <= 0) return
            var dc = root.dotColor

            // ── 1. Rasterise the wordmark with a heavy font ─────────────
            // Drawn opaque white; only its alpha coverage is sampled below.
            ctx.clearRect(0, 0, W, H)
            var text = "GRAIN//"
            var fontPx = H * 0.74
            ctx.font = "800 " + fontPx + "px 'Arial Black', 'Arial', sans-serif"
            var tw = ctx.measureText(text).width
            var maxW = W * 0.92
            if (tw > maxW) {
                fontPx = fontPx * maxW / tw
                ctx.font = "800 " + fontPx + "px 'Arial Black', 'Arial', sans-serif"
            }
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillStyle = "#ffffff"
            // Nudge up a hair: the optical centre of all-caps sits slightly low.
            ctx.fillText(text, W / 2, H / 2 - H * 0.02)

            // Snapshot the coverage, then clear to repaint as dots.
            var imageData = ctx.getImageData(0, 0, W, H)
            var data = imageData.data
            var IW = imageData.width, IH = imageData.height
            ctx.clearRect(0, 0, W, H)

            function coverAt(px, py) {
                var xi = Math.round(px), yi = Math.round(py)
                if (xi < 0 || yi < 0 || xi >= IW || yi >= IH) return 0
                return data[(yi * IW + xi) * 4 + 3] / 255   // alpha 0..1
            }

            // ── 2. Dot grid geometry (centred, symmetric margins) ───────
            var step = root._step, rr = root._dotR
            var cols = Math.max(1, Math.floor(W / step))
            var rows = Math.max(1, Math.floor(H / step))
            var gx = (W - cols * step) / 2 + step / 2
            var gy = (H - rows * step) / 2 + step / 2

            // Edge vignette — dots dim toward the borders, reaching zero at the
            // very edge so the field melts into the dark panel.
            var mx = W * 0.14, my = H * 0.16
            function edgeFade(px, py) {
                var fx = Math.min(px, W - px) / mx
                var fy = Math.min(py, H - py) / my
                return Math.max(0, Math.min(1, Math.min(fx, fy)))
            }

            // First pass: collect lit dots, draw the faint unlit field.
            var litX = [], litY = [], litB = []
            for (var r = 0; r < rows; r++) {
                for (var c = 0; c < cols; c++) {
                    var px = gx + c * step
                    var py = gy + r * step
                    var fade = edgeFade(px, py)
                    var cov = coverAt(px, py)
                    if (cov > 0.35) {
                        // Inside a glyph → lit. Coverage feeds brightness so the
                        // dots along anti-aliased edges ease off smoothly.
                        litX.push(px); litY.push(py)
                        litB.push(Math.max(0.78, Math.min(1.0, cov)) * Math.max(0.4, fade))
                    } else if (fade > 0.002) {
                        ctx.beginPath()
                        ctx.fillStyle = Qt.rgba(dc.r, dc.g, dc.b, 0.08 * fade)
                        ctx.arc(px, py, rr, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }

            // ── 3. Lit wordmark dots, with a soft LED glow ──────────────
            ctx.shadowColor = Qt.rgba(dc.r, dc.g, dc.b, 0.9)
            ctx.shadowBlur  = step * 1.0
            for (var i = 0; i < litX.length; i++) {
                ctx.beginPath()
                ctx.fillStyle = Qt.rgba(dc.r, dc.g, dc.b, litB[i])
                ctx.arc(litX[i], litY[i], rr * 1.06, 0, Math.PI * 2)
                ctx.fill()
            }
            ctx.shadowBlur = 0
        }
    }
}
