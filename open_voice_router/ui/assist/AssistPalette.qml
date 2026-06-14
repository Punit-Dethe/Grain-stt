// AssistPalette.qml — the centered summon bar for Grain Assist.
// Appears on the global hotkey with focus already in the input.
// Decoupled window: lives in its own engine, driven by assistViewModel.
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Window {
    id: paletteWindow

    // ── Theme (beige / mechanical, matching the console + website) ─────
    readonly property color surface: "#E8E1D4"
    readonly property color surfaceRecess: "#DDD5C8"
    readonly property color inputBg: "#F2ECE1"
    readonly property color ink: "#141312"
    readonly property color orange: "#FF5D1E"
    readonly property color errorRed: "#C0392F"
    // Ink-tinted alpha (text/borders) — dark ink on the light surface.
    function inkA(a) { return Qt.rgba(0.078, 0.075, 0.071, a) }

    width: 620
    height: 122
    x: Math.round((Screen.width - width) / 2)
    y: Math.round(Screen.height * 0.32)
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

    visible: (typeof assistViewModel !== "undefined" && assistViewModel)
             ? assistViewModel.palette_visible : false

    onVisibleChanged: {
        if (visible) {
            instructionInput.text = ""
            instructionInput.forceActiveFocus()
        }
    }

    Connections {
        target: (typeof assistViewModel !== "undefined" && assistViewModel) ? assistViewModel : null
        function onFocus_input_requested() {
            paletteWindow.requestActivate()
            instructionInput.forceActiveFocus()
        }
    }

    // ── Body ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: 14
        color: surface
        border.color: inkA(0.18)
        border.width: 1

        // Inner top highlight — the machined-panel look.
        Rectangle {
            anchors { fill: parent; margins: 1 }
            radius: 13
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.45)
            border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 7

            // Header: title + selection chip
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle { width: 7; height: 7; radius: 3.5; color: orange }

                Text {
                    text: "GRAIN ASSIST"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.6
                    color: inkA(0.55)
                }

                Item { Layout.fillWidth: true }

                // Selection chip
                Rectangle {
                    visible: assistViewModel.selection_char_count > 0
                    height: 20
                    width: selChipText.implicitWidth + 16
                    radius: 10
                    color: surfaceRecess
                    border.color: inkA(0.12)
                    border.width: 1
                    Text {
                        id: selChipText
                        anchors.centerIn: parent
                        text: "SELECTION · " + assistViewModel.selection_char_count + " CHARS"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 0.8
                        color: inkA(0.55)
                    }
                }
                Text {
                    visible: assistViewModel.selection_char_count === 0
                    text: "NO SELECTION"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    font.letterSpacing: 0.8
                    color: inkA(0.35)
                }
            }

            // The input
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 10
                color: inputBg
                border.color: instructionInput.activeFocus ? ink : inkA(0.15)
                border.width: instructionInput.activeFocus ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 120 } }

                TextField {
                    id: instructionInput
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 14
                    color: ink
                    placeholderText: assistViewModel.recording
                        ? "Listening… speak then press ↵, or start typing"
                        : (assistViewModel.selection_char_count > 0
                            ? "What should I do with the selection? — summarize, make polite, convert to email…"
                            : "Ask anything…")
                    placeholderTextColor: inkA(0.35)
                    background: null
                    selectByMouse: true
                    // Typing immediately abandons voice capture — the user
                    // chose to type, so kill the recording and focus on text.
                    onTextEdited: {
                        if (assistViewModel.recording) assistViewModel.stop_recording()
                        if (assistViewModel.error_text) assistViewModel.clear_error()
                    }
                    // Enter submits: typed text wins, otherwise the backend
                    // transcribes the in-progress voice recording.
                    onAccepted: assistViewModel.submit_instruction(text)
                    Keys.onEscapePressed: assistViewModel.hide_palette()
                }
            }

            // Footer: recording grid (bottom-left) + error/hints + key cues
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // ── Bottom-left: recording wave grid  OR  Speak button ──────
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.max(recRipple.width, speakBtn.width)
                    Layout.preferredHeight: 22

                    // Recording indicator — 4 × 12 dot grid, four corners removed.
                    // A ruler-wave animation: bright crests radiate outward from the
                    // centre left AND right simultaneously. Horizontal cosine bell
                    // fades the edges to zero; vertical Gaussian dims the top/bottom
                    // rows. Unlit cells (wave trough) are fully transparent.
                    Item {
                        id: recRipple
                        anchors.verticalCenter: parent.verticalCenter
                        visible: assistViewModel.recording
                        readonly property int rows: 4
                        readonly property int cols: 12
                        readonly property int cellSize: 4
                        readonly property int gap: 2
                        width:  cols * cellSize + (cols - 1) * gap   // 70 px
                        height: rows * cellSize + (rows - 1) * gap   // 22 px

                        // Phase angle drives the outward wave; one full cycle ≈ 2 s.
                        property real angle: 0.0
                        NumberAnimation on angle {
                            from: 0.0; to: 2 * Math.PI
                            duration: 2000
                            loops: Animation.Infinite
                            running: assistViewModel.recording
                        }

                        Grid {
                            anchors.fill: parent
                            columns: recRipple.cols
                            rowSpacing: recRipple.gap
                            columnSpacing: recRipple.gap
                            Repeater {
                                model: recRipple.rows * recRipple.cols
                                Rectangle {
                                    readonly property int _r: Math.floor(index / recRipple.cols)
                                    readonly property int _c: index % recRipple.cols
                                    readonly property bool _corner:
                                        (_r === 0 || _r === recRipple.rows - 1) &&
                                        (_c === 0 || _c === recRipple.cols - 1)
                                    width: recRipple.cellSize
                                    height: recRipple.cellSize
                                    radius: width / 2
                                    visible: !_corner
                                    color: "#FF5D1E"
                                    // Each dot gets a unique phase from prime-spaced offsets
                                    // so they sparkle independently. Negative half of the sine
                                    // cycle = fully transparent (no background tint).
                                    opacity: Math.max(0, Math.sin(
                                        recRipple.angle * 2.1 + _c * 1.37 + _r * 3.11))
                                }
                            }
                        }
                    }

                    // Speak button — lets the user (re)start voice after typing.
                    Rectangle {
                        id: speakBtn
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !assistViewModel.recording
                                 && assistViewModel.voice_available
                                 && !assistViewModel.busy
                        width: _speakRow.implicitWidth + 18
                        height: 22
                        radius: 11
                        color: _speakHover.hovered ? inkA(0.10) : inkA(0.05)
                        border.color: inkA(0.18); border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: _speakRow
                            anchors.centerIn: parent
                            spacing: 5
                            // Small mic glyph drawn with two rounded rects.
                            Item {
                                width: 8; height: 12; anchors.verticalCenter: parent.verticalCenter
                                Rectangle { width: 5; height: 8; radius: 2.5; color: ink
                                            anchors.horizontalCenter: parent.horizontalCenter; y: 0 }
                                Rectangle { width: 1.5; height: 3; color: ink
                                            anchors.horizontalCenter: parent.horizontalCenter; y: 8 }
                                Rectangle { width: 6; height: 1.5; radius: 0.75; color: ink
                                            anchors.horizontalCenter: parent.horizontalCenter; y: 11 }
                            }
                            Text {
                                text: "SPEAK"
                                font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true
                                font.letterSpacing: 1; color: ink
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        HoverHandler { id: _speakHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Clear typed text so the voice path takes over.
                                instructionInput.text = ""
                                assistViewModel.start_recording()
                            }
                        }
                    }
                }

                Text {
                    visible: assistViewModel.error_text.length > 0
                    text: assistViewModel.error_text
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    color: errorRed
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    visible: assistViewModel.error_text.length === 0
                    text: assistViewModel.busy
                          ? "Transcribing…"
                          : (assistViewModel.recording
                             ? "Recording — speak or type"
                             : (assistViewModel.selection_preview.length > 0
                                ? "“" + assistViewModel.selection_preview + "…”" : ""))
                    font.pixelSize: 9
                    font.italic: !assistViewModel.busy && !assistViewModel.recording
                    color: assistViewModel.recording || assistViewModel.busy ? orange : inkA(0.35)
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: "↵ SEND"
                    font.family: "JetBrains Mono"; font.pixelSize: 8
                    font.letterSpacing: 1; color: inkA(0.4)
                }
                Text {
                    text: "ESC CLOSE"
                    font.family: "JetBrains Mono"; font.pixelSize: 8
                    font.letterSpacing: 1; color: inkA(0.4)
                }
            }
        }
    }
}
