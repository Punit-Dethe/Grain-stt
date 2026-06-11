// LocalLogsContent.qml - Terminal Logs Display
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Item {
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color textDark: "#141312"
    readonly property color brandOrange: "#FF5D1E"
    readonly property color brandGreen: "#10B981"
    
    property bool serverRunning: true
    

    // Simulated log generator
    Timer {
        id: logTimer
        interval: 3000
        running: parent.visible
        repeat: true
        
        property var logMessages: [
            { type: "info", text: "[ROUTING] Keybinding triggered! Streaming audio buffers to Parakeet." },
            { type: "success", text: "[ENGINE] Audio block decoded successfully. Duration: 3.4 seconds." },
            { type: "info", text: "[TRANSCRIPTION] Complete // Result: 'Configure this app locally.'" },
            { type: "info", text: "[CLIENT] Automatically updated system clipboard." }
        ]
        
        onTriggered: {
            if (serverRunning && Math.random() < 0.45) {
                var msg = logMessages[Math.floor(Math.random() * logMessages.length)]
                var time = Qt.formatTime(new Date(), "hh:mm:ss")
                logsModel.append({
                    "timestamp": time,
                    "type": msg.type,
                    "message": msg.text
                })
                
                // Keep max 35 logs
                if (logsModel.count > 35) {
                    logsModel.remove(0)
                }
                
                // Auto-scroll to bottom
                logsList.positionViewAtEnd()
            }
        }
    }
    
    ListModel {
        id: logsModel
        
        Component.onCompleted: {
            append({ timestamp: "00:10:41", type: "info", message: "[DAEMON] Initializing localized grain core..." })
            append({ timestamp: "00:10:42", type: "success", message: "[SYSTEM] NVIDIA CUDA environment detected." })
            append({ timestamp: "00:10:42", type: "info", message: "[DAEMON] Allocated 1.25 GB CUDA VRAM for tensor attention." })
            append({ timestamp: "00:10:44", type: "success", message: "[SYSTEM] Parakeet network weights loaded and checksum validated." })
        }
    }
    
    RowLayout {
        anchors.fill: parent
        spacing: 16
        
        // Left: Server Control (2/5 width)
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.4
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                
                Text {
                    text: "Daemon Status"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.4
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                }
                
                // Server Toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Text {
                        text: "STT Server"
                        font.pixelSize: 13
                        font.bold: true
                        color: textDark
                        Layout.fillWidth: true
                    }
                    
                    // Mechanical Toggle Switch
                    Rectangle {
                        width: 32
                        height: 18
                        radius: 99
                        color: "#1c1a18"
                        
                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            x: serverRunning ? 16 : 2
                            y: 2
                            
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: serverRunning ? brandOrange : "#ECE5DA" }
                                GradientStop { position: 1.0; color: serverRunning ? brandOrange : "#c3bcaf" }
                            }
                            
                            Behavior on x {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                serverRunning = !serverRunning
                                var time = Qt.formatTime(new Date(), "hh:mm:ss")
                                if (serverRunning) {
                                    logsModel.append({
                                        timestamp: time,
                                        type: "success",
                                        message: "[DAEMON] STT Core rebooted. Armed."
                                    })
                                } else {
                                    logsModel.append({
                                        timestamp: time,
                                        type: "error",
                                        message: "[DAEMON] SIGINT command received. Offline."
                                    })
                                }
                                logsList.positionViewAtEnd()
                            }
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
                
                // Copy Config Path Button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: copyButtonHover.containsMouse ? "#000000" : textDark
                    

                    
                    Behavior on color { ColorAnimation { duration: 200 } }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Copy Config Path"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.4
                        color: surfaceRecess
                    }
                    
                    HoverHandler {
                        id: copyButtonHover
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            console.log("Copy config path to clipboard")
                        }
                    }
                }
            }
        }
        
        // Right: Terminal Display (3/5 width)
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.6
            radius: 12
            color: "#000000"
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            
            // Top gradient overlay
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height * 0.3
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            
            ScrollView {
                anchors.fill: parent
                anchors.margins: 16
                clip: true
                
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                
                ListView {
                    id: logsList
                    model: logsModel
                    spacing: 6
                    
                    delegate: Text {
                        width: ListView.view.width
                        text: "[INFO] " + model.timestamp + " - " + model.message
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                        
                        color: {
                            if (model.type === "success") return brandGreen
                            if (model.type === "error") return "#EF4444"
                            return Qt.rgba(1, 1, 1, 0.4)
                        }
                    }
                }
            }
        }
    }
}
