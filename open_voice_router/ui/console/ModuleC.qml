// ModuleC.qml — Processing Module
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects

Rectangle {
    id: root
    property alias inputJack: processingInputJack
    property alias outputJack: processingOutputJack
    // Shared light/dark palette, injected by ConsoleWindow.
    property var theme

    // ── Computed lists from backend ──────────────────────────────────────
    property var promptNames: {
        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        if (!vm || !vm.prompts || vm.prompts.length === 0) return ["No prompts"]
        var names = []
        for (var i = 0; i < vm.prompts.length; i++) names.push(vm.prompts[i].name)
        return names
    }
    property int activePromptIndex: {
        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        if (!vm || !vm.prompts) return 0
        for (var i = 0; i < vm.prompts.length; i++)
            if (vm.prompts[i].is_active) return i
        return 0
    }
    // All LLM providers — no cloud/custom split
    property var llmProviders: {
        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        if (!vm || !vm.llm_providers) return []
        return vm.llm_providers
    }
    property var llmProviderNames: {
        if (root.llmProviders.length === 0) return ["No providers configured"]
        var names = []
        for (var i = 0; i < root.llmProviders.length; i++) names.push(root.llmProviders[i].name)
        return names
    }

    // Smart Rotation — managed imperatively (MechanicalToggle.onClicked does
    // root.checked = !root.checked internally, so any QML binding on `checked`
    // breaks on first user click; use explicit Connections assignments instead).
    property bool smartRotation: false

    radius: 22
    color: theme.cardOuter
    border.color: theme.cardOuterBorder
    border.width: 1

    Connections {
        target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null

        function onPromptsChanged() {
            promptCombo.currentIndex = root.activePromptIndex
        }

        // Read directly from consoleViewModel (not root.llmProviders binding) so
        // we always have the freshest value when the signal fires.
        function onLlm_providers_changed() {
            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
            if (!vm) return
            var ps = vm.llm_providers
            var idx = 0
            for (var i = 0; i < ps.length; i++) {
                if (ps[i].enabled === true) { idx = i; break }
            }
            llmCombo.currentIndex = idx
            // Sync processing history (QVariantList bindings are unreliable)
            pHistoryBox._data = (vm.processing_history || []).slice().reverse()
        }

        // Explicit handler — MechanicalToggle breaks checked: binding on first click
        function onLlm_smart_rotation_changed(val) {
            root.smartRotation = val
            _llmSmartRotToggle.checked = val
        }

        function onProcessing_history_changed() {
            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
            if (vm) pHistoryBox._data = (vm.processing_history || []).slice().reverse()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 9
        anchors.topMargin: 15
        anchors.bottomMargin: 9
        spacing: 0

        // ── Module Header ───────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 40
            Layout.leftMargin: 6; Layout.rightMargin: 6
            ColumnLayout {
                anchors.fill: parent; spacing: 2
                Text { text: "MODULE C"; font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 2; color: theme.inkOnOuter(0.4) }
                Text { text: "Processing"; font.family: "Syne"; font.pixelSize: 17; font.weight: Font.ExtraBold; font.capitalization: Font.AllUppercase; font.letterSpacing: -0.3; color: theme.cardOuterTitle }
            }
        }

        // ── Travertine Pocket ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.topMargin: 9; Layout.bottomMargin: 5
            Layout.leftMargin: 3; Layout.rightMargin: 3
            radius: 14; color: theme.cardInner
            border.color: theme.cardInnerBorder; border.width: 1

            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 10; radius: 14
                gradient: Gradient {
                    GradientStop { position: 0.0; color: theme.cardInnerTopShade }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 14; anchors.bottomMargin: 0; spacing: 0

                // ── Directive Prompt ──────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4

                    Text {
                        text: "Directive Prompt"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true
                        color: theme.ink(0.45)
                    }

                    // Prompt selector ComboBox — synced with advanced panel
                    ComboBox {
                        id: promptCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        model: root.promptNames
                        currentIndex: root.activePromptIndex
                        Component.onCompleted: currentIndex = root.activePromptIndex

                        onActivated: {
                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                            if (!vm || !vm.prompts || index >= vm.prompts.length) return
                            vm.set_active_prompt(vm.prompts[index].id)
                        }

                        background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                        contentItem: Text {
                            leftPadding: 10; rightPadding: 28
                            text: promptCombo.displayText
                            font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.inputText
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                        }
                        indicator: Text {
                            x: promptCombo.width - width - 10
                            y: Math.round((promptCombo.height - height) / 2)
                            text: "▾"; font.pixelSize: 10; color: theme.inputText
                        }
                        popup: Popup {
                            y: promptCombo.height + 2; width: promptCombo.width; padding: 4
                            background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                            contentItem: ListView {
                                clip: true; implicitHeight: Math.min(contentHeight, 180)
                                model: promptCombo.count; currentIndex: promptCombo.currentIndex
                                delegate: ItemDelegate {
                                    width: ListView.view ? ListView.view.width : 0; height: 32
                                    contentItem: Text {
                                        leftPadding: 10
                                        text: promptCombo.textAt(index)
                                        font.pixelSize: 10; font.weight: Font.DemiBold; color: theme.inputText
                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                    }
                                    background: Rectangle { radius: 4; color: index === promptCombo.currentIndex ? Qt.rgba(0.545,0.361,0.965,0.15) : "transparent" }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { promptCombo.currentIndex = index; promptCombo.activated(index); promptCombo.popup.close() }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── Vocabulary Dictionary ─────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 98
                    radius: 8
                    color: theme.fill(0.04); border.color: theme.fill(0.04); border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

                        // Header + input row
                        RowLayout {
                            Layout.fillWidth: true; spacing: 14

                            ColumnLayout {
                                spacing: 1
                                Text { text: "Add to dictionary"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.9) }
                                Text { text: "Press enter to add"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                            }

                            // Input field — fills remaining width after the label column
                            Rectangle {
                                Layout.fillWidth: true; height: 28; radius: 5
                                color: theme.fill(0.05)
                                border.color: wordInput.activeFocus ? "#FF5D1E" : theme.fill(0.14)
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                TextInput {
                                    id: wordInput
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    verticalAlignment: Text.AlignVCenter
                                    font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                    color: theme.inputText; clip: true

                                    Text {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        text: "type word…"; font.family: "JetBrains Mono"; font.pixelSize: 9
                                        color: theme.ink(0.35)
                                        visible: parent.text.length === 0 && !parent.activeFocus
                                    }

                                    Keys.onReturnPressed: {
                                        var w = text.trim()
                                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        if (w.length > 0 && vm) { vm.add_word(w); text = "" }
                                    }
                                }
                            }
                        }

                        // Horizontally scrollable word chips (newest leftmost)
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "no words added yet"
                                font.family: "JetBrains Mono"; font.pixelSize: 8
                                color: theme.ink(0.35)
                                visible: {
                                    var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                    return !vm || !vm.word_dictionary || vm.word_dictionary.length === 0
                                }
                            }

                            Flickable {
                                id: chipFlickable
                                width: parent.width; height: 22
                                anchors.verticalCenter: parent.verticalCenter
                                contentWidth: chipInnerRow.implicitWidth
                                contentHeight: 22
                                flickableDirection: Flickable.HorizontalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                visible: {
                                    var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                    return vm !== null && vm.word_dictionary !== null && vm.word_dictionary.length > 0
                                }

                                WheelHandler {
                                    onWheel: function(event) {
                                        var delta = event.angleDelta.x !== 0 ? -event.angleDelta.x : -event.angleDelta.y
                                        chipFlickable.contentX = Math.max(0, Math.min(
                                            Math.max(0, chipFlickable.contentWidth - chipFlickable.width),
                                            chipFlickable.contentX + delta / 120 * 50
                                        ))
                                        event.accepted = true
                                    }
                                }

                                Row {
                                    id: chipInnerRow
                                    spacing: 5

                                    Repeater {
                                        // Reverse: newest word shown leftmost
                                        model: {
                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                            if (!vm || !vm.word_dictionary) return []
                                            var arr = []
                                            for (var i = vm.word_dictionary.length - 1; i >= 0; i--)
                                                arr.push(vm.word_dictionary[i])
                                            return arr
                                        }

                                        Rectangle {
                                            height: 22; width: _wLabel.implicitWidth + 16; radius: 5
                                            color: _chipH.containsMouse === true ? theme.fill(0.08) : theme.fill(0.05)
                                            border.color: theme.fill(0.08); border.width: 1
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            HoverHandler { id: _chipH }

                                            Row {
                                                anchors.centerIn: parent; spacing: 4

                                                Text {
                                                    id: _wLabel
                                                    text: modelData
                                                    font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                                    color: theme.ink(0.75)
                                                }

                                                Text {
                                                    text: "×"; font.pixelSize: 11
                                                    color: _chipH.containsMouse === true ? theme.ink(0.7) : theme.ink(0.3)
                                                    visible: _chipH.containsMouse === true
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                    MouseArea {
                                                        anchors.fill: parent; anchors.margins: -3
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                                            if (vm) vm.remove_word(modelData)
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

                Item { Layout.preferredHeight: 8 }

                // ── Processor LLM ─────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3

                    Component.onCompleted: {
                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                        if (!vm) return
                        // Init smart rotation state imperatively
                        root.smartRotation = vm.llm_smart_rotation
                        _llmSmartRotToggle.checked = vm.llm_smart_rotation
                        // Pre-select the enabled provider
                        var ps = vm.llm_providers
                        for (var i = 0; i < ps.length; i++) {
                            if (ps[i].enabled === true) { llmCombo.currentIndex = i; break }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text {
                            text: "Processor LLM"
                            font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.5
                            color: theme.ink(0.45)
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            width: 80; height: 28; radius: 8
                            color: theme.fill(0.1)
                            border.color: theme.fill(0.05); border.width: 1

                            RowLayout {
                                anchors.fill: parent; anchors.margins: 2; spacing: 2

                                Rectangle {
                                    id: _lclLlmBtn
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                                    property bool lclMode: false
                                    color: lclMode ? "#8B5CF6" : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent; text: "XIX"
                                        font.family: "JetBrains Mono"; font.pixelSize: 10; font.bold: true
                                        color: _lclLlmBtn.lclMode ? "#ffffff" : theme.ink(0.5)
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                                    color: !_lclLlmBtn.lclMode ? "#8B5CF6" : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent; text: "LLM"
                                        font.family: "JetBrains Mono"; font.pixelSize: 10; font.bold: true
                                        color: !_lclLlmBtn.lclMode ? "#ffffff" : theme.ink(0.5)
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Unified provider dropdown — single-select OFF, multi-select (circles) ON
                    ComboBox {
                        id: llmCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        model: root.llmProviderNames
                        currentIndex: 0

                        background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                        contentItem: Text {
                            leftPadding: 10; rightPadding: 28
                            text: llmCombo.displayText
                            font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.inputText
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            opacity: root.llmProviderNames[0] === "No providers configured" ? 0.45 : 1.0
                        }
                        indicator: Text {
                            x: llmCombo.width - width - 10
                            y: Math.round((llmCombo.height - height) / 2)
                            text: "▾"; font.pixelSize: 10; color: theme.inputText
                        }
                        popup: Popup {
                            y: llmCombo.height + 2; width: llmCombo.width; padding: 4
                            background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                            contentItem: ListView {
                                id: _llmListView
                                clip: true; implicitHeight: Math.min(contentHeight, 180)
                                model: llmCombo.count; currentIndex: llmCombo.currentIndex
                                delegate: Item {
                                    width: _llmListView.width; height: 32

                                    Rectangle {
                                        anchors.fill: parent; radius: 4
                                        color: (!root.smartRotation && index === llmCombo.currentIndex)
                                               ? Qt.rgba(0.545, 0.361, 0.965, 0.15) : "transparent"
                                    }

                                    Text {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter
                                                  right: _llmRotCircle.left; rightMargin: 6 }
                                        text: llmCombo.textAt(index)
                                        font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.inputText
                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                    }

                                    Item {
                                        id: _llmRotCircle
                                        width: 20; height: 20
                                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        visible: root.smartRotation

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 16; height: 16; radius: 8
                                            color: "transparent"
                                            border.color: theme.ink(0.30)
                                            border.width: 1.5
                                        }
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10; radius: 5
                                            color: "#FF5D1E"
                                            visible: {
                                                var ps = root.llmProviders
                                                return index < ps.length && ps[index].enabled === true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                            var ps = root.llmProviders
                                            if (root.smartRotation) {
                                                if (vm && index < ps.length)
                                                    vm.set_llm_provider_enabled(ps[index].id, !(ps[index].enabled === true))
                                            } else {
                                                llmCombo.currentIndex = index
                                                llmCombo.popup.close()
                                                if (vm && index < ps.length)
                                                    vm.set_llm_provider_enabled(ps[index].id, true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── LLM error banner ─────────────────────────────────
                    Rectangle {
                        id: _llmErrBanner
                        Layout.fillWidth: true; Layout.topMargin: 4
                        implicitHeight: _llmErrText.implicitHeight + 14
                        radius: 6
                        color: Qt.rgba(0.8, 0.15, 0.15, 0.10)
                        border.color: Qt.rgba(0.8, 0.15, 0.15, 0.30); border.width: 1
                        visible: {
                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                            return vm && vm.llm_error_message && vm.llm_error_message.length > 0
                        }
                        Text {
                            id: _llmErrText
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                      leftMargin: 10; rightMargin: 10 }
                            text: {
                                var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                return vm ? (vm.llm_error_message || "") : ""
                            }
                            font.family: "JetBrains Mono"; font.pixelSize: 8
                            color: Qt.rgba(0.85, 0.25, 0.25, 0.95)
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Smart Rotation toggle
                    Rectangle {
                        Layout.fillWidth: true; Layout.topMargin: 5; height: 52; radius: 8
                        color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1
                        Item {
                            anchors.fill: parent; anchors.margins: 12
                            ColumnLayout {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { text: "Smart Rotate"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                Text { text: "Round-robin routing"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                            }
                            MechanicalToggle {
                                id: _llmSmartRotToggle
                                trackColor: theme.toggleTrack
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                // checked is NOT bound declaratively — MechanicalToggle breaks QML
                                // bindings by self-assigning inside onClicked. Managed via
                                // Component.onCompleted + Connections.onLlm_smart_rotation_changed.
                                onToggled: {
                                    var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                    if (vm) vm.set_llm_smart_rotation(checked)
                                }
                            }
                        }
                    }
                }

                // ── Processing History ────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.topMargin: 14; Layout.bottomMargin: 8; spacing: 2

                    Text {
                        text: "PROCESSED"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.5
                        color: theme.ink(0.45); Layout.leftMargin: 2
                    }

                    Rectangle {
                        id: pHistoryBox
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 40
                        radius: 8; color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1; clip: true

                        // Explicit local copy — same pattern as ModuleB's transcription history.
                        // Declarative bindings on QVariantList are unreliable for ListView updates.
                        property var _data: []

                        Component.onCompleted: {
                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                            if (vm) pHistoryBox._data = (vm.processing_history || []).slice().reverse()
                        }

                        Text {
                            anchors.centerIn: parent; text: "No history yet"
                            font.family: "JetBrains Mono"; font.pixelSize: 10
                            color: theme.ink(0.4)
                            visible: pHistoryBox._data.length === 0
                        }

                        ListView {
                            anchors.fill: parent; anchors.margins: 4; clip: true; spacing: 2
                            ScrollIndicator.vertical: ScrollIndicator { }
                            model: pHistoryBox._data
                            delegate: Rectangle {
                                width: ListView.view.width; height: 26; radius: 6
                                color: pRowHov.hovered ? theme.fill(0.04) : "transparent"
                                HoverHandler { id: pRowHov }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 8
                                    Text { text: modelData.time; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.4); Layout.alignment: Qt.AlignVCenter }
                                    Text { text: modelData.text; font.family: "JetBrains Mono"; font.pixelSize: 9; color: theme.ink(0.85); elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 24
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: theme.historyFade }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }
                Rectangle { Layout.fillWidth: true; height: 1; color: theme.fill(0.10) }

                Item { Layout.preferredHeight: 8 }

                // ── Input / Output Jacks ──────────────────────────────
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 54
                    RowLayout {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10; spacing: 4
                        Rectangle {
                            width: 104; height: 46; radius: 8
                            gradient: Gradient { GradientStop { position: 0.0; color: theme.jackHousingTop } GradientStop { position: 1.0; color: theme.jackHousingBottom } }
                            border.color: theme.fill(0.1); border.width: 1
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 8
                                Jack { id: processingInputJack; jackColor: "#10B981"; jackId: "modulec.input"; size: 34 }
                                Text { text: "INPUT"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2; color: "#10B981"; Layout.fillWidth: true }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 104; height: 46; radius: 8
                            gradient: Gradient { GradientStop { position: 0.0; color: theme.jackHousingTop } GradientStop { position: 1.0; color: theme.jackHousingBottom } }
                            border.color: theme.fill(0.1); border.width: 1
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
                                Text { text: "OUTPUT"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2; color: "#8B5CF6"; Layout.fillWidth: true }
                                Jack { id: processingOutputJack; jackColor: "#8B5CF6"; jackId: "modulec.output"; activeSink: true; size: 34 }
                            }
                        }
                    }
                }
            }
        }

        // ── Module Footer ───────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 16
            Layout.leftMargin: 6; Layout.rightMargin: 6
            RowLayout {
                anchors.fill: parent; spacing: 0
                Text { text: "CACHE: ACTIVE_RAM"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.inkOnOuter(0.4); Layout.fillWidth: true }
                Text { text: "TYPE: CHAT-LLM"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.inkOnOuter(0.4) }
            }
        }
    }
}
