/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D

// Orbit camera for overview drag, fling, and scripted switch yaw.

Item {
    id: root

    readonly property bool busy: status.useMouse || status.coasting

    signal tapped(real x, real y)

    required property Camera camera

    property quaternion rotation: Quaternion.fromEulerAngles(0, 0, 0)
    readonly property real yawAngle: root.rotation.toEulerAngles().y
    property real radius: 2000
    property bool dragEnabled: true
    property real inertia: 0

    property real xSpeed: 10
    property real ySpeed: 10
    property real minElevation: -60
    property real maxElevation: 60
    property bool freezeRotation: false  // one-frame guard so Behavior does not fight a snap

    Keys.forwardTo: [parent]

    implicitWidth: parent.width
    implicitHeight: parent.height

    onRotationChanged: root.updateCamera();
    onRadiusChanged: root.updateCamera();
    onDragEnabledChanged: {
        if (!root.dragEnabled) {
            root.stopCoast();
        }
    }

    DragHandler {
        id: dragHandler
        enabled: root.dragEnabled
        target: null
        acceptedModifiers: Qt.NoModifier
        onCentroidChanged: {
            mouseMoved(Qt.vector2d(centroid.position.x, centroid.position.y));
        }

        onActiveChanged: {
            if (active) {
                mousePressed(Qt.vector2d(centroid.position.x, centroid.position.y));
            } else {
                const press = status.pressPos;
                const release = Qt.vector2d(centroid.position.x, centroid.position.y);
                const dx = release.x - press.x;
                const dy = release.y - press.y;
                mouseReleased();
                if ((dx * dx + dy * dy) < 64) {
                    root.stopCoast();
                    root.tapped(press.x, press.y);
                }
            }
        }
    }

    WheelHandler {
        id: wheelHandler
        enabled: root.dragEnabled
        orientation: Qt.Vertical
        target: null
        onWheel: event => {
            let delta = (event.inverted ? -1 : 1) * event.angleDelta.y * 0.01;
            root.radius += root.radius * 0.1 * delta;
        }
    }

    TapHandler {
        enabled: root.dragEnabled
        acceptedButtons: Qt.LeftButton
        onTapped: root.tapped(point.position.x, point.position.y)
    }

    function mousePressed(newPos) {
        root.forceActiveFocus();
        root.stopCoast();
        status.currentPos = newPos;
        status.lastPos = newPos;
        status.pressPos = newPos;
        status.azimuthVel = 0;
        status.elevationVel = 0;
        status.useMouse = true;
    }

    function mouseReleased() {
        status.useMouse = false;
        const speed2 = status.azimuthVel * status.azimuthVel + status.elevationVel * status.elevationVel;
        if (root.inertia > 0.001 && speed2 > 25) {
            status.coasting = true;
        } else {
            root.stopCoast();
        }
    }

    function mouseMoved(newPos) {
        status.currentPos = newPos;
    }

    function stopCoast() {
        status.coasting = false;
        status.azimuthVel = 0;
        status.elevationVel = 0;
    }

    function updateCamera() {
        const eulerRotation = root.rotation.toEulerAngles();
        const theta = (eulerRotation.x + 90) * Math.PI / 180;
        const phi = eulerRotation.y * Math.PI / 180;

        camera.position = Qt.vector3d(radius * Math.sin(phi) * Math.sin(theta),
                                      radius * Math.cos(theta),
                                      radius * Math.cos(phi) * Math.sin(theta));
        camera.rotation = root.rotation;
    }

    function pitch() {
        return root.rotation.toEulerAngles().x;
    }

    function setOrientation(pitchDegrees, yawDegrees) {
        root.rotation = Quaternion.fromEulerAngles(pitchDegrees, yawDegrees, 0);
    }

    function snapOrientation(pitchDegrees, yawDegrees) {
        root.stopCoast();
        root.freezeRotation = true;
        root.setOrientation(pitchDegrees, yawDegrees);
        unfreezeTimer.restart();
    }

    function applyRotation(azimuthDelta, elevationDelta) {
        const eulerRotation = root.rotation.toEulerAngles();
        const azimuth = eulerRotation.y + azimuthDelta;
        let elevation = eulerRotation.x + elevationDelta;
        if (elevation < root.minElevation) {
            elevation = root.minElevation;
            status.elevationVel = 0;
        } else if (elevation > root.maxElevation) {
            elevation = root.maxElevation;
            status.elevationVel = 0;
        }
        root.rotation = Quaternion.fromEulerAngles(elevation, azimuth, 0);
    }

    FrameAnimation {
        running: root.busy
        onTriggered: status.processInput(frameTime);
    }

    Timer {
        id: unfreezeTimer
        interval: 1
        onTriggered: root.freezeRotation = false
    }

    QtObject {
        id: status

        property bool useMouse: false
        property bool coasting: false
        property vector2d lastPos: Qt.vector2d(0, 0)
        property vector2d currentPos: Qt.vector2d(0, 0)
        property vector2d pressPos: Qt.vector2d(0, 0)
        property real azimuthVel: 0
        property real elevationVel: 0

        function processInput(dt) {
            if (dt <= 0) {
                return;
            }
            if (useMouse) {
                const pixelDelta = Qt.vector2d(lastPos.x - currentPos.x,
                                               lastPos.y - currentPos.y);
                lastPos = currentPos;
                const instantAz = pixelDelta.x * xSpeed;
                const instantEl = pixelDelta.y * ySpeed;
                azimuthVel = azimuthVel * 0.65 + instantAz * 0.35;
                elevationVel = elevationVel * 0.65 + instantEl * 0.35;
                root.applyRotation(instantAz * dt, instantEl * dt);
                return;
            }
            if (!coasting) {
                return;
            }
            root.applyRotation(azimuthVel * dt, elevationVel * dt);
            const tau = 0.18 + root.inertia * 1.7;
            const decay = Math.exp(-dt / tau);
            azimuthVel *= decay;
            elevationVel *= decay;
            if ((azimuthVel * azimuthVel + elevationVel * elevationVel) < 4) {
                root.stopCoast();
            }
        }
    }
}