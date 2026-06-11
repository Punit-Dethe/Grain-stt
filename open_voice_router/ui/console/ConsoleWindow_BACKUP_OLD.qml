// ConsoleWindow.qml — Modular Eurorack-inspired Console Interface
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Effects

ApplicationWindow {
    id: root
    title: "Grain Console"
    width: 1280
    height: 860
    minimumWidth: 980
    minimumHeight: 670
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: true

    readonly property int cornerRadius: 36

    // ── Color Palette (Modular Hardware Theme) ──────────────────────────────
    readonly property color bgDark: "#0c0b0a"
    readonly property color bgWindow: "#0c0b0a"  // Now using dark bg for main window
    readonly property color surfaceTravertine: "#ECE5DA"
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color surfaceCharcoal: "#141312"  // Dark module backgrounds
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

        // Main window background
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: root.bgWindow
            
            // Radial gradient overlay
            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.216, 0.157, 0.118, 0.15) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // ── Main Layout ─────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 0

            // ── HEADER BAR ──────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                RowLayout {
                    anchors.fill: parent
                    spacing: 16

                    // Left: Brand + Navigation
                    RowLayout {
                        spacing: 16
                        Layout.fillWidth: true

                        // Brand Button
                        Rectangle {
                            width: 160
                            height: 24
                            radius: 4
                            color: root.drawerOpen ? root.brandOrange : root.surfaceTravertine
                            
                            Text {
                                anchors.centerIn: parent
                                text: "GRAIN // QUICK PANEL"
                                font.family: "Syne"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1.2
                                color: root.drawerOpen ? root.textLight : root.textDark
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: closeDrawer()
                            }

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        // Module Navigation Buttons
                        RowLayout {
                            spacing: 4

                            NavButton {
                                text: "[ A: CONFIGURATION ]"
                                active: root.activeDrawerTab === "configuration"
                                onClicked: toggleDrawer("configuration")
                            }

                            NavButton {
                                text: "[ B: TRANSCRIPTION ]"
                                active: root.activeDrawerTab === "transcription"
                                onClicked: toggleDrawer("transcription")
                            }

                            NavButton {
                                text: "[ C: PROCESSING ]"
                                active: root.activeDrawerTab === "processing"
                                onClicked: toggleDrawer("processing")
                            }
                        }
                    }

                    // Right: Window Controls
                    Rectangle {
                        width: 100
                        height: 28
                        radius: 8
                        color: windowControlsHover.containsMouse ? Qt.rgba(1.000, 1.000, 1.000, 0.08) : Qt.rgba(1.000, 1.000, 1.000, 0.04)
                        border.color: Qt.rgba(1.000, 1.000, 1.000, 0.06)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 14

                            // Minimize
                            IconButton {
                                iconPath: "M20 12H4"
                                onClicked: root.showMinimized()
                            }

                            // Maximize/Restore
                            IconButton {
                                iconPath: root.visibility === Window.Maximized ? "M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3" : "M4 4h16v16H4z"
                                onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                            }

                            // Close
                            IconButton {
                                iconPath: "M6 18L18 6M6 6l12 12"
                                onClicked: Qt.quit()
                            }
                        }

                        HoverHandler { id: windowControlsHover }

                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                // Bottom border
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: root.borderSubtle
                }
            }

            Item { Layout.preferredHeight: 16 }

            // ── MODULAR CHASSIS (3 Modules) ─────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    spacing: 20

                    // Module A: Configuration
                    ModuleA {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        squished: root.drawerOpen
                    }

                    // Module B: Transcription
                    ModuleB {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        squished: root.drawerOpen
                    }

                    // Module C: Processing
                    ModuleC {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        squished: root.drawerOpen
                    }
                }
            }

            Item { Layout.preferredHeight: 16 }
        }

        // ── TABLET DRAWER OVERLAY ───────────────────────────────────────────
        Rectangle {
            id: tabletDrawer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.top: parent.top
            anchors.topMargin: 53
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.bottomMargin: 24

            radius: 24
            color: root.surfaceTravertine
            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.08)
            border.width: 1

            transform: Translate {
                id: drawerTransform
                y: root.height
            }

            visible: opacity > 0
            opacity: root.drawerOpen ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0

                // Drawer Content
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: tabletDrawer.width - 48
                        spacing: 16

                        // Configuration Panel
                        ConfigurationPanel {
                            Layout.fillWidth: true
                            visible: root.activeDrawerTab === "configuration"
                        }

                        // Transcription Panel
                        TranscriptionPanel {
                            Layout.fillWidth: true
                            visible: root.activeDrawerTab === "transcription"
                        }

                        // Processing Panel
                        ProcessingPanel {
                            Layout.fillWidth: true
                            visible: root.activeDrawerTab === "processing"
                        }
                    }
                }

                // Footer
                Item { Layout.preferredHeight: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                }

                Item { Layout.preferredHeight: 12 }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "DOCK LINK: SECURED"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "SYSTEM DAEMON OK"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                    }
                }
            }

            states: [
                State {
                    name: "open"
                    when: root.drawerOpen
                    PropertyChanges { target: drawerTransform; y: 0 }
                },
                State {
                    name: "closed"
                    when: !root.drawerOpen
                    PropertyChanges { target: drawerTransform; y: root.height }
                }
            ]
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

    // ── Functions ───────────────────────────────────────────────────────────
    function toggleDrawer(tab) {
        if (root.drawerOpen && root.activeDrawerTab === tab) {
            closeDrawer()
        } else {
            root.activeDrawerTab = tab
            root.drawerOpen = true
        }
    }

    function closeDrawer() {
        root.drawerOpen = false
        root.activeDrawerTab = ""
    }

    // ── Reusable Components ─────────────────────────────────────────────────
    
    // Navigation Button Component
    component NavButton: Rectangle {
        property string text
        property bool active: false
        signal clicked()

        width: textItem.width + 20
        height: 24
        radius: 4
        color: active ? Qt.rgba(1.000, 0.365, 0.118, 0.1) : "transparent"
        border.color: active ? Qt.rgba(1.000, 0.365, 0.118, 0.3) : Qt.rgba(1.000, 1.000, 1.000, 0.05)
        border.width: 1

        Text {
            id: textItem
            anchors.centerIn: parent
            text: parent.text
            font.family: "JetBrains Mono"
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 0.8
            color: parent.active ? root.brandOrange : root.textMuted
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
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
                ctx.strokeStyle = iconHover.containsMouse ? root.brandOrange : Qt.rgba(1.000, 1.000, 1.000, 0.4)
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                // Simple path rendering (you'd expand this for real icons)
                ctx.beginPath()
                if (iconPath.includes("M20 12H4")) {
                    // Minimize line
                    ctx.moveTo(1, 5)
                    ctx.lineTo(9, 5)
                } else if (iconPath.includes("M6 18L18 6")) {
                    // Close X
                    ctx.moveTo(2, 2)
                    ctx.lineTo(8, 8)
                    ctx.moveTo(8, 2)
                    ctx.lineTo(2, 8)
                } else {
                    // Maximize square
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
