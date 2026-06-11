// MechanicalToggle.qml — Hardware-style toggle switch
import QtQuick 2.15

Item {
    id: root
    
    property bool checked: false
    property color activeColor: "#ff5d1e"
    // Track colour — themed by the caller (black on a light well, charcoal on a
    // dark well) so the switch reads correctly in both light and dark modes.
    property color trackColor: "#000000"

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
