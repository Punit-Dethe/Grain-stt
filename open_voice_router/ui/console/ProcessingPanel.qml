// ProcessingPanel.qml — Tablet drawer processing panel
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    spacing: 16

    // System Prompt Directives Section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: promptCol.implicitHeight + 32
        radius: 12
        color: "#DDD5C8"
        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
        border.width: 1

        ColumnLayout {
            id: promptCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "SYSTEM PROMPT DIRECTIVES TEMPLATE"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2
                color: "#8B5CF6"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "EDIT CASUAL CONVERSATIONAL DIRECTIVES"
                    font.pixelSize: 10
                    font.bold: true
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 128
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    TextArea {
                        width: parent.width
                        text: "Format transcription outputs to naturally match a quick, friendly, human tone. Strip excess space, placeholder stutters, and formal elements."
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.9)
                        wrapMode: Text.WordWrap
                        
                        background: Rectangle {
                            radius: 8
                            color: "#ECE5DA"
                            border.color: parent.activeFocus ? "#8B5CF6" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                            border.width: 1
                            
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                    }
                }
            }
        }
    }

    // Cloud LLM Routing Section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: cloudLlmCol.implicitHeight + 32
        radius: 12
        color: "#DDD5C8"
        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
        border.width: 1

        ColumnLayout {
            id: cloudLlmCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "CLOUD LLM ROUTING CREDENTIALS"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2
                color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
            }

            // Endpoint Host URL
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "ENDPOINT HOST URL"
                    font.pixelSize: 10
                    font.bold: true
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                }

                TextField {
                    Layout.fillWidth: true
                    height: 32
                    text: "https://api.openai.com/v1"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    color: "#141312"
                    
                    background: Rectangle {
                        radius: 8
                        color: "#ECE5DA"
                        border.color: parent.activeFocus ? "#8B5CF6" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                        border.width: 1
                    }
                }
            }

            // API Authorization Token
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "API AUTHORIZATION TOKEN"
                    font.pixelSize: 10
                    font.bold: true
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                }

                TextField {
                    Layout.fillWidth: true
                    height: 32
                    text: "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
                    echoMode: TextInput.Password
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    color: "#141312"
                    
                    background: Rectangle {
                        radius: 8
                        color: "#ECE5DA"
                        border.color: parent.activeFocus ? "#8B5CF6" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                        border.width: 1
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "Note: Full prompt and provider management is available in the original Settings window"
        font.pixelSize: 10
        font.italic: true
        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
        wrapMode: Text.WordWrap
    }
}
