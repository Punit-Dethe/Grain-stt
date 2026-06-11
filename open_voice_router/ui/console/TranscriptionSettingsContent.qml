// TranscriptionSettingsContent.qml - STT Configuration Card Content
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Item {
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color textDark: "#141312"
    readonly property color brandOrange: "#FF5D1E"
    readonly property color brandGreen: "#10B981"

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // Column 1: Local Model Management
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.33
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Section Header
                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "Local Models"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.4
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 1; color: Qt.rgba(0.078, 0.075, 0.071, 0.1)
                    }
                }

                // Real-time Toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: "Real-time Transcription"
                        font.pixelSize: 11
                        font.bold: true
                        color: textDark
                        Layout.fillWidth: true
                    }
                    MechanicalToggle { checked: true }
                }

                // Auto-unload Slider
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: "Auto-unload after inactivity"
                        font.pixelSize: 10
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Slider {
                            id: unloadSlider
                            from: 0
                            to: 60
                            value: 15
                            Layout.fillWidth: true
                        }
                        Text {
                            text: Math.round(unloadSlider.value) + " min"
                            font.pixelSize: 10
                            font.bold: true
                            color: textDark
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // Models List
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: parent.width
                        spacing: 8

                        // Model Item: Installed
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 8
                            color: Qt.rgba(0,0,0,0.05)
                            border.color: Qt.rgba(0,0,0,0.1)
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: "Parakeet FP16"; font.pixelSize: 11; font.bold: true; color: textDark }
                                    Text { text: "Installed • 1.2 GB"; font.pixelSize: 9; color: brandGreen }
                                }
                                Rectangle {
                                    width: 60; height: 24; radius: 4; color: "transparent"; border.color: "#EF4444"; border.width: 1
                                    Text { anchors.centerIn: parent; text: "Uninstall"; font.pixelSize: 9; font.bold: true; color: "#EF4444" }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }

                        // Model Item: Available
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 8
                            color: Qt.rgba(0,0,0,0.02)
                            border.color: Qt.rgba(0,0,0,0.08)
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: "Whisper Medium"; font.pixelSize: 11; font.bold: true; color: textDark }
                                    Text { text: "Available • 1.5 GB"; font.pixelSize: 9; color: Qt.rgba(0.078, 0.075, 0.071, 0.6) }
                                }
                                Rectangle {
                                    width: 60; height: 24; radius: 4; color: brandOrange
                                    Text { anchors.centerIn: parent; text: "Install"; font.pixelSize: 9; font.bold: true; color: "white" }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }

                        // Coming Soon Info
                        Text {
                            text: "More lightweight local models coming soon."
                            font.pixelSize: 9
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                            font.italic: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8
                        }
                    }
                }
            }
        }

        // Column 2: Cloud Endpoints
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.33
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Section Header
                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "Cloud Endpoints"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.4
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0.078, 0.075, 0.071, 0.1) }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: parent.width
                        spacing: 16

                        // Form to add new
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: "Add New API Configuration"; font.pixelSize: 11; font.bold: true; color: textDark }

                            TextField {
                                id: newSttName
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                placeholderText: "Display Name (e.g. OpenAI Whisper)"
                                font.pixelSize: 10
                                background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            TextField {
                                id: newSttUrl
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                placeholderText: "Endpoint URL"
                                font.pixelSize: 10
                                background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            TextField {
                                id: newSttModel
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                placeholderText: "Model Name (e.g. whisper-1)"
                                font.pixelSize: 10
                                background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            TextField {
                                id: newSttKey
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                placeholderText: "API Key"
                                echoMode: TextInput.Password
                                font.pixelSize: 10
                                background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignRight
                                width: 80; height: 26; radius: 4; color: brandOrange
                                Text { anchors.centerIn: parent; text: "Save API"; font.pixelSize: 10; font.bold: true; color: "white" }
                                MouseArea {
                                    anchors.fill: parent;
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
                                            consoleViewModel.add_provider("stt", newSttName.text, newSttUrl.text, newSttModel.text, newSttKey.text, -1, "")
                                            newSttName.text = ""
                                            newSttUrl.text = ""
                                            newSttModel.text = ""
                                            newSttKey.text = ""
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0,0,0,0.06) }

                        // Saved Endpoints List
                        Text { text: "Saved Endpoints"; font.pixelSize: 11; font.bold: true; color: textDark }

                        Repeater {
                            model: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.stt_providers : []

                            delegate: Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 6
                                color: Qt.rgba(0,0,0,0.03); border.color: Qt.rgba(0,0,0,0.08); border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: modelData.name; font.pixelSize: 11; font.bold: true; color: textDark }
                                        Text { text: modelData.base_url; font.pixelSize: 9; color: Qt.rgba(0.078, 0.075, 0.071, 0.6) }
                                    }
                                    Text {
                                        text: "Remove"; font.pixelSize: 10; font.bold: true; color: "#EF4444"
                                        MouseArea {
                                            anchors.fill: parent;
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
                                                    consoleViewModel.remove_provider(modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Column 3: Smart Rotation & Dictionary
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.33
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Smart Rotation
                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text { text: "Smart Provider Rotation"; font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4; color: Qt.rgba(0.078, 0.075, 0.071, 0.5) }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0.078, 0.075, 0.071, 0.1) }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Enable Auto-Fallback"; font.pixelSize: 11; font.bold: true; color: textDark; Layout.fillWidth: true }
                    MechanicalToggle { checked: true }
                }
                Text {
                    text: "Automatically cycles through your selected pool if an endpoint fails or limits are hit."
                    font.pixelSize: 9
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                // Rotation Pool
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 80; radius: 6
                    color: Qt.rgba(0,0,0,0.02); border.color: Qt.rgba(0,0,0,0.08); border.width: 1
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8; spacing: 4
                        Text { text: "Rotation Priority Pool:"; font.pixelSize: 10; font.bold: true; color: textDark }
                        Text { text: "1. Parakeet FP16 (Local)\n2. Deepgram API (Cloud)"; font.pixelSize: 10; color: Qt.rgba(0.078, 0.075, 0.071, 0.8) }
                    }
                }

                Item { Layout.preferredHeight: 12 }

                // Custom Dictionary
                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text { text: "Custom Dictionary"; font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4; color: Qt.rgba(0.078, 0.075, 0.071, 0.5) }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0.078, 0.075, 0.071, 0.1) }
                }

                Text {
                    text: "Add unique jargon or names to help the STT engine recognize them."
                    font.pixelSize: 9
                    color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                TextArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: "e.g. Antigravity, Parakeet, STT, Eurorack\n(Comma separated list)"
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    background: Rectangle { radius: 6; color: Qt.rgba(0,0,0,0.03); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.08); border.width: 1 }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    width: 100; height: 26; radius: 4; color: brandOrange
                    Text { anchors.centerIn: parent; text: "Save Dictionary"; font.pixelSize: 10; font.bold: true; color: "white" }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                }
            }
        }
    }
}
