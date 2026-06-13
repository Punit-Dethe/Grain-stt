// MechanicalToggle.qml — Hardware-style toggle switch
import QtQuick 2.15

Item {
    id: root

    property bool checked: false
    property color activeColor: "#ff5d1e"
    // Track colour — themed by the caller (black on a light well, charcoal on a
    // dark well) so the switch reads correctly in both light and dark modes.
    property color trackColor: "#000000"

    // ── Controlled mode (optional) ──────────────────────────────────────────
    // Clicking self-assigns `checked`, which BREAKS a plain `checked:` binding
    // to a model — after the first click the visual can desync from the source
    // of truth (the classic "both toggles show ON" bug in a provider list).
    // When the caller binds `value` to the authoritative state instead, we
    // re-sync `checked` to it on every change (survives the self-assign), so
    // the switch always reflects the model. Leave `value` unset for the legacy
    // uncontrolled behaviour.
    property var value: undefined
    onValueChanged: if (value !== undefined) checked = (value === true)
    Component.onCompleted: if (value !== undefined) checked = (value === true)

    signal toggled()

    width: 32
    height: 18

    // Track
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
        Behavior on color { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }

        // Lever
        Rectangle {
            id: lever
            width: 14
            height: 14
            radius: width / 2
            x: root.checked ? parent.width - width - 2 : 2
            y: 2
            
            color: root.checked ? root.activeColor : "#bbb"
            
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.checked ? root.activeColor : "#eee" }
                GradientStop { position: 1.0; color: root.checked ? Qt.darker(root.activeColor, 1.2) : "#bbb" }
            }

            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutCubic
                }
            }

            Behavior on color {
                ColorAnimation { duration: 200 }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.checked = !root.checked
                root.toggled()
            }
        }
    }
}
