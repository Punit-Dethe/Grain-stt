// ModuleB.qml — Transcription Module (PIXEL-PERFECT REDESIGN)
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
                    text: "Module B"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 2
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }

                Text {
                    text: "Transcription"
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

                // ── Orange LED Matrix Display Panel ────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Aura Core Monitor"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Qt.rgba(0.078, 0.075, 0.071, 0.45)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 76
                        radius: 8
                        color: "#120500"
                        border.color: Qt.rgba(1.000, 0.365, 0.118, 0.25)
                        border.width: 1

                        DotMatrixDisplay {
                            anchors.fill: parent
                            anchors.margins: 4
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── Model Choice Configurations ─────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: "Model Route"
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

                            // Inner shadow
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: parent.radius - 2
                                color: "transparent"
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Rectangle {
                                    id: localSttBtn
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: sttLocalMode ? "#FF5D1E" : "transparent"
                                    
                                    property bool sttLocalMode: true

                                    Text {
                                        anchors.centerIn: parent
                                        text: "LCL"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 8.5
                                        font.bold: true
                                        color: localSttBtn.sttLocalMode ? "#ffffff" : Qt.rgba(0.078, 0.075, 0.071, 0.5)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: localSttBtn.sttLocalMode = true
                                    }

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: !localSttBtn.sttLocalMode ? "#FF5D1E" : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "CLD"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 8.5
                                        font.bold: true
                                        color: !localSttBtn.sttLocalMode ? "#ffffff" : Qt.rgba(0.078, 0.075, 0.071, 0.5)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: localSttBtn.sttLocalMode = false
                                    }

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }
                    }

                    // Model Selector Dropdown
                    ComboBox {
                        id: sttModelSelector
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        
                        model: localSttBtn.sttLocalMode ? 
                            ["Parakeet 0.6B (TDT)", "Whisper Base (Q4)", "Whisper Tiny (FP16)"] :
                            ["OpenAI Whisper-1", "Groq Whisper Large v3", "Deepgram Nova-2"]
                        
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
                                model: sttModelSelector.popup.visible ? sttModelSelector.delegateModel : null
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }

                        delegate: ItemDelegate {
                            width: sttModelSelector.width - 8
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
                                color: parent.highlighted ? Qt.rgba(1.000, 0.365, 0.118, 0.15) : "transparent"
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 4 }

                // ── Input/Output Jacks ──────────────────────────────────
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
                                    jackColor: "#FF5D1E"
                                }

                                Text {
                                    text: "INPUT"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 8
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: "#FF5D1E"
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // OUTPUT Jack with pulsing ring
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
                                    color: "#10B981"
                                }

                                Jack {
                                    jackColor: "#10B981"
                                    activeSink: true
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
                    text: "MODEL: PARAKEET"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                    Layout.fillWidth: true
                }

                Text {
                    text: "TYPE: AUDIO-STT"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    color: Qt.rgba(0.925, 0.898, 0.855, 0.4)
                }
            }
        }
    }
}
