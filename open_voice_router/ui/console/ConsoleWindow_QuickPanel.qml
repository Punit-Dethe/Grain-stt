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
    height: 630
    minimumWidth: 980
    minimumHeight: 630
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: true

    readonly property int cornerRadius: 36

    // ── Color Palette ───────────────────────────────────────────────────────
    readonly property color bgDark: "#0c0b0a"
    readonly property color bgWindow: "#0c0b0a"
    readonly property color surfaceTravertine: "#ECE5DA"
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color surfaceCharcoal: "#141312"
    readonly property color textDark: "#141312"
    readonly property color textLight: "#ECE5DA"
    readonly property color textMuted: Qt.rgba(0.925, 0.898, 0.855, 0.4)
    readonly property color brandOrange: "#FF5D1E"
    readonly property color brandGreen: "#10B981"
    readonly property color brandPurple: "#8B5CF6"

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
            
            // Radial gradient overlay
            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                gradient: Gradient {
                    orientation: Gradient.Radial
                    GradientStop { position: 0.0; color: Qt.rgba(0.925, 0.898, 0.855, 0.15) }
                    GradientStop { position: 0.65; color: "transparent" }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // QUICK LOOK PANEL
        // ═══════════════════════════════════════════════════════════════════
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 0

            // ── HEADER BAR ──────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                // Bottom border
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
                                onClicked: {
                                    console.log("Advanced Calibration clicked - to be implemented")
                                }
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

                        // Inner shadow hint
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.radius - 2
                            color: "transparent"
                        }

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

            // ── MODULE RACK VIEWPORT ───────────────────────────────────────
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

            // ── BOTTOM STATUS BAR ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                spacing: 0

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
                        hoverEnabled: true
                        
                        onEntered: parent.color = root.brandOrange
                        onExited: parent.color = Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        
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
                        font.pixelSize: 9.5
                        font.bold: true
                        font.letterSpacing: 1.5
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
                    }

                    Text {
                        text: "STANDBY // MOUNT PATCH LINES"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9.5
                        font.bold: true
                        font.letterSpacing: 1
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.8)
                    }
                }
            }

            Item { Layout.preferredHeight: 4 }
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

        width: 10
        height: 10

        Canvas {
            id: iconCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = iconHover.containsMouse ? root.brandOrange : Qt.rgba(0.078, 0.075, 0.071, 0.55)
                ctx.lineWidth: 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

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
