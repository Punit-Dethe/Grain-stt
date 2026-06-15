// Onboarding.qml — GRAIN // First-run setup wizard
//
// One-time flow, summoned exactly once on a fresh install and then disposed
// COMPLETELY (engine destroyed, working set trimmed) by main.py. Nothing here
// is retained after finished() fires — keep it self-contained and light.
//
// All operations reuse the SettingsViewModel exposed as `consoleViewModel`, so
// this wizard adds no backend object of its own. Theme is fixed LIGHT (the
// travertine look) — the user picks panel dark/light later, inside the panels.
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

ApplicationWindow {
    id: root
    width: 860
    height: 680
    minimumWidth: 720
    minimumHeight: 620
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    visible: false
    title: "Welcome to Grain"

    // Emitted on "Done" (or a forced skip). main.py persists completion and
    // tears the whole wizard down on this signal.
    signal finished()

    // ── palette (light only) ────────────────────────────────────────────────
    readonly property color bgMain:      "#ECE5DA"
    readonly property color bgPanel:     "#DDD5C8"
    readonly property color charcoal:    "#141312"
    readonly property color cream:       "#ECE5DA"
    readonly property color textPrimary: "#141312"
    readonly property color textMuted:   Qt.rgba(0.078, 0.075, 0.071, 0.5)
    readonly property color textGhost:   Qt.rgba(0.078, 0.075, 0.071, 0.35)
    readonly property color divider:     Qt.rgba(0, 0, 0, 0.08)
    // Input fields — a warm greige recess (NOT stark white) so they read as
    // editable fields against the travertine card, matching the Advanced panel.
    readonly property color inputBg:     Qt.rgba(0.078, 0.075, 0.071, 0.07)
    readonly property color inputBorder: Qt.rgba(0.078, 0.075, 0.071, 0.22)
    readonly property color orange:      "#FF5D1E"
    readonly property color green:       "#10B981"
    readonly property int   cornerRadius: 22

    // ── wizard state ────────────────────────────────────────────────────────
    property int step: 0
    readonly property int stepCount: 4
    readonly property var stepTitles: [
        "Microphone & audio", "Transcription engine", "Try it out", "AI processing"
    ]

    // Transcription mode chosen in step 2: "local" (recommended) or "cloud".
    property string transcriptionMode: "local"
    property string installProgressMsg: ""

    readonly property string recommendedId:
        (typeof consoleViewModel !== "undefined" && consoleViewModel)
            ? consoleViewModel.recommended_model_id : "parakeet-tdt-0.6b-v2"

    function recommendedModel() {
        if (typeof consoleViewModel === "undefined" || !consoleViewModel) return null
        var cat = consoleViewModel.local_stt_models
        for (var i = 0; i < cat.length; i++)
            if (cat[i].id === recommendedId) return cat[i]
        return cat.length > 0 ? cat[0] : null
    }
    function ramLabel(mb) { return mb >= 1000 ? (mb / 1000).toFixed(1) + " GB" : mb + " MB" }

    function latestTranscription() {
        if (typeof consoleViewModel === "undefined" || !consoleViewModel) return ""
        var h = consoleViewModel.transcription_history
        return (h && h.length > 0) ? h[h.length - 1].text : ""
    }
    function latestProcessing() {
        if (typeof consoleViewModel === "undefined" || !consoleViewModel) return ""
        var h = consoleViewModel.processing_history
        return (h && h.length > 0) ? h[h.length - 1].text : ""
    }

    Component.onCompleted: {
        if (typeof consoleViewModel !== "undefined" && consoleViewModel) {
            consoleViewModel.load()
            // Apply the recommended default: noise/gain conditioning ON. The user
            // can flip it on the first screen; this just pre-checks the box.
            consoleViewModel.save_process_audio(true)
        }
    }

    // Live install-progress feed for step 2.
    Connections {
        target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        function onLocal_stt_install_progress(msg) { root.installProgressMsg = msg }
    }

    // ── hotkey capture helpers (shared by the ShortcutKeyBox component) ───────
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
        else if (k >= Qt.Key_F1 && k <= Qt.Key_F35)         name = "f" + (k - Qt.Key_F1 + 1)
        else if (event.text.length > 0)                     name = event.text.toLowerCase()
        if (!name) return null
        parts.push(name)
        return parts.join("+")
    }

    // ════════════════════════════════════════════════════════════════════════
    //  Reusable components
    // ════════════════════════════════════════════════════════════════════════
    component MonoText: Text {
        font.family: "JetBrains Mono"; font.pixelSize: 11; color: root.textMuted
    }

    component PrimaryBtn: Rectangle {
        id: pbtn
        property string label: "Next"
        property bool enabledBtn: true
        signal clicked()
        implicitWidth: pbLbl.implicitWidth + 44
        implicitHeight: 42
        radius: 8
        color: !enabledBtn ? Qt.rgba(0.078, 0.075, 0.071, 0.18)
                           : (pbHov.hovered ? Qt.rgba(1, 0.365, 0.118, 0.9) : root.charcoal)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: pbLbl; anchors.centerIn: parent; text: pbtn.label
            font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
            font.letterSpacing: 1.2
            color: pbtn.enabledBtn ? root.cream : Qt.rgba(0.925, 0.898, 0.855, 0.5)
        }
        HoverHandler { id: pbHov; enabled: pbtn.enabledBtn }
        MouseArea {
            anchors.fill: parent; enabled: pbtn.enabledBtn
            cursorShape: Qt.PointingHandCursor; onClicked: pbtn.clicked()
        }
    }

    component GhostBtn: Rectangle {
        id: gbtn
        property string label: "Back"
        signal clicked()
        implicitWidth: gbLbl.implicitWidth + 40
        implicitHeight: 42
        radius: 8
        color: gbHov.hovered ? Qt.rgba(0, 0, 0, 0.04) : "transparent"
        border.color: root.divider; border.width: 1
        Text {
            id: gbLbl; anchors.centerIn: parent; text: gbtn.label
            font.family: "JetBrains Mono"; font.pixelSize: 11; font.bold: true
            font.letterSpacing: 1.2; color: root.textMuted
        }
        HoverHandler { id: gbHov }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: gbtn.clicked() }
    }

    // Mechanical-feel on/off toggle.
    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled(bool value)
        width: 46; height: 26; radius: 13
        color: checked ? root.green : Qt.rgba(0.078, 0.075, 0.071, 0.18)
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            width: 20; height: 20; radius: 10; y: 3
            x: tg.checked ? tg.width - width - 3 : 3
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: { tg.checked = !tg.checked; tg.toggled(tg.checked) }
        }
    }

    component ShortcutKeyBox: FocusScope {
        id: skb
        property string currentValue: ""
        property bool listening: false
        signal captured(string hotkey)
        implicitWidth: 168; implicitHeight: 38
        Keys.onPressed: function(event) {
            if (!listening) return
            if (event.key === Qt.Key_Escape) { listening = false; event.accepted = true; return }
            var hk = root.buildHotkeyStr(event)
            if (hk) { currentValue = hk; listening = false; captured(hk) }
            event.accepted = true
        }
        Rectangle {
            anchors.fill: parent; radius: 7
            color: root.inputBg
            border.color: skb.listening ? root.orange : (skbHov.hovered ? root.inputBorder : root.divider)
            border.width: skb.listening ? 2 : 1.5
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: skb.listening ? "press shortcut…" : root.formatHotkey(skb.currentValue)
                font.family: "JetBrains Mono"; font.pixelSize: 12
                color: skb.listening ? root.textMuted : root.textPrimary
            }
            HoverHandler { id: skbHov }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { skb.forceActiveFocus(); skb.listening = true }
            }
        }
    }

    // Reusable styled input background (warm greige recess, NOT white).
    component InputBg: Rectangle {
        property bool focused: false
        radius: 7
        color: root.inputBg
        border.color: focused ? root.orange : root.inputBorder
        border.width: focused ? 2 : 1.5
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }

    // Provider form mirroring the Advanced panel's Add-Provider: a preset
    // DROPDOWN (left) auto-fills the model (right) + endpoint URL (below, locked
    // unless "Custom Endpoint"), then the API key. Same add_provider data flow.
    component ProviderForm: ColumnLayout {
        id: pf
        property string kind: "stt"       // "stt" or "llm"
        property string heading: "Add an OpenAI-compatible endpoint"
        spacing: 12
        Layout.fillWidth: true

        // Built-in presets for THIS provider type, from the view model.
        readonly property var presets: {
            if (typeof consoleViewModel === "undefined" || !consoleViewModel) return []
            var all = consoleViewModel.get_presets()
            var out = []
            for (var i = 0; i < all.length; i++)
                if (all[i].provider_type === pf.kind) out.push(all[i])
            return out
        }
        function isCustom() { return nameCombo.currentIndex >= pf.presets.length }
        function currentName() {
            return isCustom() ? "Custom" : pf.presets[nameCombo.currentIndex].name
        }
        function applyPreset(idx) {
            if (idx < pf.presets.length) {
                modelF.text = pf.presets[idx].model
                urlF.text   = pf.presets[idx].base_url
            } else {
                modelF.text = ""
                urlF.text   = ""
            }
        }

        Text {
            text: pf.heading; color: root.textPrimary
            font.family: "Plus Jakarta Sans"; font.pixelSize: 14; font.bold: true
        }

        // Row 1: provider dropdown (left) + model (right)
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            ComboBox {
                id: nameCombo
                Layout.fillWidth: true; Layout.preferredHeight: 40
                model: {
                    var names = []
                    for (var i = 0; i < pf.presets.length; i++) names.push(pf.presets[i].name)
                    names.push("Custom Endpoint")
                    return names
                }
                Component.onCompleted: pf.applyPreset(0)
                onActivated: pf.applyPreset(currentIndex)

                background: InputBg {}
                contentItem: Text {
                    leftPadding: 14; rightPadding: 32; text: nameCombo.displayText
                    font.family: "JetBrains Mono"; font.pixelSize: 12; font.bold: true
                    color: root.textPrimary; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                }
                indicator: Text {
                    x: nameCombo.width - width - 12; y: (nameCombo.height - height) / 2
                    text: "▾"; font.pixelSize: 11; color: root.textMuted
                }
                delegate: ItemDelegate {
                    width: nameCombo.width; height: 36; padding: 0
                    highlighted: nameCombo.highlightedIndex === index
                    contentItem: Text {
                        leftPadding: 14; text: modelData
                        font.family: "JetBrains Mono"; font.pixelSize: 12; color: root.textPrimary
                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: parent.highlighted ? Qt.rgba(0,0,0,0.06) : "transparent"
                    }
                }
                popup: Popup {
                    y: nameCombo.height + 4; width: nameCombo.width; padding: 1
                    implicitHeight: Math.min(contentItem.implicitHeight, 220)
                    background: Rectangle { radius: 8; color: root.bgMain; border.color: Qt.rgba(0,0,0,0.12); border.width: 1 }
                    contentItem: ListView {
                        clip: true; implicitHeight: contentHeight
                        model: nameCombo.popup.visible ? nameCombo.delegateModel : null
                        currentIndex: nameCombo.highlightedIndex
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }
                }
            }

            TextField {
                id: modelF
                Layout.fillWidth: true; Layout.preferredHeight: 40
                placeholderText: pf.kind === "stt" ? "Model (e.g. nova-3)" : "Model (e.g. gpt-4o)"
                placeholderTextColor: root.textGhost
                font.family: "JetBrains Mono"; font.pixelSize: 12; color: root.textPrimary
                leftPadding: 14
                background: InputBg { focused: modelF.activeFocus }
            }
        }

        // Row 2: endpoint URL (auto-filled; editable only for Custom Endpoint)
        TextField {
            id: urlF
            Layout.fillWidth: true; Layout.preferredHeight: 40
            placeholderText: "Endpoint URL"
            placeholderTextColor: root.textGhost
            readOnly: !pf.isCustom()
            opacity: pf.isCustom() ? 1.0 : 0.6
            font.family: "JetBrains Mono"; font.pixelSize: 12; color: root.textPrimary
            leftPadding: 14
            background: InputBg { focused: urlF.activeFocus }
        }

        // Row 3: API key
        TextField {
            id: keyF
            Layout.fillWidth: true; Layout.preferredHeight: 40
            placeholderText: "API key"; placeholderTextColor: root.textGhost
            echoMode: TextInput.Password
            font.family: "JetBrains Mono"; font.pixelSize: 12; color: root.textPrimary
            leftPadding: 14
            background: InputBg { focused: keyF.activeFocus }
        }

        RowLayout {
            Layout.fillWidth: true
            MonoText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 10
                text: (typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.error_message)
                      ? consoleViewModel.error_message : "Stored securely in your OS keychain."
                color: (typeof consoleViewModel !== "undefined" && consoleViewModel && consoleViewModel.error_message)
                      ? "#EF4444" : root.textGhost
            }
            PrimaryBtn {
                label: "ADD PROVIDER"
                enabledBtn: urlF.text.trim().length > 0 && keyF.text.length > 0
                onClicked: {
                    if (typeof consoleViewModel === "undefined" || !consoleViewModel) return
                    consoleViewModel.add_provider(
                        pf.kind,
                        pf.currentName() + " (" + modelF.text.trim() + ")",
                        urlF.text.trim(), modelF.text.trim(), keyF.text, -1, "")
                    if (!consoleViewModel.error_message) keyF.text = ""
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  WINDOW CHROME
    // ════════════════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.bgMain
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ──────────────────────────────────────────────────────────────
            //  LEFT — wizard content
            // ──────────────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 0
                spacing: 0

                // Header (brand + drag + close)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    DragHandler { target: null; onActiveChanged: if (active) root.startSystemMove() }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 36; anchors.rightMargin: 24
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Skip setup"
                            font.family: "JetBrains Mono"; font.pixelSize: 10; font.letterSpacing: 0.5
                            color: skipHov.hovered ? root.orange : root.textGhost
                            HoverHandler { id: skipHov }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor; onClicked: root.finished()
                            }
                        }
                    }
                }

                // Title + a single slim progress bar (clean — no eyebrow, no dots)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 36; Layout.rightMargin: 36
                    spacing: 14

                    Text {
                        text: root.stepTitles[root.step]
                        font.family: "Syne"; font.pixelSize: 36; color: root.textPrimary
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4; radius: 2
                        color: Qt.rgba(0, 0, 0, 0.08)
                        Rectangle {
                            height: parent.height; radius: 2
                            width: parent.width * ((root.step + 1) / root.stepCount)
                            color: root.orange
                            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                Item { Layout.preferredHeight: 22 }

                // Step body
                ScrollView {
                    id: bodyScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 36; Layout.rightMargin: 36
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: bodyScroll.availableWidth
                        spacing: 0

                    // ── STEP 1: mic + sound ───────────────────────────────
                    ColumnLayout {
                        visible: root.step === 0
                        Layout.fillWidth: true
                        spacing: 18
                        MonoText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "Pick the microphone Grain listens to, and let us clean the signal before transcription. You can change either of these any time in the panel."
                        }

                        // Mic picker
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text { text: "Microphone"; color: root.textPrimary
                                   font.family: "Plus Jakarta Sans"; font.pixelSize: 15; font.bold: true }
                            ComboBox {
                                id: micCombo
                                Layout.fillWidth: true; Layout.preferredHeight: 42
                                model: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                       ? consoleViewModel.available_microphones : []
                                currentIndex: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                       ? consoleViewModel.microphone_combo_index : 0
                                onActivated: function(idx) {
                                    if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        consoleViewModel.save_microphone_by_index(idx)
                                }
                                background: Rectangle { radius: 7; color: root.inputBg; border.color: root.inputBorder; border.width: 1.5 }
                                contentItem: Text {
                                    leftPadding: 12; rightPadding: 28; text: micCombo.displayText
                                    font.family: "JetBrains Mono"; font.pixelSize: 12; color: root.textPrimary
                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                }
                                indicator: Text {
                                    x: micCombo.width - width - 10; y: (micCombo.height - height) / 2
                                    text: "▾"; font.pixelSize: 11; color: root.textMuted
                                }
                            }
                        }

                        // Sound processing
                        Rectangle {
                            Layout.fillWidth: true; radius: 12
                            color: root.bgPanel; border.color: root.divider; border.width: 1
                            implicitHeight: 84
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 18; spacing: 16
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 3
                                    RowLayout {
                                        spacing: 8
                                        Text { text: "Process audio"; color: root.textPrimary
                                               font.family: "Plus Jakarta Sans"; font.pixelSize: 15; font.bold: true }
                                        Rectangle {
                                            radius: 9; height: 18; width: recTag.implicitWidth + 14
                                            color: Qt.rgba(0.063, 0.725, 0.506, 0.12)
                                            border.color: Qt.rgba(0.063, 0.725, 0.506, 0.4); border.width: 1
                                            Text {
                                                id: recTag; anchors.centerIn: parent; text: "RECOMMENDED"
                                                font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; color: root.green
                                            }
                                        }
                                    }
                                    MonoText {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 10
                                        text: "85 Hz rumble filter + automatic gain for quiet mics, applied before transcription."
                                    }
                                }
                                Toggle {
                                    checked: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                             ? consoleViewModel.process_audio : true
                                    onToggled: function(v) {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            consoleViewModel.save_process_audio(v)
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    // ── STEP 2: transcription engine ──────────────────────
                    ColumnLayout {
                        visible: root.step === 1
                        Layout.fillWidth: true
                        spacing: 16

                        // Mode switch: Local vs Cloud
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Repeater {
                                model: [
                                    { id: "local", t: "On-device model", s: "Private · free · no internet" },
                                    { id: "cloud", t: "Cloud endpoint",   s: "OpenAI-compatible API" }
                                ]
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: 66; radius: 12
                                    property bool sel: root.transcriptionMode === modelData.id
                                    color: sel ? Qt.rgba(1, 0.365, 0.118, 0.08) : root.bgPanel
                                    border.color: sel ? root.orange : root.divider
                                    border.width: sel ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 14; spacing: 2
                                        Text { text: modelData.t; color: root.textPrimary
                                               font.family: "Plus Jakarta Sans"; font.pixelSize: 14; font.bold: true }
                                        MonoText { text: modelData.s; font.pixelSize: 10 }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.transcriptionMode = modelData.id
                                    }
                                }
                            }
                        }

                        // LOCAL: recommended model card + install
                        Rectangle {
                            visible: root.transcriptionMode === "local"
                            Layout.fillWidth: true; radius: 12
                            color: root.bgPanel; border.color: root.divider; border.width: 1
                            implicitHeight: localCol.implicitHeight + 32
                            ColumnLayout {
                                id: localCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                spacing: 12
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 3
                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: { var m = root.recommendedModel(); return m ? m.name : "Parakeet TDT 0.6B v2 (INT8)" }
                                                color: root.textPrimary
                                                font.family: "Plus Jakarta Sans"; font.pixelSize: 15; font.bold: true
                                            }
                                            Rectangle {
                                                radius: 9; height: 18; width: recM.implicitWidth + 14
                                                color: Qt.rgba(1, 0.365, 0.118, 0.12)
                                                border.color: Qt.rgba(1, 0.365, 0.118, 0.4); border.width: 1
                                                Text { id: recM; anchors.centerIn: parent; text: "RECOMMENDED"
                                                       font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; color: root.orange }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: {
                                                var m = root.recommendedModel()
                                                var sz = m ? ("~" + root.ramLabel(m.ramMb)) : "~1.2 GB"
                                                return "Our most accurate model, and it runs fully on your device. One-time download of " + sz + "."
                                            }
                                            color: root.textMuted
                                            font.family: "Plus Jakarta Sans"; font.pixelSize: 13
                                        }
                                    }
                                }

                                // status + install/loaded button
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    property string st: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                                         ? (consoleViewModel.local_stt_status || "not_installed") : "not_installed"
                                    RowLayout {
                                        spacing: 7; Layout.fillWidth: true
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            color: parent.parent.st === "running" ? root.green
                                                 : parent.parent.st === "error" ? "#EF4444"
                                                 : (parent.parent.st === "installing" || parent.parent.st === "starting") ? root.orange
                                                 : Qt.rgba(0.078,0.075,0.071,0.25)
                                        }
                                        MonoText {
                                            Layout.fillWidth: true; font.pixelSize: 11
                                            text: {
                                                var s = parent.parent.st
                                                if (s === "running")    return "Loaded and ready."
                                                if (s === "starting")   return "Starting server…"
                                                if (s === "installing") return root.installProgressMsg || "Installing…"
                                                if (s === "stopped")    return "Installed · not loaded."
                                                if (s === "error")      return "Something went wrong — click Retry."
                                                return "Not installed yet — downloads on first install."
                                            }
                                        }
                                    }
                                    PrimaryBtn {
                                        property string s: parent.st
                                        enabledBtn: s !== "installing" && s !== "starting"
                                        label: {
                                            if (s === "not_installed") return "INSTALL"
                                            if (s === "installing")    return "INSTALLING…"
                                            if (s === "starting")      return "LOADING…"
                                            if (s === "running")       return "LOADED ✓"
                                            if (s === "stopped")       return "LOAD"
                                            if (s === "error")         return "RETRY"
                                            return "INSTALL"
                                        }
                                        onClicked: {
                                            if (typeof consoleViewModel === "undefined" || !consoleViewModel) return
                                            // Make the recommended model the active one, then act on state.
                                            consoleViewModel.save_local_stt_model(root.recommendedId)
                                            if (s === "not_installed" || s === "error") consoleViewModel.install_local_stt()
                                            else if (s === "stopped")                   consoleViewModel.start_local_stt()
                                        }
                                    }
                                }
                                MonoText {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 9
                                    text: "Switch models anytime in the Advanced panel."
                                    color: root.textGhost
                                }
                            }
                        }

                        // CLOUD: provider form
                        Rectangle {
                            visible: root.transcriptionMode === "cloud"
                            Layout.fillWidth: true; radius: 12
                            color: root.bgPanel; border.color: root.divider; border.width: 1
                            implicitHeight: cloudCol.implicitHeight + 32
                            ColumnLayout {
                                id: cloudCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                ProviderForm { kind: "stt"; heading: "Connect a cloud transcription endpoint" }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    // ── STEP 3: try it ────────────────────────────────────
                    ColumnLayout {
                        visible: root.step === 2
                        Layout.fillWidth: true
                        spacing: 18

                        // Two methods, each clearly explained
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12

                            // Real-time
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 140
                                radius: 12; color: root.bgPanel; border.color: root.divider; border.width: 1
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 16; spacing: 6
                                    Text { text: "Real-time"; color: root.textPrimary
                                           font.family: "Plus Jakarta Sans"; font.pixelSize: 16; font.bold: true }
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        text: "Words appear live as you speak. Fast — great for quick notes and chat."
                                        color: root.textMuted; font.family: "Plus Jakarta Sans"; font.pixelSize: 13
                                    }
                                    Item { Layout.fillHeight: true }
                                    ShortcutKeyBox {
                                        Layout.fillWidth: true
                                        currentValue: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel.hotkey : ""
                                        onCaptured: function(hk) { if (consoleViewModel) consoleViewModel.save_hotkey(hk) }
                                    }
                                }
                            }

                            // Record, then transcribe
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 140
                                radius: 12; color: root.bgPanel; border.color: root.divider; border.width: 1
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 16; spacing: 6
                                    Text { text: "Record, then transcribe"; color: root.textPrimary
                                           font.family: "Plus Jakarta Sans"; font.pixelSize: 16; font.bold: true }
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        text: "Records first, then types it all at once. Slower, but the most accurate."
                                        color: root.textMuted; font.family: "Plus Jakarta Sans"; font.pixelSize: 13
                                    }
                                    Item { Layout.fillHeight: true }
                                    ShortcutKeyBox {
                                        Layout.fillWidth: true
                                        currentValue: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel.hotkey_batch : ""
                                        onCaptured: function(hk) { if (consoleViewModel) consoleViewModel.save_hotkey_batch(hk) }
                                    }
                                }
                            }
                        }

                        // The shared explanation now sits BELOW the two shortcuts.
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "Both work the same way — press a shortcut to start, speak, then press it again to stop. Your words land wherever your cursor is."
                            color: root.textMuted; font.family: "Plus Jakarta Sans"; font.pixelSize: 13
                        }

                        // One title for the whole try-it experience: read + result.
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            Text { text: "Press a shortcut and read this out loud"; color: root.textPrimary
                                   font.family: "Plus Jakarta Sans"; font.pixelSize: 16; font.bold: true }

                            Rectangle {
                                Layout.fillWidth: true; radius: 10; color: root.bgPanel
                                border.color: root.divider; border.width: 1; implicitHeight: 56
                                Text {
                                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                                    wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
                                    text: "“The quick brown fox jumps over the lazy dog.”"
                                    font.family: "Plus Jakarta Sans"; font.pixelSize: 15; font.italic: true
                                    color: root.textPrimary
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 88
                                radius: 10; color: root.inputBg; border.color: root.inputBorder; border.width: 1.5
                                Flow {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 0
                                    property string body: root.latestTranscription()
                                    Connections {
                                        target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        function onTranscription_history_changed() { parent.body = root.latestTranscription() }
                                    }
                                    Text {
                                        text: parent.body || "Your transcribed words will appear here…"
                                        color: parent.body ? root.textPrimary : root.textGhost
                                        wrapMode: Text.WordWrap; width: parent.width
                                        font.family: "Plus Jakarta Sans"; font.pixelSize: 14
                                    }
                                    Rectangle {
                                        width: 2; height: 17; color: root.orange
                                        SequentialAnimation on opacity {
                                            running: true; loops: Animation.Infinite
                                            NumberAnimation { to: 0; duration: 100 }
                                            PauseAnimation { duration: 480 }
                                            NumberAnimation { to: 1; duration: 100 }
                                            PauseAnimation { duration: 480 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── STEP 4: AI processing ─────────────────────────────
                    ColumnLayout {
                        visible: root.step === 3
                        Layout.fillWidth: true
                        spacing: 22

                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "The shortcut you press to FINISH a recording decides what you get:"
                            color: root.textPrimary; font.family: "Plus Jakarta Sans"; font.pixelSize: 15; font.bold: true
                        }

                        // Two outcomes, side by side — finish one way or the other.
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12

                            // Outcome A — plain transcription
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 152
                                radius: 12; color: root.bgPanel; border.color: root.divider; border.width: 1
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 16; spacing: 6
                                    Text { text: "Plain transcription"; color: root.textPrimary
                                           font.family: "Plus Jakarta Sans"; font.pixelSize: 16; font.bold: true }
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        text: "Your words, typed exactly as you spoke them."
                                        color: root.textMuted; font.family: "Plus Jakarta Sans"; font.pixelSize: 13
                                    }
                                    Item { Layout.fillHeight: true }
                                    Text { text: "Finish with"; color: root.textGhost
                                           font.family: "JetBrains Mono"; font.pixelSize: 9; font.letterSpacing: 1 }
                                    Rectangle {
                                        implicitWidth: kcA.implicitWidth + 24; implicitHeight: 34; radius: 8
                                        color: root.inputBg; border.color: root.inputBorder; border.width: 1.5
                                        Text { id: kcA; anchors.centerIn: parent
                                               text: "the same shortcut"
                                               font.family: "JetBrains Mono"; font.pixelSize: 12; font.bold: true; color: root.textPrimary }
                                    }
                                }
                            }

                            // Outcome B — AI-polished (the key here is rebindable)
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 152
                                radius: 12; color: Qt.rgba(1, 0.365, 0.118, 0.06)
                                border.color: Qt.rgba(1, 0.365, 0.118, 0.4); border.width: 1.5
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 16; spacing: 6
                                    Text { text: "Cleaned up by AI"; color: root.textPrimary
                                           font.family: "Plus Jakarta Sans"; font.pixelSize: 16; font.bold: true }
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        text: "Punctuation, grammar and your style — polished by your AI provider."
                                        color: root.textMuted; font.family: "Plus Jakarta Sans"; font.pixelSize: 13
                                    }
                                    Item { Layout.fillHeight: true }
                                    Text { text: "Finish with  ·  tap to change"; color: root.textGhost
                                           font.family: "JetBrains Mono"; font.pixelSize: 9; font.letterSpacing: 1 }
                                    ShortcutKeyBox {
                                        Layout.fillWidth: true
                                        currentValue: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel.hotkey_ai : ""
                                        onCaptured: function(hk) { if (consoleViewModel) consoleViewModel.save_hotkey_ai(hk) }
                                    }
                                }
                            }
                        }

                        // LLM provider form
                        Rectangle {
                            Layout.fillWidth: true; radius: 12
                            color: root.bgPanel; border.color: root.divider; border.width: 1
                            implicitHeight: llmCol.implicitHeight + 32
                            ColumnLayout {
                                id: llmCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                ProviderForm { kind: "llm"; heading: "Add an AI provider for processing" }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                    }
                }

                Item { Layout.preferredHeight: 10 }

                // Footer nav
                Rectangle { Layout.fillWidth: true; Layout.leftMargin: 36; Layout.rightMargin: 36; height: 1; color: root.divider }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 36; Layout.rightMargin: 36
                    Layout.topMargin: 14; Layout.bottomMargin: 18
                    GhostBtn {
                        label: "BACK"; visible: root.step > 0
                        onClicked: if (root.step > 0) root.step--
                    }
                    Item { Layout.fillWidth: true }
                    MonoText {
                        text: (root.step + 1) + " / " + root.stepCount
                        font.pixelSize: 10; color: root.textGhost
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { width: 16 }
                    // On the last step, let users finish without configuring AI.
                    GhostBtn {
                        label: "CONTINUE WITHOUT PROCESSING"
                        visible: root.step === root.stepCount - 1
                        onClicked: root.finished()
                    }
                    Item { width: 10; visible: root.step === root.stepCount - 1 }
                    PrimaryBtn {
                        label: root.step === root.stepCount - 1 ? "DONE" : "NEXT"
                        onClicked: {
                            if (root.step < root.stepCount - 1) root.step++
                            else root.finished()
                        }
                    }
                }
            }
        }
    }

    // Drag-resize edges (frameless).
    MouseArea { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 5; cursorShape: Qt.SizeHorCursor; onPressed: root.startSystemResize(Qt.LeftEdge) }
    MouseArea { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 5; cursorShape: Qt.SizeHorCursor; onPressed: root.startSystemResize(Qt.RightEdge) }
    MouseArea { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 5; cursorShape: Qt.SizeVerCursor; onPressed: root.startSystemResize(Qt.BottomEdge) }
}
