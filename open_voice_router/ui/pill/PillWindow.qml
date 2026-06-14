// PillWindow.qml — Dot-grid pill, ported from reference pill.html design
// Key improvements: proper noise gate, power curve, multiple grey shades,
// hot/active/dim cell tiers, flicker, isolated mic-to-display pipeline.
// NOTE: deliberately NO QtQuick.Controls import — the pill is the only
// PERMANENT QML window, and it uses zero Controls types. Importing Controls
// here would keep the whole Controls plugin stack resident for the app's
// entire lifetime (~4+ MB measured). Plain Window has everything we need.
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: root

    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

    readonly property int cols: 25
    readonly property int rows: 8
    readonly property int dotD: 3      // dot diameter px (slightly smaller than original 4)
    readonly property int gap:  2      // gap between dots (same as original)
    readonly property int cell: dotD + gap   // 5px per cell

    // Height of the dot-grid pill body itself (unchanged from the original).
    readonly property int pillBodyHeight: rows * cell + 2
    // Extra space reserved ABOVE the pill so the prompt "riser" can slide up
    // out of it. The window grows by this much and shifts up by the same
    // amount (see y below), so the pill body stays in its exact prior place.
    readonly property int riserReserve: 32

    width:  cols * cell + 2
    height: pillBodyHeight + riserReserve

    // Button zone: 4x4 at right side, 3 cols from right edge
    // Cols 18–21, rows 2–5
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
    // Curved silhouette for 25x8 grid.
    // Col 0/24: fully hidden.
    // Col 1/23: rows 2-5 only (one dot trimmed from top and bottom).
    // Col 2/22: rows 1-6 only.
    // ----------------------------------------------------------------
    function isEdgeCell(c, r) {
        if (c === 0 || c === cols - 1) return true
        if (c === 1 || c === cols - 2) return (r < 2 || r > 5)
        if (c === 2 || c === cols - 3) return (r < 1 || r > 6)
        return false
    }

    function isButtonZone(c, r) {
        if (!(c >= btnCol && c < btnCol + btnSpan &&
              r >= btnRow && r < btnRow + btnSpan)) return false
        // four corners become normal sound-reactive dots
        var lc = c - btnCol; var lr = r - btnRow
        if ((lc === 0 || lc === 3) && (lr === 0 || lr === 3)) return false
        return true
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

        // Processing: unified diagonal sweep across every dot in the pill.
        // Replaces the shuffle entirely — one white wave, bottom-left → top-right.
        if (isProcessing) {
            _btnAngle = (_btnAngle + 0.08) % (Math.PI * 2)
            var procArr = new Array(rows * cols)
            // Three bands, evenly spaced, sliding in one direction
            var totalD  = 31.0
            var spacing = totalD / 3.0
            var lead    = (_btnAngle / (Math.PI * 2)) * totalD
            for (var pr = 0; pr < rows; pr++) {
                for (var pc = 0; pc < cols; pc++) {
                    if (isEdgeCell(pc, pr)) continue
                    var pd = pc + (7 - pr)      // diagonal coord 0–31
                    var pBright = 0.0
                    for (var wi = 0; wi < 3; wi++) {
                        var wpos = (lead + wi * spacing) % totalD
                        var dd = Math.abs(pd - wpos)
                        dd = Math.min(dd, totalD - dd)  // wrap-around distance
                        pBright = Math.max(pBright, Math.max(0.0, 1.0 - dd / 3.5))
                    }
                    procArr[pr * cols + pc] =
                        "rgba(255,93,30," + (0.03 + pBright * 0.93).toFixed(2) + ")"
                }
            }
            dotStates = procArr
            dotCanvas.requestPaint()
            return
        }

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
                        ? "rgba(255,93,30,0.95)"        // signature orange for processing
                        : "rgba(189,193,201,0.92)"      // near-white for recording
                } else if (isActive) {
                    // Mid tier — active cells with sparkle alpha
                    var sparkle = Math.random() * flicker
                    if (isProcessing) {
                        var a1 = Math.min(0.88, 0.48 + litBase * 0.28 + sparkle)
                        color = "rgba(255,93,30," + a1.toFixed(2) + ")"    // signature orange
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
                        ? "rgba(255,93,30,0.14)"        // dim signature orange tint
                        : "rgba(96,102,112,0.30)"        // dim grey (matches reference)
                }

                arr[idx] = color
            }
        }

        // ── Button-zone independent animation ────────────────────────
        // 12 cells: 4×4 minus 4 corners. Two distinct animations.
        // Recording: orange radial ripple — center pulses first, perimeter lags.
        // Processing: white diagonal spotlight — sweeps bottom-left → top-right
        //             with soft falloff on both sides of the bright peak.
        var btnActive = (st === "recording" || st === "streaming" || isProcessing)
        if (btnActive) {
            _btnAngle = (_btnAngle + 0.26) % (Math.PI * 2)

            for (var blr = 0; blr < 4; blr++) {
                for (var blc = 0; blc < 4; blc++) {
                    if ((blr === 0 || blr === 3) && (blc === 0 || blc === 3)) continue

                    // Radial ripple — inner cells lead, perimeter lags
                    var dr = blr - 1.5; var dc = blc - 1.5
                    var rdist = Math.sqrt(dr * dr + dc * dc)
                    var brightness = 0.5 + 0.5 * Math.sin(_btnAngle - rdist * 1.4)
                    var balpha = 0.04 + brightness * 0.96
                    arr[(btnRow + blr) * cols + (btnCol + blc)] =
                        "rgba(255,93,30," + balpha.toFixed(2) + ")"
                }
            }
        } else {
            _btnAngle = 0.0
            for (var blr2 = 0; blr2 < 4; blr2++) {
                for (var blc2 = 0; blc2 < 4; blc2++) {
                    if ((blr2 === 0 || blr2 === 3) && (blc2 === 0 || blc2 === 3)) continue
                    arr[(btnRow + blr2) * cols + (btnCol + blc2)] = "rgba(0,0,0,0)"
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
        // The prompt riser only makes sense while actively recording — once we
        // leave recording/streaming (stop, processing, idle) snap it away.
        if (pillState !== "recording" && pillState !== "streaming") {
            promptRiser.shown = false
            riserHideTimer.stop()
        }
    }

    // ================================================================
    // Prompt-profile RISER
    // A SECOND pill, the SAME width as the main pill, that slides up from
    // behind it — only its top crescent shows, carrying the active prompt
    // name with ‹ / › chevrons. Declared BEFORE pillBody so the opaque main
    // pill draws on top of it; the riser's lower half is fully hidden behind
    // the pill (identical width → no edges peek out), and the pill casts a
    // soft shadow onto it at the seam (seamShadow below). Auto-retracts a
    // moment after the last switch.
    // ================================================================
    Item {
        id: promptRiser

        property bool shown: false

        // Same x / width as the main pill so they share a footprint.
        x: root.cell - 2
        width:  (root.cols - 2) * root.cell + 5

        // Visible crescent height above the pill.
        readonly property int _peek: 22
        // The bottom reaches the pill's 50% mark (its widest point). With SQUARE
        // bottom corners (below), that lower edge is swallowed by the full-width
        // middle of the pill, so nothing curved ever pokes past its rounded ends.
        height: _peek + root.pillBodyHeight / 2

        readonly property int _hiddenY: root.riserReserve            // fully behind the pill
        readonly property int _shownY: root.riserReserve - _peek      // crescent peeking out
        y: shown ? _shownY : _hiddenY
        opacity: shown ? 1.0 : 0.0

        Behavior on y       { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.InOutQuad } }

        // Rounded TOP corners — the visible crescent.
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: "#0b0b0a"
            border.color: "#1c1c1c"
            border.width: 1
        }
        // SQUARE bottom corners — a flat-cornered panel over the lower portion
        // (hidden behind the pill) so the bottom-left/right are not rounded.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height - 13
            color: "#0b0b0a"
        }

        // Content lives in the VISIBLE crescent only (above the pill).
        Item {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.topMargin: 1
            height: promptRiser._peek

            Text {
                anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                text: "‹"
                font.family: "JetBrains Mono"
                font.pixelSize: 14
                color: Qt.rgba(1.0, 0.365, 0.118, 0.9)
            }

            Text {
                anchors.centerIn: parent
                text: pillViewModel ? pillViewModel.active_prompt_name : ""
                elide: Text.ElideRight
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                font.letterSpacing: 0.4
                color: "#ECE5DA"
            }

            Text {
                anchors { right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter }
                text: "›"
                font.family: "JetBrains Mono"
                font.pixelSize: 14
                color: Qt.rgba(1.0, 0.365, 0.118, 0.9)
            }
        }
    }

    // Auto-hide timer — restarted on every prompt switch.
    Timer {
        id: riserHideTimer
        interval: 1600
        onTriggered: promptRiser.shown = false
    }

    // Reveal the riser whenever the controller reports a prompt switch, but
    // only while actually recording (the controller already guards this too).
    Connections {
        target: pillViewModel
        function onPrompt_nav_pulse() {
            if (root.pillState === "recording" || root.pillState === "streaming") {
                promptRiser.shown = true
                riserHideTimer.restart()
            }
        }
    }

    // ================================================================
    // PILL BODY — the dot-grid pill itself. Bottom-anchored so the
    // reserved riser space sits above it and the pill keeps its exact
    // prior on-screen position.
    // ================================================================
    Item {
        id: pillBody
        width: parent.width
        height: root.pillBodyHeight
        anchors.bottom: parent.bottom

        // Drop shadow the pill casts upward onto the riser. Only active while
        // the riser is visible; fades in/out with it via promptRiser.opacity.
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: "#4a4a4a"
            shadowOpacity: promptRiser.opacity * 0.28
            shadowBlur: 1.0
            shadowVerticalOffset: -5
            shadowHorizontalOffset: 0
        }

        // ----------------------------------------------------------------
        // Dark pill background — full height, width trimmed to the visible
        // dot columns (cols 1–23), one cell inset on each side.
        // ----------------------------------------------------------------
        Rectangle {
            x: root.cell - 2
            y: 0
            width:  (root.cols - 2) * root.cell + 5
            height: parent.height
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
}
