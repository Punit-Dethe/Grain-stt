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
                border.color: instructionInput.activeFocus ? orange : inkA(0.15)
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
                    Layout.preferredWidth: Math.max(recGrid.width, speakBtn.width)
                    Layout.preferredHeight: 22

                    // 3 rows × 6 cols black "pixel" grid. Two soft diagonal
                    // waves sweep bottom-left → top-right; a cell's opacity is
                    // its brightness under the nearest wave (smooth, faded
                    // edges), so it reads as two travelling bands of pixels.
                    Item {
                        id: recGrid
                        anchors.verticalCenter: parent.verticalCenter
                        visible: assistViewModel.recording
                        readonly property int cols: 6
                        readonly property int rows: 3
                        readonly property int cellSize: 5
                        readonly property int gap: 2
                        width: cols * cellSize + (cols - 1) * gap
                        height: rows * cellSize + (rows - 1) * gap

                        // Animated phase (0..1, looping) drives both waves.
                        property real phase: 0.0
                        NumberAnimation on phase {
                            from: 0.0; to: 1.0
                            duration: 1500
                            loops: Animation.Infinite
                            running: assistViewModel.recording
                        }
                        // Diagonal extent: d = col + (rows-1 - row) ranges 0..(cols-1)+(rows-1).
                        readonly property int maxD: (cols - 1) + (rows - 1)
                        readonly property real waveWidth: 1.7
                        // Brightness at diagonal coord d from TWO waves half a
                        // phase apart, each sweeping the full diagonal with a
                        // little margin so they enter/exit off-grid.
                        function brightnessFor(d) {
                            var span = maxD + 2 * waveWidth
                            var b = 0.0
                            for (var k = 0; k < 2; k++) {
                                var p = ((phase + k * 0.5) % 1.0) * span - waveWidth
                                var dist = Math.abs(d - p)
                                b = Math.max(b, Math.max(0.0, 1.0 - dist / waveWidth))
                            }
                            return b
                        }

                        Grid {
                            anchors.fill: parent
                            columns: recGrid.cols
                            rowSpacing: recGrid.gap
                            columnSpacing: recGrid.gap
                            Repeater {
                                model: recGrid.cols * recGrid.rows
                                Rectangle {
                                    width: recGrid.cellSize
                                    height: recGrid.cellSize
                                    radius: 1.5
                                    color: "#141312"   // black pixels
                                    // d for this cell (bottom-left → top-right).
                                    readonly property int _row: Math.floor(index / recGrid.cols)
                                    readonly property int _col: index % recGrid.cols
                                    readonly property int _d: _col + (recGrid.rows - 1 - _row)
                                    // Faint floor + smooth wave crest.
                                    opacity: 0.08 + recGrid.brightnessFor(_d) * 0.82
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
                        color: _speakHover.containsMouse ? inkA(0.10) : inkA(0.05)
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
