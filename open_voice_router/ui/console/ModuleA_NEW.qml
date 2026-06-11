// ModuleA.qml — Configuration Module (PIXEL-PERFECT REDESIGN)
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    
    radius: 22
    color: "#141312"  // Dark charcoal module background
    border.color: Qt.rgba(1.000, 1.000, 1.000, 0.06)
    border.width: 1

    // Dark metal grain texture overlay
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
        anchors.margins: 8
        anchors.topMargin: 12
        anchors.bottomMargin: 8
        spacing: 0

        // ── Module Header ───────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.leftMargin: 6
            Layout.rightMargin: 6

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    text: "Module A"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 2
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }

                Text {
                    text: "Configuration"
                    font.family: "Syne"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#ECE5DA"
                }
            }
        }

        // ── Travertine Pocket (Light Inner Well) ───────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            Layout.bottomMargin: 4
            radius: 14
            color: "#DDD5C8"  // Light travertine recess
            
            // Inset shadow effect
            layer.enabled: true
            layer.effect: ShaderEffect {
                fragmentShader: "
                    varying highp vec2 qt_TexCoord0;
                    uniform sampler2D source;
                    uniform lowp float qt_Opacity;
                    void main() {
                        lowp vec4 tex = texture2D(source, qt_TexCoord0);
                        gl_FragColor = tex * qt_Opacity;
                    }
                "
            }
            
            // Manual inset shadow with border
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
                border.width: 1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 0

                // ── Hotkeys Info Cards ──────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "System Hotkeys"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.letterSpacing: 1.2
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        // Dictation Hotkey Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 6
                            color: Qt.rgba(1.000, 1.000, 1.000, 0.45)
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 0

                                Text {
                                    text: "Dictation"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: Qt.rgba(0.078, 0.075, 0.071, 0.75)
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: typeof consoleViewModel !== "undefined" ? consoleViewModel.hotkey : "ctrl + shift + space"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: "#FF5D1E"
                                }
                            }
                        }

                        // Voice-to-AI Hotkey Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 6
                            color: Qt.rgba(1.000, 1.000, 1.000, 0.45)
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 0

                                Text {
                                    text: "Voice-to-AI"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: Qt.rgba(0.078, 0.075, 0.071, 0.75)
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: typeof consoleViewModel !== "undefined" ? consoleViewModel.hotkey_ai : "ctrl + shift + enter"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: "#10B981"
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }

                // ── Microphone Hardware Dropdown ────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Mic Input Target"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }

                    ComboBox {
                        id: micSelector
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        
                        model: ["Macbook Studio Mic Array", "Sennheiser Profile Core", "Focusrite Scarlett 2x2", "Virtual Audio Loopback"]
                        
                        background: Rectangle {
                            radius: 6
                            color: "#ECE5DA"
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.1)
                            border.width: 1
                        }

                        contentItem: Text {
                            leftPadding: 8
                            rightPadding: 28
                            text: parent.displayText
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#141312"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: Canvas {
                            x: parent.width - width - 8
                            y: parent.height / 2 - height / 2
                            width: 10
                            height: 6
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.moveTo(0, 0)
                                ctx.lineTo(width, 0)
                                ctx.lineTo(width / 2, height)
                                ctx.closePath()
                                ctx.fillStyle = "#141312"
                                ctx.fill()
                            }
                        }

                        popup: Popup {
                            y: parent.height + 2
                            width: parent.width
                            padding: 4

                            background: Rectangle {
                                radius: 6
                                color: "#ECE5DA"
                                border.color: Qt.rgba(0.000, 0.000, 0.000, 0.1)
                                border.width: 1
                            }

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: micSelector.popup.visible ? micSelector.delegateModel : null

                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }

                        delegate: ItemDelegate {
                            width: micSelector.width - 8
                            height: 32

                            contentItem: Text {
                                text: modelData
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: "#141312"
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 4
                                color: parent.highlighted ? Qt.rgba(1.000, 0.365, 0.118, 0.15) : "transparent"
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }

                // ── Rotary Sensitivity Calibration Dial ────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: Qt.rgba(0.000, 0.000, 0.000, 0.03)
                    border.color: Qt.rgba(0.000, 0.000, 0.000, 0.03)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Mic Sensitivity"
                                font.pixelSize: 10
                                font.bold: true
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.8)
                            }

                            Text {
                                text: "Gain calibration"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 8
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                            }
                        }

                        RowLayout {
                            spacing: 8

                            Text {
                                id: sensitivityLabel
                                text: "45%"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 9
                                font.bold: true
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.7)
                            }

                            KnurledDial {
                                id: sensitivityDial
                                size: 20
                                onDialValueChanged: {
                                    sensitivityLabel.text = Math.round(value * 100) + "%"
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 4 }

                // ── Launch Preferences Toggle ───────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    color: "transparent"

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Launch on Boot"
                                font.pixelSize: 10
                                font.bold: true
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.8)
                            }

                            Text {
                                text: "Autoload system daemon"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 8
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
                            }
                        }

                        MechanicalToggle {
                            id: startupToggle
                        }
                    }
                }

                // ── Output Signal Port Jack ─────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: "transparent"

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: 4
                        spacing: 0

                        Text {
                            text: "Signal Output"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 8
                            font.bold: true
                            font.letterSpacing: 0.5
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 90
                            height: 22
                            radius: 8
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#e5decb" }
                                GradientStop { position: 1.0; color: "#c7bca7" }
                            }
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.1)
                            border.width: 1

                            // Inner shadow effect
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: parent.radius - 1
                                color: "transparent"
                                border.color: Qt.rgba(0.000, 0.000, 0.000, 0.04)
                                border.width: 1
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: "OUTPUT"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 8
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: "#FF5D1E"
                                }

                                Jack {
                                    jackColor: "#FF5D1E"
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 2 }
            }
        }

        // ── Module Footer ───────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            Layout.leftMargin: 6
            Layout.rightMargin: 6

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    text: "HARDWARE: ARMED"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                    Layout.fillWidth: true
                }

                Text {
                    text: "TYPE: CONTROL"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }
            }
        }
    }
}
