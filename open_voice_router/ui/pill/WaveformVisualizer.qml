// WaveformVisualizer.qml
import QtQuick 2.15

Item {
    id: root

    property real amplitudeLevel: 0.0

    implicitWidth: barRow.implicitWidth
    implicitHeight: 32

    readonly property var barMultipliers: [
        0.55, 0.70, 0.85, 0.95, 1.00, 0.90, 0.78, 0.65,
        0.60, 0.75, 0.88, 0.97, 1.00, 0.92, 0.80, 0.68,
        0.58, 0.73, 0.86, 0.94, 0.98, 0.89, 0.76, 0.62
    ]

    Row {
        id: barRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: 24

            Rectangle {
                readonly property real multiplier: root.barMultipliers[index]
                readonly property real targetHeight: Math.max(3, root.amplitudeLevel * root.height * multiplier)

                width: 3
                height: targetHeight
                radius: 2
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter

                Behavior on height {
                    NumberAnimation {
                        duration: 60
                        easing.type: Easing.OutQuad
                    }
                }

                Component.onCompleted: height = targetHeight
                onTargetHeightChanged: height = targetHeight
            }
        }
    }
}
