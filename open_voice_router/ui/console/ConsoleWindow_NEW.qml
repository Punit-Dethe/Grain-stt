// ConsoleWindow.qml — Complete UI Overhaul with 3D Carousel Advanced Mode
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Effects

ApplicationWindow {
    id: root
    title: "Grain Console"
    width: 1280
    height: 630
    minimumWidth: 980
    minimumHeight: 630
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: true

    readonly property int cornerRadius: 36

    // ── Color Palette (Modular Hardware Theme) ──────────────────────────────
    readonly property color bgDark: "#0c0b0a"
    readonly property color bgWindow: "#0c0b0a"
    readonly property color surfaceTravertine: "#ECE5DA"
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color surfaceCharcoal: "#141312"
    readonly property color carbonPocket: "#0c0b0a"
    readonly property color textDark: "#141312"
    readonly property color textLight: "#ECE5DA"
    readonly property color textMuted: Qt.rgba(0.925, 0.898, 0.855, 0.4)
    readonly property color brandOrange: "#FF5D1E"
    readonly property color brandGreen: "#10B981"
    readonly property color brandPurple: "#8B5CF6"
    readonly property color borderSubtle: Qt.rgba(1.000, 1.000, 1.000, 0.06)

    // ── State Management ────────────────────────────────────────────────────
    property bool advancedMode: false
    property int activeCardIndex: 0  // 0=general, 1=transcription, 2=processing, 3=logs

    Component.onCompleted: {
        if (typeof consoleViewModel !== "undefined") {
            consoleViewModel.load()
        }
    }

    // ── Content Root with Rounded Mask ──────────────────────────────────────
    Item {
        id: contentRoot
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskRect
        }

        // Main window background with radial gradient
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: root.bgWindow
            
            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.925, 0.898, 0.855, 0.15) }
                    GradientStop { position: 0.65; color: "transparent" }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // 1. QUICK LOOK PANEL (Main Default Screen)
        // ═══════════════════════════════════════════════════════════════════
        Item {
            id: mainQuickPanel
            anchors.fill: parent
            visible: opacity > 0
            opacity: !root.advancedMode ? 1.0 : 0.0
            
            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0

                // ── HEADER BAR ──────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    Rectangle {
                        anchors.fill: parent
                        anchors.bottomMargin: 1
                        color: "transparent"
                        
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.rgba(0.000, 0.000, 0.000, 0.08)
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
                                width: 160
                                height: 24
                                radius: 4
                                color: root.surfaceCharcoal
                                
                                // Dark metal grain
                                Canvas {
                                    anchors.fill: parent
                                    opacity: 0.03
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.fillStyle = "#ffffff"
                                        for (var x = 0; x < width; x += 4) {
                                            for (var y = 0; y < height; y += 4) {
                                                if ((x + y) % 8 === 0) ctx.fillRect(x, y, 1, 1)
                                            }
                                        }
                                    }
                                }
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "GRAIN // QUICK PANEL"
                                    font.family: "Syne"
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: root.textLight
                                }
                            }

                            // Advanced Calibration Button
                            Text {
                                text: "[ Advanced Calibration ]"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1.5
                                color: root.brandOrange
                                
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.advancedMode = true
                                }
                            }
                        }

                        // Right: Window Controls
                        Rectangle {
                            width: 100
                            height: 28
                            radius: 8
                            color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 14

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
                                    onClicked: Qt.quit()
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                // ── MODULE RACK VIEWPORT ───────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: 20

                        ModuleA {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }

                        ModuleB {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }

                        ModuleC {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                // ── BOTTOM STATUS BAR ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20

                    Text {
                        text: "[ View Telemetry Logs ]"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9.5
                        font.bold: true
                        font.letterSpacing: 1.5
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        Layout.fillWidth: true
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.advancedMode = true
                                root.activeCardIndex = 3
                            }
                        }
                    }

                    Text {
                        text: "ACTIVE ROUTE: STANDBY // MOUNT PATCH LINES"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9.5
                        font.bold: true
                        font.letterSpacing: 1
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.8)
                    }
                }

                Item { Layout.preferredHeight: 4 }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // 2. ADVANCED CALIBRATION PANEL (3D Carousel Overlay)
        // ═══════════════════════════════════════════════════════════════════
        Rectangle {
            id: advancedCalibrationPanel
            anchors.fill: parent
            color: "#050505"
            visible: opacity > 0
            opacity: root.advancedMode ? 1.0 : 0.0
            
            Behavior on opacity {
                NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
            }

            // Dark metal grain
            Canvas {
                anchors.fill: parent
                opacity: 0.03
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.fillStyle = "#ffffff"
                    for (var x = 0; x < width; x += 4) {
                        for (var y = 0; y < height; y += 4) {
                            if ((x + y) % 8 === 0) ctx.fillRect(x, y, 1, 1)
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                anchors.topMargin: 24
                spacing: 0

                // ── TOP ADVANCED HEADER ─────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    RowLayout {
                        anchors.fill: parent
                        spacing: 24

                        // Left: Title + Navigation
                        RowLayout {
                            spacing: 24
                            Layout.fillWidth: true

                            // Title Badge
                            Rectangle {
                                width: 200
                                height: 24
                                radius: 4
                                color: "#4A4844"
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "// ADVANCED CALIBRATION"
                                    font.family: "Syne"
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: root.textLight
                                }
                            }

                            // Navigation Markers
                            RowLayout {
                                spacing: 16

                                CardMarker {
                                    text: "GENERAL"
                                    active: root.activeCardIndex === 0
                                    onClicked: root.activeCardIndex = 0
                                }

                                CardMarker {
                                    text: "TRANSCRIPTION"
                                    active: root.activeCardIndex === 1
                                    onClicked: root.activeCardIndex = 1
                                }

                                CardMarker {
                                    text: "PROCESSING"
                                    active: root.activeCardIndex === 2
                                    onClicked: root.activeCardIndex = 2
                                }

                                CardMarker {
                                    text: "LOCAL LOGS"
                                    active: root.activeCardIndex === 3
                                    onClicked: root.activeCardIndex = 3
                                }
                            }
                        }

                        // Right: Close Button
                        Rectangle {
                            width: 80
                            height: 28
                            radius: 8
                            color: Qt.rgba(1.000, 1.000, 1.000, 0.04)
                            border.color: Qt.rgba(1.000, 1.000, 1.000, 0.08)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "[ CLOSE ]"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1.5
                                color: root.brandOrange
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.advancedMode = false
                            }
                        }
                    }
                }

                // ── 3D CAROUSEL SCENE ───────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // 3D perspective transform
                    transform: [
                        Rotation {
                            origin.x: width / 2
                            origin.y: height * 0.36
                            axis { x: 1; y: 0; z: 0 }
                            angle: 0
                        }
                    ]

                    // Carousel Track Container
                    Item {
                        id: deckTrack
                        width: 760
                        height: 490
                        anchors.centerIn: parent

                        // Card 0: General/Configuration
                        ConfigurationPanel {
                            id: card0
                            anchors.fill: parent
                            
                            transform: [
                                Translate {
                                    x: root.activeCardIndex === 0 ? 0 : 
                                       root.activeCardIndex === 1 ? -390 :
                                       0
                                    y: 0
                                    z: root.activeCardIndex === 0 ? 0 :
                                       root.activeCardIndex === 1 ? -240 :
                                       -600
                                       
                                    Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                    Behavior on z { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                },
                                Rotation {
                                    origin.x: 380
                                    origin.y: 245
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: root.activeCardIndex === 0 ? 0 :
                                           root.activeCardIndex === 1 ? 40 :
                                           0
                                    
                                    Behavior on angle { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                }
                            ]
                            
                            opacity: root.activeCardIndex === 0 ? 1.0 :
                                   root.activeCardIndex === 1 ? 0.45 :
                                   0.0
                            
                            Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                        }

                        // Card 1: Transcription
                        TranscriptionPanel {
                            id: card1
                            anchors.fill: parent
                            
                            transform: [
                                Translate {
                                    x: root.activeCardIndex === 1 ? 0 :
                                       root.activeCardIndex === 0 ? 390 :
                                       root.activeCardIndex === 2 ? -390 :
                                       0
                                    y: 0
                                    z: root.activeCardIndex === 1 ? 0 :
                                       (root.activeCardIndex === 0 || root.activeCardIndex === 2) ? -240 :
                                       -600
                                       
                                    Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                    Behavior on z { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                },
                                Rotation {
                                    origin.x: 380
                                    origin.y: 245
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: root.activeCardIndex === 1 ? 0 :
                                           root.activeCardIndex === 0 ? -40 :
                                           root.activeCardIndex === 2 ? 40 :
                                           0
                                    
                                    Behavior on angle { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                }
                            ]
                            
                            opacity: root.activeCardIndex === 1 ? 1.0 :
                                   (root.activeCardIndex === 0 || root.activeCardIndex === 2) ? 0.45 :
                                   0.0
                            
                            Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                        }

                        // Card 2: Processing
                        ProcessingPanel {
                            id: card2
                            anchors.fill: parent
                            
                            transform: [
                                Translate {
                                    x: root.activeCardIndex === 2 ? 0 :
                                       root.activeCardIndex === 1 ? 390 :
                                       root.activeCardIndex === 3 ? -390 :
                                       0
                                    y: 0
                                    z: root.activeCardIndex === 2 ? 0 :
                                       (root.activeCardIndex === 1 || root.activeCardIndex === 3) ? -240 :
                                       -600
                                       
                                    Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                    Behavior on z { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                },
                                Rotation {
                                    origin.x: 380
                                    origin.y: 245
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: root.activeCardIndex === 2 ? 0 :
                                           root.activeCardIndex === 1 ? -40 :
                                           root.activeCardIndex === 3 ? 40 :
                                           0
                                    
                                    Behavior on angle { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                }
                            ]
                            
                            opacity: root.activeCardIndex === 2 ? 1.0 :
                                   (root.activeCardIndex === 1 || root.activeCardIndex === 3) ? 0.45 :
                                   0.0
                            
                            Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                        }

                        // Card 3: Local Logs
                        Rectangle {
                            id: card3
                            anchors.fill: parent
                            radius: 16
                            color: root.surfaceTravertine
                            border.color: Qt.rgba(1.000, 1.000, 1.000, 0.2)
                            border.width: 1
                            
                            Text {
                                anchors.centerIn: parent
                                text: "LOCAL LOGS\n(Coming Soon)"
                                font.family: "Syne"
                                font.pixelSize: 24
                                font.bold: true
                                color: root.textDark
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            transform: [
                                Translate {
                                    x: root.activeCardIndex === 3 ? 0 :
                                       root.activeCardIndex === 2 ? 390 :
                                       0
                                    y: 0
                                    z: root.activeCardIndex === 3 ? 0 :
                                       root.activeCardIndex === 2 ? -240 :
                                       -600
                                       
                                    Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                    Behavior on z { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                },
                                Rotation {
                                    origin.x: 380
                                    origin.y: 245
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: root.activeCardIndex === 3 ? 0 :
                                           root.activeCardIndex === 2 ? -40 :
                                           0
                                    
                                    Behavior on angle { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                                }
                            ]
                            
                            opacity: root.activeCardIndex === 3 ? 1.0 :
                                   root.activeCardIndex === 2 ? 0.45 :
                                   0.0
                            
                            Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
                        }
                    }
                }
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

    // ── Reusable Components ─────────────────────────────────────────────────
    
    // Card Navigation Marker
    component CardMarker: Text {
        property bool active: false
        signal clicked()

        text: "MARKER"
        font.family: "JetBrains Mono"
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.2
        color: active ? root.brandOrange : Qt.rgba(1.000, 1.000, 1.000, 0.3)
        
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
        
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // Icon Button Component
    component IconButton: Item {
        property string iconPath
        signal clicked()

        width: 10
        height: 10

        Canvas {
            id: iconCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = iconHover.containsMouse ? root.brandOrange : Qt.rgba(0.078, 0.075, 0.071, 0.55)
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                ctx.beginPath()
                if (iconPath.includes("M20 12H4")) {
                    ctx.moveTo(1, 5)
                    ctx.lineTo(9, 5)
                } else if (iconPath.includes("M6 18L18 6")) {
                    ctx.moveTo(2, 2)
                    ctx.lineTo(8, 8)
                    ctx.moveTo(8, 2)
                    ctx.lineTo(2, 8)
                } else {
                    ctx.rect(2, 2, 6, 6)
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
