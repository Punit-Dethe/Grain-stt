// ProcessingSettingsContent.qml - Processing Configuration Card Content
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Item {
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color textDark: "#141312"
    readonly property color brandOrange: "#FF5D1E"

    // Internal state
    property var promptsList: typeof consoleViewModel !== `"undefined`" && consoleViewModel ? consoleViewModel.prompts : []
    property int selectedPromptIndex: 0

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // Left Column: LLM Endpoints & Rotation
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.4
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
                    Text { text: "LLM Endpoints & Rotation"; font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4; color: Qt.rgba(0.078, 0.075, 0.071, 0.5) }
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

                                                // Add new LLM endpoint
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: "Configure New Provider"; font.pixelSize: 11; font.bold: true; color: textDark }

                            TextField {
                                id: newLlmName
                                Layout.fillWidth: true; Layout.preferredHeight: 28; placeholderText: "Display Name (e.g. GPT-4 Turbo)"
                                font.pixelSize: 10; background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            TextField {
                                id: newLlmUrl
                                Layout.fillWidth: true; Layout.preferredHeight: 28; placeholderText: "Base URL (e.g. https://api.openai.com/v1)"
                                font.pixelSize: 10; background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            TextField {
                                id: newLlmModel
                                Layout.fillWidth: true; Layout.preferredHeight: 28; placeholderText: "Model (e.g. gpt-4-turbo)"
                                font.pixelSize: 10; background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            TextField {
                                id: newLlmKey
                                Layout.fillWidth: true; Layout.preferredHeight: 28; placeholderText: "API Key"
                                echoMode: TextInput.Password
                                font.pixelSize: 10; background: Rectangle { radius: 4; color: Qt.rgba(0,0,0,0.05); border.color: parent.activeFocus ? brandOrange : Qt.rgba(0,0,0,0.1) }
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignRight
                                width: 80; height: 26; radius: 4; color: brandOrange
                                Text { anchors.centerIn: parent; text: "Save LLM"; font.pixelSize: 10; font.bold: true; color: "white" }
                                MouseArea {
                                    anchors.fill: parent;
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
                                            consoleViewModel.add_provider("llm", newLlmName.text, newLlmUrl.text, newLlmModel.text, newLlmKey.text, -1, "")
                                            newLlmName.text = ""
                                            newLlmUrl.text = ""
                                            newLlmModel.text = ""
                                            newLlmKey.text = ""
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0,0,0,0.06) }

                        // Smart Provider Rotation for LLMs
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Smart Provider Rotation"; font.pixelSize: 11; font.bold: true; color: textDark; Layout.fillWidth: true }
                                MechanicalToggle { checked: true }
                            }
                            Text {
                                text: "Automatically fallback to the next LLM if one is rate-limited."
                                font.pixelSize: 9; color: Qt.rgba(0.078, 0.075, 0.071, 0.6); Layout.fillWidth: true; wrapMode: Text.WordWrap
                            }

                                                        // Rotation Pool Config
                            Text { text: "Saved Endpoints"; font.pixelSize: 11; font.bold: true; color: textDark }

                            Repeater {
                                model: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.llm_providers : []

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
        }

        // Right Column: Prompts Library
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredWidth: parent.width * 0.6
            radius: 12
            color: surfaceRecess
            border.color: Qt.rgba(0, 0, 0, 0.06)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Section Header
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 4; Layout.fillWidth: true
                        Text { text: "Prompt Library"; font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4; color: Qt.rgba(0.078, 0.075, 0.071, 0.5) }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0.078, 0.075, 0.071, 0.1) }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16

                    // Prompts List
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 160
                        color: Qt.rgba(0, 0, 0, 0.02)
                        border.color: Qt.rgba(0, 0, 0, 0.08)
                        border.width: 1
                        radius: 8

                        ScrollView {
                            anchors.fill: parent
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            ColumnLayout {
                                width: parent.width
                                spacing: 4
                                anchors.margins: 4

                                Repeater {
                                    model: promptsList

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 32
                                        radius: 4
                                        color: modelData.is_active ? brandOrange : (promptHover.containsMouse ? Qt.rgba(0, 0, 0, 0.05) : "transparent")

                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            verticalAlignment: Text.AlignVCenter
                                            text: modelData.name
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: modelData.is_active ? "white" : textDark
                                            elide: Text.ElideRight
                                        }

                                        HoverHandler { id: promptHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if(consoleViewModel) consoleViewModel.set_active_prompt(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Prompt Editor
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        TextField {
                            id: promptNameField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            text: { var activeP = promptsList.find(function(p) { return p.is_active === true; }); return activeP ? activeP.name : ""; }
                            font.pixelSize: 12
                            font.bold: true
                            color: textDark
                            background: Rectangle {
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.04)
                                border.color: parent.activeFocus ? brandOrange : "transparent"
                                border.width: 1
                            }
                        }

                        TextArea {
                            id: promptTextArea
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: { var activeP = promptsList.find(function(p) { return p.is_active === true; }); return activeP ? activeP.text : ""; }
                            font.pixelSize: 11
                            color: textDark
                            wrapMode: Text.Wrap
                            background: Rectangle {
                                radius: 8
                                color: Qt.rgba(0, 0, 0, 0.02)
                                border.color: parent.activeFocus ? brandOrange : Qt.rgba(0, 0, 0, 0.08)
                                border.width: 1
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true } // spacer

                            Rectangle {
                                width: 90
                                height: 32
                                radius: 6
                                color: brandOrange

                                Text {
                                    anchors.centerIn: parent
                                    text: "Save Prompt"
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: "white"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        if (!vm) return
                                        var activeP = promptsList.find(function(p) { return p.is_active === true })
                                        if (activeP) vm.update_prompt(activeP.id, promptNameField.text, promptTextArea.text)
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
