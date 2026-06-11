// TranscriptionPanel.qml — Tablet drawer transcription panel
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    spacing: 16

    // Cloud STT Routing Section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: cloudSttCol.implicitHeight + 32
        radius: 12
        color: "#DDD5C8"
        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
        border.width: 1

        ColumnLayout {
            id: cloudSttCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "CUSTOM CLOUD STT ROUTING"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2
                color: "#ff5d1e"
            }

            // API Endpoint
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "OPENAI COMPATIBLE API ENDPOINT"
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
                        border.color: parent.activeFocus ? "#ff5d1e" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                        border.width: 1
                    }
                }
            }

            // Bearer Token
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "BEARER KEY TOKEN"
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
                        border.color: parent.activeFocus ? "#ff5d1e" : Qt.rgba(0.000, 0.000, 0.000, 0.08)
                        border.width: 1
                    }
                }
            }
        }
    }

    // Local STT Section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: localSttCol.implicitHeight + 32
        radius: 12
        color: "#DDD5C8"
        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
        border.width: 1

        ColumnLayout {
            id: localSttCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Local parakeet-tdt Offline weights"
                        font.pixelSize: 12
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.85)
                    }

                    Text {
                        text: "Optimized local transcription model"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                }

                Button {
                    text: "INSTALL"
                    height: 32
                    leftPadding: 16
                    rightPadding: 16
                    
                    background: Rectangle {
                        radius: 8
                        color: installHover.containsMouse ? Qt.darker("#ff5d1e", 1.1) : "#ff5d1e"
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    contentItem: Text {
                        text: parent.text
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    HoverHandler { id: installHover }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "Note: Provider management (add/edit/remove STT providers) is available in the original Settings window"
        font.pixelSize: 10
        font.italic: true
        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
        wrapMode: Text.WordWrap
    }
}
