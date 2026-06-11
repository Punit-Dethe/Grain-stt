// ConfigurationPanel.qml — Tablet drawer configuration panel
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    spacing: 16

    // Hotkey Bindings Section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: hotkeyCol.implicitHeight + 32
        radius: 12
        color: "#DDD5C8"
        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
        border.width: 1

        ColumnLayout {
            id: hotkeyCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Text {
                text: "DEVICE KEY BINDINGS"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2
                color: "#ff5d1e"
            }

            // Dictation Hotkey
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "DICTATION SHORTCUT (KEY COMBINATION)"
                    font.pixelSize: 10
                    font.bold: true
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                }

                TextField {
                    id: dictationField
                    Layout.fillWidth: true
                    height: 36
                    text: typeof consoleViewModel !== "undefined" ? consoleViewModel.hotkey : "ctrl+shift+space"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    color: "#141312"
                    
                    background: Rectangle {
                        radius: 8
                        color: "#ECE5DA"
                        border.color: dictationField.activeFocus ? "#ff5d1e" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                        border.width: 1
                        
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Keys.onReturnPressed: {
                        if (typeof consoleViewModel !== "undefined") {
                            consoleViewModel.save_hotkey(text)
                        }
                    }
                }
            }

            // Voice-to-AI Hotkey
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "VOICE-TO-AI SHORTCUT (KEY COMBINATION)"
                    font.pixelSize: 10
                    font.bold: true
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                }

                TextField {
                    id: voiceAiField
                    Layout.fillWidth: true
                    height: 36
                    text: typeof consoleViewModel !== "undefined" ? consoleViewModel.hotkey_ai : "ctrl+shift+enter"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    color: "#141312"
                    
                    background: Rectangle {
                        radius: 8
                        color: "#ECE5DA"
                        border.color: voiceAiField.activeFocus ? "#ff5d1e" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                        border.width: 1
                        
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Keys.onReturnPressed: {
                        if (typeof consoleViewModel !== "undefined") {
                            consoleViewModel.save_hotkey_ai(text)
                        }
                    }
                }
            }
        }
    }

    // Boot Parameters Section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: bootCol.implicitHeight + 32
        radius: 12
        color: "#DDD5C8"
        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
        border.width: 1

        ColumnLayout {
            id: bootCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "BOOT PARAMETERS"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2
                color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
            }

            // Launch on Startup
            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Launch On Startup"
                        font.pixelSize: 12
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.8)
                    }

                    Text {
                        text: "Start daemon with local OS"
                        font.pixelSize: 9
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                }

                MechanicalToggle {
                    id: startupToggle
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
            }

            // Unload Model on Idle
            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Unload Model on Idle"
                        font.pixelSize: 12
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.8)
                    }

                    Text {
                        text: "Release GPU memory after 5m of inactivity"
                        font.pixelSize: 9
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                }

                MechanicalToggle {
                    id: unloadToggle
                    checked: true
                }
            }
        }
    }
}
