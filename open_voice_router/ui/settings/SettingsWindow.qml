// SettingsWindow.qml — Accordion Column Architecture · Warm Light Theme · Grain
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Effects

ApplicationWindow {
    id: root
    title: "Grain"
    width: 980
    height: 680
    minimumWidth: 780
    minimumHeight: 560
    flags: Qt.Window | Qt.FramelessWindowHint

    // Transparent so the rounded MultiEffect mask shows through the corners.
    color: "transparent"

    // Window corner radius — content is clipped to this via a MultiEffect mask.
    readonly property int cornerRadius: 14

    // ── Warm Light Palette ───────────────────────────────────────────────────
    readonly property color bgSurface:   "#f5f1ea"   // warm off-white/beige base
    readonly property color bgWhite:     "#fdfbf7"   // card surface (warm white)
    readonly property color cardBorder:  "#e4ddd0"   // soft warm border
    readonly property color textMain:    "#2a2620"   // warm near-black
    readonly property color textMuted:   "#8a8275"   // warm grey
    readonly property color outline:     "#b5ab99"   // warm outline
    readonly property color divider:     "#ece6db"   // subtle divider
    readonly property color inputBg:     "#efe9df"   // input/row bg (warm)
    readonly property color inputBdr:    "#ddd4c4"   // input border
    readonly property color accent:      "#3a3530"   // dark warm accent (buttons)
    readonly property color accentText:  "#fdfbf7"   // text on accent
    readonly property color accentHov:   "#4a443c"   // accent hover (slightly lighter)
    readonly property color danger:      "#c0492f"   // warm red
    readonly property color green:       "#5a7d4f"   // muted sage green
    readonly property color btnHov:      "#e8e1d4"   // button hover
    readonly property color dangerTint:  "#f0ddd5"   // warm danger hover tint
    readonly property color greenTint:   "#dfe7d8"   // warm sage hover tint

    // Collapsed strip tints (warm, progressively slightly deeper)
    readonly property var stripColors: ["#efe9df", "#ebe4d8", "#e6ded0"]

    // Which column is expanded (0=General, 1=Processing, 2=Providers, 3=LocalSTT)
    property int expandedCol: 0

    Component.onCompleted: {
        if (settingsViewModel) settingsViewModel.load()
    }

    // ── Provider add/edit dialog ─────────────────────────────────────────────
    Dialog {
        id: providerDialog
        property string dlgMode: "add"
        property string provType: "stt"
        property string editId: ""

        function openAdd(t) {
            dlgMode = "add"; provType = t; editId = ""
            nameField.text = ""; urlField.text = ""
            modelField.text = ""; keyField.text = ""
            quotaField.text = "-1"
            presetCombo.reloadPresets()
            open()
        }
        function openEdit(t, p) {
            dlgMode = "edit"; provType = t; editId = p.id
            nameField.text = p.name; urlField.text = p.base_url
            modelField.text = p.model
            keyField.text = settingsViewModel ? settingsViewModel.get_provider_api_key(p.id) : ""
            quotaField.text = p.quota_limit === -1 ? "-1" : p.quota_limit.toString()
            presetCombo.reloadPresets()
            open()
        }

        modal: true
        anchors.centerIn: Overlay.overlay
        width: 500
        padding: 0
        background: Rectangle {
            color: root.bgWhite
            border.color: root.cardBorder
            border.width: 1
            radius: 14
        }

        header: Item {
            height: 60
            Rectangle {
                anchors.fill: parent
                color: root.inputBg
                radius: 14
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 14
                    color: root.inputBg
                }
            }
            Text {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: (providerDialog.dlgMode === "add" ? "Add " : "Edit ")
                    + (providerDialog.provType === "stt" ? "STT" : "LLM") + " Provider"
                color: root.textMain
                font.pixelSize: 15
                font.bold: true
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.cardBorder }
        }

        contentItem: ColumnLayout {
            spacing: 0
            Item { height: 20 }

            // Preset
            ColumnLayout {
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.fillWidth: true; spacing: 6
                Text { text: "Preset"; color: root.textMuted; font.pixelSize: 12 }
                ComboBox {
                    id: presetCombo
                    Layout.fillWidth: true
                    property var plist: []
                    function reloadPresets() {
                        if (!settingsViewModel) return
                        var all = settingsViewModel.get_presets()
                        var out = [{ key: "", name: "Custom", base_url: "", model: "" }]
                        for (var i = 0; i < all.length; i++) {
                            if (all[i].provider_type === providerDialog.provType) out.push(all[i])
                        }
                        plist = out; model = out.map(function(x) { return x.name }); currentIndex = 0
                    }
                    onActivated: {
                        if (currentIndex > 0) {
                            nameField.text = plist[currentIndex].name
                            urlField.text = plist[currentIndex].base_url
                            modelField.text = plist[currentIndex].model
                        }
                    }
                    height: 36
                    background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 8 }
                    contentItem: Text { leftPadding: 10; text: presetCombo.displayText; color: root.textMain; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                    popup: Popup {
                        y: presetCombo.height; width: presetCombo.width; padding: 0
                        background: Rectangle { color: root.bgWhite; border.color: root.inputBdr; border.width: 1; radius: 8 }
                        contentItem: ListView { implicitHeight: contentHeight; model: presetCombo.delegateModel; clip: true }
                    }
                    delegate: ItemDelegate {
                        width: presetCombo.width; height: 34
                        contentItem: Text { text: modelData; color: root.textMain; font.pixelSize: 13; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: parent.hovered ? root.btnHov : "transparent" }
                    }
                }
            }

            Item { height: 14 }
            ColumnLayout {
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.fillWidth: true; spacing: 6
                Text { text: "Name"; color: root.textMuted; font.pixelSize: 12 }
                TextField {
                    id: nameField; Layout.fillWidth: true; height: 36
                    color: root.textMain; font.pixelSize: 13; placeholderText: "Provider name"
                    placeholderTextColor: root.textMuted; leftPadding: 10
                    background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 8 }
                }
            }

            Item { height: 14 }
            ColumnLayout {
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.fillWidth: true; spacing: 6
                Text { text: "Base URL"; color: root.textMuted; font.pixelSize: 12 }
                TextField {
                    id: urlField; Layout.fillWidth: true; height: 36
                    color: root.textMain; font.pixelSize: 13; placeholderText: "https://api.example.com/v1"
                    placeholderTextColor: root.textMuted; leftPadding: 10
                    background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 8 }
                }
            }

            Item { height: 14 }
            RowLayout {
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.fillWidth: true; spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text { text: "Model"; color: root.textMuted; font.pixelSize: 12 }
                    TextField {
                        id: modelField; Layout.fillWidth: true; height: 36
                        color: root.textMain; font.pixelSize: 13; placeholderText: "model-name"
                        placeholderTextColor: root.textMuted; leftPadding: 10
                        background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 8 }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text {
                        text: providerDialog.dlgMode === "edit" ? "API Key (blank = keep)" : "API Key"
                        color: root.textMuted; font.pixelSize: 12
                    }
                    TextField {
                        id: keyField; Layout.fillWidth: true; height: 36; echoMode: TextInput.Password
                        color: root.textMain; font.pixelSize: 13; placeholderText: "sk-\u2026"
                        placeholderTextColor: root.textMuted; leftPadding: 10
                        background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 8 }
                    }
                }
            }

            Item { height: 14 }
            ColumnLayout {
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.fillWidth: true; spacing: 6
                Text { text: "Daily Quota  (-1 = unlimited)"; color: root.textMuted; font.pixelSize: 12 }
                TextField {
                    id: quotaField; Layout.preferredWidth: 160; height: 36; text: "-1"
                    color: root.textMain; font.pixelSize: 13; inputMethodHints: Qt.ImhDigitsOnly; leftPadding: 10
                    background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 8 }
                }
            }

            Item { height: 12 }
            Text {
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.fillWidth: true
                text: settingsViewModel ? settingsViewModel.error_message : ""
                color: root.danger; font.pixelSize: 12; wrapMode: Text.WordWrap
                visible: text !== ""
            }
            Item { height: 20 }
        }

        footer: Item {
            height: 60
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.cardBorder }
            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                spacing: 8
                Item { Layout.fillWidth: true }
                Button {
                    text: "Cancel"; height: 36; leftPadding: 20; rightPadding: 20
                    onClicked: providerDialog.close()
                    background: Rectangle {
                        color: dlgCancelH.containsMouse ? root.btnHov : "transparent"
                        border.color: root.cardBorder; border.width: 1; radius: 8
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    contentItem: Text { text: parent.text; color: root.textMuted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    HoverHandler { id: dlgCancelH }
                }
                Button {
                    text: providerDialog.dlgMode === "add" ? "Add Provider" : "Save Changes"
                    height: 36; leftPadding: 20; rightPadding: 20
                    onClicked: {
                        if (!settingsViewModel) return
                        var q = parseInt(quotaField.text)
                        if (isNaN(q)) q = -1
                        if (providerDialog.dlgMode === "add")
                            settingsViewModel.add_provider(providerDialog.provType, nameField.text, urlField.text, modelField.text, keyField.text, q, "")
                        else
                            settingsViewModel.update_provider(providerDialog.editId, nameField.text, urlField.text, modelField.text, keyField.text, q, "")
                        if (!settingsViewModel || settingsViewModel.error_message === "") providerDialog.close()
                    }
                    background: Rectangle {
                        color: dlgSaveH.containsMouse ? root.accentHov : root.accent
                        border.color: "transparent"; radius: 8
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    HoverHandler { id: dlgSaveH }
                }
            }
        }
    } // Dialog

    // ── CONTENT ROOT — all visible UI lives here, masked to rounded corners ──
    // MultiEffect with a rounded maskSource clips EVERYTHING (including square
    // child Rectangles) to the rounded window shape. This is the verified fix
    // for sharp 90° corners showing behind a rounded background.
    Item {
        id: contentRoot
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskRect
        }

        // Rounded surface — the warm window background fill behind all content.
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: root.bgSurface
            z: -1
        }

        // ── COLUMNS ROW ─────────────────────────────────────────────────────
        Row {
            id: columnsRow
            anchors.fill: parent
            spacing: 0

            // ── COLUMN 0 — General ──────────────────────────────────────────
            Item {
                id: col0
                height: parent.height
                width: root.expandedCol === 0
                    ? (parent.width - 3 * 72)
                    : 72
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.InOutQuart } }
                clip: true

                // Background
                Rectangle {
                    anchors.fill: parent
                    color: root.expandedCol === 0 ? root.bgSurface : root.stripColors[0]
                    Behavior on color { ColorAnimation { duration: 380 } }
                }
                // Right border
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: root.cardBorder
                }

                // ── EXPANDED content (General) ──────────────────────────────
                ScrollView {
                    anchors.fill: parent
                    visible: root.expandedCol === 0
                    opacity: root.expandedCol === 0 ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: col0.width
                        spacing: 0

                        Item { height: 120 }

                        // Card: Hotkeys
                        Rectangle {
                            Layout.leftMargin: 40; Layout.rightMargin: 40; Layout.fillWidth: true
                            implicitHeight: hotkeysCardCol.implicitHeight + 64
                            color: root.bgWhite
                            border.color: root.cardBorder
                            border.width: 1
                            radius: 24

                            ColumnLayout {
                                id: hotkeysCardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 32 }
                                spacing: 0

                                // Card header
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Hotkeys"; color: root.textMain; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                                    Text { text: "\u2328"; color: root.textMuted; font.pixelSize: 20 }
                                }
                                Item { height: 24 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 20 }

                                // Dictation hotkey row
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    ColumnLayout {
                                        spacing: 4; Layout.fillWidth: true
                                        Text { text: "Dictation"; color: root.textMain; font.pixelSize: 13; font.bold: true }
                                        Text { text: "Record and paste transcript."; color: root.textMuted; font.pixelSize: 12 }
                                    }
                                    TextField {
                                        id: hotkeyField
                                        Layout.preferredWidth: 200; height: 38
                                        text: settingsViewModel ? settingsViewModel.hotkey : "ctrl+shift+space"
                                        color: root.textMain; font.pixelSize: 13; placeholderText: "ctrl+shift+space"
                                        placeholderTextColor: root.textMuted; leftPadding: 12
                                        background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 10 }
                                        Keys.onReturnPressed: { if (settingsViewModel) settingsViewModel.save_hotkey(text) }
                                    }
                                    Button {
                                        text: "Save"; height: 38; leftPadding: 18; rightPadding: 18
                                        onClicked: { if (settingsViewModel) settingsViewModel.save_hotkey(hotkeyField.text) }
                                        background: Rectangle {
                                            color: hkSaveH.containsMouse ? root.accentHov : root.accent
                                            radius: 10; Behavior on color { ColorAnimation { duration: 80 } }
                                        }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: hkSaveH }
                                    }
                                }
                                Item { height: 16 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 16 }

                                // Voice to AI hotkey row
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    ColumnLayout {
                                        spacing: 4; Layout.fillWidth: true
                                        Text { text: "Voice to AI"; color: root.textMain; font.pixelSize: 13; font.bold: true }
                                        Text { text: "Record and send to AI."; color: root.textMuted; font.pixelSize: 12 }
                                    }
                                    TextField {
                                        id: hotkeyAiField
                                        Layout.preferredWidth: 200; height: 38
                                        text: settingsViewModel ? settingsViewModel.hotkey_ai : "ctrl+shift+enter"
                                        color: root.textMain; font.pixelSize: 13; placeholderText: "ctrl+shift+enter"
                                        placeholderTextColor: root.textMuted; leftPadding: 12
                                        background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 10 }
                                        Keys.onReturnPressed: { if (settingsViewModel) settingsViewModel.save_hotkey_ai(text) }
                                    }
                                    Button {
                                        text: "Save"; height: 38; leftPadding: 18; rightPadding: 18
                                        onClicked: { if (settingsViewModel) settingsViewModel.save_hotkey_ai(hotkeyAiField.text) }
                                        background: Rectangle {
                                            color: hkAiH.containsMouse ? root.accentHov : root.accent
                                            radius: 10; Behavior on color { ColorAnimation { duration: 80 } }
                                        }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: hkAiH }
                                    }
                                }
                            } // hotkeysCardCol
                        } // Card: Hotkeys

                        Item { height: 20 }

                        // Card: Microphone
                        Rectangle {
                            Layout.leftMargin: 40; Layout.rightMargin: 40; Layout.fillWidth: true
                            implicitHeight: micCardCol.implicitHeight + 64
                            color: root.bgWhite
                            border.color: root.cardBorder
                            border.width: 1
                            radius: 24

                            ColumnLayout {
                                id: micCardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 32 }
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Microphone"; color: root.textMain; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                                    Text { text: "\uD83C\uDF99"; color: root.textMuted; font.pixelSize: 18 }
                                }
                                Item { height: 16 }
                                Text { text: "Input device for recording."; color: root.textMuted; font.pixelSize: 13 }
                                Item { height: 20 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 16 }
                                ComboBox {
                                    Layout.preferredWidth: 300; height: 40
                                    model: ["System Default"]
                                    onActivated: { if (settingsViewModel) settingsViewModel.save_microphone(-1) }
                                    background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 12 }
                                    contentItem: Text { leftPadding: 14; text: parent.displayText; color: root.textMain; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        } // Card: Microphone

                        Item { height: 32 }
                    } // ColumnLayout (General scroll content)
                } // ScrollView (General)

                // ── COLLAPSED strip (General) ───────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.expandedCol !== 0

                    Rectangle {
                        anchors.fill: parent
                        color: col0Hov.containsMouse ? root.btnHov : root.stripColors[0]
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 28
                        spacing: 1

                        Repeater {
                            model: ["G","E","N","E","R","A","L"]
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                font.letterSpacing: 0.2
                                color: col0Hov.containsMouse ? root.textMain : root.textMuted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.expandedCol = 0; cursorShape: Qt.PointingHandCursor }
                    HoverHandler { id: col0Hov }
                }
            } // col0

            // ── COLUMN 1 — Processing ───────────────────────────────────────
            Item {
                id: col1
                height: parent.height
                width: root.expandedCol === 1
                    ? (parent.width - 3 * 72)
                    : 72
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.InOutQuart } }
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: root.expandedCol === 1 ? root.bgSurface : root.stripColors[1]
                    Behavior on color { ColorAnimation { duration: 380 } }
                }
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1; color: root.cardBorder
                }

                // ── EXPANDED content (Processing) ───────────────────────────
                Item {
                    id: processingTab
                    anchors.fill: parent
                    visible: root.expandedCol === 1
                    opacity: root.expandedCol === 1 ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

                    property string editingId: ""
                    property bool isEditing: false

                    function startNew() {
                        editingId = ""; isEditing = true
                        promptNameField.text = ""; promptTextArea.text = ""
                        promptNameField.forceActiveFocus()
                    }
                    function startEdit(p) {
                        editingId = p.id; isEditing = true
                        promptNameField.text = p.name; promptTextArea.text = p.text
                    }
                    function cancelEdit() { isEditing = false; editingId = "" }
                    function saveEdit() {
                        if (!settingsViewModel) return
                        if (editingId === "") settingsViewModel.add_prompt(promptNameField.text, promptTextArea.text)
                        else settingsViewModel.update_prompt(editingId, promptNameField.text, promptTextArea.text)
                        isEditing = false; editingId = ""
                    }

                    // Body row: list + editor
                    RowLayout {
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; topMargin: 72; bottom: parent.bottom
                        }
                        spacing: 0

                        // Prompt list panel (left, 200px)
                        Rectangle {
                            Layout.preferredWidth: 200; Layout.fillHeight: true
                            color: root.inputBg
                            border.color: root.cardBorder
                            border.width: 0

                            ColumnLayout {
                                anchors.fill: parent; spacing: 0
                                Item {
                                    Layout.fillWidth: true; height: 52
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                        spacing: 8
                                        Text { text: "Prompts"; color: root.textMain; font.pixelSize: 14; font.bold: true; Layout.fillWidth: true }
                                        Button {
                                            text: "+"; width: 28; height: 28
                                            onClicked: processingTab.startNew()
                                            background: Rectangle { color: addPH.containsMouse ? root.accent : root.btnHov; radius: 6; Behavior on color { ColorAnimation { duration: 80 } } }
                                            contentItem: Text { text: parent.text; color: addPH.containsMouse ? root.accentText : root.textMain; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            HoverHandler { id: addPH }
                                        }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.cardBorder }
                                ListView {
                                    id: promptList; Layout.fillWidth: true; Layout.fillHeight: true
                                    model: settingsViewModel ? settingsViewModel.prompts : []; clip: true
                                    delegate: Item {
                                        width: promptList.width; height: 56
                                        readonly property bool isSelected: processingTab.editingId === modelData.id
                                        Rectangle { anchors.fill: parent; color: isSelected ? root.btnHov : "transparent" }
                                        Rectangle { visible: modelData.is_active; width: 3; height: parent.height; color: root.green; anchors.left: parent.left }
                                        ColumnLayout {
                                            anchors { left: parent.left; leftMargin: modelData.is_active ? 12 : 16; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                            spacing: 3
                                            Text { text: modelData.name; color: root.textMain; font.pixelSize: 13; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text {
                                                text: modelData.text.length > 40 ? modelData.text.substring(0, 40) + "\u2026" : modelData.text
                                                color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true
                                            }
                                        }
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.divider }
                                        MouseArea { anchors.fill: parent; onClicked: processingTab.startEdit(modelData) }
                                    }
                                    Text { anchors.centerIn: parent; visible: promptList.count === 0; text: "No prompts yet.\nClick + to add."; color: root.textMuted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                                }
                            }
                            Rectangle {
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: 1
                                color: root.cardBorder
                            }
                        } // prompt list panel

                        // Prompt editor (right)
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                visible: !processingTab.isEditing
                                Text { anchors.centerIn: parent; text: "Select a prompt or click + to create one"; color: root.textMuted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                                visible: processingTab.isEditing

                                Item { height: 24 }
                                ColumnLayout {
                                    Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.fillWidth: true; spacing: 6
                                    Text { text: "Name"; color: root.textMuted; font.pixelSize: 12 }
                                    TextField {
                                        id: promptNameField; Layout.fillWidth: true; height: 38
                                        color: root.textMain; font.pixelSize: 13; placeholderText: "e.g. Email, Coding\u2026"
                                        placeholderTextColor: root.textMuted; leftPadding: 12
                                        background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 10 }
                                    }
                                }
                                Item { height: 16 }
                                ColumnLayout {
                                    Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
                                    Text { text: "Prompt Text"; color: root.textMuted; font.pixelSize: 12 }
                                    ScrollView {
                                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                        background: Rectangle { color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 10 }
                                        TextArea {
                                            id: promptTextArea; color: root.textMain; font.pixelSize: 13
                                            placeholderText: "Write your system prompt here."
                                            placeholderTextColor: root.textMuted; wrapMode: TextArea.Wrap; background: null; padding: 12
                                        }
                                    }
                                }
                                Item { height: 16 }
                                RowLayout {
                                    Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.bottomMargin: 24; spacing: 8
                                    Button {
                                        text: "Save"; height: 38; leftPadding: 24; rightPadding: 24
                                        onClicked: processingTab.saveEdit()
                                        background: Rectangle { color: pSaveH.containsMouse ? root.accentHov : root.accent; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: pSaveH }
                                    }
                                    Button {
                                        visible: processingTab.editingId !== ""; text: "Set Active"; height: 38; leftPadding: 16; rightPadding: 16
                                        onClicked: { if (settingsViewModel) settingsViewModel.set_active_prompt(processingTab.editingId) }
                                        background: Rectangle { color: pActH.containsMouse ? root.greenTint : "transparent"; border.color: root.green; border.width: 1; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.green; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: pActH }
                                    }
                                    Button {
                                        visible: processingTab.editingId !== ""; text: "Delete"; height: 38; leftPadding: 16; rightPadding: 16
                                        onClicked: { if (settingsViewModel) { settingsViewModel.delete_prompt(processingTab.editingId); processingTab.cancelEdit() } }
                                        background: Rectangle { color: pDelH.containsMouse ? root.dangerTint : "transparent"; border.color: root.danger; border.width: 1; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.danger; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: pDelH }
                                    }
                                    Button {
                                        text: "Cancel"; height: 38; leftPadding: 16; rightPadding: 16
                                        onClicked: processingTab.cancelEdit()
                                        background: Rectangle { color: pCancelH.containsMouse ? root.btnHov : "transparent"; border.color: root.cardBorder; border.width: 1; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.textMuted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: pCancelH }
                                    }
                                }
                            } // editor visible
                        } // editor ColumnLayout
                    } // RowLayout (Processing body)
                } // processingTab Item

                // ── COLLAPSED strip (Processing) ────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.expandedCol !== 1

                    Rectangle {
                        anchors.fill: parent
                        color: col1Hov.containsMouse ? root.btnHov : root.stripColors[1]
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 92
                        text: "\u2736"
                        font.pixelSize: 16
                        color: col1Hov.containsMouse ? root.textMain : root.outline
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 28
                        spacing: 1

                        Repeater {
                            model: ["P","R","O","C","E","S","S","I","N","G"]
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                font.letterSpacing: 0.2
                                color: col1Hov.containsMouse ? root.textMain : root.textMuted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.expandedCol = 1; cursorShape: Qt.PointingHandCursor }
                    HoverHandler { id: col1Hov }
                }
            } // col1

            // ── COLUMN 2 — Providers ────────────────────────────────────────
            Item {
                id: col2
                height: parent.height
                width: root.expandedCol === 2
                    ? (parent.width - 3 * 72)
                    : 72
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.InOutQuart } }
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: root.expandedCol === 2 ? root.bgSurface : root.stripColors[2]
                    Behavior on color { ColorAnimation { duration: 380 } }
                }
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1; color: root.cardBorder
                }

                // ── EXPANDED content (Providers) ────────────────────────────
                ScrollView {
                    anchors.fill: parent
                    visible: root.expandedCol === 2
                    opacity: root.expandedCol === 2 ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: col2.width
                        spacing: 0

                        Item { height: 120 }

                        // Card: STT providers
                        Rectangle {
                            Layout.leftMargin: 40; Layout.rightMargin: 40; Layout.fillWidth: true
                            implicitHeight: sttCardCol.implicitHeight + 64
                            color: root.bgWhite
                            border.color: root.cardBorder
                            border.width: 1
                            radius: 24

                            ColumnLayout {
                                id: sttCardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 32 }
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        spacing: 3; Layout.fillWidth: true
                                        Text { text: "Speech-to-Text"; color: root.textMain; font.pixelSize: 20; font.bold: true }
                                        Text { text: "Providers are tried in order."; color: root.textMuted; font.pixelSize: 13 }
                                    }
                                    Button {
                                        text: "+ Add"; height: 36; leftPadding: 16; rightPadding: 16
                                        onClicked: providerDialog.openAdd("stt")
                                        background: Rectangle { color: sttAddH.containsMouse ? root.accentHov : root.accent; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: sttAddH }
                                    }
                                }
                                Item { height: 16 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 12 }

                                Repeater {
                                    model: settingsViewModel ? settingsViewModel.stt_providers : []
                                    delegate: ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        Rectangle {
                                            Layout.fillWidth: true; height: 60
                                            color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 12
                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 16; rightMargin: 10 }
                                                spacing: 8
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 3
                                                    RowLayout {
                                                        spacing: 8
                                                        Text { text: modelData.name; color: root.textMain; font.pixelSize: 13; font.bold: true }
                                                        Text { text: modelData.model; color: root.textMuted; font.pixelSize: 12 }
                                                        Item { Layout.fillWidth: true }
                                                    }
                                                    Text { text: modelData.base_url; color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                Button {
                                                    text: "Edit"; height: 30; leftPadding: 12; rightPadding: 12
                                                    onClicked: providerDialog.openEdit("stt", modelData)
                                                    background: Rectangle { color: sttEH.containsMouse ? root.btnHov : "transparent"; border.color: root.cardBorder; border.width: 1; radius: 8; Behavior on color { ColorAnimation { duration: 80 } } }
                                                    contentItem: Text { text: parent.text; color: root.textMain; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                                    HoverHandler { id: sttEH }
                                                }
                                                Button {
                                                    text: "Remove"; height: 30; leftPadding: 12; rightPadding: 12
                                                    onClicked: { if (settingsViewModel) settingsViewModel.remove_provider(modelData.id) }
                                                    background: Rectangle { color: sttRH.containsMouse ? root.dangerTint : "transparent"; border.color: root.danger; border.width: 1; radius: 8; Behavior on color { ColorAnimation { duration: 80 } } }
                                                    contentItem: Text { text: parent.text; color: root.danger; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                                    HoverHandler { id: sttRH }
                                                }
                                            }
                                        }
                                        Item { height: 8 }
                                    }
                                }
                                Text {
                                    visible: !settingsViewModel || settingsViewModel.stt_providers.length === 0
                                    text: "No providers added yet."
                                    color: root.textMuted; font.pixelSize: 13
                                }
                            } // sttCardCol
                        } // Card: STT

                        Item { height: 20 }

                        // Card: LLM providers
                        Rectangle {
                            Layout.leftMargin: 40; Layout.rightMargin: 40; Layout.fillWidth: true
                            implicitHeight: llmCardCol.implicitHeight + 64
                            color: root.bgWhite
                            border.color: root.cardBorder
                            border.width: 1
                            radius: 24

                            ColumnLayout {
                                id: llmCardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 32 }
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        spacing: 3; Layout.fillWidth: true
                                        Text { text: "Language Model"; color: root.textMain; font.pixelSize: 20; font.bold: true }
                                        Text { text: "Used for Voice to AI mode."; color: root.textMuted; font.pixelSize: 13 }
                                    }
                                    Button {
                                        text: "+ Add"; height: 36; leftPadding: 16; rightPadding: 16
                                        onClicked: providerDialog.openAdd("llm")
                                        background: Rectangle { color: llmAddH.containsMouse ? root.accentHov : root.accent; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: llmAddH }
                                    }
                                }
                                Item { height: 16 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 12 }

                                Repeater {
                                    model: settingsViewModel ? settingsViewModel.llm_providers : []
                                    delegate: ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        Rectangle {
                                            Layout.fillWidth: true; height: 60
                                            color: root.inputBg; border.color: root.inputBdr; border.width: 1; radius: 12
                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 16; rightMargin: 10 }
                                                spacing: 8
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 3
                                                    RowLayout {
                                                        spacing: 8
                                                        Text { text: modelData.name; color: root.textMain; font.pixelSize: 13; font.bold: true }
                                                        Text { text: modelData.model; color: root.textMuted; font.pixelSize: 12 }
                                                        Item { Layout.fillWidth: true }
                                                    }
                                                    Text { text: modelData.base_url; color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                Button {
                                                    text: "Edit"; height: 30; leftPadding: 12; rightPadding: 12
                                                    onClicked: providerDialog.openEdit("llm", modelData)
                                                    background: Rectangle { color: llmEH.containsMouse ? root.btnHov : "transparent"; border.color: root.cardBorder; border.width: 1; radius: 8; Behavior on color { ColorAnimation { duration: 80 } } }
                                                    contentItem: Text { text: parent.text; color: root.textMain; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                                    HoverHandler { id: llmEH }
                                                }
                                                Button {
                                                    text: "Remove"; height: 30; leftPadding: 12; rightPadding: 12
                                                    onClicked: { if (settingsViewModel) settingsViewModel.remove_provider(modelData.id) }
                                                    background: Rectangle { color: llmRH.containsMouse ? root.dangerTint : "transparent"; border.color: root.danger; border.width: 1; radius: 8; Behavior on color { ColorAnimation { duration: 80 } } }
                                                    contentItem: Text { text: parent.text; color: root.danger; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                                    HoverHandler { id: llmRH }
                                                }
                                            }
                                        }
                                        Item { height: 8 }
                                    }
                                }
                                Text {
                                    visible: !settingsViewModel || settingsViewModel.llm_providers.length === 0
                                    text: "No providers added yet."
                                    color: root.textMuted; font.pixelSize: 13
                                }
                            } // llmCardCol
                        } // Card: LLM

                        Item { height: 32 }
                    } // ColumnLayout (Providers scroll content)
                } // ScrollView (Providers)

                // ── COLLAPSED strip (Providers) ─────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.expandedCol !== 2

                    Rectangle {
                        anchors.fill: parent
                        color: col2Hov.containsMouse ? root.btnHov : root.stripColors[2]
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 92
                        text: "\u26A1"
                        font.pixelSize: 16
                        color: col2Hov.containsMouse ? root.textMain : root.outline
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 28
                        spacing: 1

                        Repeater {
                            model: ["P","R","O","V","I","D","E","R","S"]
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                font.letterSpacing: 0.2
                                color: col2Hov.containsMouse ? root.textMain : root.textMuted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.expandedCol = 2; cursorShape: Qt.PointingHandCursor }
                    HoverHandler { id: col2Hov }
                }
            } // col2

            // ── COLUMN 3 — Local STT ────────────────────────────────────────
            Item {
                id: col3
                height: parent.height
                width: root.expandedCol === 3
                    ? (parent.width - 3 * 72)
                    : 72
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.InOutQuart } }
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: root.expandedCol === 3 ? root.bgSurface : root.stripColors[2]
                    Behavior on color { ColorAnimation { duration: 380 } }
                }
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1; color: root.cardBorder
                }

                // ── EXPANDED content (Local STT) ────────────────────────────
                ScrollView {
                    anchors.fill: parent
                    visible: root.expandedCol === 3
                    opacity: root.expandedCol === 3 ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: col3.width
                        spacing: 0

                        Item { height: 120 }

                        // Card: Local STT status + controls
                        Rectangle {
                            Layout.leftMargin: 40; Layout.rightMargin: 40; Layout.fillWidth: true
                            implicitHeight: localCardCol.implicitHeight + 64
                            color: root.bgWhite
                            border.color: root.cardBorder
                            border.width: 1
                            radius: 24

                            ColumnLayout {
                                id: localCardCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 32 }
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Local STT Server"; color: root.textMain; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                                    Text { text: "\uD83C\uDF99"; color: root.textMuted; font.pixelSize: 18 }
                                }
                                Item { height: 20 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 20 }

                                // Status indicator row
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        color: {
                                            var s = settingsViewModel ? settingsViewModel.local_stt_status : "not_installed"
                                            if (s === "running") return root.green
                                            if (s === "error") return root.danger
                                            if (s === "installing" || s === "starting") return "#d99a3a"
                                            return root.outline
                                        }
                                    }
                                    Text {
                                        text: {
                                            var s = settingsViewModel ? settingsViewModel.local_stt_status : "not_installed"
                                            if (s === "not_installed") return "Not installed"
                                            if (s === "installing") return "Installing\u2026"
                                            if (s === "stopped") return "Stopped"
                                            if (s === "starting") return "Starting\u2026"
                                            if (s === "running") return "Running"
                                            if (s === "error") return "Error"
                                            return s
                                        }
                                        color: root.textMain; font.pixelSize: 14
                                    }
                                }
                                Item { height: 20 }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.divider }
                                Item { height: 20 }

                                // Action buttons
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    Button {
                                        visible: {
                                            var s = settingsViewModel ? settingsViewModel.local_stt_status : "not_installed"
                                            return s === "not_installed" || s === "error"
                                        }
                                        text: "Install"; height: 38; leftPadding: 24; rightPadding: 24
                                        onClicked: { if (settingsViewModel) settingsViewModel.install_local_stt() }
                                        background: Rectangle { color: lInstH.containsMouse ? root.accentHov : root.accent; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: lInstH }
                                    }
                                    Button {
                                        visible: settingsViewModel ? settingsViewModel.local_stt_status === "stopped" : false
                                        text: "Start"; height: 38; leftPadding: 24; rightPadding: 24
                                        onClicked: { if (settingsViewModel) settingsViewModel.start_local_stt() }
                                        background: Rectangle { color: lStartH.containsMouse ? root.accentHov : root.accent; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.accentText; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: lStartH }
                                    }
                                    Button {
                                        visible: settingsViewModel ? settingsViewModel.local_stt_status === "running" : false
                                        text: "Stop"; height: 38; leftPadding: 24; rightPadding: 24
                                        onClicked: { if (settingsViewModel) settingsViewModel.stop_local_stt() }
                                        background: Rectangle { color: lStopH.containsMouse ? root.dangerTint : "transparent"; border.color: root.danger; border.width: 1; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.danger; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: lStopH }
                                    }
                                    Button {
                                        visible: {
                                            var s = settingsViewModel ? settingsViewModel.local_stt_status : "not_installed"
                                            return s !== "not_installed"
                                        }
                                        text: "Open Folder"; height: 38; leftPadding: 20; rightPadding: 20
                                        onClicked: { if (settingsViewModel) settingsViewModel.open_local_stt_folder() }
                                        background: Rectangle { color: lFolderH.containsMouse ? root.btnHov : "transparent"; border.color: root.cardBorder; border.width: 1; radius: 10; Behavior on color { ColorAnimation { duration: 80 } } }
                                        contentItem: Text { text: parent.text; color: root.textMuted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        HoverHandler { id: lFolderH }
                                    }
                                }

                                Item { height: 20 }
                                Text {
                                    text: settingsViewModel ? settingsViewModel.local_stt_install_path : ""
                                    color: root.textMuted; font.pixelSize: 11; elide: Text.ElideLeft
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                }
                            } // localCardCol
                        } // Card: Local STT

                        Item { height: 32 }
                    } // ColumnLayout (Local STT scroll content)
                } // ScrollView (Local STT)

                // ── COLLAPSED strip (Local STT) ─────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.expandedCol !== 3

                    Rectangle {
                        anchors.fill: parent
                        color: col3Hov.containsMouse ? root.btnHov : root.stripColors[2]
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 92
                        text: "\uD83C\uDF99"
                        font.pixelSize: 16
                        color: col3Hov.containsMouse ? root.textMain : root.outline
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 28
                        spacing: 1

                        Repeater {
                            model: ["L","O","C","A","L"," ","S","T","T"]
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                font.letterSpacing: 0.2
                                color: col3Hov.containsMouse ? root.textMain : root.textMuted
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.expandedCol = 3; cursorShape: Qt.PointingHandCursor }
                    HoverHandler { id: col3Hov }
                }
            } // col3

        } // Row (columnsRow)

        // ── TOP GRADIENT OVERLAY ─────────────────────────────────────────────
        // Fixed warm gradient, z=10, sits on top of everything inside contentRoot.
        // Contains wordmark (left) + window controls (right) + drag area.
        Item {
            id: topOverlay
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 100
            z: 10

            // Gradient background — warm fade from top
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#ece4d6" }
                    GradientStop { position: 1.0; color: "#00f5f1ea" }
                }
            }

            // Wordmark — left side
            Text {
                anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                anchors.verticalCenterOffset: -10
                text: "Grain"
                color: root.textMain
                font.pixelSize: 26
                font.bold: true
                font.letterSpacing: -0.5
            }

            // Window controls — horizontal Row, top-right, Windows order: Close · Maximize · Minimize
            Item {
                id: tlItem
                anchors {
                    right: parent.right
                    rightMargin: 18
                    top: parent.top
                    topMargin: 14
                }
                width: 58
                height: 14

                property bool tlHovered: false

                Row {
                    anchors.fill: parent
                    spacing: 8

                    // Close — red
                    Rectangle {
                        width: 13; height: 13; radius: 7
                        color: tlItem.tlHovered ? "#ff5f57" : "#c8c0b0"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u00D7"
                            visible: tlItem.tlHovered
                            color: "#7a0000"
                            font.pixelSize: 9
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.close() }
                    }

                    // Maximize — green
                    Rectangle {
                        width: 13; height: 13; radius: 7
                        color: tlItem.tlHovered ? "#28c840" : "#c8c0b0"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u25A1"
                            visible: tlItem.tlHovered
                            color: "#004a10"
                            font.pixelSize: 8
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                        }
                    }

                    // Minimize — yellow
                    Rectangle {
                        width: 13; height: 13; radius: 7
                        color: tlItem.tlHovered ? "#ffbd2e" : "#c8c0b0"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u2212"
                            visible: tlItem.tlHovered
                            color: "#6b4000"
                            font.pixelSize: 9
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.showMinimized() }
                    }
                }

                HoverHandler { id: tlHov }
                Binding { target: tlItem; property: "tlHovered"; value: tlHov.containsMouse }
            } // tlItem

            // Drag area — full overlay minus button zone
            MouseArea {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width - 100
                property point clickPos
                onPressed: (mouse) => { clickPos = Qt.point(mouse.x, mouse.y) }
                onPositionChanged: (mouse) => {
                    root.x = root.x + (mouse.x - clickPos.x)
                    root.y = root.y + (mouse.y - clickPos.y)
                }
            }
        } // topOverlay

        // ── Thin rounded border overlay ──────────────────────────────────────
        // LAST child inside contentRoot so it's masked too — sits on top of all
        // content and traces the rounded window edge.
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "transparent"
            border.color: "#ddd4c4"
            border.width: 1
            z: 500
        }
    } // contentRoot

    // ── Rounded mask shape ───────────────────────────────────────────────────
    // Rendered to a hidden layer and referenced by contentRoot's MultiEffect.
    // This is what actually clips the square child Rectangles to rounded corners.
    Item {
        id: maskRect
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "black"
        }
    }
} // ApplicationWindow
