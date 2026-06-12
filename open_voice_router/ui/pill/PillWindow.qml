// PillWindow.qml — Dot-grid pill, ported from reference pill.html design
// Key improvements: proper noise gate, power curve, multiple grey shades,
// hot/active/dim cell tiers, flicker, isolated mic-to-display pipeline.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window

ApplicationWindow {
    id: root

    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

    // Grid: 25 cols x 8 rows (restored to original 8 rows)
    readonly property int cols: 25
    readonly property int rows: 8
    readonly property int dotD: 3      // dot diameter px (slightly smaller than original 4)
    readonly property int gap:  2      // gap between dots (same as original)
    readonly property int cell: dotD + gap   // 5px per cell

    width:  cols * cell + 2
    height: rows * cell + 2

    // Button zone: 4x4 at right side, 3 cols from right edge
    // Cols 18–21, rows 2–5 (matching original 25x8 design)
    readonly property int btnCol:  18
    readonly property int btnRow:  2
    readonly property int btnSpan: 4

    color: "transparent"

    x: Screen.width / 2 - root.width / 2
    y: Screen.desktopAvailableHeight - root.height - 16

    visible: pillViewModel ? pillViewModel.is_visible : false
    opacity: root.visible ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.InOutQuad }
    }

    // On Windows, WindowStaysOnTopHint can lose effect when the window is
    // re-shown after being hidden. Explicitly raise() on every visibility
    // transition to true to guarantee it stays above all other windows.
    onVisibleChanged: if (visible) raise()

    readonly property string pillState: pillViewModel ? pillViewModel.state : "idle"

    // ----------------------------------------------------------------
    // Energy — driven by amplitude inside rollDots() each timer tick.
    // No separate change handler — simpler and avoids race with timer decay.
    // ----------------------------------------------------------------
    property real energy: 0.0

    // ----------------------------------------------------------------
    // Button-zone animation state — independent of mic input
    // 12-cell perimeter orbit (comet) + inner 2x2 pulse.
    // Perimeter order: clockwise from top-left of the 4x4 zone.
    // ----------------------------------------------------------------
    property int  _btnTick:       0     // head position on perimeter (0-11)
    property int  _btnSubTick:    0     // sub-tick so head advances every 2 frames
    property real _btnPulseAngle: 0.0   // sine angle for inner-cell breathing

    readonly property var _btnPerim: [
        [0,0],[0,1],[0,2],[0,3],
        [1,3],[2,3],
        [3,3],[3,2],[3,1],[3,0],
        [2,0],[1,0]
    ]

    // ----------------------------------------------------------------
    // Curved silhouette for 25x8 grid
    // Col 0, 24: fully hidden; Col 1/23: rows 2-5 only; Col 2/22: rows 1-6 only
    // ----------------------------------------------------------------
    function isEdgeCell(c, r) {
        if (c === 0 || c === cols - 1) return true
        if (c === 1 || c === cols - 2) return (r < 1 || r > 6)
        if (c === 2 || c === cols - 3) return (r < 1 || r > 6)
        return false
    }

    function isButtonZone(c, r) {
        return c >= btnCol && c < btnCol + btnSpan &&
               r >= btnRow && r < btnRow + btnSpan
    }

    // ----------------------------------------------------------------
    // Dot state array — recomputed each frame tick
    // Each entry: color string
    // ----------------------------------------------------------------
    property var dotStates: []

    // Pre-computed list of drawable cell indices (excludes silhouette edges and
    // button zone). Rebuilt only when grid constants change (never at runtime).
    readonly property var _eligibleCells: {
        var list = []
        for (var r = 0; r < rows; r++) {
            for (var c = 0; c < cols; c++) {
                if (!isEdgeCell(c, r) && !isButtonZone(c, r))
                    list.push(r * cols + c)
            }
        }
        return list
    }

    function rollDots() {
        var st = pillState
        var isProcessing = (st === "processing")

        // amplitude_level here is ALREADY fully display-shaped by the isolated
        // VolumeMeterService (noise-gated, normalized to loud-speech reference,
        // sqrt-curved, lightly smoothed). The pill consumes it close to directly,
        // so there is NO in-QML noise gate or curve anymore.
        var amp = (pillViewModel && pillViewModel.amplitude_level !== undefined)
            ? pillViewModel.amplitude_level
            : 0.0

        // Energy: in recording we track the shaped mic level with a light EMA
        // for fluidity. In processing there is no mic input, so we self-animate.
        if (isProcessing) {
            energy = Math.max(energy, 0.42)
        } else {
            energy = energy * 0.35 + amp * 0.65
        }

        var litBase = isProcessing ? Math.max(energy, 0.42) : energy

        var maxRatio = isProcessing ? 0.96 : 0.94
        var flicker  = isProcessing ? 0.24 : 0.10
        // Recording floor is 0.00 — at true silence NO dots light up.
        var visualFloor = isProcessing ? 0.18 : 0.00
        // Only apply flicker jitter when there is genuine signal (or processing),
        // so silence stays completely dark instead of randomly sparkling.
        var jitter = (isProcessing || litBase > 0.001)
            ? (Math.random() - 0.5) * flicker
            : 0.0
        var litRatio = Math.max(visualFloor, Math.min(maxRatio, litBase + jitter))

        // Copy the precomputed eligible cell list so we can shuffle in-place
        var eligible = _eligibleCells.slice()

        var activeCount = Math.round(eligible.length * litRatio)
        var hotCount = isProcessing
            ? Math.max(1, Math.round(activeCount * 0.18))
            : Math.max(0, Math.round(activeCount * 0.08))

        // Fisher-Yates shuffle
        for (var i = eligible.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1))
            var tmp = eligible[i]; eligible[i] = eligible[j]; eligible[j] = tmp
        }

        var activeSet = {}
        var hotSet = {}
        for (var k = 0; k < activeCount && k < eligible.length; k++) {
            activeSet[eligible[k]] = true
        }
        for (var h = 0; h < hotCount && h < eligible.length; h++) {
            hotSet[eligible[h]] = true
        }

        var arr = new Array(rows * cols)
        for (var rr = 0; rr < rows; rr++) {
            for (var cc = 0; cc < cols; cc++) {
                var idx = rr * cols + cc
                var isHot    = hotSet[idx] === true
                var isActive = activeSet[idx] === true
                var color

                if (isHot) {
                    // Brightest tier — hot cells
                    color = isProcessing
                        ? "rgba(255,159,61,0.95)"      // orange for processing
                        : "rgba(189,193,201,0.92)"      // near-white for recording
                } else if (isActive) {
                    // Mid tier — active cells with sparkle alpha
                    var sparkle = Math.random() * flicker
                    if (isProcessing) {
                        var a1 = Math.min(0.88, 0.48 + litBase * 0.28 + sparkle)
                        color = "rgba(255,188,111," + a1.toFixed(2) + ")"  // warm amber
                    } else {
                        var a2 = Math.min(0.82, 0.34 + litBase * 0.30 + sparkle)
                        // Multi-tone grey: randomly pick one of 3 grey shades
                        var g = Math.random()
                        if (g < 0.33) {
                            color = "rgba(168,174,184," + a2.toFixed(2) + ")"  // mid grey
                        } else if (g < 0.66) {
                            color = "rgba(140,148,160," + a2.toFixed(2) + ")"  // darker grey
                        } else {
                            color = "rgba(200,204,212," + a2.toFixed(2) + ")"  // lighter grey
                        }
                    }
                } else {
                    // Dim tier — background dots
                    color = isProcessing
                        ? "rgba(255,159,61,0.14)"       // dim orange tint
                        : "rgba(96,102,112,0.30)"        // dim grey (matches reference)
                }

                arr[idx] = color
            }
        }

        // ── Button-zone independent animation ────────────────────────
        // Comet orbits the 12-cell perimeter; inner 2x2 breathes.
        // Color: orange in recording, white in processing.
        var btnActive = (st === "recording" || st === "streaming" || isProcessing)
        if (btnActive) {
            // Advance head every 2 frames (~150 ms/step → ~0.55 rev/sec)
            _btnSubTick++
            if (_btnSubTick >= 2) {
                _btnSubTick = 0
                _btnTick = (_btnTick + 1) % 12
            }
            // Pulse angle for inner cells
            _btnPulseAngle = (_btnPulseAngle + 0.28) % (Math.PI * 2)

            var cR = 255
            var cG = isProcessing ? 255 : 93
            var cB = isProcessing ? 255 : 30

            // Perimeter cells — comet with 3-dot tail
            for (var p = 0; p < 12; p++) {
                var pr = _btnPerim[p][0]
                var pc = _btnPerim[p][1]
                var pidx = (btnRow + pr) * cols + (btnCol + pc)
                // clockwise distance from head (wraps)
                var dist = (_btnTick - p + 12) % 12
                var palpha
                if      (dist === 0) palpha = 1.00
                else if (dist === 1) palpha = 0.60
                else if (dist === 2) palpha = 0.28
                else                 palpha = 0.07
                arr[pidx] = "rgba(" + cR + "," + cG + "," + cB + "," + palpha.toFixed(2) + ")"
            }

            // Inner 2x2 — breathing pulse
            var pAlpha = 0.12 + 0.50 * (0.5 + 0.5 * Math.sin(_btnPulseAngle))
            var innerCells = [[1,1],[1,2],[2,1],[2,2]]
            for (var ic = 0; ic < 4; ic++) {
                var ir = innerCells[ic][0]
                var icc = innerCells[ic][1]
                arr[(btnRow + ir) * cols + (btnCol + icc)] =
                    "rgba(" + cR + "," + cG + "," + cB + "," + pAlpha.toFixed(2) + ")"
            }
        } else {
            // Idle — clear button zone and reset tick
            _btnTick = 0; _btnSubTick = 0; _btnPulseAngle = 0.0
            for (var bp = 0; bp < 12; bp++) {
                arr[(btnRow + _btnPerim[bp][0]) * cols + (btnCol + _btnPerim[bp][1])] = "rgba(0,0,0,0)"
            }
            arr[(btnRow+1)*cols+(btnCol+1)] = "rgba(0,0,0,0)"
            arr[(btnRow+1)*cols+(btnCol+2)] = "rgba(0,0,0,0)"
            arr[(btnRow+2)*cols+(btnCol+1)] = "rgba(0,0,0,0)"
            arr[(btnRow+2)*cols+(btnCol+2)] = "rgba(0,0,0,0)"
        }

        dotStates = arr
        dotCanvas.requestPaint()

        // Energy decay after each frame (matches reference)
        energy = Math.max(isProcessing ? 0.04 : 0.00, energy * (isProcessing ? 0.82 : 0.74))
    }

    // ----------------------------------------------------------------
    // FrameAnimation — vsync-locked, fires inside Qt's render loop.
    // Unlike QTimer, it cannot be delayed by main-thread work (audio
    // signal delivery, Python callbacks, etc.), so animation is jitter-free.
    // We accumulate elapsed time and roll dots at ~80 ms intervals.
    // ----------------------------------------------------------------
    FrameAnimation {
        id: frameAnim
        running: root.pillState === "recording" ||
                 root.pillState === "streaming" ||
                 root.pillState === "processing"

        property real _acc: 0.0

        onTriggered: {
            _acc += frameTime
            if (_acc >= 0.08) {
                _acc -= 0.08
                root.rollDots()
            }
        }

        onRunningChanged: {
            if (!running) {
                _acc = 0.0
                root.dotStates = []
                root.energy = 0.0
                root._btnTick = 0
                root._btnSubTick = 0
                root._btnPulseAngle = 0.0
                dotCanvas.requestPaint()
            }
        }
    }

    onPillStateChanged: {
        if (pillState === "processing") {
            energy = 0.54  // seed processing animation (matches reference)
        } else if (pillState === "idle" || pillState === "done") {
            dotStates = []
            energy = 0.0
            dotCanvas.requestPaint()
        }
    }

    // ----------------------------------------------------------------
    // Dark pill background
    // ----------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        radius: height / 2
        border.color: "#1a1a1a"
        border.width: 1
    }

    // ----------------------------------------------------------------
    // Canvas — single paint call for all dots
    // ----------------------------------------------------------------
    Canvas {
        id: dotCanvas
        anchors.fill: parent
        renderStrategy: Canvas.Threaded

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var states  = root.dotStates
            var cols    = root.cols
            var rows    = root.rows
            var d       = root.dotD
            var cell    = root.cell
            var rad     = d / 2
            var hasData = states && states.length > 0

            for (var row = 0; row < rows; row++) {
                for (var col = 0; col < cols; col++) {
                    if (root.isEdgeCell(col, row)) continue

                    var cx  = col * cell + rad + 1
                    var cy  = row * cell + rad + 1
                    var idx = row * cols + col
                    // Button-zone dots get their own animated color (or transparent when idle)
                    var inBtn = root.isButtonZone(col, row)
                    var color
                    if (inBtn) {
                        color = (hasData && states[idx]) ? states[idx] : "rgba(0,0,0,0)"
                    } else {
                        color = hasData && states[idx] ? states[idx] : "rgba(96,102,112,0.30)"
                    }

                    ctx.beginPath()
                    ctx.arc(cx, cy, rad, 0, Math.PI * 2)
                    ctx.fillStyle = color
                    ctx.fill()
                }
            }
        }
    }

    // ----------------------------------------------------------------
    // Confirm button — plain capital "G", no background
    // ----------------------------------------------------------------
    Item {
        readonly property real zoneX: root.btnCol  * root.cell + 1
        readonly property real zoneY: root.btnRow  * root.cell + 1
        readonly property real zoneW: root.btnSpan * root.cell
        readonly property real zoneH: root.btnSpan * root.cell

        x: zoneX + (zoneW - 16) / 2
        y: zoneY + (zoneH - 16) / 2
        width: 16
        height: 16

        visible: root.pillState === "recording" || root.pillState === "streaming" || root.pillState === "processing"

        Text {
            anchors.centerIn: parent
            text: "G"
            color: root.pillState === "processing"
                   ? (btnHover.containsMouse ? "#FF8040" : "#FF5D1E")
                   : (btnHover.containsMouse ? "#e0e4ec" : "#9098a8")
            font.pixelSize: 13
            font.bold: true
            Behavior on color { ColorAnimation { duration: 80 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (pillViewModel) pillViewModel.on_confirm_clicked() }
        }

        HoverHandler { id: btnHover }
    }
}
