// ModuleC.qml — Processing Module (PIXEL-PERFECT REDESIGN)
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
                    text: "Module C"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 2
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }

                Text {
                    text: "Processing"
                    font.family: "Syne"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#ECE5DA"
                }
            }
        }

        // ── Travertine Pocket ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            Layout.bottomMargin: 4
            radius: 14
            color: "#DDD5C8"
            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.06)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 0

                // ── Prompt Style Selection ──────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Styling Prompt Preset"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.bold: true
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
                    }

                    ComboBox {
                        id: promptSelector
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        
                        model: ["Casual Conversational Prose", "Clean Markdown Code Block", "Executive Bullet-Point Outline"]
                        
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
                                model: promptSelector.popup.visible ? promptSelector.delegateModel : null
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }

                        delegate: ItemDelegate {
                            width: promptSelector.width - 8
                            height: 32

                            contentItem: Text {
                                text: modelData
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: "#141312"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                radius: 4
                                color: parent.highlighted ? Qt.rgba(0.545, 0.361, 0.965, 0.15) : "transparent"
                            }
                        }

                        onCurrentIndexChanged: {
                            if (currentIndex === 0) {
                                promptPreviewText.text = "Format transcription outputs to naturally match a quick, friendly, human tone. Strip excess space and placeholder stutters."
                            } else if (currentIndex === 1) {
                                promptPreviewText.text = "Convert technical words to clean code snippets. Wrap formatting targets in markdown tags properly."
                            } else {
                                promptPreviewText.text = "Summarize output blocks directly into brief bullet lines. Focus on concrete tasks and action targets first."
                            }
                        }
                    }

                    // Prompt Preview
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 8
                        color: Qt.rgba(0.000, 0.000, 0.000, 0.04)
                        border.color: Qt.rgba(0.000, 0.000, 0.000, 0.04)
                        border.width: 1

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded

                            Text {
                                id: promptPreviewText
                                width: parent.width
                                text: "Format transcription outputs to naturally match a quick, friendly, human tone. Strip excess space and placeholder stutters."
                                font.family: "JetBrains Mono"
                                font.pixelSize: 8
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.6)
                                wrapMode: Text.WordWrap
                                lineHeight: 1.4
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── Model Cloud/Local Choices ───────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: "Processor LLM"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 8
                            font.bold: true
                            color: Qt.rgba(0.078, 0.075, 0.071, 0.5)
                            Layout.fillWidth: true
                        }

                        // LCL/CLD Segmented Toggle
                        Rectangle {
                            width: 68
                            height: 22
                            radius: 8
                            color: Qt.rgba(0.000, 0.000, 0.000, 0.1)
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.05)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Rectangle {
                                    id: localLlmBtn
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: llmLocalMode ? "#8B5CF6" : "transparent"
                                    
                                    property bool llmLocalMode: true

                                    Text {
                                        anchors.centerIn: parent
                                        text: "LCL"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 8.5
                                        font.bold: true
                                        color: localLlmBtn.llmLocalMode ? "#ffffff" : Qt.rgba(0.078, 0.075, 0.071, 0.5)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: localLlmBtn.llmLocalMode = true
                                    }

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: !localLlmBtn.llmLocalMode ? "#8B5CF6" : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "CLD"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 8.5
                                        font.bold: true
                                        color: !localLlmBtn.llmLocalMode ? "#ffffff" : Qt.rgba(0.078, 0.075, 0.071, 0.5)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: localLlmBtn.llmLocalMode = false
                                    }

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }
                    }

                    // Model Selector Dropdown
                    ComboBox {
                        id: llmModelSelector
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        
                        model: localLlmBtn.llmLocalMode ? 
                            ["Llama 3 (Local Q4)", "Mistral 7B (Instruct)", "Phi-3 Mini (Local)"] :
                            ["GPT-4o (Standard)", "Claude 3.5 Sonnet", "Gemini 1 Pro"]
                        
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
                            font.pixelSize: 9
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
                                model: llmModelSelector.popup.visible ? llmModelSelector.delegateModel : null
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }

                        delegate: ItemDelegate {
                            width: llmModelSelector.width - 8
                            height: 28

                            contentItem: Text {
                                text: modelData
                                font.family: "JetBrains Mono"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                color: "#141312"
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 4
                                color: parent.highlighted ? Qt.rgba(0.545, 0.361, 0.965, 0.15) : "transparent"
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 4 }

                // ── Sockets for LLM Route Processing ────────────────────
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
                        spacing: 4

                        // INPUT Jack
                        Rectangle {
                            width: 75
                            height: 22
                            radius: 8
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#e5decb" }
                                GradientStop { position: 1.0; color: "#c7bca7" }
                            }
                            border.color: Qt.rgba(0.000, 0.000, 0.000, 0.1)
                            border.width: 1

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
                                spacing: 6

                                Jack {
                                    jackColor: "#10B981"
                                }

                                Text {
                                    text: "INPUT"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 8
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: "#10B981"
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // OUTPUT Jack
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
                                spacing: 6

                                Text {
                                    text: "OUTPUT"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 8
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: "#8B5CF6"
                                }

                                Jack {
                                    jackColor: "#8B5CF6"
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
                    text: "CACHE: ACTIVE_RAM"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                    Layout.fillWidth: true
                }

                Text {
                    text: "TYPE: CHAT-LLM"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }
            }
        }
    }
}
