// ModuleA.qml — Configuration Module
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects

Rectangle {
    id: root
    property alias outputJack: signalOutputJack
    // Shared light/dark palette, injected by ConsoleWindow.
    property var theme

    radius: 22
    color: theme.cardOuter
    border.color: theme.cardOuterBorder
    border.width: 1



                ColumnLayout {
        anchors.fill: parent
        anchors.margins: 9
        anchors.topMargin: 15
        anchors.bottomMargin: 9
        spacing: 0

        // ── Module Header ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Layout.leftMargin: 6
            Layout.rightMargin: 6

            ColumnLayout {
                anchors.fill: parent
                spacing: 2

                Text { text: "MODULE A"; font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 2; color: theme.inkOnOuter(0.4) }
                Text { text: "Configuration"; font.family: "Syne"; font.pixelSize: 17; font.weight: Font.ExtraBold; font.capitalization: Font.AllUppercase; font.letterSpacing: -0.3; color: theme.cardOuterTitle }
            }
        }

        // ── Travertine Pocket ──────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 9
            Layout.bottomMargin: 5
            Layout.leftMargin: 3
            Layout.rightMargin: 3
            radius: 14
            color: theme.cardInner
            border.color: theme.cardInnerBorder
            border.width: 1

            // Simulated Inner Shadow
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 10
                radius: 14
                gradient: Gradient {
                    GradientStop { position: 0.0; color: theme.cardInnerTopShade }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                anchors.bottomMargin: 0
                spacing: 0

                // ── SYSTEM HOTKEYS ──────────────────────────────────────
                Text {
                    text: "SYSTEM HOTKEYS"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.5
                    color: theme.ink(0.4)
                    Layout.bottomMargin: 8
                }

                // Dictation hotkey row
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 6
                    color: theme.fill(0.03)
                    border.color: theme.fill(0.06)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 0

                        Text { text: "Dictation"; font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.ink(0.85); Layout.fillWidth: true }

                        Row {
                            spacing: 3
                            Repeater {
                                model: {
                                    var hk = (typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.hotkey)
                                             ? consoleViewModel.hotkey : "Ctrl+Shift+Space"
                                    return hk.split("+")
                                }
                                delegate: Rectangle {
                                    height: 26; width: _kt.implicitWidth + 14; radius: 4
                                    color: theme.ink(0.07)
                                    border.color: theme.ink(0.18); border.width: 1
                                    Rectangle {
                                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 2; radius: 4
                                        color: theme.fill(0.10)
                                    }
                                    Text {
                                        id: _kt
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                        color: theme.ink(0.72)
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 4 }

                // Voice-to-AI hotkey row
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 6
                    color: theme.fill(0.03)
                    border.color: theme.fill(0.06)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 0

                        Text { text: "Voice-to-AI"; font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.ink(0.85); Layout.fillWidth: true }

                        Row {
                            spacing: 3
                            Repeater {
                                model: {
                                    var hk = (typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.hotkey_ai)
                                             ? consoleViewModel.hotkey_ai : "Ctrl+Shift+Enter"
                                    return hk.split("+")
                                }
                                delegate: Rectangle {
                                    height: 26; width: _kt2.implicitWidth + 14; radius: 4
                                    color: theme.ink(0.07)
                                    border.color: theme.ink(0.18); border.width: 1
                                    Rectangle {
                                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 2; radius: 4
                                        color: theme.fill(0.10)
                                    }
                                    Text {
                                        id: _kt2
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                        color: theme.ink(0.72)
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 4 }

                // Assist hotkey row
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 6
                    color: theme.fill(0.03)
                    border.color: theme.fill(0.06)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 0

                        Text { text: "Assist"; font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.ink(0.85); Layout.fillWidth: true }

                        Row {
                            spacing: 3
                            Repeater {
                                model: {
                                    var hk = (typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.hotkey_grain)
                                             ? consoleViewModel.hotkey_grain : "Ctrl+Shift+G"
                                    return hk.split("+")
                                }
                                delegate: Rectangle {
                                    height: 26; width: _kt3.implicitWidth + 14; radius: 4
                                    color: theme.ink(0.07)
                                    border.color: theme.ink(0.18); border.width: 1
                                    Rectangle {
                                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: 2; radius: 4
                                        color: theme.fill(0.10)
                                    }
                                    Text {
                                        id: _kt3
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                        color: theme.ink(0.72)
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 20 }

                // ── AUDIO SETTINGS ──────────────────────────────────────
                Text {
                    text: "AUDIO SETTINGS"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
                    color: theme.ink(0.4)
                    Layout.bottomMargin: 6
                }

                ComboBox {
                    id: micSelector
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    model: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                           ? consoleViewModel.available_microphones
                           : ["System Default"]
                    currentIndex: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                  ? consoleViewModel.microphone_combo_index : 0
                    onActivated: function(idx) {
                        if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                            consoleViewModel.save_microphone_by_index(idx)
                    }

                    background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }

                    contentItem: Text {
                        leftPadding: 10; rightPadding: 30
                        text: micSelector.displayText
                        font.pixelSize: 11; font.weight: Font.DemiBold
                        color: theme.inputText; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                    }

                    indicator: Text {
                        x: micSelector.width - width - 10
                        y: Math.round((micSelector.height - height) / 2)
                        text: "▾"; font.pixelSize: 10; color: theme.inputText
                    }

                    popup: Popup {
                        y: micSelector.height + 2
                        width: micSelector.width
                        padding: 4
                        background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.min(contentHeight, 180)
                            model: micSelector.count
                            currentIndex: micSelector.currentIndex
                            ScrollIndicator.vertical: ScrollIndicator {}
                            delegate: ItemDelegate {
                                width: ListView.view ? ListView.view.width : 0
                                height: 32
                                contentItem: Text {
                                    text: micSelector.textAt(index)
                                    font.pixelSize: 11; font.weight: Font.DemiBold
                                    color: theme.inputText; verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle {
                                    radius: 4
                                    color: index === micSelector.currentIndex
                                           ? Qt.rgba(1.0, 0.365, 0.118, 0.15)
                                           : "transparent"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        micSelector.currentIndex = index
                                        micSelector.activated(index)
                                        micSelector.popup.close()
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── SIDE-BY-SIDE SETTINGS (Sensitivity + Processing) ─────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Mic Sensitivity Box
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: 8
                        color: theme.fill(0.04)
                        border.color: theme.fill(0.05)
                        border.width: 1

                        Item {
                            anchors.fill: parent
                            anchors.margins: 12

                            // Left side text
                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text { text: "Mic Sensitivity"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                Text { text: "Gain calibration"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                            }

                            // Right side dial + %
                            ColumnLayout {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Rectangle {
                                    id: dialKnob
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 24; height: 24; radius: 12
                                    color: theme.dialKnob
                                    border.color: theme.fill(0.12); border.width: 1
                                    property real value: 45

                                    Rectangle {
                                        width: 3; height: 7; radius: 1.5; color: "#FF5D1E"
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top; anchors.topMargin: 2.5
                                        transform: Rotation { origin.x: 1.5; origin.y: -2.5; angle: (dialKnob.value / 100) * 260 - 130 }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.SizeVerCursor
                                        property real startY: 0; property real startVal: 0
                                        onPressed: { startY = mouseY; startVal = dialKnob.value }
                                        onPositionChanged: { dialKnob.value = Math.max(0, Math.min(100, startVal + (startY - mouseY) * 0.8)) }
                                    }
                                }

                                Text {
                                    id: sensitivityLabel
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Math.round(dialKnob.value) + "%"
                                    font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                    color: theme.ink(0.8)
                                }
                            }
                        }
                    }

                    // Process Audio Box
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: 8
                        color: theme.fill(0.04)
                        border.color: theme.fill(0.05)
                        border.width: 1

                        Item {
                            anchors.fill: parent
                            anchors.margins: 12

                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text { text: "Process Audio"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                Text { text: "Clear enhancement"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                            }

                            MechanicalToggle {
                                id: processAudioToggle
                                trackColor: theme.toggleTrack
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                         ? consoleViewModel.process_audio : true
                                onToggled: {
                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        consoleViewModel.save_process_audio(checked)
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 20 }

                // ── SYSTEM BEHAVIOUR ────────────────────────────────────
                Text {
                    text: "SYSTEM BEHAVIOUR"
                    font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
                    color: theme.ink(0.4)
                    Layout.bottomMargin: 6
                }




                // ── LAUNCH ON BOOT ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: theme.fill(0.04)
                    border.color: theme.fill(0.05)
                    border.width: 1

                    ColumnLayout {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { text: "Launch on Boot"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                        Text { text: "Autoload system daemon"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                    }

                    MechanicalToggle {
                        id: startupToggle
                        trackColor: theme.toggleTrack
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        checked: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                 ? consoleViewModel.launch_on_boot : false
                        onToggled: {
                            if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                consoleViewModel.save_launch_on_boot(checked)
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── PLAY SOUND ON START/STOP ─────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 8
                    color: theme.fill(0.04)
                    border.color: theme.fill(0.05)
                    border.width: 1

                    ColumnLayout {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { text: "Play Sound"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                        Text { text: "Audible dictation cues"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                    }

                    MechanicalToggle {
                        id: soundToggle
                        trackColor: theme.toggleTrack
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        checked: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                 ? consoleViewModel.play_sound : true
                        onToggled: {
                            if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                consoleViewModel.save_play_sound(checked)
                        }
                    }
                }

                // Gap above divider
                Item { Layout.preferredHeight: 10 }

                // Divider
                Rectangle { Layout.fillWidth: true; height: 1; color: theme.fill(0.10) }

                Item { Layout.preferredHeight: 8 }

                // ── SIGNAL OUTPUT JACK ──────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        spacing: 0

                        Text {
                            text: "SIGNAL OUTPUT"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true
                            font.letterSpacing: 1; color: theme.ink(0.4)
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 104; height: 46; radius: 8
                            gradient: Gradient { GradientStop { position: 0.0; color: theme.jackHousingTop } GradientStop { position: 1.0; color: theme.jackHousingBottom } }
                            border.color: theme.fill(0.1); border.width: 1

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
                                Text { text: "OUTPUT"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2; color: "#FF5D1E"; Layout.fillWidth: true }
                                Jack { id: signalOutputJack; jackColor: "#FF5D1E"; jackId: "moduleA.output"; size: 34 }
                            }
                        }
                    }
                }
            }
        }

        // ── Module Footer ──────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 18
            Layout.leftMargin: 6; Layout.rightMargin: 6

            RowLayout {
                anchors.fill: parent; spacing: 0
                Text { text: "HARDWARE: ARMED"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.inkOnOuter(0.4); Layout.fillWidth: true }
                Text { text: "TYPE: CONTROL"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.inkOnOuter(0.4) }
            }
        }
    }
}
