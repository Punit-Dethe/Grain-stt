// DotMatrixDisplay.qml — Static "GRAIN//" LED dot-matrix logo
//
// A still LED-sign rendering of the GRAIN// wordmark. The word is rasterised
// from a real bold font onto a regular dot grid; every dot that falls inside a
// glyph lights warm-amber, the rest stay faint. Each dot is a distinct circle
// with a feathered edge and a clear gap to its neighbours — like a real LED
// matrix — so strokes never blob together. The wordmark is centred by measuring
// the rasterised glyph's actual bounding box. The slashes use the same typeface
// so "//" matches the GRAIN look. No animation.
import QtQuick 2.15

Item {
    id: root

    property color dotColor: "#FF8A1E"   // warm LED amber

    // Dot pitch tied to height for consistent density across widths.
    readonly property real _step: Math.max(2.8, height / 40)

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

            // ── 1. Rasterise the wordmark with a *bold* (not black) font ─
            // Bold (700) keeps the strokes ~3 dots thick, like the reference;
            // a heavier weight thickens the letters into mush.
            ctx.clearRect(0, 0, W, H)
            var text = "GRAIN//"
            var fontPx = H * 0.70
            ctx.font = "700 " + fontPx + "px 'Arial', 'Helvetica', sans-serif"
            var tw = ctx.measureText(text).width
            var maxW = W * 0.90
            if (tw > maxW) {
                fontPx = fontPx * maxW / tw
                ctx.font = "700 " + fontPx + "px 'Arial', 'Helvetica', sans-serif"
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
                    if (data[(rowBase + x) * 4 + 3] > 50) {
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

            // ── 3. Regular dot grid (centred, symmetric margins) ────────
            var step = root._step
            var cols = Math.max(1, Math.floor(W / step))
            var rows = Math.max(1, Math.floor(H / step))
            var gx = (W - cols * step) / 2 + step / 2
            var gy = (H - rows * step) / 2 + step / 2

            // Panel-edge vignette — the dot field melts into the dark border.
            var mx = W * 0.12, my = H * 0.14
            function edgeFade(px, py) {
                var fx = Math.min(px, W - px) / mx
                var fy = Math.min(py, H - py) / my
                return Math.max(0, Math.min(1, Math.min(fx, fy)))
            }

            // A soft dot: bright core feathering to transparent at its rim.
            // radius stays < half the pitch so neighbouring dots never touch.
            function softDot(cx, cy, radius, alpha) {
                var grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius)
                grad.addColorStop(0.0, Qt.rgba(dc.r, dc.g, dc.b, alpha))
                grad.addColorStop(0.6, Qt.rgba(dc.r, dc.g, dc.b, alpha * 0.78))
                grad.addColorStop(1.0, Qt.rgba(dc.r, dc.g, dc.b, 0.0))
                ctx.fillStyle = grad
                ctx.beginPath()
                ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                ctx.fill()
            }

            var litR = step * 0.46   // distinct dots: just under half the pitch
            var bgR  = step * 0.42

            // Pass A: faint unlit field; collect lit dots for the bright pass.
            var litX = [], litY = [], litB = []
            for (var r = 0; r < rows; r++) {
                for (var c = 0; c < cols; c++) {
                    var px = gx + c * step
                    var py = gy + r * step
                    var fade = edgeFade(px, py)
                    var cov = coverAt(px, py)
                    if (cov > 0.5) {
                        litX.push(px); litY.push(py)
                        litB.push(Math.max(0.85, Math.min(1.0, cov)) * Math.max(0.5, fade))
                    } else if (fade > 0.002) {
                        softDot(px, py, bgR, 0.07 * fade)
                    }
                }
            }

            // Pass B: a faint bloom halo under the lit dots so the word glows
            // as a whole — low alpha and wide, so it never blobs the dots.
            for (var b = 0; b < litX.length; b++) {
                softDot(litX[b], litY[b], step * 1.15, 0.10 * litB[b])
            }

            // Pass C: lit wordmark dots — distinct, each with its own soft rim.
            for (var i = 0; i < litX.length; i++) {
                softDot(litX[i], litY[i], litR, litB[i])
            }
        }
    }
}
