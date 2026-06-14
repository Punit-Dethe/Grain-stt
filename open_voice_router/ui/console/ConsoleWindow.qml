// ConsoleWindow.qml — QUICK PANEL ONLY (Pixel-Perfect)
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Effects

ApplicationWindow {
    id: root
    title: "Grain Console"
    width: 1280
    height: 760
    minimumWidth: 1200
    minimumHeight: 760
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: false

    readonly property int cornerRadius: 36

    // ── Color Palette ───────────────────────────────────────────────────────
    readonly property color bgDark: "#0c0b0a"
    readonly property color bgWindow: "#ECE5DA"  // LIGHT BEIGE background!
    readonly property color surfaceTravertine: "#ECE5DA"
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color surfaceCharcoal: "#141312"
    readonly property color textDark: "#141312"
    readonly property color textLight: "#ECE5DA"
    readonly property color textMuted: Qt.rgba(0.925, 0.898, 0.855, 0.4)
    readonly property color brandOrange: "#FF5D1E"
    readonly property color brandGreen: "#10B981"
    readonly property color brandPurple: "#8B5CF6"

    // State Management
    property bool showAdvancedPanel: false

    // ── Theme (light / dark) ────────────────────────────────────────────────
    // Single source of truth is the persisted ViewModel flag; toggling calls
    // save_ui_dark_mode() which updates the flag, which re-drives this binding.
    property bool isDark: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                          ? consoleViewModel.ui_dark_mode : false
    ConsoleTheme { id: theme; isDark: root.isDark }

    // ── Cable Dragging State ────────────────────────────────────────────────
    property var connections: []
    property bool dragActive: false
    property var dragSourceJack: null
    property real dragStartX: 0
    property real dragStartY: 0
    property real currentDragX: 0
    property real currentDragY: 0
    property string dragColor: "#FF5D1E"

    function getJackCenter(jackItem) {
        if (!jackItem) return Qt.point(0, 0)
        return jackItem.mapToItem(contentRoot, jackItem.width / 2, jackItem.height / 2)
    }

    function handleDragStarted(jack, sceneX, sceneY) {
        var center = getJackCenter(jack)
        dragSourceJack = jack
        dragStartX = center.x
        dragStartY = center.y
        currentDragX = sceneX
        currentDragY = sceneY
        dragColor = jack.jackColor
        dragActive = true
        cableCanvas.requestPaint()
    }

    function handleDragMoved(jack, sceneX, sceneY) {
        if (!dragActive) return
        currentDragX = sceneX
        currentDragY = sceneY
        cableCanvas.requestPaint()
    }

    function handleDragEnded(jack, sceneX, sceneY) {
        if (!dragActive) return
        dragActive = false

        var targetJack = findTargetJack(sceneX, sceneY, jack)
        if (targetJack) {
            var newConnections = []
            for (var i = 0; i < connections.length; i++) {
                var conn = connections[i]
                // For a given input, only 1 connection usually allowed, replace it
                if (conn.target !== targetJack) {
                    newConnections.push(conn)
                }
            }
            newConnections.push({
                source: dragSourceJack,
                target: targetJack,
                color: dragSourceJack.jackColor
            })
            connections = newConnections
        }

        dragSourceJack = null
        cableCanvas.requestPaint()
    }

    function findTargetJack(sceneX, sceneY, sourceJack) {
        var potentialTargets = [
            moduleB.inputJack,
            moduleC.inputJack
        ]

        if (sourceJack.jackId.indexOf("input") !== -1) {
            potentialTargets = [
                moduleA.outputJack,
                moduleB.outputJack,
                moduleC.outputJack
            ]
        }

        var dropRadius = 24

        for (var i = 0; i < potentialTargets.length; i++) {
            var t = potentialTargets[i]
            if (!t) continue

            var center = getJackCenter(t)
            var dx = center.x - sceneX
            var dy = center.y - sceneY
            var dist = Math.sqrt(dx*dx + dy*dy)

            if (dist <= dropRadius && t !== sourceJack) {
                return t
            }
        }
        return null
    }

    function bindJack(jack) {
        if (!jack) return;
        jack.dragStarted.connect(root.handleDragStarted)
        jack.dragMoved.connect(root.handleDragMoved)
        jack.dragEnded.connect(root.handleDragEnded)

        jack.clicked.connect(function() {
            var newConn = []
            for(var i=0; i<root.connections.length; i++) {
                if (root.connections[i].source !== jack && root.connections[i].target !== jack) {
                    newConn.push(root.connections[i])
                }
            }
            root.connections = newConn
            cableCanvas.requestPaint()
        })
    }

    Component.onCompleted: {
        if (typeof consoleViewModel !== "undefined") {
            consoleViewModel.load()
        }
        Qt.callLater(function() {
            bindJack(moduleA.outputJack)
            bindJack(moduleB.inputJack)
            bindJack(moduleB.outputJack)
            bindJack(moduleC.inputJack)
            bindJack(moduleC.outputJack)

            root.connections = [
                { source: moduleA.outputJack, target: moduleB.inputJack, color: "#FF5D1E" },
                { source: moduleB.outputJack, target: moduleC.inputJack, color: "#10B981" }
            ]

            cableCanvas.requestPaint()
        })
    }

    // ── Resizing Handles for Frameless Window ───────────────────────────────
    MouseArea { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; cursorShape: Qt.SizeHorCursor; onPressed: root.startSystemResize(Qt.LeftEdge) }
    MouseArea { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; cursorShape: Qt.SizeHorCursor; onPressed: root.startSystemResize(Qt.RightEdge) }
    MouseArea { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 6; cursorShape: Qt.SizeVerCursor; onPressed: root.startSystemResize(Qt.TopEdge) }
    MouseArea { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 6; cursorShape: Qt.SizeVerCursor; onPressed: root.startSystemResize(Qt.BottomEdge) }
    MouseArea { anchors.left: parent.left; anchors.top: parent.top; width: 10; height: 10; cursorShape: Qt.SizeFDiagCursor; onPressed: root.startSystemResize(Qt.TopLeftCorner) }
    MouseArea { anchors.right: parent.right; anchors.top: parent.top; width: 10; height: 10; cursorShape: Qt.SizeBDiagCursor; onPressed: root.startSystemResize(Qt.TopRightCorner) }
    MouseArea { anchors.left: parent.left; anchors.bottom: parent.bottom; width: 10; height: 10; cursorShape: Qt.SizeBDiagCursor; onPressed: root.startSystemResize(Qt.BottomLeftCorner) }
    MouseArea { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 10; height: 10; cursorShape: Qt.SizeFDiagCursor; onPressed: root.startSystemResize(Qt.BottomRightCorner) }

    // ── Content Root with Rounded Mask ──────────────────────────────────────
    Item {
        id: contentRoot
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskRect
        }

        // Main window background — themed (beige in light, black in dark)
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: theme.windowBg
        }

        // ═══════════════════════════════════════════════════════════════════
        // QUICK LOOK PANEL
        // ═══════════════════════════════════════════════════════════════════
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 29
            anchors.rightMargin: 29
            anchors.topMargin: 16
            anchors.bottomMargin: 20
            spacing: 0

            // ── HEADER BAR ──────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                DragHandler {
                    target: null
                    onActiveChanged: if (active) root.startSystemMove()
                }

                // Bottom border
                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: -5
                    color: "transparent"

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: theme.line(0.08)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 14

                    // Left: Brand + Advanced Button
                    RowLayout {
                        spacing: 14
                        Layout.fillWidth: true

                        // Brand Badge
                        Rectangle {
                            width: 210
                            height: 28
                            radius: 5
                            color: theme.brandBadgeBg

                            Text {
                                anchors.centerIn: parent
                                text: "GRAIN // QUICK PANEL"
                                font.family: "Syne"
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 1.2
                                color: theme.brandBadgeText
                            }
                        }

                        // Advanced Calibration Button
                        Text {
                            text: "[ Advanced Calibration ]"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.5
                            color: root.brandOrange

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true

                                onEntered: parent.color = Qt.rgba(1, 0.365, 0.118, 0.7)
                                onExited: parent.color = root.brandOrange

                                onClicked: {
                                    root.showAdvancedPanel = true
                                }
                            }
                        }
                    }

                    // Toggle + controls sit in one Row so the gap between them is
                    // a fixed 12 px and they visually read as a single header unit.
                    Row {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: 12

                        // ── Light / Dark toggle ─────────────────────────────
                        Rectangle {
                            id: themeToggle
                            width: 90; height: 26; radius: 8
                            // Light: dark beige track. Dark: slightly lighter than page bg.
                            color: root.isDark ? "#272422" : "#B8B0A6"
                            Behavior on color { ColorAnimation { duration: 380; easing.type: Easing.InOutCubic } }
                            border.width: 0
                            anchors.verticalCenter: parent.verticalCenter

                            // Sliding thumb — same radius as the outer box (radius: 8)
                            Rectangle {
                                id: themeThumb
                                width: 38; height: 20; radius: 8; y: 3
                                x: root.isDark ? 49 : 3
                                // Light: black thumb. Dark: cream/beige thumb.
                                color: root.isDark ? "#ECE5DA" : "#111010"
                                Behavior on x     { NumberAnimation  { duration: 320; easing.type: Easing.InOutCubic } }
                                Behavior on color { ColorAnimation   { duration: 380; easing.type: Easing.InOutCubic } }
                            }

                            // "LIGHT" label — readable on black thumb (light mode), dim otherwise
                            Text {
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: "LIGHT"
                                font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true
                                color: root.isDark ? Qt.rgba(0.925, 0.898, 0.855, 0.32) : "#DDD5C8"
                                Behavior on color { ColorAnimation { duration: 380 } }
                            }

                            // "DARK" label — readable on cream thumb (dark mode), dim otherwise
                            Text {
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: "DARK"
                                font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true
                                color: root.isDark ? "#1a1816" : Qt.rgba(0.078, 0.071, 0.063, 0.38)
                                Behavior on color { ColorAnimation { duration: 380 } }
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var newDark = !root.isDark
                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        consoleViewModel.save_ui_dark_mode(newDark)
                                    else root.isDark = newDark
                                }
                            }
                        }

                        // ── Window controls box ─────────────────────────────
                        Rectangle {
                            color: theme.windowCtrlBoxBg; radius: 6
                            width: windowControlsRow.implicitWidth + 24; height: 24
                            anchors.verticalCenter: parent.verticalCenter

                            RowLayout {
                                id: windowControlsRow
                                anchors.centerIn: parent
                                spacing: 16

                                IconButton {
                                    iconPath: "M20 12H4"
                                    onClicked: root.showMinimized()
                                }
                                IconButton {
                                    iconPath: root.visibility === Window.Maximized ? "M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3" : "M4 4h16v16H4z"
                                    onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                                }
                                IconButton {
                                    iconPath: "M6 18L18 6M6 6l12 12"
                                    onClicked: root.close()
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 12 }

            // ── MODULE RACK VIEWPORT ───────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    spacing: 19

                    ModuleA {
                        id: moduleA
                        theme: theme
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    ModuleB {
                        id: moduleB
                        theme: theme
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    ModuleC {
                        id: moduleC
                        theme: theme
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
            }

            Item { Layout.preferredHeight: 12 }

            // ── BOTTOM STATUS BAR ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 16
                spacing: 0

                Text {
                    id: telemetryLink
                    text: "[ View Telemetry Logs ]"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.5
                    property bool _hover: false
                    color: _hover ? root.brandOrange : theme.ink(0.6)
                    Layout.fillWidth: true

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        onEntered: telemetryLink._hover = true
                        onExited: telemetryLink._hover = false

                        onClicked: {
                            console.log("View Telemetry Logs clicked")
                        }
                    }
                }

                RowLayout {
                    spacing: 6

                    Text {
                        text: "ACTIVE ROUTE:"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.5
                        color: theme.ink(0.45)
                    }

                    Text {
                        text: "STANDBY // MOUNT PATCH LINES"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1
                        color: theme.ink(0.8)
                    }
                }
            }
        }

        // ── Cable Rendering Canvas ──────────────────────────────────────────────
        Canvas {
            id: cableCanvas
            anchors.fill: parent
            z: 100 // Ensure it draws above the modules
            visible: !root.showAdvancedPanel  // ← HIDE when Advanced Panel is open
            renderTarget: Canvas.FramebufferObject

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                // Draw persistent connections
                for (var i = 0; i < root.connections.length; i++) {
                    var conn = root.connections[i]
                    var p1 = root.getJackCenter(conn.source)
                    var p2 = root.getJackCenter(conn.target)
                    drawCable(ctx, p1.x, p1.y, p2.x, p2.y, conn.color)
                }

                // Draw active drag connection
                if (root.dragActive && root.dragSourceJack) {
                    var startP = root.getJackCenter(root.dragSourceJack)
                    drawCable(ctx, startP.x, startP.y, root.currentDragX, root.currentDragY, root.dragColor)
                }
            }

            function drawCable(ctx, x1, y1, x2, y2, color) {
                // Bezier curve to simulate gravity sag
                var dx = Math.abs(x2 - x1)
                var dy = Math.abs(y2 - y1)
                var distance = Math.sqrt(dx * dx + dy * dy)
                var sag = Math.max(45, distance * 0.4)

                // Shadow
                ctx.beginPath()
                ctx.moveTo(x1, y1)
                ctx.bezierCurveTo(x1, y1 + sag, x2, y2 + sag, x2, y2)
                ctx.strokeStyle = "rgba(0,0,0,0.5)"
                ctx.lineWidth = 8
                ctx.lineCap = "round"
                ctx.stroke()

                // Main Cable
                ctx.beginPath()
                ctx.moveTo(x1, y1)
                ctx.bezierCurveTo(x1, y1 + sag, x2, y2 + sag, x2, y2)
                ctx.strokeStyle = color
                ctx.lineWidth = 5
                ctx.lineCap = "round"
                ctx.stroke()

                // Inner highlight
                ctx.beginPath()
                ctx.moveTo(x1, y1)
                ctx.bezierCurveTo(x1, y1 + sag, x2, y2 + sag, x2, y2)
                ctx.strokeStyle = "rgba(255,255,255,0.4)"
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.stroke()
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // ADVANCED CALIBRATION OVERLAY PANEL (New HTML-based design)
        // ═══════════════════════════════════════════════════════════════════
        Loader {
            id: advancedPanelLoader
            active: root.showAdvancedPanel
            asynchronous: false
            width: parent.width
            height: parent.height
            source: "AdvancedCalibrationPanel_HTML.qml"

            Connections {
                target: advancedPanelLoader.item
                function onCloseRequested() {
                    root.showAdvancedPanel = false
                }
            }

            // Slide-in from bottom when loaded
            NumberAnimation on y {
                id: panelSlideIn
                running: advancedPanelLoader.status === Loader.Ready
                from: advancedPanelLoader.height
                to: 0
                duration: 500
                easing.type: Easing.OutCubic
            }
        }
    }

    // ── Rounded Mask Rectangle ──────────────────────────────────────────────
    Item {
        id: maskRect
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "white"
        }
    }

    // ── Icon Button Component ───────────────────────────────────────────────
    component IconButton: Item {
        property string iconPath
        signal clicked()

        width: 14
        height: 14

        Canvas {
            id: iconCanvas
            anchors.fill: parent

            // Repaint as the theme animates so the stroke colour keeps pace.
            Connections {
                target: theme
                function onTChanged() { iconCanvas.requestPaint() }
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = iconHover.hovered ? root.brandOrange : theme.ink(0.55)
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                ctx.beginPath()
                if (iconPath.includes("M20 12H4")) {
                    // Minimize line
                    ctx.moveTo(2, 7)
                    ctx.lineTo(12, 7)
                } else if (iconPath.includes("M6 18L18 6")) {
                    // Close X
                    ctx.moveTo(3, 3)
                    ctx.lineTo(11, 11)
                    ctx.moveTo(11, 3)
                    ctx.lineTo(3, 11)
                } else {
                    // Maximize square
                    ctx.rect(3, 3, 8, 8)
                }
                ctx.stroke()
            }
        }

        HoverHandler {
            id: iconHover
            onHoveredChanged: iconCanvas.requestPaint()
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
