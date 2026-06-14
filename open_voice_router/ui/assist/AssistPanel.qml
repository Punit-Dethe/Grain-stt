// AssistPanel.qml — the right-side reply/chat panel for Grain Assist.
// Shows the LLM conversation, one-shortcut copy of the latest reply, and a
// follow-up input at the bottom. Decoupled window driven by assistViewModel.
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Window {
    id: panelWindow

    // ── Theme (beige / mechanical, matching the console + website) ─────
    readonly property color surface: "#E8E1D4"
    readonly property color surfaceRecess: "#DDD5C8"  // user-message bubble
    readonly property color inputBg: "#F2ECE1"        // input well
    readonly property color ink: "#141312"
    readonly property color orange: "#FF5D1E"
    readonly property color green: "#10B981"
    readonly property color errorRed: "#C0392F"
    function inkA(a) { return Qt.rgba(0.078, 0.075, 0.071, a) }

    // Standardized footprint: fixed width, a bit less than display height.
    width: 500
    height: Math.min(Screen.desktopAvailableHeight - 72, 880)
    x: Screen.desktopAvailableWidth - width - 18
    y: Math.round((Screen.desktopAvailableHeight - height) / 2)
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

    visible: (typeof assistViewModel !== "undefined" && assistViewModel)
             ? assistViewModel.panel_visible : false

    onVisibleChanged: if (visible) followupInput.forceActiveFocus()

    // Esc (close) and Ctrl+Shift+C (copy) are GLOBAL hotkeys registered by
    // the backend while the panel is visible — they work even when another
    // application has keyboard focus. Replies are also auto-copied to the
    // clipboard on arrival; flash the COPIED state so the user knows.
    Connections {
        target: (typeof assistViewModel !== "undefined" && assistViewModel) ? assistViewModel : null
        function onMessages_changed() {
            if (assistViewModel.last_reply.length > 0 && !assistViewModel.busy)
                copyFlash.restart()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: surface
        border.color: inkA(0.18)
        border.width: 1

        Rectangle {
            anchors { fill: parent; margins: 1 }
            radius: 13
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.45)
            border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 10

            // ── Header (draggable) ─────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        color: assistViewModel.busy ? orange : green
                        SequentialAnimation on opacity {
                            running: assistViewModel.busy
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 420 }
                            NumberAnimation { to: 1.0; duration: 420 }
                        }
                        opacity: 1.0
                    }

                    Text {
                        text: "GRAIN ASSIST"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.6
                        color: inkA(0.55)
                    }

                    Text {
                        text: assistViewModel.busy ? "· PROCESSING" : ""
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        color: orange
                    }

                    Item { Layout.fillWidth: true }

                    // Close button
                    Rectangle {
                        width: 22; height: 22; radius: 6
                        color: closeHover.hovered ? inkA(0.08) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "×"; font.pixelSize: 15; color: inkA(0.55)
                        }
                        HoverHandler { id: closeHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: assistViewModel.dismiss()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.rightMargin: 30  // keep the close button clickable
                    onPressed: panelWindow.startSystemMove()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: inkA(0.12) }

            // ── Conversation ───────────────────────────────────────────
            ListView {
                id: chatList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 24
                model: assistViewModel.chat_messages
                boundsBehavior: Flickable.StopAtBounds

                onCountChanged: Qt.callLater(function() { chatList.positionViewAtEnd() })

                ScrollBar.vertical: ScrollBar { width: 6 }

                delegate: ColumnLayout {
                    id: msgDelegate
                    width: chatList.width - 10
                    spacing: 4
                    readonly property bool isUser: modelData.role === "user"

                    Text {
                        text: msgDelegate.isUser ? "YOU" : "GRAIN"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.4
                        color: msgDelegate.isUser ? inkA(0.4) : orange
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: msgText.implicitHeight
                                                + (msgDelegate.isUser ? 28 : 8)
                        radius: msgDelegate.isUser ? 10 : 0
                        color: msgDelegate.isUser ? surfaceRecess : "transparent"
                        border.color: msgDelegate.isUser ? inkA(0.10) : "transparent"
                        border.width: msgDelegate.isUser ? 1 : 0

                        TextEdit {
                            id: msgText
                            anchors {
                                fill: parent
                                leftMargin: 14
                                rightMargin: 14
                                topMargin: msgDelegate.isUser ? 14 : 12
                                bottomMargin: msgDelegate.isUser ? 14 : 12
                            }
                            text: modelData.text
                            textFormat: msgDelegate.isUser
                                        ? TextEdit.PlainText
                                        : TextEdit.MarkdownText
                            font.pixelSize: 15
                            color: ink
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                            selectionColor: orange
                            selectedTextColor: "white"
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            Component.onCompleted: {
                                if (!msgDelegate.isUser)
                                    textDocument.textDocument.defaultStyleSheet =
                                        "body { line-height: 1.6; } " +
                                        "p { margin: 0 0 10px 0; } " +
                                        "h1, h2, h3 { margin: 12px 0 4px 0; } " +
                                        "li { margin-bottom: 4px; } " +
                                        "code { background-color: rgba(0,0,0,0.07); padding: 1px 4px; border-radius: 3px; }"
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor
                                                                : Qt.IBeamCursor
                            }
                        }
                    }
                }
            }

            // Inline error (request failures live here, above the input)
            Text {
                visible: assistViewModel.error_text.length > 0
                text: assistViewModel.error_text
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                color: errorRed
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: inkA(0.12) }

            // ── Copy row ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: assistViewModel.last_reply.length > 0

                Rectangle {
                    id: copyBtn
                    width: 110; height: 30; radius: 8
                    color: copyFlash.running ? green
                         : (copyHover.hovered ? inkA(0.75) : ink)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: copyFlash.running ? "COPIED ✓" : "COPY REPLY"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.8
                        color: "white"
                    }
                    HoverHandler { id: copyHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { assistViewModel.copy_reply(); copyFlash.restart() }
                    }
                    PauseAnimation { id: copyFlash; duration: 1600 }
                }

                Text {
                    text: copyFlash.running ? "AUTO-COPIED · READY TO PASTE" : "CTRL+SHIFT+C COPIES"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    font.letterSpacing: 1
                    color: copyFlash.running ? green : inkA(0.4)
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "ESC CLOSE"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    font.letterSpacing: 1
                    color: inkA(0.35)
                }
            }

            // ── Follow-up input ────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 10
                color: inputBg
                border.color: followupInput.activeFocus ? ink : inkA(0.15)
                border.width: followupInput.activeFocus ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 6

                    TextField {
                        id: followupInput
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 12
                        color: ink
                        enabled: !assistViewModel.busy
                        placeholderText: assistViewModel.busy ? "Waiting for reply…" : "Follow up…"
                        placeholderTextColor: inkA(0.35)
                        background: null
                        selectByMouse: true
                        onTextEdited: if (assistViewModel.error_text) assistViewModel.clear_error()
                        onAccepted: {
                            if (text.trim().length > 0 && !assistViewModel.busy) {
                                assistViewModel.submit_followup(text)
                                text = ""
                            }
                        }
                    }

                    Rectangle {
                        width: 30; height: 30; radius: 8
                        color: sendHover.hovered && !assistViewModel.busy
                               ? inkA(0.75)
                               : (assistViewModel.busy ? inkA(0.1) : ink)
                        Text {
                            anchors.centerIn: parent
                            text: "↵"; font.pixelSize: 13; font.bold: true
                            color: assistViewModel.busy ? inkA(0.3) : "white"
                        }
                        HoverHandler { id: sendHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !assistViewModel.busy
                            onClicked: {
                                if (followupInput.text.trim().length > 0) {
                                    assistViewModel.submit_followup(followupInput.text)
                                    followupInput.text = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
