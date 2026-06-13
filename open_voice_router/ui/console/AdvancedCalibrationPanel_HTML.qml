// AdvancedCalibrationPanel.qml — GRAIN // Settings Console
// Refined, cohesive interface — June 2026
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    anchors.fill: parent

    signal closeRequested()

    // ── DESIGN TOKENS ──────────────────────────────────────────────────────────
    readonly property color bgMain:       "#ECE5DA"   // travertine
    readonly property color bgSidebar:    "#DDD5C8"   // sidebar matches original
    readonly property color surfaceCard:  "#DDD5C8"   // card surface
    readonly property color surfaceInput: "#DDD5C8"   // input fields
    readonly property color charcoal:     "#141312"
    readonly property color textPrimary:  "#141312"
    readonly property color textMuted:    Qt.rgba(0.078, 0.075, 0.071, 0.5)
    readonly property color textGhost:    Qt.rgba(0.078, 0.075, 0.071, 0.35)
    readonly property color divider:      Qt.rgba(0, 0, 0, 0.07)
    readonly property color orange:       "#FF5D1E"
    readonly property color green:        "#10B981"
    readonly property color purple:       "#8B5CF6"

    // fixed width for right-aligned controls (toggles, combos, sliders, buttons)
    readonly property int controlColumnWidth: 176

    // accent for each tab
    readonly property var tabAccents: [orange, green, purple, green]

    property int activeTab: 0

    // ── BACKGROUND ─────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: bgMain }

    // ── ROOT ROW ────────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ════════════════════════════════════════════════
        //  SIDEBAR  (240px)
        // ════════════════════════════════════════════════
        Rectangle {
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: bgSidebar

            // subtle right border
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 1
                color: divider
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                anchors.topMargin: 28
                spacing: 0

                // ── Brand Mark ────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 6
                        color: charcoal

                        Text {
                            anchors.centerIn: parent
                            text: "GRAIN // ADVANCED"
                            font.family: "Syne"
                            font.pixelSize: 11
                            font.bold: false
                            font.letterSpacing: 2
                            color: "#ECE5DA"
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "SETTINGS CONSOLE"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.bold: false
                        font.letterSpacing: 2
                        color: textGhost
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Item { Layout.preferredHeight: 28 }

                // ── Section label ─────────────────────────────
                Text {
                    text: "NAVIGATION"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 8
                    font.bold: false
                    font.letterSpacing: 2
                    color: textGhost
                    leftPadding: 4
                }

                Item { Layout.preferredHeight: 10 }

                // ── Nav Tabs ──────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: [
                            { num: "01", label: "GENERAL",       icon: "⚙" },
                            { num: "02", label: "TRANSCRIPTION", icon: "🎙" },
                            { num: "03", label: "PROCESSING",    icon: "⚡" },
                            { num: "04", label: "TELEMETRY",     icon: "📡" }
                        ]

                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: 10
                            property bool active: index === root.activeTab

                            color: active
                                   ? Qt.rgba(orange.r, orange.g, orange.b, 0.12)
                                   : navHover.containsMouse ? Qt.rgba(0,0,0,0.03) : "transparent"

                            border.color: active ? Qt.rgba(orange.r, orange.g, orange.b, 0.4) : "transparent"
                            border.width: active ? 1 : 0

                            Behavior on color      { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: modelData.num
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: false
                                    color: active ? orange : textGhost
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }

                                Text {
                                    text: modelData.label
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    font.bold: false
                                    font.letterSpacing: 1.2
                                    color: active ? orange : textMuted
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }

                                // active pip
                                Rectangle {
                                    width: 5; height: 5; radius: 3
                                    color: orange
                                    opacity: active ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                }
                            }

                            HoverHandler { id: navHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = index
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // ── Close ─────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: 8
                    color: closeBtnHover.containsMouse
                           ? Qt.rgba(1, 0.365, 0.118, 0.1) : "transparent"
                    border.color: closeBtnHover.containsMouse
                           ? Qt.rgba(1, 0.365, 0.118, 0.3) : "transparent"
                    border.width: 1

                    Behavior on color       { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "[ CLOSE PANEL ]"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: false
                        font.letterSpacing: 1.5
                        color: orange
                    }

                    HoverHandler { id: closeBtnHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }

                Item { Layout.preferredHeight: 4 }
            }
        }

        // ════════════════════════════════════════════════
        //  CONTENT AREA
        // ════════════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: bgMain

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                anchors.bottomMargin: 20
                spacing: 0

                // ── Page Header ───────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // vertical accent bar
                    Rectangle {
                        width: 3; height: 36; radius: 2
                        color: orange
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Text {
                            text: ["Module Alpha", "Module Beta", "Module Gamma", "Module Delta"][root.activeTab]
                            font.family: "JetBrains Mono"
                            font.pixelSize: 9
                            font.bold: false
                            font.letterSpacing: 2.5
                            color: textGhost
                        }

                        Text {
                            text: ["System Parameters", "Transcription Arrays", "Processing Directives", "Mainframe Logs"][root.activeTab]
                            font.family: "Syne"
                            font.pixelSize: 20
                            font.bold: false
                            color: textPrimary
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Slot badge (right-aligned)
                    Rectangle {
                        width: 96; height: 26; radius: 6
                        color: Qt.rgba(0, 0, 0, 0.05)
                        border.color: divider; border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 7

                            Text {
                                text: ["SLOT_A","SLOT_B","SLOT_C","SLOT_D"][root.activeTab]
                                font.family: "JetBrains Mono"
                                font.pixelSize: 9
                                font.bold: false
                                color: textMuted
                            }

                            Rectangle {
                                width: 5; height: 5; radius: 3
                                color: orange
                            }
                        }
                    }
                }

                // divider
                Rectangle { Layout.fillWidth: true; height: 1; color: divider; Layout.topMargin: 16; Layout.bottomMargin: 20 }

                // ── Content Loader ────────────────────────────
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: [generalCard, transcriptionCard, processingCard, telemetryCard][root.activeTab]
                }

                // ── Status Footer ─────────────────────────────
                Rectangle { Layout.fillWidth: true; height: 1; color: divider; Layout.topMargin: 12; Layout.bottomMargin: 10 }

                RowLayout {
                    Layout.fillWidth: true

                    // left status
                    RowLayout {
                        spacing: 6
                        Rectangle { width: 5; height: 5; radius: 3; color: green }
                        Text {
                            text: ["AUDIO_SOURCE: STUDIO_ARRAY_MIC","MODEL: PARAKEET-FP16","MODEL: OLLAMA-MISTRAL","COMPILER: CUDA_12.1"][root.activeTab]
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            color: textGhost
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: ["HARDWARE_LINK: OK","CHECK: OK","CHECK: OK","STATUS: RUNNING"][root.activeTab]
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        color: textGhost
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    //  HELPER: reusable section card
    // ══════════════════════════════════════════════════════════
    component SectionCard: Rectangle {
        Layout.fillWidth: true
        radius: 12
        color: surfaceCard
        border.color: divider
        border.width: 1
    }

    component SectionTitle: Text {
        font.family: "JetBrains Mono"
        font.pixelSize: 10
        font.bold: false
        font.letterSpacing: 1.5
        color: textGhost
    }

    // Larger heading that groups several cards into one logical section.
    // Semibold (not heavy) per the requested type weight.
    //
    // IMPORTANT: this is a plain Item, NOT a nested Layout. A nested
    // ColumnLayout/RowLayout reports a real implicitWidth (its longest text),
    // which the content ScrollView latches onto and collapses every sibling
    // card to ~1/3 width. A plain Item with Layout.fillWidth fills the column
    // while contributing zero implicitWidth — exactly like the SectionCards.
    component GroupHeader: Item {
        property string title: ""
        property string subtitle: ""
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 2
        implicitHeight: _ghTitle.implicitHeight
                        + (_ghSub.visible ? _ghSub.implicitHeight + 3 : 0)

        Text {
            id: _ghTitle
            anchors { left: parent.left; top: parent.top }
            text: title
            font.family: "Plus Jakarta Sans"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: textPrimary
        }
        Rectangle {
            anchors {
                left: _ghTitle.right; leftMargin: 12; right: parent.right
                verticalCenter: _ghTitle.verticalCenter
            }
            height: 1
            color: divider
        }
        Text {
            id: _ghSub
            anchors { left: parent.left; right: parent.right; top: _ghTitle.bottom; topMargin: 3 }
            visible: subtitle.length > 0
            text: subtitle
            font.family: "JetBrains Mono"
            font.pixelSize: 9
            font.letterSpacing: 0.5
            color: textGhost
            elide: Text.ElideRight
        }
    }

    component FieldLabel: Text {
        font.family: "Plus Jakarta Sans"
        font.pixelSize: 14
        font.bold: false
        color: textPrimary
    }

    component FieldSubtitle: Text {
        font.family: "Plus Jakarta Sans"
        font.pixelSize: 12
        color: textMuted
    }

    component SettingRow: RowLayout {
        id: settingRow
        property string label: ""
        property string hint: ""
        default property alias controls: controlRow.data

        Layout.fillWidth: true
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            FieldLabel { text: settingRow.label }
            FieldSubtitle {
                text: settingRow.hint
                visible: settingRow.hint.length > 0
            }
        }

        RowLayout {
            id: controlRow
            Layout.preferredWidth: root.controlColumnWidth
            Layout.minimumWidth: root.controlColumnWidth
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: 10

            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
        }
    }

    component SettingControlSlot: Item {
        Layout.preferredWidth: root.controlColumnWidth
        Layout.minimumWidth: root.controlColumnWidth
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        default property alias contents: slotRoot.data

        Item {
            id: slotRoot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    // ── Shortcut helpers ─────────────────────────────────────────────────────
    function formatHotkey(raw) {
        if (!raw) return "—"
        return raw.split("+").map(function(p) {
            p = p.trim()
            return p.length > 0 ? p.charAt(0).toUpperCase() + p.slice(1) : p
        }).join(" + ")
    }

    function buildHotkeyStr(event) {
        var parts = []
        if (event.modifiers & Qt.ControlModifier) parts.push("ctrl")
        if (event.modifiers & Qt.AltModifier)     parts.push("alt")
        if (event.modifiers & Qt.ShiftModifier)   parts.push("shift")
        if (event.modifiers & Qt.MetaModifier)    parts.push("meta")
        var k = event.key
        var pureMods = [Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift, Qt.Key_Meta,
                        Qt.Key_Super_L, Qt.Key_Super_R]
        if (pureMods.indexOf(k) >= 0) return null
        if (k === Qt.Key_Escape) return null
        var name = ""
        if      (k === Qt.Key_Space)                        name = "space"
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) name = "enter"
        else if (k === Qt.Key_Backspace)                    name = "backspace"
        else if (k === Qt.Key_Delete)                       name = "delete"
        else if (k === Qt.Key_Tab)                          name = "tab"
        else if (k >= Qt.Key_F1 && k <= Qt.Key_F35)        name = "f" + (k - Qt.Key_F1 + 1)
        else if (event.text.length > 0)                     name = event.text.toLowerCase()
        if (!name) return null
        parts.push(name)
        return parts.join("+")
    }

    component ShortcutKeyBox : FocusScope {
        id: skb
        height: 32
        Layout.preferredWidth: root.controlColumnWidth
        Layout.minimumWidth: root.controlColumnWidth

        property bool listening: false
        property string currentValue: ""

        signal captured(string hotkey)

        Keys.onPressed: function(event) {
            if (!listening) return
            if (event.key === Qt.Key_Escape) {
                listening = false
                event.accepted = true
                return
            }
            var hk = buildHotkeyStr(event)
            if (hk) {
                currentValue = hk
                listening = false
                captured(hk)
            }
            event.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: surfaceInput
            border.color: skb.listening ? orange : (skbHov.containsMouse ? Qt.rgba(0,0,0,0.12) : divider)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: skb.listening ? "press shortcut…" : formatHotkey(skb.currentValue)
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: skb.listening ? textMuted : textPrimary
            }

            HoverHandler { id: skbHov }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { skb.forceActiveFocus(); skb.listening = true }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    //  CARD 1: GENERAL
    // ══════════════════════════════════════════════════════════
    Component {
        id: generalCard

        ScrollView {
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width - 16
                spacing: 14

                // ── Keybindings ────────────────────────────────
                SectionCard {
                    implicitHeight: keybindCol.implicitHeight + 32

                    ColumnLayout {
                        id: keybindCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        SectionTitle { text: "KEYBINDINGS" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        SettingRow {
                            label: "Dictation Shortcut"
                            hint: "Trigger raw microphone transcription"
                            ShortcutKeyBox {
                                currentValue: consoleViewModel.hotkey
                                onCaptured: function(hk) { consoleViewModel.save_hotkey(hk) }
                            }
                        }

                        SettingRow {
                            label: "Voice-to-AI Shortcut"
                            hint: "Process and style with active LLM"
                            ShortcutKeyBox {
                                currentValue: consoleViewModel.hotkey_ai
                                onCaptured: function(hk) { consoleViewModel.save_hotkey_ai(hk) }
                            }
                        }

                        SettingRow {
                            label: "Grain Assist Shortcut"
                            hint: "Invoke AI assistant with smart suggestions"
                            Rectangle {
                                height: 18
                                width: _csGrainPill.implicitWidth + 12
                                radius: 9
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.06)
                                border.color: Qt.rgba(0.078, 0.075, 0.071, 0.15)
                                border.width: 1
                                Text {
                                    id: _csGrainPill
                                    anchors.centerIn: parent
                                    text: "select text → instruct"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                                }
                            }
                            ShortcutKeyBox {
                                currentValue: consoleViewModel.hotkey_grain
                                onCaptured: function(hk) { consoleViewModel.save_hotkey_grain(hk) }
                            }
                        }
                    }
                }

                // ── Hardware Capture ───────────────────────────
                SectionCard {
                    implicitHeight: hwCol.implicitHeight + 32

                    ColumnLayout {
                        id: hwCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        SectionTitle { text: "HARDWARE CAPTURE" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        SettingRow {
                            label: "Mic Input Target"
                            hint: "Choose active hardware microphone"

                            ComboBox {
                                id: micCombo
                                Layout.preferredWidth: root.controlColumnWidth
                                implicitHeight: 32
                                model: consoleViewModel.available_microphones
                                currentIndex: consoleViewModel.microphone_combo_index
                                onActivated: function(idx) { consoleViewModel.save_microphone_by_index(idx) }

                                background: Rectangle {
                                    radius: 6
                                    color: surfaceInput
                                    border.color: divider
                                    border.width: 1
                                }

                                contentItem: Text {
                                    leftPadding: 10
                                    rightPadding: 24
                                    text: micCombo.displayText
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    color: textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                indicator: Text {
                                    x: micCombo.width - width - 8
                                    y: Math.round((micCombo.height - height) / 2)
                                    text: "▾"
                                    font.pixelSize: 10
                                    color: textMuted
                                }

                                delegate: ItemDelegate {
                                    id: micDel
                                    width: micCombo.width
                                    height: 32
                                    highlighted: micCombo.highlightedIndex === index
                                    padding: 0

                                    contentItem: Text {
                                        leftPadding: 10
                                        text: modelData
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 11
                                        color: textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    background: Rectangle {
                                        color: micDel.highlighted ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
                                    }
                                }

                                popup: Popup {
                                    y: micCombo.height + 4
                                    width: micCombo.width
                                    height: Math.min(micCombo.count * 32, 192)
                                    padding: 0
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                    background: Rectangle {
                                        radius: 8
                                        color: bgMain
                                        border.color: Qt.rgba(0, 0, 0, 0.10)
                                        border.width: 1
                                    }

                                    contentItem: ListView {
                                        clip: true
                                        model: micCombo.count
                                        currentIndex: micCombo.currentIndex
                                        ScrollBar.vertical: ScrollBar {
                                            policy: micCombo.count > 6
                                                    ? ScrollBar.AlwaysOn
                                                    : ScrollBar.AlwaysOff
                                        }
                                        delegate: ItemDelegate {
                                            width: ListView.view ? ListView.view.width : 0
                                            height: 32
                                            padding: 0
                                            highlighted: index === micCombo.currentIndex
                                            contentItem: Text {
                                                leftPadding: 10
                                                text: micCombo.textAt(index)
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: 11
                                                color: textPrimary
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            background: Rectangle {
                                                color: parent.highlighted
                                                       ? Qt.rgba(0, 0, 0, 0.06)
                                                       : (parent.hovered ? Qt.rgba(0, 0, 0, 0.03) : "transparent")
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    micCombo.currentIndex = index
                                                    micCombo.activated(index)
                                                    micCombo.popup.close()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SettingRow {
                            label: "Process Audio"
                            hint: "85 Hz rumble filter + auto gain for quiet mics, applied before transcription"

                            Rectangle {
                                height: 18
                                width: _csAudioText.implicitWidth + 12
                                radius: 9
                                color: consoleViewModel.process_audio
                                       ? Qt.rgba(0.063, 0.725, 0.506, 0.10)
                                       : Qt.rgba(0.078, 0.075, 0.071, 0.06)
                                border.color: consoleViewModel.process_audio
                                       ? Qt.rgba(0.063, 0.725, 0.506, 0.4)
                                       : Qt.rgba(0.078, 0.075, 0.071, 0.15)
                                border.width: 1

                                Text {
                                    id: _csAudioText
                                    anchors.centerIn: parent
                                    text: consoleViewModel.process_audio ? "active" : "off"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    color: consoleViewModel.process_audio
                                           ? "#10B981"
                                           : Qt.rgba(0.078, 0.075, 0.071, 0.4)
                                }
                            }

                            MechanicalToggle {
                                checked: consoleViewModel.process_audio
                                onToggled: consoleViewModel.save_process_audio(checked)
                            }
                        }
                    }
                }

                // ── Daemon Preferences ─────────────────────────
                SectionCard {
                    implicitHeight: daemonCol.implicitHeight + 32

                    ColumnLayout {
                        id: daemonCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        SectionTitle { text: "DAEMON PREFERENCES" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        SettingRow {
                            label: "Launch on Startup"
                            hint: "Autoload system daemon at desktop boot"
                            MechanicalToggle {
                                checked: consoleViewModel.launch_on_boot
                                onToggled: consoleViewModel.save_launch_on_boot(checked)
                            }
                        }

                        SettingRow {
                            label: "Launch Minimized"
                            hint: "Start silently in tray — turn off to open console on launch"
                            MechanicalToggle {
                                // Controlled — stays in sync if changed elsewhere.
                                value: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        ? consoleViewModel.start_minimized : true
                                onToggled: {
                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        consoleViewModel.save_start_minimized(checked)
                                }
                            }
                        }

                        SettingRow {
                            label: "Play Sound"
                            hint: "Play confirmation sounds on keybind triggers"
                            MechanicalToggle {
                                // Controlled — mirrors the quick panel's Play Sound toggle.
                                value: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        ? consoleViewModel.play_sound : true
                                onToggled: consoleViewModel.save_play_sound(checked)
                            }
                        }

                        SettingRow {
                            label: "Close to System Tray"
                            hint: "Minimize to tray instead of quitting"
                            MechanicalToggle {
                                // Controlled — mirrors the quick panel's tray toggle.
                                value: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        ? consoleViewModel.close_to_tray : true
                                onToggled: consoleViewModel.save_close_to_tray(checked)
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    //  CARD 2: TRANSCRIPTION
    // ══════════════════════════════════════════════════════════
    Component {
        id: transcriptionCard

        ScrollView {
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width - 16
                spacing: 14

                // ════ OFFLINE MODULE CONFIGURATION ════
                GroupHeader {
                    title: "Configure Local Model"
                    subtitle: "OFFLINE MODULE CONFIGURATION — ENGINE + STREAM PARAMETERS"
                }

                // ── Offline Weights ────────────────────────────
                SectionCard {
                    id: offlineWeightsCard
                    property bool expanded: false

                    // Latest install-progress message forwarded from the backend.
                    property string installProgressMsg: ""

                    // Auto-unload is now owned by the BACKEND (AppController +
                    // LocalSTTManager) so it works with the UI closed. This array
                    // only maps the Settings combo box index to the persisted
                    // millisecond value; the combo writes it via
                    // consoleViewModel.save_unload_idle_ms and the backend enforces
                    // the idle timer per session. -1 = Never, 0 = Instant.
                    readonly property var unloadValuesMs: [
                        0,                    // Instant
                        5  * 60 * 1000,       // 5 minutes
                        10 * 60 * 1000,       // 10 minutes
                        15 * 60 * 1000,       // 15 minutes
                        30 * 60 * 1000,       // 30 minutes
                        60 * 60 * 1000,       // 1 hour
                        24 * 60 * 60 * 1000,  // 24 hours
                        -1                    // Never
                    ]
                    function unloadIndexForMs(ms) {
                        for (var i = 0; i < unloadValuesMs.length; i++)
                            if (unloadValuesMs[i] === ms) return i
                        return 1  // default → 5 minutes
                    }

                    // Live status from the SettingsViewModel / LocalSTTManager.
                    // Falls back to "not_installed" when the VM is not yet available.
                    property string liveStatus: {
                        if (typeof consoleViewModel === "undefined" || !consoleViewModel)
                            return "not_installed"
                        return consoleViewModel.local_stt_status || "not_installed"
                    }

                    // Model registry catalog + current selection (both live from
                    // the backend; local_stt_model_id re-binds on its notify signal).
                    readonly property var modelCatalog:
                        (typeof consoleViewModel !== "undefined" && consoleViewModel)
                            ? consoleViewModel.local_stt_models : []
                    readonly property string selectedModelId:
                        (typeof consoleViewModel !== "undefined" && consoleViewModel)
                            ? consoleViewModel.local_stt_model_id : ""
                    function selectedModelEntry() {
                        for (var i = 0; i < modelCatalog.length; i++)
                            if (modelCatalog[i].id === selectedModelId) return modelCatalog[i]
                        return null
                    }
                    function ramLabel(mb) {
                        return mb >= 1000 ? (mb / 1000).toFixed(1) + " GB" : mb + " MB"
                    }

                    // Backend signal hooks
                    Connections {
                        target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                        function onLocal_stt_install_progress(msg) {
                            offlineWeightsCard.installProgressMsg = msg
                        }
                    }

                    implicitHeight: expanded
                        ? (weightsCol.implicitHeight + 32 + expandedModelsColumn.implicitHeight + 16 + 36)
                        : (weightsCol.implicitHeight + 32 + 36)
                    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: weightsCol
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                        spacing: 14

                        SectionTitle { text: "OFFLINE ENGINE WEIGHTS" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        // ── Active local model (from the registry) ─────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            // Model name + live status subtitle
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                FieldLabel {
                                    text: {
                                        var m = offlineWeightsCard.selectedModelEntry()
                                        return m ? m.name : "Local model"
                                    }
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                RowLayout {
                                    spacing: 6
                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        color: {
                                            var s = offlineWeightsCard.liveStatus
                                            if (s === "running")   return green
                                            if (s === "error")     return "#EF4444"
                                            if (s === "installing" || s === "starting") return orange
                                            if (s === "stopped")   return Qt.rgba(0.078, 0.075, 0.071, 0.35)
                                            return Qt.rgba(0.078, 0.075, 0.071, 0.18)
                                        }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    FieldSubtitle {
                                        text: {
                                            var s = offlineWeightsCard.liveStatus
                                            var m = offlineWeightsCard.selectedModelEntry()
                                            var ram = m ? offlineWeightsCard.ramLabel(m.ramMb) : ""
                                            if (s === "running")    return "loaded · active"
                                            if (s === "starting")   return "starting server…"
                                            if (s === "installing") return "installing…"
                                            if (s === "stopped")    return "installed · not loaded"
                                            if (s === "error")      return "error — see retry below"
                                            return "~" + ram + " RAM · downloads on first start"
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Trash — visible only when the venv actually exists
                            Rectangle {
                                width: 28; height: 28; radius: 6
                                color: deleteTopHover.containsMouse ? Qt.rgba(0.8, 0.2, 0.2, 0.1) : "transparent"
                                visible: {
                                    var s = offlineWeightsCard.liveStatus
                                    return s === "stopped" || s === "starting" || s === "running" || s === "error"
                                }
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Canvas {
                                    anchors.centerIn: parent; width: 14; height: 14
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.strokeStyle = deleteTopHover.containsMouse ? "#CC3333" : Qt.rgba(0.078, 0.075, 0.071, 0.4)
                                        ctx.lineWidth = 1.5; ctx.lineCap = "round"
                                        ctx.strokeRect(2, 4, 10, 9)
                                        ctx.beginPath(); ctx.moveTo(1, 4); ctx.lineTo(13, 4); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(5, 4); ctx.lineTo(5, 2); ctx.lineTo(9, 2); ctx.lineTo(9, 4); ctx.stroke()
                                    }
                                }

                                HoverHandler {
                                    id: deleteTopHover
                                    onHoveredChanged: parent.children[0].requestPaint()
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            consoleViewModel.uninstall_local_stt()
                                    }
                                }
                            }

                            // Indeterminate progress bar (installing / starting)
                            Item {
                                Layout.preferredWidth: 120; Layout.preferredHeight: 32
                                visible: offlineWeightsCard.liveStatus === "installing" ||
                                         offlineWeightsCard.liveStatus === "starting"

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 6; radius: 3
                                    color: Qt.rgba(0, 0, 0, 0.1); clip: true

                                    Rectangle {
                                        id: progressPill
                                        width: parent.width * 0.35; height: parent.height; radius: 3
                                        color: orange
                                        NumberAnimation on x {
                                            from: -progressPill.width
                                            to: progressPill.parent.width
                                            duration: 1400; loops: Animation.Infinite
                                            running: offlineWeightsCard.liveStatus === "installing" ||
                                                     offlineWeightsCard.liveStatus === "starting"
                                            easing.type: Easing.InOutSine
                                        }
                                    }
                                }
                            }

                            // Main action button
                            Rectangle {
                                id: sttActionBtn
                                width: 100; height: 32; radius: 6

                                property bool isDisabled:
                                    offlineWeightsCard.liveStatus === "installing" ||
                                    offlineWeightsCard.liveStatus === "starting"

                                color: {
                                    var s = offlineWeightsCard.liveStatus
                                    if (s === "running")  return charcoal
                                    if (s === "stopped")  return Qt.rgba(0.078, 0.075, 0.071, 0.15)
                                    if (s === "error")    return "#C0392F"
                                    return orange   // not_installed, installing, starting
                                }
                                border.color: offlineWeightsCard.liveStatus === "stopped" ? divider : "transparent"
                                border.width:  offlineWeightsCard.liveStatus === "stopped" ? 1 : 0
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    font.family: "JetBrains Mono"; font.pixelSize: 9
                                    font.bold: true; font.letterSpacing: 0.5
                                    color: {
                                        var s = offlineWeightsCard.liveStatus
                                        if (s === "running") return textLight
                                        if (s === "stopped") return Qt.rgba(0.078, 0.075, 0.071, 0.5)
                                        return "white"
                                    }
                                    text: {
                                        var s = offlineWeightsCard.liveStatus
                                        if (s === "not_installed") return "INSTALL"
                                        if (s === "installing")    return "INSTALLING"
                                        if (s === "starting")      return "LOADING…"
                                        if (s === "running")       return "LOADED"
                                        if (s === "stopped")       return "UNLOADED"
                                        if (s === "error")         return "RETRY"
                                        return "INSTALL"
                                    }
                                }

                                HoverHandler { id: sttBtnHover }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    enabled: !sttActionBtn.isDisabled
                                    onClicked: {
                                        if (typeof consoleViewModel === "undefined" || !consoleViewModel) return
                                        var s = offlineWeightsCard.liveStatus
                                        if (s === "not_installed" || s === "error") consoleViewModel.install_local_stt()
                                        else if (s === "stopped")                   consoleViewModel.start_local_stt()
                                        else if (s === "running")                   consoleViewModel.stop_local_stt()
                                    }
                                }
                            }
                        }

                        // Install progress message
                        Text {
                            visible: offlineWeightsCard.liveStatus === "installing"
                            text: offlineWeightsCard.installProgressMsg || "Installing dependencies…"
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            color: textMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }

                        // Server-start message
                        Text {
                            visible: offlineWeightsCard.liveStatus === "starting"
                            text: "Starting local STT server — the model loads on first launch (~30 s)."
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            color: textMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }

                        // Error message
                        Text {
                            visible: offlineWeightsCard.liveStatus === "error"
                            text: "Server failed to start. Ensure port 5092 is free, then click RETRY."
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            color: "#EF4444"; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }

                    // EXPANDED SECTION — model catalog from the registry.
                    // Selecting a model persists it, retargets the sidecar, and
                    // installs any missing engine packages (all backend-driven).
                    ColumnLayout {
                        id: expandedModelsColumn
                        anchors {
                            top: weightsCol.bottom
                            left: parent.left
                            right: parent.right
                            topMargin: 16
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 10
                        visible: offlineWeightsCard.expanded
                        opacity: offlineWeightsCard.expanded ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        Text {
                            text: "AVAILABLE MODELS — accuracy vs. memory"
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            font.bold: true; font.letterSpacing: 1.2
                            color: textGhost; Layout.fillWidth: true
                        }

                        Repeater {
                            model: offlineWeightsCard.modelCatalog

                            delegate: Item {
                                Layout.fillWidth: true
                                height: 52

                                property bool isActive: modelData.id === offlineWeightsCard.selectedModelId

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: isActive ? Qt.rgba(0,0,0,0.05)
                                         : (modelHover.containsMouse ? Qt.rgba(0,0,0,0.04) : "transparent")
                                    border.color: isActive ? Qt.rgba(0,0,0,0.10) : "transparent"
                                    border.width: isActive ? 1 : 0
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    HoverHandler { id: modelHover }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            FieldLabel {
                                                text: modelData.name
                                                font.pixelSize: 12
                                            }
                                            FieldSubtitle {
                                                text: (modelData.installed ? "installed · " : "")
                                                      + modelData.wer
                                                      + " · ~" + offlineWeightsCard.ramLabel(modelData.ramMb) + " RAM"
                                                      + " · " + modelData.languages
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Select / Active button
                                        Rectangle {
                                            width: 100
                                            height: 32
                                            radius: 6
                                            color: {
                                                if (isActive) return charcoal
                                                if (selectBtnHover.containsMouse) return Qt.rgba(1, 0.365, 0.118, 0.85)
                                                return Qt.rgba(0.078, 0.075, 0.071, 0.15)
                                            }
                                            border.color: isActive ? "transparent" : divider
                                            border.width: isActive ? 0 : 1
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: "✓"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    color: green
                                                    visible: isActive
                                                }

                                                Text {
                                                    text: isActive ? "ACTIVE" : "SELECT"
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    font.letterSpacing: 0.5
                                                    color: isActive ? textLight
                                                         : (selectBtnHover.containsMouse ? "white"
                                                            : Qt.rgba(0.078, 0.075, 0.071, 0.5))
                                                }
                                            }

                                            HoverHandler { id: selectBtnHover }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                enabled: !isActive
                                                onClicked: {
                                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                        consoleViewModel.save_local_stt_model(modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Switching downloads the model on its first load. WER ≈ English Open ASR average; lower is better."
                            font.family: "JetBrains Mono"; font.pixelSize: 9; font.italic: true
                            color: textGhost; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }

                    // VIEW MORE / LESS BAR (single thin bar)
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 36
                        radius: 12
                        color: Qt.rgba(0,0,0,0.06)

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: offlineWeightsCard.expanded ? "VIEW LESS" : "VIEW MORE"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 9
                                font.bold: true
                                font.letterSpacing: 1.5
                                color: viewMoreHover.containsMouse ? orange : textGhost
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                text: offlineWeightsCard.expanded ? "▲" : "▼"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 11
                                color: viewMoreHover.containsMouse ? orange : textGhost
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            HoverHandler { id: viewMoreHover }

                            onClicked: {
                                offlineWeightsCard.expanded = !offlineWeightsCard.expanded
                            }
                        }
                    }
                }

                // ── Stream Parameters ──────────────────────────
                SectionCard {
                    implicitHeight: streamCol.implicitHeight + 32
                    ColumnLayout {
                        id: streamCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        SectionTitle { text: "REAL-TIME STREAM PARAMETERS" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        // Model Unload — the only wired parameter; kept at the top.
                        SettingRow {
                            label: "Model Unload"
                            hint: "Auto-unload after this much idle time"

                            ComboBox {
                                id: unloadCombo
                                Layout.preferredWidth: 176
                                implicitHeight: 32
                                model: ["Instant", "5 minutes", "10 minutes", "15 minutes", "30 minutes", "1 hour", "24 hours", "Never"]
                                // Initialise from the backend-persisted value and
                                // keep in sync if it changes elsewhere.
                                currentIndex: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                    ? offlineWeightsCard.unloadIndexForMs(consoleViewModel.local_stt_unload_idle_ms)
                                    : 1
                                // Persist only on explicit user selection; the
                                // backend enforces the policy headless.
                                onActivated: {
                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        consoleViewModel.save_unload_idle_ms(offlineWeightsCard.unloadValuesMs[currentIndex])
                                }
                                background: Rectangle { radius: 6; color: surfaceInput; border.color: divider; border.width: 1 }
                                contentItem: Text { leftPadding: 10; text: parent.displayText; font.family: "JetBrains Mono"; font.pixelSize: 11; color: textPrimary; verticalAlignment: Text.AlignVCenter }
                            }
                        }

                        // Rolling Window — not user-configurable yet. A wrong value
                        // can hurt accuracy, so it stays fixed (overlap is locked at
                        // 2 s internally). Surfaced as "coming soon".
                        SettingRow {
                            label: "Rolling Window"
                            hint: "Audio buffer window duration"

                            Rectangle {
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: _rwSoonText.implicitWidth + 18
                                radius: 11
                                color: Qt.rgba(0.078, 0.075, 0.071, 0.06)
                                border.color: Qt.rgba(0.078, 0.075, 0.071, 0.15)
                                border.width: 1
                                Text {
                                    id: _rwSoonText
                                    anchors.centerIn: parent
                                    text: "coming soon"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    color: Qt.rgba(0.078, 0.075, 0.071, 0.4)
                                }
                            }
                        }
                    }
                }

                // ════ CLOUD MODEL CONFIGURATION ════
                GroupHeader {
                    title: "Cloud Model Configuration"
                    subtitle: "STREAMING STT PROVIDERS — ADD, ENABLE, ROTATE"
                }

                // ── ADD NEW CLOUD PROVIDER ─────────────────────────────
                SectionCard {
                    id: addProviderCard
                    property bool expanded: false

                    implicitHeight: expanded ? (addProviderCol.implicitHeight + 32 + addFormColumn.implicitHeight + 16) : (addProviderCol.implicitHeight + 32)
                    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: addProviderCol
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                        spacing: 14

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 40

                            // Title + subtitle column (fills all space left of buttons)
                            Column {
                                anchors {
                                    left: parent.left
                                    right: _addProviderCloseBtn.left
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: 12
                                }
                                spacing: 2

                                Text {
                                    text: "Add New Provider"
                                    font.family: "Plus Jakarta Sans"
                                    font.pixelSize: 14
                                    font.bold: false
                                    color: textPrimary
                                }

                                Text {
                                    text: "Connect a speech or language model endpoint"
                                    font.family: "Plus Jakarta Sans"
                                    font.pixelSize: 11
                                    color: textMuted
                                    visible: !addProviderCard.expanded
                                }
                            }

                            // CLOSE button — anchored to left of ADD, right edge
                            Rectangle {
                                id: _addProviderCloseBtn
                                width: 80; height: 34; radius: 6
                                anchors {
                                    right: _addProviderAddBtn.left
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: 12
                                }
                                color: "transparent"
                                border.color: orange
                                border.width: 2
                                visible: addProviderCard.expanded

                                Text {
                                    anchors.centerIn: parent
                                    text: "CLOSE"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: orange
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: addProviderCard.expanded = false
                                }
                            }

                            // ADD button — pinned to right edge
                            Rectangle {
                                id: _addProviderAddBtn
                                width: 80; height: 34; radius: 6
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                color: charcoal

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: "+"
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "white"
                                        visible: !addProviderCard.expanded
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "ADD"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "white"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (addProviderCard.expanded) {
                                            if (typeof consoleViewModel === "undefined" || !consoleViewModel) return
                                            var autoName = providerDropdown.currentText + " (" + modelNameField.text.trim() + ")"
                                            consoleViewModel.add_provider("stt", autoName, endpointUrl.text.trim(), modelNameField.text.trim(), apiKeyField.text, -1, "")
                                            if (consoleViewModel.error_message === "") {
                                                addProviderCard.expanded = false
                                                apiKeyField.text = ""
                                                providerDropdown.currentIndex = 0
                                            }
                                        } else {
                                            addProviderCard.expanded = true
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider; visible: !addProviderCard.expanded }

                        Item { Layout.preferredHeight: 20; visible: addProviderCard.expanded }
                    }

                    // ADD FORM (expanded)
                    ColumnLayout {
                        id: addFormColumn
                        anchors {
                            top: addProviderCol.bottom
                            left: parent.left
                            right: parent.right
                            topMargin: 0
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 14
                        visible: addProviderCard.expanded
                        opacity: addProviderCard.expanded ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        // Row 1: Provider dropdown (left) + Model name (right)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Provider dropdown (left)
                            ComboBox {
                                id: providerDropdown
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                model: ["Deepgram", "AssemblyAI", "Groq (Whisper)", "Custom Endpoint"]
                                Component.onCompleted: {
                                    modelNameField.text = "nova-3"
                                }
                                onCurrentIndexChanged: {
                                    if (currentText === "Deepgram")         modelNameField.text = "nova-3"
                                    else if (currentText === "AssemblyAI")   modelNameField.text = "best"
                                    else if (currentText === "Groq (Whisper)") modelNameField.text = "whisper-large-v3-turbo"
                                    else                                    modelNameField.text = ""
                                }

                                background: Rectangle {
                                    radius: 6
                                    color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                    border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                    border.width: 1.5
                                }

                                contentItem: Text {
                                    leftPadding: 14
                                    rightPadding: 35
                                    text: parent.displayText
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: charcoal
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                indicator: Canvas {
                                    x: parent.width - width - 12
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
                                        ctx.fillStyle = charcoal
                                        ctx.fill()
                                    }
                                }
                            }

                            // Model name (right)
                            TextField {
                                id: modelNameField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                placeholderText: "Model Name (e.g., Whisper Large v3)"
                                placeholderTextColor: charcoal
                                font.family: "JetBrains Mono"
                                font.pixelSize: 11
                                color: charcoal
                                leftPadding: 14

                                background: Rectangle {
                                    radius: 6
                                    color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                    border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                    border.width: 1.5
                                }
                            }
                        }

                        // Row 2: Endpoint URL
                        TextField {
                            id: endpointUrl
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            placeholderText: "Endpoint URL"
                            readOnly: providerDropdown.currentText !== "Custom Endpoint"
                            opacity: providerDropdown.currentText !== "Custom Endpoint" ? 0.55 : 1.0
                            text: {
                                if (providerDropdown.currentText === "Deepgram")        return "https://api.deepgram.com"
                                if (providerDropdown.currentText === "AssemblyAI")      return "https://api.assemblyai.com"
                                if (providerDropdown.currentText === "Groq (Whisper)") return "https://api.groq.com/openai/v1"
                                return ""
                            }
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            color: charcoal
                            leftPadding: 14

                            background: Rectangle {
                                radius: 6
                                color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                border.width: 1.5
                            }
                        }

                        // Row 3: API Key
                        TextField {
                            id: apiKeyField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            placeholderText: "API Key"
                            placeholderTextColor: charcoal
                            echoMode: TextInput.Password
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            color: charcoal
                            leftPadding: 14

                            background: Rectangle {
                                radius: 6
                                color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                border.width: 1.5
                            }
                        }

                        // Inline validation error
                        Text {
                            visible: typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.error_message !== ""
                            text: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.error_message : ""
                            font.family: "JetBrains Mono"; font.pixelSize: 10
                            color: "#EF4444"
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }
                }

                // ── INSTALLED PROVIDERS ────────────────────────────────
                SectionCard {
                    id: installedProvidersCard
                    implicitHeight: installedCol.implicitHeight + 32

                    // Mirrors consoleViewModel.stt_smart_rotation — reactive via binding
                    property bool smartRotation: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                  ? consoleViewModel.stt_smart_rotation : false

                    ColumnLayout {
                        id: installedCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "INSTALLED PROVIDERS"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.bold: false
                                font.letterSpacing: 1.5
                                color: textGhost
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "SMART ROTATION"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                    color: textGhost
                                }
                                MechanicalToggle {
                                    // Controlled by the shared viewmodel (stays in sync with
                                    // the quick panel); onToggled fires on user intent only,
                                    // avoiding the binding/feedback issues of onCheckedChanged.
                                    value: installedProvidersCard.smartRotation
                                    onToggled: {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            consoleViewModel.set_stt_smart_rotation(checked)
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        // Provider list — Parakeet (local) always first, then cloud providers
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // ── LOCAL: Parakeet (always present) ──────────────
                            Rectangle {
                                Layout.fillWidth: true; height: 52; radius: 8; color: "transparent"
                                // Grey out when smart rotation is ON (local not supported in rotation)
                                opacity: installedProvidersCard.smartRotation ? 0.4 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 12
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        RowLayout {
                                            spacing: 8
                                            Text { text: "Parakeet 0.6"; font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true; color: textPrimary }
                                            Rectangle { width: 1; height: 12; color: Qt.rgba(0.078,0.075,0.071,0.18); Layout.alignment: Qt.AlignVCenter }
                                            Text { text: "LOCAL"; font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2; color: Qt.rgba(0.078,0.075,0.071,0.35); Layout.alignment: Qt.AlignVCenter }
                                        }
                                        Text { text: "parakeet-ctc-0.6b-v2"; font.family: "JetBrains Mono"; font.pixelSize: 9; color: textGhost }
                                    }
                                    Item { Layout.fillWidth: true }
                                    // Live status dot
                                    Rectangle {
                                        width: 6; height: 6; radius: 3; Layout.alignment: Qt.AlignVCenter
                                        color: {
                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                            if (!vm) return Qt.rgba(0.078,0.075,0.071,0.18)
                                            var s = vm.local_stt_status
                                            if (s === "running")   return "#10B981"
                                            if (s === "error")     return "#EF4444"
                                            if (s === "installing" || s === "starting") return "#FF5D1E"
                                            if (s === "stopped")   return Qt.rgba(0.078,0.075,0.071,0.35)
                                            return Qt.rgba(0.078,0.075,0.071,0.18)
                                        }
                                    }
                                    MechanicalToggle {
                                        value: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                  ? consoleViewModel.stt_local_enabled : true
                                        enabled: !installedProvidersCard.smartRotation
                                        onToggled: {
                                            if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                consoleViewModel.set_stt_local_enabled(checked)
                                        }
                                    }
                                }
                            }

                            // ── CLOUD section header (only when cloud providers exist) ──
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                visible: {
                                    var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                    if (!vm) return false
                                    return vm.stt_providers.filter(function(p) {
                                        var u = p.base_url || ""
                                        return u.indexOf("127.0.0.1") === -1 && u.indexOf("localhost") === -1
                                    }).length > 0
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: divider }
                                Text { text: "CLOUD"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2; color: textGhost }
                                Rectangle { Layout.fillWidth: true; height: 1; color: divider }
                            }

                            // Empty state for cloud (no cloud providers yet)
                            Rectangle {
                                visible: {
                                    var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                    if (!vm) return true
                                    return vm.stt_providers.filter(function(p) {
                                        var u = p.base_url || ""
                                        return u.indexOf("127.0.0.1") === -1 && u.indexOf("localhost") === -1
                                    }).length === 0
                                }
                                Layout.fillWidth: true; height: 36; radius: 8; color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "— add a cloud provider above —"
                                    font.family: "JetBrains Mono"; font.pixelSize: 10; color: textGhost
                                }
                            }

                            Repeater {
                                model: {
                                    var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                    if (!vm) return []
                                    return vm.stt_providers.filter(function(p) {
                                        var u = p.base_url || ""
                                        return u.indexOf("127.0.0.1") === -1 && u.indexOf("localhost") === -1
                                    })
                                }

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 8
                                    color: sttRowHover.containsMouse ? Qt.rgba(0,0,0,0.04) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    HoverHandler { id: sttRowHover }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                text: modelData.name
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: textPrimary
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: modelData.model
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: 9
                                                color: textGhost
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Trash icon — appears on row hover, left of toggle
                                        Rectangle {
                                            width: 28; height: 28; radius: 6
                                            color: sttTrashHover.containsMouse ? Qt.rgba(0.8, 0.2, 0.2, 0.12) : "transparent"
                                            visible: sttRowHover.containsMouse === true || sttTrashHover.containsMouse === true
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Canvas {
                                                anchors.centerIn: parent
                                                width: 14; height: 14
                                                onPaint: {
                                                    var ctx = getContext("2d")
                                                    ctx.clearRect(0, 0, width, height)
                                                    ctx.strokeStyle = sttTrashHover.containsMouse ? "#CC3333" : Qt.rgba(0.078, 0.075, 0.071, 0.45)
                                                    ctx.lineWidth = 1.5
                                                    ctx.lineCap = "round"
                                                    ctx.strokeRect(2, 4, 10, 9)
                                                    ctx.beginPath(); ctx.moveTo(1, 4); ctx.lineTo(13, 4); ctx.stroke()
                                                    ctx.beginPath(); ctx.moveTo(5, 4); ctx.lineTo(5, 2); ctx.lineTo(9, 2); ctx.lineTo(9, 4); ctx.stroke()
                                                }
                                            }

                                            HoverHandler {
                                                id: sttTrashHover
                                                onHoveredChanged: parent.children[0].requestPaint()
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                        consoleViewModel.remove_provider(modelData.id)
                                                }
                                            }
                                        }

                                        MechanicalToggle {
                                            value: modelData.enabled === true
                                            onToggled: {
                                                if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                    consoleViewModel.set_stt_provider_enabled(modelData.id, checked)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    //  CARD 3: PROCESSING
    // ══════════════════════════════════════════════════════════
    Component {
        id: processingCard

        ScrollView {
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width - 16
                spacing: 14

                // ════ PROVIDERS & ROUTING ════
                GroupHeader {
                    title: "Processing Models"
                    subtitle: "ADD PROVIDERS, CHOOSE ROUTING & THE GRAIN ASSIST MODEL"
                }

                // ── ADD NEW LLM PROVIDER ─────────────────────────────
                SectionCard {
                    id: addLlmProviderCard
                    property bool expanded: false

                    // Preset list is the SINGLE SOURCE OF TRUTH from the backend
                    // (PROVIDER_PRESETS via get_presets) — so every provider we
                    // add server-side (Mistral, OpenRouter, …) appears here with
                    // its correct default model + endpoint, no hardcoded drift.
                    readonly property var llmPresets: {
                        var out = []
                        if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
                            var all = consoleViewModel.get_presets()
                            for (var i = 0; i < all.length; i++)
                                if (all[i].provider_type === "llm") out.push(all[i])
                        }
                        return out
                    }
                    readonly property var llmOptionNames: {
                        var names = []
                        for (var i = 0; i < llmPresets.length; i++) names.push(llmPresets[i].name)
                        names.push("Custom Endpoint")
                        return names
                    }
                    function isCustomIndex(i) { return i >= llmPresets.length }

                    implicitHeight: expanded ? (addLlmProviderCol.implicitHeight + 32 + addLlmFormColumn.implicitHeight + 16) : (addLlmProviderCol.implicitHeight + 32)
                    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: addLlmProviderCol
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                text: "ADD NEW PROVIDER"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.bold: false
                                font.letterSpacing: 1.5
                                color: textGhost
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                width: 80
                                height: 34
                                radius: 6
                                color: "transparent"
                                border.color: orange
                                border.width: 2
                                visible: addLlmProviderCard.expanded

                                Text {
                                    anchors.centerIn: parent
                                    text: "CLOSE"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: orange
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: addLlmProviderCard.expanded = false
                                }
                            }

                            Rectangle {
                                width: 80
                                height: 34
                                radius: 6
                                color: charcoal

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: "+"
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: "white"
                                        visible: !addLlmProviderCard.expanded
                                    }

                                    Text {
                                        text: "ADD"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "white"
                                    }
                                }

                                HoverHandler { id: addLlmBtnHover }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (addLlmProviderCard.expanded) {
                                            if (typeof consoleViewModel === "undefined" || !consoleViewModel) return
                                            var autoName = llmProviderDropdown.currentText + " (" + llmModelNameField.text.trim() + ")"
                                            consoleViewModel.add_provider("llm", autoName, llmEndpointUrl.text.trim(), llmModelNameField.text.trim(), llmApiKeyField.text, -1, "")
                                            if (consoleViewModel.error_message === "") {
                                                addLlmProviderCard.expanded = false
                                                llmApiKeyField.text = ""
                                                llmProviderDropdown.currentIndex = 0
                                            }
                                        } else {
                                            addLlmProviderCard.expanded = true
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider; visible: !addLlmProviderCard.expanded }

                        Item { Layout.preferredHeight: 20; visible: addLlmProviderCard.expanded }
                    }

                    ColumnLayout {
                        id: addLlmFormColumn
                        anchors {
                            top: addLlmProviderCol.bottom
                            left: parent.left
                            right: parent.right
                            topMargin: 0
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 14
                        visible: addLlmProviderCard.expanded
                        opacity: addLlmProviderCard.expanded ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ComboBox {
                                id: llmProviderDropdown
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                model: addLlmProviderCard.llmOptionNames
                                // Auto-fill the model field from the selected preset
                                // (empty for Custom so the user types their own).
                                function _applyPreset() {
                                    if (addLlmProviderCard.isCustomIndex(currentIndex)) {
                                        llmModelNameField.text = ""
                                    } else {
                                        var p = addLlmProviderCard.llmPresets[currentIndex]
                                        if (p) llmModelNameField.text = p.model
                                    }
                                }
                                Component.onCompleted: _applyPreset()
                                onCurrentIndexChanged: _applyPreset()

                                background: Rectangle {
                                    radius: 6
                                    color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                    border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                    border.width: 1.5
                                }

                                contentItem: Text {
                                    leftPadding: 14
                                    rightPadding: 35
                                    text: parent.displayText
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: charcoal
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                indicator: Canvas {
                                    x: parent.width - width - 12
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
                                        ctx.fillStyle = charcoal
                                        ctx.fill()
                                    }
                                }
                            }

                            TextField {
                                id: llmModelNameField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                placeholderText: "Model Name (e.g., GPT-4o)"
                                placeholderTextColor: charcoal
                                font.family: "JetBrains Mono"
                                font.pixelSize: 11
                                color: charcoal
                                leftPadding: 14

                                background: Rectangle {
                                    radius: 6
                                    color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                    border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                    border.width: 1.5
                                }
                            }
                        }

                        TextField {
                            id: llmEndpointUrl
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            placeholderText: "Endpoint URL"
                            readOnly: !addLlmProviderCard.isCustomIndex(llmProviderDropdown.currentIndex)
                            opacity: addLlmProviderCard.isCustomIndex(llmProviderDropdown.currentIndex) ? 1.0 : 0.55
                            // Preset endpoints come straight from the backend preset
                            // data; Custom leaves the field empty + editable.
                            text: {
                                if (addLlmProviderCard.isCustomIndex(llmProviderDropdown.currentIndex)) return ""
                                var p = addLlmProviderCard.llmPresets[llmProviderDropdown.currentIndex]
                                return p ? p.base_url : ""
                            }
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            color: charcoal
                            leftPadding: 14

                            background: Rectangle {
                                radius: 6
                                color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                border.width: 1.5
                            }
                        }

                        TextField {
                            id: llmApiKeyField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            placeholderText: "API Key"
                            placeholderTextColor: charcoal
                            echoMode: TextInput.Password
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            color: charcoal
                            leftPadding: 14

                            background: Rectangle {
                                radius: 6
                                color: Qt.rgba(0.925, 0.898, 0.855, 0.15)
                                border.color: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                border.width: 1.5
                            }
                        }

                        // Inline validation error
                        Text {
                            visible: typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.error_message !== ""
                            text: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.error_message : ""
                            font.family: "JetBrains Mono"; font.pixelSize: 10
                            color: "#EF4444"
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                    }
                }

                // ── INSTALLED LLM PROVIDERS ────────────────────────────────
                SectionCard {
                    id: installedLlmProvidersCard
                    implicitHeight: installedLlmCol.implicitHeight + 32

                    // Reactive binding to the shared viewmodel — the quick panel
                    // (ModuleC) drives the same property, so the two panels always
                    // agree. The toggle uses controlled `value:` mode below.
                    property bool smartRotation: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                  ? consoleViewModel.llm_smart_rotation : false

                    ColumnLayout {
                        id: installedLlmCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "INSTALLED PROVIDERS"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 10
                                font.bold: false
                                font.letterSpacing: 1.5
                                color: textGhost
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "SMART ROTATION"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                    color: textGhost
                                }
                                MechanicalToggle {
                                    id: _llmAdvSmartRotToggle
                                    // Controlled by the shared viewmodel — stays in sync with
                                    // the quick panel's smart-rotation toggle automatically.
                                    value: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            ? consoleViewModel.llm_smart_rotation : false
                                    onToggled: {
                                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        if (vm) vm.set_llm_smart_rotation(checked)
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        // Provider list — live data from consoleViewModel.llm_providers
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Empty state
                            Rectangle {
                                visible: typeof consoleViewModel === "undefined" || !consoleViewModel || consoleViewModel.llm_providers.length === 0
                                Layout.fillWidth: true
                                height: 52
                                radius: 8
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "— add your first provider above —"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    color: textGhost
                                }
                            }

                            Repeater {
                                model: typeof consoleViewModel !== "undefined" && consoleViewModel ? consoleViewModel.llm_providers : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 8
                                    color: llmRowHover.containsMouse ? Qt.rgba(0,0,0,0.04) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    HoverHandler { id: llmRowHover }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                spacing: 8; Layout.fillWidth: true
                                                Text {
                                                    text: modelData.name
                                                    font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
                                                    color: textPrimary; elide: Text.ElideRight; Layout.fillWidth: true
                                                }
                                                // CUSTOM tag — visible for user-added custom endpoints
                                                Rectangle {
                                                    width: 1; height: 12; color: Qt.rgba(0.078,0.075,0.071,0.18)
                                                    Layout.alignment: Qt.AlignVCenter
                                                    visible: modelData.kind === "custom"
                                                }
                                                Text {
                                                    text: "CUSTOM"
                                                    font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                                    font.letterSpacing: 1.2; color: Qt.rgba(0.078,0.075,0.071,0.35)
                                                    Layout.alignment: Qt.AlignVCenter
                                                    visible: modelData.kind === "custom"
                                                }
                                            }
                                            Text {
                                                text: modelData.model
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: 9
                                                color: textGhost
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Trash icon — appears on row hover
                                        Rectangle {
                                            width: 28; height: 28; radius: 6
                                            color: llmTrashHover.containsMouse ? Qt.rgba(0.8, 0.2, 0.2, 0.12) : "transparent"
                                            visible: llmRowHover.containsMouse === true || llmTrashHover.containsMouse === true
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            Canvas {
                                                anchors.centerIn: parent
                                                width: 14; height: 14
                                                onPaint: {
                                                    var ctx = getContext("2d")
                                                    ctx.clearRect(0, 0, width, height)
                                                    ctx.strokeStyle = llmTrashHover.containsMouse ? "#CC3333" : Qt.rgba(0.078, 0.075, 0.071, 0.45)
                                                    ctx.lineWidth = 1.5
                                                    ctx.lineCap = "round"
                                                    ctx.strokeRect(2, 4, 10, 9)
                                                    ctx.beginPath(); ctx.moveTo(1, 4); ctx.lineTo(13, 4); ctx.stroke()
                                                    ctx.beginPath(); ctx.moveTo(5, 4); ctx.lineTo(5, 2); ctx.lineTo(9, 2); ctx.lineTo(9, 4); ctx.stroke()
                                                }
                                            }

                                            HoverHandler {
                                                id: llmTrashHover
                                                onHoveredChanged: parent.children[0].requestPaint()
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                        consoleViewModel.remove_provider(modelData.id)
                                                }
                                            }
                                        }

                                        MechanicalToggle {
                                            // Controlled by the model so radio behaviour (rotation
                                            // OFF → exactly one ON) can never desync the switches.
                                            value: modelData.enabled === true
                                            onToggled: {
                                                var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                                if (vm) vm.set_llm_provider_enabled(modelData.id, checked)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── GRAIN ASSIST MODEL ─────────────────────────────────────
                // Which provider the select-text agent (Ctrl+Shift+G) uses.
                // Independent of the rotation enable flags above — an explicit
                // choice is honoured even if that provider isn't enabled for
                // dictation processing.
                SectionCard {
                    id: grainAssistCard
                    implicitHeight: grainAssistCol.implicitHeight + 32

                    // Build the option list: "Auto" first, then every added LLM
                    // provider. Reactive to the live provider list.
                    readonly property var llmList:
                        (typeof consoleViewModel !== "undefined" && consoleViewModel)
                            ? consoleViewModel.llm_providers : []
                    readonly property var options: {
                        var opts = [{ id: "", label: "Auto — first enabled provider" }]
                        for (var i = 0; i < llmList.length; i++)
                            opts.push({ id: llmList[i].id,
                                        label: llmList[i].name + "  ·  " + llmList[i].model })
                        return opts
                    }
                    function indexForId(id) {
                        for (var i = 0; i < options.length; i++)
                            if (options[i].id === id) return i
                        return 0  // configured provider was deleted → Auto
                    }

                    ColumnLayout {
                        id: grainAssistCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "GRAIN ASSIST MODEL"
                                font.family: "JetBrains Mono"; font.pixelSize: 10
                                font.letterSpacing: 1.5; color: textGhost
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "⌃⇧G"
                                font.family: "JetBrains Mono"; font.pixelSize: 9
                                font.letterSpacing: 1; color: textGhost
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        Text {
                            text: "The select-text agent uses this provider. Pick any one you've added — it doesn't have to be enabled for rotation above."
                            font.family: "JetBrains Mono"; font.pixelSize: 9
                            color: textGhost; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }

                        ComboBox {
                            id: grainAssistCombo
                            Layout.fillWidth: true
                            implicitHeight: 34
                            model: grainAssistCard.options.map(function(o) { return o.label })
                            currentIndex: grainAssistCard.indexForId(
                                (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                    ? consoleViewModel.grain_assist_provider_id : "")
                            onActivated: function(index) {
                                var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                if (vm && index >= 0 && index < grainAssistCard.options.length)
                                    vm.save_grain_assist_provider(grainAssistCard.options[index].id)
                            }
                            // Re-sync if the provider list or selection changes elsewhere.
                            Connections {
                                target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                function onGrain_assist_provider_changed() {
                                    grainAssistCombo.currentIndex = grainAssistCard.indexForId(consoleViewModel.grain_assist_provider_id)
                                }
                                function onLlm_providers_changed() {
                                    grainAssistCombo.currentIndex = grainAssistCard.indexForId(consoleViewModel.grain_assist_provider_id)
                                }
                            }
                            background: Rectangle { radius: 6; color: surfaceInput; border.color: divider; border.width: 1 }
                            contentItem: Text {
                                leftPadding: 10; rightPadding: 28
                                text: grainAssistCombo.displayText
                                font.family: "JetBrains Mono"; font.pixelSize: 11
                                color: textPrimary; verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ════ PROMPTS & VOCABULARY ════
                GroupHeader {
                    title: "Prompts & Vocabulary"
                    subtitle: "DIRECTIVE PROMPTS AND CUSTOM DICTIONARY"
                }

                // ── Directive Prompts ──────────────────────────
                SectionCard {
                    id: promptsBuilderCard
                    property string selectedPromptId: ""
                    property bool _justAdded: false

                    implicitHeight: promptsMainCol.implicitHeight + 32

                    function _selectedData() {
                        var ps = consoleViewModel ? consoleViewModel.prompts : []
                        for (var i = 0; i < ps.length; i++) {
                            if (ps[i].id === selectedPromptId) return ps[i]
                        }
                        return null
                    }

                    function _loadSelected() {
                        var d = _selectedData()
                        promptNameField.text   = d ? d.name : ""
                        promptContentArea.text = d ? d.text : ""
                    }

                    onSelectedPromptIdChanged: _loadSelected()

                    Component.onCompleted: {
                        // Defer one tick so all child TextFields finish their own
                        // Component.onCompleted bindings before we write into them.
                        Qt.callLater(function() {
                            if (!consoleViewModel) return
                            var ps = consoleViewModel.prompts
                            if (ps.length === 0) return
                            // Prefer the currently-active prompt; fall back to first.
                            var targetId = ""
                            for (var i = 0; i < ps.length; i++) {
                                if (ps[i].is_active) { targetId = ps[i].id; break }
                            }
                            promptsBuilderCard.selectedPromptId = targetId !== "" ? targetId : ps[0].id
                        })
                    }

                    Connections {
                        target: consoleViewModel
                        function onPromptsChanged() {
                            var ps = consoleViewModel.prompts
                            if (promptsBuilderCard._justAdded && ps.length > 0) {
                                // User just added a new prompt — jump to it.
                                promptsBuilderCard.selectedPromptId = ps[ps.length - 1].id
                                promptsBuilderCard._justAdded = false
                            } else if (ps.length > 0 && promptsBuilderCard.selectedPromptId === "") {
                                // Panel opened before prompts were ready — now seed it.
                                for (var i = 0; i < ps.length; i++) {
                                    if (ps[i].is_active) {
                                        promptsBuilderCard.selectedPromptId = ps[i].id
                                        return
                                    }
                                }
                                promptsBuilderCard.selectedPromptId = ps[0].id
                            } else {
                                // Active prompt changed externally (e.g. ModuleC ComboBox) — reload editor.
                                Qt.callLater(function() { promptsBuilderCard._loadSelected() })
                            }
                        }
                    }

                    // Auto-save: 800 ms after last keystroke
                    Timer {
                        id: autoSaveTimer
                        interval: 800
                        repeat: false
                        onTriggered: {
                            var d = promptsBuilderCard._selectedData()
                            if (d) consoleViewModel.update_prompt(d.id, promptNameField.text, promptContentArea.text)
                        }
                    }

                    ColumnLayout {
                        id: promptsMainCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        // Header row
                        RowLayout {
                            Layout.fillWidth: true
                            SectionTitle { text: "DIRECTIVE PROMPTS BUILDER" }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: {
                                    var n = consoleViewModel ? consoleViewModel.prompts.length : 0
                                    return n + (n === 1 ? " prompt" : " prompts")
                                }
                                font.family: "JetBrains Mono"; font.pixelSize: 9; color: textGhost
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        // ── Horizontal tab strip ──────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // Scrollable tab row — overflow shown via edge fades
                            Item {
                                Layout.fillWidth: true
                                height: 32
                                clip: true

                                Flickable {
                                    id: tabFlick
                                    anchors.fill: parent
                                    contentWidth: tabRow.implicitWidth
                                    contentHeight: height
                                    flickableDirection: Flickable.HorizontalFlick
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds

                                    Row {
                                        id: tabRow
                                        spacing: 6
                                        height: parent.height

                                        Repeater {
                                            model: consoleViewModel ? consoleViewModel.prompts : []

                                            Rectangle {
                                                id: promptTab
                                                height: 32
                                                width: tabInner.implicitWidth + 20
                                                radius: 8

                                                property bool isSelected: promptsBuilderCard.selectedPromptId === modelData.id
                                                property bool isActive: modelData && modelData.is_active === true

                                                color: isSelected
                                                       ? charcoal
                                                       : (tabHov.containsMouse ? Qt.rgba(0,0,0,0.10) : Qt.rgba(0,0,0,0.05))
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                HoverHandler { id: tabHov }

                                                Row {
                                                    id: tabInner
                                                    anchors.centerIn: parent
                                                    spacing: 5

                                                    Rectangle {
                                                        width: 5; height: 5; radius: 2.5
                                                        color: green
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: promptTab.isActive
                                                    }

                                                    Text {
                                                        text: modelData ? modelData.name : ""
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: 10
                                                        font.bold: promptTab.isSelected
                                                        color: promptTab.isSelected
                                                               ? "#ECE5DA"
                                                               : (tabHov.containsMouse ? charcoal : textMuted)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                    }

                                                    Text {
                                                        text: "×"
                                                        font.pixelSize: 14
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: promptTab.isSelected ? Qt.rgba(1,1,1,0.45) : textGhost
                                                        visible: tabHov.containsMouse === true &&
                                                                 (consoleViewModel && consoleViewModel.prompts ? consoleViewModel.prompts.length > 1 : false)

                                                        MouseArea {
                                                            anchors.fill: parent; anchors.margins: -4
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                mouse.accepted = true
                                                                var delId = modelData.id
                                                                var ps = consoleViewModel.prompts
                                                                for (var i = 0; i < ps.length; i++) {
                                                                    if (ps[i].id === delId) {
                                                                        promptsBuilderCard.selectedPromptId = ps[i > 0 ? i - 1 : 1].id
                                                                        break
                                                                    }
                                                                }
                                                                consoleViewModel.delete_prompt(delId)
                                                            }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.rightMargin: tabHov.containsMouse ? 22 : 0
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: promptsBuilderCard.selectedPromptId = modelData.id
                                                }
                                            }
                                        }
                                    }
                                }

                                // Right-edge fade — inside the Item, overlaid on top of Flickable
                                Rectangle {
                                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                    width: 36
                                    visible: tabFlick.contentWidth > tabFlick.width
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: surfaceCard }
                                    }
                                    z: 1
                                }

                                // Left-edge fade — appears after scrolling right
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: 24
                                    visible: tabFlick.contentX > 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: surfaceCard }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                    z: 1
                                }
                            }

                            // + add new prompt tab
                            Rectangle {
                                height: 32; width: 32; radius: 8
                                color: addTabHov.containsMouse ? Qt.rgba(0,0,0,0.10) : Qt.rgba(0,0,0,0.05)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                HoverHandler { id: addTabHov }
                                Text {
                                    anchors.centerIn: parent; text: "+"
                                    font.pixelSize: 16; color: addTabHov.containsMouse ? charcoal : textMuted
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        promptsBuilderCard._justAdded = true
                                        consoleViewModel.add_prompt("New Prompt", "")
                                    }
                                }
                            }
                        }

                        // ── Editor (visible only when a prompt is selected) ───
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: promptsBuilderCard.selectedPromptId !== ""

                            // Name field — clearly an input, always has visible background
                            TextField {
                                id: promptNameField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                font.family: "JetBrains Mono"
                                font.pixelSize: 13
                                font.bold: true
                                color: charcoal
                                leftPadding: 12; rightPadding: 12
                                placeholderText: "Prompt name…"
                                placeholderTextColor: Qt.rgba(0.078, 0.075, 0.071, 0.3)

                                background: Rectangle {
                                    radius: 7
                                    color: surfaceInput
                                    border.color: promptNameField.activeFocus
                                                  ? orange
                                                  : (nameHov.containsMouse
                                                     ? Qt.rgba(0,0,0,0.15)
                                                     : Qt.rgba(0,0,0,0.08))
                                    border.width: 1.5
                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                    HoverHandler { id: nameHov }
                                }

                                onTextChanged: autoSaveTimer.restart()
                            }

                            // Content editor
                            Rectangle {
                                Layout.fillWidth: true
                                height: 158
                                radius: 8
                                color: surfaceInput
                                border.color: promptContentArea.activeFocus
                                              ? orange
                                              : Qt.rgba(0, 0, 0, 0.08)
                                border.width: 1.5
                                clip: true
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                ScrollView {
                                    anchors.fill: parent
                                    clip: true

                                    TextArea {
                                        id: promptContentArea
                                        font.family: "JetBrains Mono"; font.pixelSize: 11
                                        color: charcoal; wrapMode: Text.Wrap
                                        leftPadding: 14; rightPadding: 14
                                        topPadding: 12; bottomPadding: 12
                                        placeholderText: "Write your directive prompt here…"
                                        placeholderTextColor: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                        background: Rectangle { color: "transparent" }
                                        onTextChanged: autoSaveTimer.restart()
                                    }
                                }
                            }

                            // ── Action bar: status + activate + delete ────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: 8

                                property bool isActive: {
                                    var d = promptsBuilderCard._selectedData()
                                    return d ? d.is_active : false
                                }

                                color: Qt.rgba(0, 0, 0, 0.04)
                                border.color: Qt.rgba(0, 0, 0, 0.07)
                                border.width: 1

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 12 }
                                    spacing: 8

                                    // Active indicator dot — only shown when active
                                    Rectangle {
                                        width: 5; height: 5; radius: 2.5
                                        color: green
                                        visible: parent.parent.isActive
                                    }

                                    // Status label
                                    Text {
                                        Layout.fillWidth: true
                                        text: parent.parent.isActive
                                              ? "Active prompt"
                                              : "Not active"
                                        font.family: "JetBrains Mono"; font.pixelSize: 10
                                        color: parent.parent.isActive ? green : textGhost
                                    }

                                    // ACTIVATE button (only when not active)
                                    Rectangle {
                                        height: 30; width: 88
                                        radius: 6
                                        visible: !parent.parent.isActive
                                        color: activateHov.containsMouse ? "#2a2826" : charcoal
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        HoverHandler { id: activateHov }

                                        Text {
                                            id: activateLbl
                                            anchors.centerIn: parent
                                            text: "ACTIVATE"
                                            font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                            color: green
                                        }

                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var d = promptsBuilderCard._selectedData()
                                                if (d) consoleViewModel.set_active_prompt(d.id)
                                            }
                                        }
                                    }

                                    // DELETE button (always visible when >1 prompt)
                                    Rectangle {
                                        height: 30; width: 88
                                        radius: 6
                                        visible: consoleViewModel && consoleViewModel.prompts.length > 1
                                        color: delActionHov.containsMouse ? "#2a2826" : charcoal
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        HoverHandler { id: delActionHov }

                                        Text {
                                            id: delActionLbl
                                            anchors.centerIn: parent
                                            text: "DELETE"
                                            font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                            color: "white"
                                        }

                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var delId = promptsBuilderCard.selectedPromptId
                                                var ps = consoleViewModel.prompts
                                                for (var i = 0; i < ps.length; i++) {
                                                    if (ps[i].id === delId) {
                                                        promptsBuilderCard.selectedPromptId = ps[i > 0 ? i - 1 : 1].id
                                                        break
                                                    }
                                                }
                                                consoleViewModel.delete_prompt(delId)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Vocabulary Dictionary ──────────────────────
                SectionCard {
                    implicitHeight: vocabCol.implicitHeight + 32

                    ColumnLayout {
                        id: vocabCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 14

                        SectionTitle { text: "CUSTOM VOCABULARY DICTIONARY" }
                        Rectangle { Layout.fillWidth: true; height: 1; color: divider }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            ColumnLayout {
                                spacing: 2

                                Text {
                                    text: "Add a word"
                                    font.family: "Plus Jakarta Sans"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: textPrimary
                                }

                                Text {
                                    text: "Let the processing AI know"
                                    font.family: "Plus Jakarta Sans"
                                    font.pixelSize: 11
                                    color: textMuted
                                }
                            }

                            Item { Layout.fillWidth: true }

                            RowLayout {
                                spacing: 8
                                Layout.alignment: Qt.AlignRight

                                TextField {
                                    id: vocabInputField
                                    Layout.preferredWidth: 240
                                    Layout.preferredHeight: 42
                                    placeholderText: "add a word"
                                    placeholderTextColor: Qt.rgba(0.078, 0.075, 0.071, 0.25)
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    color: charcoal
                                    leftPadding: 14

                                    background: Rectangle {
                                        radius: 6
                                        color: surfaceInput
                                        border.color: vocabInputField.activeFocus
                                                      ? orange
                                                      : (vocabInputField.hovered ? Qt.rgba(0,0,0,0.20) : Qt.rgba(0,0,0,0.14))
                                        border.width: 1.5
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                    }

                                    Keys.onReturnPressed: {
                                        var w = text.trim()
                                        if (w.length > 0 && consoleViewModel) {
                                            consoleViewModel.add_word(w)
                                            text = ""
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 64
                                    height: 42
                                    radius: 6
                                    color: addVocabHover.containsMouse ? Qt.rgba(0.078, 0.075, 0.071, 0.9) : charcoal
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "ADD"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#ECE5DA"
                                    }

                                    HoverHandler { id: addVocabHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var w = vocabInputField.text.trim()
                                            if (w.length > 0 && consoleViewModel) {
                                                consoleViewModel.add_word(w)
                                                vocabInputField.text = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: divider; Layout.topMargin: -13; Layout.bottomMargin: -13 }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: consoleViewModel ? consoleViewModel.word_dictionary : []

                                Rectangle {
                                    width: badgeTxt.width + 28
                                    height: 26
                                    radius: 5
                                    color: Qt.rgba(0,0,0,0.07)

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            id: badgeTxt
                                            text: modelData
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: 10
                                            color: textPrimary
                                        }

                                        Text {
                                            text: "×"
                                            font.pixelSize: 12
                                            color: textGhost

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true

                                                onEntered: parent.color = orange
                                                onExited: parent.color = textGhost

                                                onClicked: {
                                                    if (consoleViewModel) consoleViewModel.remove_word(modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    //  CARD 4: TELEMETRY
    // ══════════════════════════════════════════════════════════
    Component {
        id: telemetryCard

        ColumnLayout {
            width: parent.width
            spacing: 0

            // ── Terminal Log (Full Page, Fixed Height) ───────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 600
                Layout.minimumHeight: 600
                Layout.maximumHeight: 600
                radius: 12
                color: "#0E0D0C"
                border.color: Qt.rgba(1,1,1,0.06); border.width: 1

                // CRT-style header
                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 32; radius: 12
                    // only round top corners
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 16
                        color: parent.color
                    }
                    color: Qt.rgba(1,1,1,0.04)

                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        Text { text: "SYSTEM LOG"; font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: false; font.letterSpacing: 2; color: Qt.rgba(1,1,1,0.3) }
                        Item { Layout.fillWidth: true }
                        // traffic-light dots
                        Repeater {
                            model: ["#EF4444","#F59E0B","#10B981"]
                            Rectangle { width: 8; height: 8; radius: 4; color: modelData; opacity: 0.7 }
                        }
                    }
                }

                ColumnLayout {
                    anchors { fill: parent; topMargin: 36; leftMargin: 14; rightMargin: 14; bottomMargin: 12 }
                    spacing: 0

                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: parent.width; spacing: 5

                            Repeater {
                                model: [
                                    { t: "info",    msg: "[DAEMON]  00:10:41 · Initializing localized grain core…"         },
                                    { t: "success", msg: "[SYSTEM]  00:10:42 · NVIDIA CUDA environment detected."           },
                                    { t: "info",    msg: "[DAEMON]  00:10:42 · Allocated 1.25 GB CUDA VRAM for tensors."    },
                                    { t: "success", msg: "[SYSTEM]  00:10:44 · Parakeet weights loaded & checksum verified."},
                                    { t: "info",    msg: "[ROUTING] Keybinding triggered! Streaming to Parakeet."           },
                                    { t: "info",    msg: "[ENGINE]  Audio block decoded. Duration: 3.4 seconds."            },
                                    { t: "success", msg: "[OUTPUT]  Complete · 'Configure this app locally.'"               },
                                    { t: "info",    msg: "[CLIENT]  System clipboard updated automatically."                }
                                ]

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.msg
                                    font.family: "JetBrains Mono"; font.pixelSize: 10
                                    color: modelData.t === "success" ? "#10B981"
                                         : modelData.t === "error"   ? "#EF4444"
                                         : Qt.rgba(1,1,1,0.38)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
