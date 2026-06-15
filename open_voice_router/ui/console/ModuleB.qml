// ModuleB.qml — Transcription Module
import QtQuick 2.15
import QtQuick.Controls.Basic 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects

Rectangle {
    id: root
    property alias inputJack: transcriptionInputJack
    property alias outputJack: transcriptionOutputJack
    // Shared light/dark palette, injected by ConsoleWindow.
    property var theme

    // ── Unload idle mapping (mirrors the advanced panel exactly) ──────────
    readonly property var unloadValuesMs: [
        0,
        5  * 60 * 1000,
        10 * 60 * 1000,
        15 * 60 * 1000,
        30 * 60 * 1000,
        60 * 60 * 1000,
        24 * 60 * 60 * 1000,
        -1
    ]
    readonly property var unloadLabels: ["Instant", "5 min", "10 min", "15 min", "30 min", "1 hr", "24 hr", "Never"]

    function unloadIndexForMs(ms) {
        for (var i = 0; i < unloadValuesMs.length; i++)
            if (unloadValuesMs[i] === ms) return i
        return 1  // default → 5 min
    }

    // Cloud-only providers (local 127.0.0.1 / localhost filtered out)
    property var cloudProviders: {
        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        if (!vm || !vm.stt_providers) return []
        return vm.stt_providers.filter(function(p) {
            var u = p.base_url || ""
            return u.indexOf("127.0.0.1") === -1 && u.indexOf("localhost") === -1
        })
    }
    property var cloudProviderNames: {
        var ps = root.cloudProviders
        return ps.length > 0 ? ps.map(function(p) { return p.name }) : ["No providers yet"]
    }

    // Smart Rotation — purely reactive binding; never assign directly or the binding breaks
    // Changes from EITHER panel update consoleViewModel → this re-evaluates automatically
    readonly property bool smartRotation: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                           ? consoleViewModel.stt_smart_rotation : false

    radius: 22
    color: theme.cardOuter
    border.color: theme.cardOuterBorder
    border.width: 1

    // Keep controls in sync when backend state changes
    Connections {
        target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        function onLocal_stt_unload_idle_changed(ms) {
            unloadCombo.currentIndex = root.unloadIndexForMs(ms)
        }
        function onStt_providers_changed() {
            // Rebuild cloud-only list
            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
            if (!vm) return
            var ps = vm.stt_providers.filter(function(p) {
                var u = p.base_url || ""
                return u.indexOf("127.0.0.1") === -1 && u.indexOf("localhost") === -1
            })
            root.cloudProviders = ps
            root.cloudProviderNames = ps.length > 0 ? ps.map(function(p) { return p.name }) : ["No providers yet"]
            // Sync combo index to the currently-enabled cloud provider
            for (var i = 0; i < ps.length; i++) {
                if (ps[i].enabled === true) { cloudProviderCombo.currentIndex = i; break }
            }
        }
        function onStt_local_enabled_changed(val) {
            localSttBtn.sttLocalMode = val
        }
        // Note: onStt_smart_rotation_changed is NOT needed — root.smartRotation
        // is a readonly binding so it auto-updates when the ViewModel changes.
    }

    Component.onCompleted: {
        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
        if (!vm) return
        localSttBtn.sttLocalMode = vm.stt_local_enabled
        // Pre-select the enabled cloud provider in the combo
        var ps = root.cloudProviders
        for (var i = 0; i < ps.length; i++) {
            if (ps[i].enabled === true) { cloudProviderCombo.currentIndex = i; break }
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
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Layout.leftMargin: 6
            Layout.rightMargin: 6

            ColumnLayout {
                anchors.fill: parent
                spacing: 2
                Text { text: "MODULE B"; font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 2; color: theme.inkOnOuter(0.4) }
                Text { text: "Transcription"; font.family: "Syne"; font.pixelSize: 17; font.weight: Font.ExtraBold; font.capitalization: Font.AllUppercase; font.letterSpacing: -0.3; color: theme.cardOuterTitle }
            }
        }

        // ── Travertine Pocket ───────────────────────────────────────────
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

            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: 10; radius: 14
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

                // ── Aura Core Monitor ─────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Aura Core Monitor"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2
                        color: theme.ink(0.45)
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 140
                        radius: 8; color: "#120500"
                        border.color: Qt.rgba(1.000, 0.365, 0.118, 0.25); border.width: 1
                        clip: true
                        DotMatrixDisplay { anchors.fill: parent }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── Model Route ──────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    // LCL / CLD header row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: "Model Route"
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
                                    id: localSttBtn
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                                    color: sttLocalMode ? "#FF5D1E" : "transparent"
                                    property bool sttLocalMode: true
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent; text: "LCL"
                                        font.family: "JetBrains Mono"; font.pixelSize: 10; font.bold: true
                                        color: localSttBtn.sttLocalMode ? "#ffffff" : theme.ink(0.5)
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                            if (vm) vm.set_stt_local_enabled(true)
                                            else localSttBtn.sttLocalMode = true
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                                    color: !localSttBtn.sttLocalMode ? "#FF5D1E" : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent; text: "CLD"
                                        font.family: "JetBrains Mono"; font.pixelSize: 10; font.bold: true
                                        color: !localSttBtn.sttLocalMode ? "#ffffff" : theme.ink(0.5)
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                            if (vm) {
                                                // Enable the cloud provider currently shown in the dropdown
                                                var ps = root.cloudProviders
                                                if (ps.length > 0) {
                                                    var idx = cloudProviderCombo.currentIndex
                                                    if (idx < 0 || idx >= ps.length) idx = 0
                                                    vm.set_stt_provider_enabled(ps[idx].id, true)
                                                } else {
                                                    vm.set_stt_local_enabled(false)
                                                }
                                            } else {
                                                localSttBtn.sttLocalMode = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── LOCAL model dropdown ──────────────────────────
                    // Driven by the backend model registry; selecting persists
                    // the choice and retargets the sidecar (same backend slot
                    // the Advanced panel's picker uses).
                    ComboBox {
                        id: localModelCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        visible: localSttBtn.sttLocalMode
                        // Greyed out when smart rotation is ON (local not available)
                        opacity: root.smartRotation ? 0.45 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        readonly property var catalog:
                            (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                ? consoleViewModel.local_stt_models : []
                        function selectedIndex() {
                            if (typeof consoleViewModel === "undefined" || !consoleViewModel) return 0
                            for (var i = 0; i < catalog.length; i++)
                                if (catalog[i].id === consoleViewModel.local_stt_model_id) return i
                            return 0
                        }

                        model: catalog.map(function(m) { return m.name })
                        currentIndex: selectedIndex()
                        onActivated: function(index) {
                            if (typeof consoleViewModel !== "undefined" && consoleViewModel
                                    && index >= 0 && index < catalog.length)
                                consoleViewModel.save_local_stt_model(catalog[index].id)
                        }
                        // Keep in sync when the model is switched from the
                        // Advanced panel (binding breaks after user interaction).
                        Connections {
                            target: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        ? consoleViewModel : null
                            function onLocal_stt_model_changed() {
                                localModelCombo.currentIndex = localModelCombo.selectedIndex()
                            }
                        }

                        background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                        contentItem: RowLayout {
                            spacing: 6
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 28; verticalCenter: parent.verticalCenter }

                            // Status dot
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: {
                                    var s = (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            ? consoleViewModel.local_stt_status : "not_installed"
                                    if (s === "running")   return "#10B981"
                                    if (s === "error")     return "#EF4444"
                                    if (s === "installing" || s === "starting") return "#FF5D1E"
                                    if (s === "stopped")   return theme.ink(0.35)
                                    return theme.ink(0.18)
                                }
                            }

                            Text {
                                text: localModelCombo.displayText
                                font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.inputText
                                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        indicator: Text {
                            x: localModelCombo.width - width - 10
                            y: Math.round((localModelCombo.height - height) / 2)
                            text: "▾"; font.pixelSize: 10; color: theme.inputText
                        }
                        popup: Popup {
                            y: localModelCombo.height + 2; width: localModelCombo.width; padding: 4
                            background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                            contentItem: ListView {
                                clip: true; implicitHeight: Math.min(contentHeight, 180)
                                model: localModelCombo.count; currentIndex: localModelCombo.currentIndex
                                delegate: ItemDelegate {
                                    width: ListView.view ? ListView.view.width : 0; height: 32
                                    contentItem: RowLayout {
                                        spacing: 6
                                        // Installed marker: green = weights cached locally,
                                        // hollow = will download on first load.
                                        Rectangle {
                                            Layout.leftMargin: 10
                                            width: 6; height: 6; radius: 3
                                            color: (localModelCombo.catalog[index] && localModelCombo.catalog[index].installed)
                                                   ? "#10B981" : "transparent"
                                            border.color: (localModelCombo.catalog[index] && localModelCombo.catalog[index].installed)
                                                   ? "#10B981" : theme.ink(0.3)
                                            border.width: 1
                                        }
                                        Text {
                                            text: localModelCombo.textAt(index)
                                            font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.inputText
                                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            visible: !(localModelCombo.catalog[index] && localModelCombo.catalog[index].installed)
                                            text: "↓"
                                            rightPadding: 8
                                            font.pixelSize: 10; color: theme.ink(0.4)
                                        }
                                    }
                                    background: Rectangle { radius: 4; color: index === localModelCombo.currentIndex ? Qt.rgba(1.0,0.365,0.118,0.15) : "transparent" }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { localModelCombo.currentIndex = index; localModelCombo.activated(index); localModelCombo.popup.close() } }
                                }
                            }
                        }
                    }

                    // ── CLOUD provider dropdown ───────────────────────
                    // Smart rotation OFF → single-select (radio).
                    // Smart rotation ON  → multi-select; each row shows a radio circle;
                    //                       popup stays open so user can toggle multiple.
                    ComboBox {
                        id: cloudProviderCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        visible: !localSttBtn.sttLocalMode
                        model: root.cloudProviderNames
                        currentIndex: 0

                        background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                        contentItem: Text {
                            leftPadding: 10; rightPadding: 28
                            text: cloudProviderCombo.displayText
                            font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.inputText
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            opacity: root.cloudProviderNames[0] === "No providers yet" ? 0.45 : 1.0
                        }
                        indicator: Text {
                            x: cloudProviderCombo.width - width - 10
                            y: Math.round((cloudProviderCombo.height - height) / 2)
                            text: "▾"; font.pixelSize: 10; color: theme.inputText
                        }
                        popup: Popup {
                            y: cloudProviderCombo.height + 2; width: cloudProviderCombo.width; padding: 4
                            background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                            contentItem: ListView {
                                id: _cloudListView
                                clip: true; implicitHeight: Math.min(contentHeight, 180)
                                model: cloudProviderCombo.count; currentIndex: cloudProviderCombo.currentIndex
                                delegate: Item {
                                    width: _cloudListView.width; height: 32

                                    // Row background — highlight current in single-select mode
                                    Rectangle {
                                        anchors.fill: parent; radius: 4
                                        color: (!root.smartRotation && index === cloudProviderCombo.currentIndex)
                                               ? Qt.rgba(1.0, 0.365, 0.118, 0.15) : "transparent"
                                    }

                                    // Provider name
                                    Text {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter
                                                  right: _rotCircle.left; rightMargin: 6 }
                                        text: cloudProviderCombo.textAt(index)
                                        font.pixelSize: 11; font.weight: Font.DemiBold; color: theme.inputText
                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                    }

                                    // Radio circle — visible only in smart-rotation mode
                                    Item {
                                        id: _rotCircle
                                        width: 20; height: 20
                                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        visible: root.smartRotation

                                        // Outer ring
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 16; height: 16; radius: 8
                                            color: "transparent"
                                            border.color: theme.ink(0.30)
                                            border.width: 1.5
                                        }
                                        // Orange fill — shown when this provider is enabled in pool
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10; radius: 5
                                            color: "#FF5D1E"
                                            visible: {
                                                var ps = root.cloudProviders
                                                return index < ps.length && ps[index].enabled === true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                            var ps = root.cloudProviders
                                            if (root.smartRotation) {
                                                // Multi-select: toggle this provider in/out of the rotation pool
                                                if (vm && index < ps.length)
                                                    vm.set_stt_provider_enabled(ps[index].id, !(ps[index].enabled === true))
                                                // Popup stays open for multi-toggle
                                            } else {
                                                // Single-select: enable this one, close popup
                                                cloudProviderCombo.currentIndex = index
                                                cloudProviderCombo.popup.close()
                                                if (vm && index < ps.length)
                                                    vm.set_stt_provider_enabled(ps[index].id, true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── LOCAL: Real-time + Unload side by side ────────
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 5; spacing: 8
                        visible: localSttBtn.sttLocalMode
                        // Greyed out when smart rotation is ON
                        opacity: root.smartRotation ? 0.45 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        // Launch on startup — pre-load the selected local model
                        // at app launch. Wired to the shared view model; stays in
                        // sync with the advanced panel's "Load on Startup" row.
                        Rectangle {
                            Layout.fillWidth: true; height: 52; radius: 8
                            color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1
                            Item {
                                anchors.fill: parent; anchors.margins: 10
                                ColumnLayout {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { text: "Launch"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                    Text { text: "Load on start"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                                }
                                MechanicalToggle {
                                    trackColor: theme.toggleTrack
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    value: (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                        ? consoleViewModel.local_stt_load_on_startup : false
                                    onToggled: {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            consoleViewModel.save_load_on_startup(checked)
                                    }
                                }
                            }
                        }

                        // Unload — wired to backend, stays in sync via Connections above
                        Rectangle {
                            Layout.fillWidth: true; height: 52; radius: 8
                            color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1
                            Item {
                                anchors.fill: parent; anchors.margins: 10
                                ColumnLayout {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { text: "Unload"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                    Text { text: "Auto-idle"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                                }
                                ComboBox {
                                    id: unloadCombo
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    width: 68; height: 26
                                    model: root.unloadLabels
                                    Component.onCompleted: {
                                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        currentIndex = vm ? root.unloadIndexForMs(vm.local_stt_unload_idle_ms) : 1
                                    }
                                    onActivated: {
                                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        if (vm) vm.save_unload_idle_ms(root.unloadValuesMs[currentIndex])
                                    }
                                    background: Rectangle { radius: 5; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                                    contentItem: Text {
                                        leftPadding: 5; rightPadding: 16; text: unloadCombo.displayText
                                        font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true
                                        color: theme.inputText; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                    }
                                    indicator: Text {
                                        x: unloadCombo.width - width - 5
                                        y: Math.round((unloadCombo.height - height) / 2)
                                        text: "▾"; font.pixelSize: 9; color: theme.inputText
                                    }
                                    popup: Popup {
                                        y: unloadCombo.height + 2; width: 100; padding: 4
                                        background: Rectangle { radius: 6; color: theme.inputBg; border.color: theme.fill(0.1); border.width: 1 }
                                        contentItem: ListView {
                                            clip: true; implicitHeight: Math.min(contentHeight, 220)
                                            model: unloadCombo.count; currentIndex: unloadCombo.currentIndex
                                            delegate: ItemDelegate {
                                                width: ListView.view ? ListView.view.width : 0; height: 28
                                                contentItem: Text { leftPadding: 8; text: unloadCombo.textAt(index); font.family: "JetBrains Mono"; font.pixelSize: 9; font.bold: true; color: theme.inputText; verticalAlignment: Text.AlignVCenter }
                                                background: Rectangle { radius: 4; color: index === unloadCombo.currentIndex ? Qt.rgba(1.0,0.365,0.118,0.15) : "transparent" }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { unloadCombo.currentIndex = index; unloadCombo.activated(index); unloadCombo.popup.close() }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── CLOUD: Real-time + Smart Rotation side by side ─
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 5; spacing: 8
                        visible: !localSttBtn.sttLocalMode

                        // Real-time — locked OFF, coming soon
                        Rectangle {
                            Layout.fillWidth: true; height: 52; radius: 8
                            color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1
                            Item {
                                anchors.fill: parent; anchors.margins: 10
                                ColumnLayout {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { text: "Real-time"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                    Text { text: "coming soon"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.4) }
                                }
                                MechanicalToggle {
                                    trackColor: theme.toggleTrack
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    checked: false
                                    onToggled: { if (checked) checked = false }
                                }
                            }
                        }

                        // Smart Rotation — functional toggle
                        Rectangle {
                            Layout.fillWidth: true; height: 52; radius: 8
                            color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1
                            Item {
                                anchors.fill: parent; anchors.margins: 10
                                ColumnLayout {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { text: "Smart Rotate"; font.pixelSize: 11; font.bold: true; color: theme.ink(0.85) }
                                    Text { text: "Provider fallback"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.45) }
                                }
                                MechanicalToggle {
                                    trackColor: theme.toggleTrack
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    // Controlled by the shared viewmodel — survives the click
                                    // self-assign so it stays in sync with the advanced panel.
                                    value: root.smartRotation
                                    onToggled: {
                                        if (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                            consoleViewModel.set_stt_smart_rotation(checked)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Transcription History ─────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.topMargin: 14; Layout.bottomMargin: 8; spacing: 2

                    Text {
                        text: "TRANSCRIBED"
                        font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.5
                        color: theme.ink(0.45); Layout.leftMargin: 2
                    }

                    Rectangle {
                        id: txHistoryBox
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 40
                        radius: 8; color: theme.fill(0.04); border.color: theme.fill(0.05); border.width: 1; clip: true

                        // Explicit local copy — updated by Connections below.
                        // This is more reliable than a declarative binding on
                        // QVariantList because it guarantees re-assignment every
                        // time the notify signal fires.
                        property var _data: []

                        Component.onCompleted: {
                            var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                            if (vm) txHistoryBox._data = (vm.transcription_history || []).slice().reverse()
                        }

                        Connections {
                            target: (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                            function onTranscription_history_changed() {
                                txHistoryBox._data = (consoleViewModel.transcription_history || []).slice().reverse()
                            }
                        }

                        Text {
                            anchors.centerIn: parent; text: "No history yet"
                            font.family: "JetBrains Mono"; font.pixelSize: 10
                            color: theme.ink(0.4)
                            visible: txHistoryBox._data.length === 0
                        }

                        ListView {
                            anchors.fill: parent; anchors.margins: 4; clip: true; spacing: 2
                            ScrollIndicator.vertical: ScrollIndicator { }
                            model: txHistoryBox._data
                            delegate: Rectangle {
                                id: histRow
                                width: ListView.view.width; height: 26; radius: 6
                                color: rowHov.hovered ? theme.fill(0.05) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                property bool _copied: false

                                HoverHandler { id: rowHov }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel) ? consoleViewModel : null
                                        if (vm) {
                                            vm.copy_to_clipboard(modelData.text)
                                            histRow._copied = true
                                            _copyReset.restart()
                                        }
                                    }
                                }

                                Timer { id: _copyReset; interval: 1100; onTriggered: histRow._copied = false }

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: rowHov.hovered ? 28 : 8 }
                                    spacing: 8
                                    Behavior on anchors.rightMargin { NumberAnimation { duration: 130 } }
                                    Text { text: modelData.time; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.ink(0.4); Layout.alignment: Qt.AlignVCenter }
                                    // Single-line preview: collapse any newlines/whitespace runs so a
                                    // multi-line result never expands the row (see ModuleC history).
                                    Text { text: (modelData.text || "").replace(/\s+/g, " ").trim(); font.family: "JetBrains Mono"; font.pixelSize: 9; color: theme.ink(0.85); wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                                }

                                // Copy icon — fades in on hover, swaps to ✓ on copy
                                Item {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 7 }
                                    width: 14; height: 14
                                    opacity: rowHov.hovered ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    // Two stacked document outlines = copy icon
                                    Item {
                                        anchors.fill: parent
                                        visible: !histRow._copied
                                        Rectangle { x: 3; y: 0; width: 9; height: 11; radius: 2; color: "transparent"; border.color: theme.ink(0.5); border.width: 1.3 }
                                        Rectangle { x: 0; y: 3; width: 9; height: 11; radius: 2; color: "transparent"; border.color: theme.ink(0.5); border.width: 1.3 }
                                    }

                                    // Checkmark after copy
                                    Text {
                                        anchors.centerIn: parent
                                        visible: histRow._copied
                                        text: "✓"; font.pixelSize: 11; font.bold: true
                                        color: Qt.rgba(0.18, 0.58, 0.25, 0.9)
                                    }
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
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 8
                                Jack { id: transcriptionInputJack; jackColor: "#FF5D1E"; jackId: "moduleb.input"; size: 34 }
                                Text { text: "INPUT"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2; color: "#FF5D1E"; Layout.fillWidth: true }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 104; height: 46; radius: 8
                            gradient: Gradient { GradientStop { position: 0.0; color: theme.jackHousingTop } GradientStop { position: 1.0; color: theme.jackHousingBottom } }
                            border.color: theme.fill(0.1); border.width: 1
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
                                Text { text: "OUTPUT"; font.family: "JetBrains Mono"; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1.2; color: "#10B981"; Layout.fillWidth: true }
                                Jack { id: transcriptionOutputJack; jackColor: "#10B981"; jackId: "moduleb.output"; activeSink: true; size: 34 }
                            }
                        }
                    }
                }
            }
        }

        // ── Module Footer ───────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 18
            Layout.leftMargin: 6; Layout.rightMargin: 6
            RowLayout {
                anchors.fill: parent; spacing: 0
                Text {
                    text: {
                        var vm = (typeof consoleViewModel !== "undefined" && consoleViewModel)
                                 ? consoleViewModel : null
                        if (!vm || vm.local_stt_status === "not_installed")
                            return "MODEL: NONE"
                        // Short id of the selected registry model, e.g.
                        // "PARAKEET-TDT-0.6B-V3" or "CANARY-180M-FLASH".
                        return "MODEL: " + (vm.local_stt_model_id || "").toUpperCase()
                    }
                    font.family: "JetBrains Mono"; font.pixelSize: 8
                    color: theme.inkOnOuter(0.4); Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text { text: "TYPE: AUDIO-STT"; font.family: "JetBrains Mono"; font.pixelSize: 8; color: theme.inkOnOuter(0.4) }
            }
        }
    }
}
