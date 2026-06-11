// Jack.qml — Eurorack-style jack socket component
import QtQuick 2.15

Item {
    id: root
    
    property color jackColor: "#FF5D1E"
    property bool activeSink: false
    property string jackId: ""
    property int size: 28
    
    signal clicked()
    signal dragStarted(var jack, real sceneX, real sceneY)
    signal dragMoved(var jack, real sceneX, real sceneY)
    signal dragEnded(var jack, real sceneX, real sceneY)
    
    width: size
    height: size

    // Main jack body
    Rectangle {
        id: jackBody
        anchors.fill: parent
        radius: width / 2
        color: "#2a2420"
        
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#555" }
            GradientStop { position: 0.75; color: "#1c1a17" }
        }

        // Inner socket hole
        Rectangle {
            anchors.centerIn: parent
            width: 14
            height: 14
            radius: width / 2
            color: "#0d0c0b"
        }

        // Active sink pulse ring
        Rectangle {
            anchors.centerIn: parent
            width: 38
            height: 38
            radius: width / 2
            color: "transparent"
            border.color: root.jackColor
            border.width: 2
            visible: root.activeSink
            opacity: pulseAnim.running ? 0.8 : 0

            SequentialAnimation on opacity {
                id: pulseAnim
                running: root.activeSink
                loops: Animation.Infinite
                
                NumberAnimation {
                    from: 1.0
                    to: 0.0
                    duration: 1600
                    easing.type: Easing.OutCubic
                }
            }

            SequentialAnimation on scale {
                running: root.activeSink
                loops: Animation.Infinite
                
                NumberAnimation {
                    from: 0.9
                    to: 1.3
                    duration: 1600
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            
            onEntered: jackBody.scale = 1.08
            onExited: jackBody.scale = 1.0
            onPressed: (mouse) => {
                var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
                root.dragStarted(root, scenePoint.x, scenePoint.y)
            }
            onPositionChanged: (mouse) => { if (pressed) {
                var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
                root.dragMoved(root, scenePoint.x, scenePoint.y)
            } }
            onReleased: (mouse) => {
                var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
                root.dragEnded(root, scenePoint.x, scenePoint.y)
            }
            onClicked: root.clicked()
        }

        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }
}
