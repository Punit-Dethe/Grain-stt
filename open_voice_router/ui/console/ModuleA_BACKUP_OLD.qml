// ModuleA.qml — Configuration Module
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    
    property bool squished: false
    
    radius: 22
    color: "#141312"  // Dark charcoal module background
    border.color: Qt.rgba(1.000, 1.000, 1.000, 0.06)
    border.width: 1

    // Dark metal grain texture overlay
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        opacity: 0.03
        color: "transparent"
        
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = "#ffffff"
                for (var x = 0; x < width; x += 4) {
                    for (var y = 0; y < height; y += 4) {
                        if ((x + y) % 8 === 0) {
                            ctx.fillRect(x, y, 1, 1)
                        }
                    }
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

        // Module Header
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.leftMargin: 6
            Layout.rightMargin: 6

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    text: "MODULE A"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 2
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }

                Text {
                    text: "CONFIGURATION"
                    font.family: "Syne"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#ECE5DA"
                }
            }
        }

        // Travertine Pocket (main content area with light background)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            Layout.bottomMargin: 4
            radius: 14
            color: "#DDD5C8"  // Light travertine pocket
            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 0

                // Hotkey Cards
                ColumnLayout {
                    id: hotkeySection
                    Layout.fillWidth: true
                    spacing: 6
                    
                    clip: true
                    
                    Text {
                        text: "ACTIVE SYSTEM HOTKEYS"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.letterSpacing: 1.2
                        color: Qt.rgba(1.000, 1.000, 1.000, 0.35)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        // Dictation hotkey
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 6
                            color: Qt.rgba(0.000, 0.000, 0.000, 0.4)
                            border.color: Qt.rgba(1.000, 1.000, 1.000, 0.05)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                Text {
                                    text: "Dictation"
                                    font.pixelSize: 9
                                    color: Qt.rgba(1.000, 1.000, 1.000, 0.6)
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: typeof consoleViewModel !== "undefined" ? consoleViewModel.hotkey : "ctrl+shift+space"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: "#ff5d1e"
                                }
                            }
                        }

                        // Voice-to-AI hotkey
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 6
                            color: Qt.rgba(0.000, 0.000, 0.000, 0.4)
                            border.color: Qt.rgba(1.000, 1.000, 1.000, 0.05)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                Text {
                                    text: "Voice-to-AI"
                                    font.pixelSize: 9
                                    color: Qt.rgba(1.000, 1.000, 1.000, 0.6)
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: typeof consoleViewModel !== "undefined" ? consoleViewModel.hotkey_ai : "ctrl+shift+enter"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: "#10B981"
                                }
                            }
                        }
                    }

                    states: [
                        State {
                            name: "squished"
                            when: root.squished
                            PropertyChanges { target: hotkeySection; Layout.preferredHeight: 0; opacity: 0 }
                        },
                        State {
                            name: "normal"
                            when: !root.squished
                            PropertyChanges { target: hotkeySection; Layout.preferredHeight: -1; opacity: 1 }
                        }
                    ]

                    transitions: [
                        Transition {
                            NumberAnimation { properties: "Layout.preferredHeight,opacity"; duration: 380; easing.type: Easing.OutCubic }
                        }
                    ]
                }

                Item { Layout.preferredHeight: 8 }

                // Microphone Selector
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "MIC INPUT TARGET"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.letterSpacing: 0.5
                        color: Qt.rgba(1.000, 1.000, 1.000, 0.45)
                    }

                    ComboBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        
                        model: ["System Default"]
                        
                        background: Rectangle {
                            radius: 6
                            color: "#1e1c1a"
                            border.color: Qt.rgba(1.000, 1.000, 1.000, 0.05)
                            border.width: 1
                        }

                        contentItem: Text {
                            leftPadding: 8
                            text: parent.displayText
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            color: Qt.rgba(1.000, 1.000, 1.000, 0.8)
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // Sensitivity Dial
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    radius: 8
                    color: Qt.rgba(0.102, 0.094, 0.086, 0.4)
                    border.color: Qt.rgba(1.000, 1.000, 1.000, 0.02)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Mic Sensitivity"
                                font.pixelSize: 10
                                font.bold: true
                                color: Qt.rgba(1.000, 1.000, 1.000, 0.85)
                            }

                            Text {
                                text: "Gain calibration index"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 8
                                color: Qt.rgba(1.000, 1.000, 1.000, 0.45)
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
                                color: Qt.rgba(1.000, 1.000, 1.000, 0.7)
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

                Item { Layout.fillHeight: true }

                // Launch on Boot Toggle
                Rectangle {
                    id: bootToggleSection
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    color: "transparent"
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 8
                        color: "transparent"
                        
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.rgba(1.000, 1.000, 1.000, 0.04)
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
                                    color: Qt.rgba(1.000, 1.000, 1.000, 0.85)
                                }

                                Text {
                                    text: "Daemon loads instantly"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 8
                                    color: Qt.rgba(1.000, 1.000, 1.000, 0.35)
                                }
                            }

                            MechanicalToggle {
                                id: bootToggle
                            }
                        }
                    }

                    states: [
                        State {
                            name: "squished"
                            when: root.squished
                            PropertyChanges { target: bootToggleSection; Layout.preferredHeight: 0; opacity: 0 }
                        },
                        State {
                            name: "normal"
                            when: !root.squished
                            PropertyChanges { target: bootToggleSection; Layout.preferredHeight: 42; opacity: 1 }
                        }
                    ]

                    transitions: [
                        Transition {
                            NumberAnimation { properties: "Layout.preferredHeight,opacity"; duration: 380; easing.type: Easing.OutCubic }
                        }
                    ]
                }

                // Jack Output
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    color: "transparent"
                    
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Qt.rgba(1.000, 1.000, 1.000, 0.04)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: 4

                        Text {
                            text: "SIGNAL OUTPUT"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 8
                            font.letterSpacing: 0.5
                            color: Qt.rgba(1.000, 1.000, 1.000, 0.4)
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 80
                            height: 26
                            radius: 8
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#2a2825" }
                                GradientStop { position: 1.0; color: "#121110" }
                            }
                            border.color: Qt.rgba(1.000, 1.000, 1.000, 0.05)
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: "OUTPUT"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 8
                                    font.bold: true
                                    font.letterSpacing: 1
                                    color: "#ff5d1e"
                                }

                                Jack {
                                    jackColor: "#FF5D1E"
                                }
                            }
                        }
                    }
                }
            }
        }

        // Module Footer
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            Layout.leftMargin: 6
            Layout.rightMargin: 6

            RowLayout {
                anchors.fill: parent

                Text {
                    text: "HARDWARE: ARMED"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.094, 0.090, 0.086, 0.6)
                    Layout.fillWidth: true
                }

                Text {
                    text: "TYPE: CONTROL"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.094, 0.090, 0.086, 0.6)
                }
            }
        }
    }
}
