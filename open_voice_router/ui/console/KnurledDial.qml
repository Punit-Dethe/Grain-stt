// KnurledDial.qml — Rotary knob control
import QtQuick 2.15

Item {
    id: root
    
    property real value: 0.45  // 0.0 to 1.0
    property int size: 20
    property color indicatorColor: "#ff5d1e"
    
    signal dialValueChanged(real newValue)
    
    width: size
    height: size

    // Dial body
    Rectangle {
        id: dialBody
        anchors.fill: parent
        radius: width / 2
        color: "#3a3530"
        
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#5a5349" }
            GradientStop { position: 0.8; color: "#1c1a17" }
        }
        
        border.color: "#000"
        border.width: 1

        // Position indicator line
        Rectangle {
            id: indicator
            width: 2
            height: parent.height * 0.4
            radius: width / 2
            color: root.indicatorColor
            
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 2
            
            transformOrigin: Item.Bottom
            
            rotation: -135 + (root.value * 270)
            
            Behavior on rotation {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeVerCursor
            
            property real startY: 0
            property real startValue: 0
            
            onPressed: {
                startY = mouse.y
                startValue = root.value
                cursorShape = Qt.ClosedHandCursor
            }
            
            onPositionChanged: {
                if (pressed) {
                    var delta = (startY - mouse.y) / 100.0
                    var newValue = Math.max(0.0, Math.min(1.0, startValue + delta))
                    
                    if (Math.abs(newValue - root.value) > 0.001) {
                        root.value = newValue
                        root.dialValueChanged(newValue)
                    }
                }
            }
            
            onReleased: {
                cursorShape = Qt.SizeVerCursor
            }
        }
    }
}
