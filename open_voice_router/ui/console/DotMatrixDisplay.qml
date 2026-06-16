// DotMatrixDisplay.qml — Static "GRAIN//" LED dot-matrix logo
//
// Renders the GRAIN// wordmark as a dense field of soft LED dots. The word is
// rasterised from a real heavy font onto a fine dot grid: every dot inside a
// glyph lights warm-amber, the rest stay faint, and the field vignettes toward
// the panel edges. Each dot is drawn with a radial gradient so its edges fade
// softly (the LED look), and the whole wordmark is centred by measuring the
// rasterised glyph's actual bounding box rather than trusting font metrics.
// The slashes use the same typeface so "//" matches the GRAIN look. No animation.
import QtQuick 2.15

Item {
    id: root

    property color dotColor: "#FF8A1E"   // warm LED amber

    // Dot pitch tied to height for consistent density across widths.
    // ~42 dot-rows tall — dense enough to render the slashes cleanly.
    readonly property real _step: Math.max(2.6, height / 42)
    readonly property real _dotR: _step * 0.5

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
            ctx.clearRect(0, 0, W, H)
            var text = "GRAIN//"
            var fontPx = H * 0.72
            ctx.font = "800 " + fontPx + "px 'Arial Black', 'Arial', sans-serif"
            var tw = ctx.measureText(text).width
            var maxW = W * 0.90
            if (tw > maxW) {
                fontPx = fontPx * maxW / tw
                ctx.font = "800 " + fontPx + "px 'Arial Black', 'Arial', sans-serif"
            }
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillStyle = "#ffffff"
            ctx.fillText(text, W / 2, H / 2)

            var imageData = ctx.getImageData(0, 0, W, H)
            var data = imageData.data
            var IW = imageData.width, IH = imageData.height
            ctx.clearRect(0, 0, W, H)

            // ── 2. Measure the glyph bbox → true centring offset ────────
            var minX = IW, minY = IH, maxX = -1, maxY = -1
            for (var y = 0; y < IH; y++) {
                var rowBase = y * IW
                for (var x = 0; x < IW; x++) {
                    if (data[(rowBase + x) * 4 + 3] > 40) {
                        if (x < minX) minX = x
                        if (x > maxX) maxX = x
                        if (y < minY) minY = y
                        if (y > maxY) maxY = y
                    }
                }
            }
            var offX = 0, offY = 0
            if (maxX >= 0) {
                offX = W / 2 - (minX + maxX) / 2
                offY = H / 2 - (minY + maxY) / 2
            }

            function coverAt(px, py) {
                var xi = Math.round(px - offX), yi = Math.round(py - offY)
                if (xi < 0 || yi < 0 || xi >= IW || yi >= IH) return 0
                return data[(yi * IW + xi) * 4 + 3] / 255
            }

            // ── 3. Dot grid geometry (centred, symmetric margins) ───────
            var step = root._step, rr = root._dotR
            var cols = Math.max(1, Math.floor(W / step))
            var rows = Math.max(1, Math.floor(H / step))
            var gx = (W - cols * step) / 2 + step / 2
            var gy = (H - rows * step) / 2 + step / 2

            // Panel-edge vignette — the dot field melts into the dark border.
            var mx = W * 0.13, my = H * 0.15
            function edgeFade(px, py) {
                var fx = Math.min(px, W - px) / mx
                var fy = Math.min(py, H - py) / my
                return Math.max(0, Math.min(1, Math.min(fx, fy)))
            }

            // A soft dot: bright core fading to transparent at the rim, so the
            // edge of every dot is feathered rather than a hard circle.
            function softDot(cx, cy, radius, alpha) {
                var grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius)
                grad.addColorStop(0.0, Qt.rgba(dc.r, dc.g, dc.b, alpha))
                grad.addColorStop(0.55, Qt.rgba(dc.r, dc.g, dc.b, alpha * 0.8))
                grad.addColorStop(1.0, Qt.rgba(dc.r, dc.g, dc.b, 0.0))
                ctx.fillStyle = grad
                ctx.beginPath()
                ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                ctx.fill()
            }

            // Pass A: faint unlit field; collect lit dots for the bright pass.
            var litX = [], litY = [], litB = []
            for (var r = 0; r < rows; r++) {
                for (var c = 0; c < cols; c++) {
                    var px = gx + c * step
                    var py = gy + r * step
                    var fade = edgeFade(px, py)
                    var cov = coverAt(px, py)
                    if (cov > 0.4) {
                        litX.push(px); litY.push(py)
                        litB.push(Math.max(0.8, Math.min(1.0, cov)) * Math.max(0.45, fade))
                    } else if (fade > 0.002) {
                        softDot(px, py, rr * 1.1, 0.08 * fade)
                    }
                }
            }

            // Pass B: lit wordmark dots — a touch larger so the soft rims meet
            // and the strokes read as solid, with a gentle outer glow.
            ctx.shadowColor = Qt.rgba(dc.r, dc.g, dc.b, 0.7)
            ctx.shadowBlur  = step * 0.7
            for (var i = 0; i < litX.length; i++) {
                softDot(litX[i], litY[i], rr * 1.35, litB[i])
            }
            ctx.shadowBlur = 0
        }
    }
}
