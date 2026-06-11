// CassetteDisplay.qml — Cassette tape animation
// Two spinning reels, angled window at top center, green VU bars inside.
import QtQuick 2.15

Item {
    id: root

    property color accentColor: "#FF5D1E"

    property real _reelAngle: 0.0
    property int  _frame:     0

    Timer {
        interval: 40
        running:  root.visible
        repeat:   true
        onTriggered: {
            root._frame++
            root._reelAngle = (root._reelAngle + 2.6) % 360
            cassetteCanvas.requestPaint()
        }
    }

    Canvas {
        id: cassetteCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            // ── Responsive geometry ──────────────────────────────────────
            var lx  = width * 0.225         // left reel center x
            var rx  = width * 0.775         // right reel center x
            var rcy = height * 0.615        // reel center y
            var rr  = Math.min(width * 0.130, height * 0.385)  // reel radius

            var wx  = width  * 0.340        // window x (left edge)
            var wy  = height * 0.055        // window y (top edge)
            var ww  = width  * 0.320        // window width
            var wh  = height * 0.225        // window height
            var tap = ww * 0.115            // taper — top edge is narrower by this on each side

            var angle = root._reelAngle * Math.PI / 180
            var frame = root._frame

            // ── Tape ribbons (reel tangent → window bottom corners) ──────
            var lwA = Math.atan2((wy + wh) - rcy, wx - lx)
            var rwA = Math.atan2((wy + wh) - rcy, (wx + ww) - rx)

            ctx.strokeStyle = "rgba(255, 93, 30, 0.16)"
            ctx.lineWidth = 1

            ctx.beginPath()
            ctx.moveTo(lx + Math.cos(lwA) * rr, rcy + Math.sin(lwA) * rr)
            ctx.lineTo(wx, wy + wh)
            ctx.stroke()

            ctx.beginPath()
            ctx.moveTo(rx + Math.cos(rwA) * rr, rcy + Math.sin(rwA) * rr)
            ctx.lineTo(wx + ww, wy + wh)
            ctx.stroke()

            // ── Cassette window — trapezoid, sides tilt inward at top ────
            ctx.beginPath()
            ctx.moveTo(wx + tap, wy)
            ctx.lineTo(wx + ww - tap, wy)
            ctx.lineTo(wx + ww, wy + wh)
            ctx.lineTo(wx, wy + wh)
            ctx.closePath()
            ctx.fillStyle = "rgba(0, 3, 0, 0.88)"
            ctx.fill()
            ctx.strokeStyle = "rgba(255, 93, 30, 0.55)"
            ctx.lineWidth = 1
            ctx.stroke()

            // ── Green VU bars inside the window ─────────────────────────
            var inX  = wx + tap + 5
            var inW  = ww - tap * 2 - 10
            var inY  = wy + 5
            var inH  = wh - 9
            var nBar = 8
            var gap  = 2
            var barW = (inW - (nBar - 1) * gap) / nBar

            ctx.save()
            ctx.beginPath()
            ctx.moveTo(wx + tap, wy)
            ctx.lineTo(wx + ww - tap, wy)
            ctx.lineTo(wx + ww, wy + wh)
            ctx.lineTo(wx, wy + wh)
            ctx.closePath()
            ctx.clip()

            for (var b = 0; b < nBar; b++) {
                var ph   = (b / nBar) * Math.PI * 2 - 0.5
                var wave = Math.abs(Math.sin(frame * 0.10 + ph))
                var bH   = inH * (0.18 + wave * 0.80)
                var bx   = inX + b * (barW + gap)
                var by   = inY + inH - bH
                var al   = 0.50 + wave * 0.45
                ctx.fillStyle = "rgba(16, 185, 129, " + al.toFixed(2) + ")"
                ctx.fillRect(bx, by, barW, bH)
            }
            ctx.restore()

            // ── Reels ────────────────────────────────────────────────────
            function drawReel(cx, cy, a) {
                // Outer ring
                ctx.beginPath()
                ctx.arc(cx, cy, rr, 0, Math.PI * 2)
                ctx.strokeStyle = "rgba(255, 93, 30, 0.72)"
                ctx.lineWidth = 1.5
                ctx.stroke()

                // Mid ring
                ctx.beginPath()
                ctx.arc(cx, cy, rr * 0.55, 0, Math.PI * 2)
                ctx.strokeStyle = "rgba(255, 93, 30, 0.28)"
                ctx.lineWidth = 1
                ctx.stroke()

                // 3 spokes
                for (var s = 0; s < 3; s++) {
                    var sa = a + (s / 3) * Math.PI * 2
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(sa) * rr * 0.25, cy + Math.sin(sa) * rr * 0.25)
                    ctx.lineTo(cx + Math.cos(sa) * rr * 0.88, cy + Math.sin(sa) * rr * 0.88)
                    ctx.strokeStyle = "rgba(255, 93, 30, 0.72)"
                    ctx.lineWidth = 1.5
                    ctx.stroke()
                }

                // Hub fill
                ctx.beginPath()
                ctx.arc(cx, cy, rr * 0.21, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255, 93, 30, 0.92)"
                ctx.fill()
            }

            drawReel(lx, rcy, angle)
            drawReel(rx, rcy, angle)
        }
    }
}
