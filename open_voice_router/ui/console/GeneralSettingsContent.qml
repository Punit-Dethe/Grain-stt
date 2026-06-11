// GeneralSettingsContent.qml - System Parameters Card Content
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Item {
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color textDark: "#141312"
    readonly property color brandOrange: "#FF5D1E"
    
    RowLayout {
        anchors.fill: parent
        spacing: 16
        
        // Left: Application Behavior (1/2 width)
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.5
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                
                // Section Header
                ColumnLayout {
                    spacing: 4
                    
                    Text {
                        text: "Application Behavior"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.4
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.1)
                    }
                }
                
                // Toggle 1: Launch on Boot
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Launch on Boot"
                            font.pixelSize: 13
                            font.bold: true
                            color: textDark
                        }
                        
                        Text {
                            text: "Start daemon automatically on system startup"
                            font.pixelSize: 10
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        }
                    }
                    
                    MechanicalToggle {
                        checked: true
                    }
                }
                
                // Toggle 2: Launch Minimized
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Launch Minimized"
                            font.pixelSize: 13
                            font.bold: true
                            color: textDark
                        }
                        
                        Text {
                            text: "Hide main window and run in system tray"
                            font.pixelSize: 10
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        }
                    }
                    
                    MechanicalToggle {
                        checked: false
                    }
                }
                
                // Toggle 3: Play UI Sounds
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Interface Sounds"
                            font.pixelSize: 13
                            font.bold: true
                            color: textDark
                        }
                        
                        Text {
                            text: "Play audio cues for transcription states"
                            font.pixelSize: 10
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        }
                    }
                    
                    MechanicalToggle {
                        checked: true
                    }
                }
                
                Item { Layout.fillHeight: true }
                
                // Footer Note
                Text {
                    text: "System configurations apply globally"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                    Layout.alignment: Qt.AlignLeft
                }
            }
        }
        
        // Right: Custom Keys mapping (1/2 width)
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.5
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                
                // Section Header
                ColumnLayout {
                    spacing: 4
                    
                    Text {
                        text: "Custom Keys mapping"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.4
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.1)
                    }
                }
                
                // Hotkey 1: Dictation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Dictation Shortcut"
                            font.pixelSize: 13
                            font.bold: true
                            color: textDark
                        }
                        
                        Text {
                            text: "Trigger raw microphone transcribing"
                            font.pixelSize: 10
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        }
                    }
                    
                    Rectangle {
                        width: 144
                        height: 36
                        radius: 5
                        color: Qt.rgba(0, 0, 0, 0.1)
                        border.color: hotkeyHover1.containsMouse ? brandOrange : Qt.rgba(0, 0, 0, 0.1)
                        border.width: 1
                        
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                        
                        TextInput {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            horizontalAlignment: TextInput.AlignHCenter
                            text: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.hotkey : "ctrl+shift+space"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            font.bold: true
                            color: textDark
                            selectByMouse: true
                            
                            onEditingFinished: {
                                if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
                                    consoleViewModel.save_hotkey(text)
                                }
                            }
                        }
                        
                        HoverHandler {
                            id: hotkeyHover1
                        }
                    }
                }
                
                // Hotkey 2: Voice-to-AI
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Voice-to-AI Shortcut"
                            font.pixelSize: 13
                            font.bold: true
                            color: textDark
                        }
                        
                        Text {
                            text: "Process and style with active LLMs"
                            font.pixelSize: 10
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        }
                    }
                    
                    Rectangle {
                        width: 144
                        height: 36
                        radius: 5
                        color: Qt.rgba(0, 0, 0, 0.1)
                        border.color: hotkeyHover2.containsMouse ? brandOrange : Qt.rgba(0, 0, 0, 0.1)
                        border.width: 1
                        
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                        
                        TextInput {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            horizontalAlignment: TextInput.AlignHCenter
                            text: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.hotkey_ai : "ctrl+shift+enter"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            font.bold: true
                            color: textDark
                            selectByMouse: true

                            onEditingFinished: {
                                if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
                                    consoleViewModel.save_hotkey_ai(text)
                                }
                            }
                        }
                        
                        HoverHandler {
                            id: hotkeyHover2
                        }
                    }
                }

                // Hotkey 3: Grain Assist
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Grain Assist Shortcut"
                            font.pixelSize: 13
                            font.bold: true
                            color: textDark
                        }
                        
                        Text {
                            text: "Invoke AI assistant with smart suggestions"
                            font.pixelSize: 10
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                        }
                    }
                    
                    Rectangle {
                        width: 144
                        height: 36
                        radius: 5
                        color: Qt.rgba(0, 0, 0, 0.1)
                        border.color: hotkeyHover3.containsMouse ? brandOrange : Qt.rgba(0, 0, 0, 0.1)
                        border.width: 1
                        
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                        
                        Text {
                            anchors.centerIn: parent
                            text: "ctrl + shift + g"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            font.bold: true
                            color: textDark
                        }
                        
                        HoverHandler {
                            id: hotkeyHover3
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                console.log("Record grain assist hotkey")
                            }
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
                
                // Footer Note
                Text {
                    text: "Active daemon listens system-wide"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                    Layout.alignment: Qt.AlignLeft
                }
            }
        }
    }
}
