/*
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick

Item {
    id: root

    property int style: 1  // 0 solid, 1 vertical gradient, 2 radial, 3 horizon
    property color color1: "#212427"
    property color color2: "#0a1020"

    Rectangle {
        anchors.fill: parent
        visible: root.style === 0
        color: root.color1
    }

    Rectangle {
        anchors.fill: parent
        visible: root.style === 1
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.color1 }
            GradientStop { position: 1.0; color: root.color2 }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.style === 2
        color: root.color2

        Rectangle {
            width: Math.max(parent.width, parent.height) * 1.15
            height: width
            radius: width / 2
            anchors.centerIn: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.color1 }
                GradientStop { position: 0.55; color: Qt.rgba(root.color1.r, root.color1.g, root.color1.b, 0.45) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: root.style === 3
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Qt.darker(root.color2, 1.25)
        }

        Rectangle {
            width: parent.width * 1.2
            height: parent.height * 0.7
            radius: width
            opacity: 0.55
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -height * 0.35
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.color1 }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Rectangle {
            width: parent.width * 0.9
            height: parent.height * 0.55
            radius: width
            opacity: 0.4
            anchors.right: parent.right
            anchors.rightMargin: -width * 0.25
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -height * 0.2
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.color2 }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(root.color1.r, root.color1.g, root.color1.b, 0.35) }
                GradientStop { position: 0.5; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(root.color2.r, root.color2.g, root.color2.b, 0.8) }
            }
        }
    }
}