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
    // ----------------------------------------------------------------
    property real _btnAngle: 0.0

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
        // Wave cascade fills all 16 dots.
        // Recording: diagonal flow (orange). Processing: radial pulse (white).
        var btnActive = (st === "recording" || st === "streaming" || isProcessing)
        if (btnActive) {
            _btnAngle = (_btnAngle + 0.35) % (Math.PI * 2)

            var cR = 255
            var cG = isProcessing ? 255 : 93
            var cB = isProcessing ? 255 : 30

            for (var br = 0; br < 4; br++) {
                for (var bc = 0; bc < 4; bc++) {
                    var phase
                    if (isProcessing) {
                        var dr = br - 1.5
                        var dc = bc - 1.5
                        phase = -Math.sqrt(dr * dr + dc * dc) * 1.6
                    } else {
                        phase = bc * 1.4 + br * 0.5
                    }
                    var brightness = 0.5 + 0.5 * Math.sin(_btnAngle + phase)
                    var balpha = isProcessing
                        ? (0.12 + brightness * 0.88)
                        : (0.08 + brightness * 0.92)
                    arr[(btnRow + br) * cols + (btnCol + bc)] =
                        "rgba(" + cR + "," + cG + "," + cB + "," + balpha.toFixed(2) + ")"
                }
            }
        } else {
            _btnAngle = 0.0
            for (var bp = 0; bp < 4; bp++) {
                for (var bq = 0; bq < 4; bq++) {
                    arr[(btnRow + bp) * cols + (btnCol + bq)] = "rgba(0,0,0,0)"
                }
            }
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
                root._btnAngle = 0.0
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
    // Confirm button — invisible click zone over button grid
    // ----------------------------------------------------------------
    Item {
        x: root.btnCol  * root.cell + 1
        y: root.btnRow  * root.cell + 1
        width:  root.btnSpan * root.cell
        height: root.btnSpan * root.cell

        visible: root.pillState === "recording" || root.pillState === "streaming" || root.pillState === "processing"

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (pillViewModel) pillViewModel.on_confirm_clicked() }
        }
    }
}
