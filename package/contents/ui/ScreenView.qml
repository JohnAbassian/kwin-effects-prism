/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick.Window
import QtQuick3D
import org.kde.kwin as KWinComponents

// Per-output scene: camera, stacked prisms, switch animation, overview input.

Item {
    id: root
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property QtObject currentDesktop: KWinComponents.Workspace.currentDesktop
    readonly property int gridWidth: Math.max(1, KWinComponents.Workspace.desktopGridWidth || 1)
    readonly property real angleTick: 360 / root.gridWidth
    readonly property real faceDisplacement: effect.finiteNumber(effect.configuration ? effect.configuration.FaceDisplacement : NaN, 0)
    readonly property real faceDistance: {
        const width = Math.max(1, root.width);
        return 0.5 * width / Math.tan(root.angleTick * Math.PI / 360) + root.faceDisplacement;
    }
    // Face height is the screen height; keep a small gap so the next/previous
    // row stays in the zoomed-out field of view instead of overlapping or flying off-screen.
    readonly property real prismPitch: Math.max(1, root.height) * 1.12
    readonly property real windowFloat: Math.max(0, effect.finiteNumber(effect.configuration ? effect.configuration.WindowFloat : NaN, 40))
    readonly property real desktopRadius: {
        const fov = camera.fieldOfView * Math.PI / 180;
        return root.faceDistance + 0.5 * Math.max(1, root.height) / Math.tan(0.5 * fov);
    }
    readonly property real distantRadius: {
        const factor = effect.finiteNumber(effect.configuration ? effect.configuration.DistanceFactor : NaN, 1);
        const zoom = factor >= 1 ? factor : 1;
        // 1.00 is the original default zoom-out (15% further than close-up framing).
        return root.desktopRadius * 1.15 * zoom;
    }
    readonly property real floatAmount: {
        const near = root.desktopRadius;
        const far = root.distantRadius;
        if (!(far > near)) {
            return effect.interactive ? 1 : 0;
        }
        const t = (cameraController.radius - near) / (far - near);
        return Math.max(0, Math.min(1, t));
    }

    property int lastToken: -1
    property bool running: false
    property real switchYaw: 0

    onSwitchYawChanged: {
        if (root.running) {
            cameraController.setOrientation(effect.switchElevation, switchYaw);
        }
    }

    BackgroundLayer {
        anchors.fill: parent
        z: 0
        style: effect.finiteNumber(effect.configuration ? effect.configuration.BackgroundStyle : NaN, 1)
        color1: effect.configuration.BackgroundColor || "#212427"
        color2: effect.configuration.BackgroundColor2 || "#0a1020"
    }

    View3D {
        id: view
        anchors.fill: parent
        z: 1
        renderMode: View3D.Offscreen

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            depthPrePassEnabled: true
        }

        PerspectiveCamera {
            id: camera
            clipNear: 10.0
            clipFar: Math.max(8000, cameraController.radius * 6 + root.faceDistance + 2000)
        }

        Cube {
            id: cube
            faceDisplacement: root.faceDisplacement
            faceSize: Qt.size(Math.max(1, root.width), Math.max(1, root.height))
            viewRow: effect.viewRow
            rowShift: effect.rowShift
            cameraYaw: cameraController.yawAngle
            prismPitch: root.prismPitch
            windowFloat: root.windowFloat * root.floatAmount
        }
    }

    CubeCameraController {
        id: cameraController
        anchors.fill: parent
        z: 10
        camera: camera
        dragEnabled: effect.interactive
        inertia: effect.inertia
        state: {
            if (root.running) {
                return "";
            }
            return effect.interactive ? "distant" : "close";
        }

        states: [
            State {
                name: "close"
                PropertyChanges {
                    target: cameraController
                    radius: root.desktopRadius
                    rotation: Quaternion.fromEulerAngles(effect.switchElevation, root.landingYaw(), 0)
                }
            },
            State {
                name: "distant"
                PropertyChanges {
                    target: cameraController
                    radius: root.distantRadius
                }
            }
        ]

        Behavior on rotation {
            enabled: !cameraController.freezeRotation && !cameraController.busy && !root.running
            QuaternionAnimation {
                duration: effect.animationDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on radius {
            enabled: !root.running
            NumberAnimation {
                duration: effect.animationDuration
                easing.type: Easing.OutCubic
            }
        }

        onTapped: (x, y) => root.pickDesktop(x, y)

        function rotateToLeft() {
            const eulerAngles = rotation.toEulerAngles();
            let next = Math.floor(eulerAngles.y / root.angleTick) * root.angleTick;
            if (Math.abs(next - eulerAngles.y) < 0.05 * root.angleTick) {
                next -= root.angleTick;
            }
            rotation = Quaternion.fromEulerAngles(eulerAngles.x, next, 0);
        }

        function rotateToRight() {
            const eulerAngles = rotation.toEulerAngles();
            let next = Math.ceil(eulerAngles.y / root.angleTick) * root.angleTick;
            if (Math.abs(next - eulerAngles.y) < 0.05 * root.angleTick) {
                next += root.angleTick;
            }
            rotation = Quaternion.fromEulerAngles(eulerAngles.x, next, 0);
        }
    }

    Binding {
        target: root.Window.window
        property: "color"
        value: effect.configuration.BackgroundColor2 || effect.configuration.BackgroundColor || "#0a1020"
    }

    ParallelAnimation {
        id: switchAnimation

        NumberAnimation {
            id: yawAnimation
            target: root
            property: "switchYaw"
            duration: effect.animationDuration
            easing.type: Easing.InOutCubic
        }

        NumberAnimation {
            id: rowAnimation
            target: effect
            property: "rowShift"
            duration: effect.animationDuration
            easing.type: Easing.InOutCubic
        }

        SequentialAnimation {
            NumberAnimation {
                id: zoomOutAnimation
                target: cameraController
                property: "radius"
                duration: Math.max(25, effect.animationDuration / 2)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                id: zoomInAnimation
                target: cameraController
                property: "radius"
                duration: Math.max(25, effect.animationDuration / 2)
                easing.type: Easing.InCubic
            }
        }

        onFinished: {
            root.switchYaw = root.normalizedYaw(root.switchYaw);
            cameraController.snapOrientation(effect.switchElevation, root.switchYaw);
            effect.setCenteredRow(effect.desktopRow(effect.toDesktop || root.currentDesktop));
            effect.switchRunning = false;
            root.running = false;
            if (effect.interactive) {
                return;
            }
            const current = KWinComponents.Workspace.currentDesktopForScreen(root.targetScreen);
            if (effect.toDesktop === current || effect.toDesktop === null) {
                effect.deactivate();
            }
        }
    }

    function pickDesktop(x, y) {
        const hitResult = view.pick(x, y);
        if (hitResult.objectHit && hitResult.objectHit.desktop) {
            root.switchTo(hitResult.objectHit.desktop);
            return;
        }
        root.switchToSelected();
    }

    function viewedDesktop() {
        return cube.desktopAt(cameraController.yawAngle);
    }

    function landingYaw() {
        const desktop = root.currentDesktop;
        if (!desktop) {
            return root.normalizedYaw(cameraController.yawAngle);
        }
        return root.normalizedYaw(cube.desktopAzimuth(desktop));
    }

    function switchTo(desktop) {
        if (!desktop) {
            return;
        }
        effect.setCenteredRow(effect.desktopRow(desktop));
        cameraController.setOrientation(effect.switchElevation, cube.desktopAzimuth(desktop));
        KWinComponents.Workspace.setCurrentDesktopForScreen(desktop, root.targetScreen);
        effect.deactivate();
    }

    function switchToSelected() {
        root.switchTo(root.viewedDesktop());
    }

    function normalizedYaw(yaw) {
        yaw = ((yaw % 360) + 360) % 360;
        if (yaw > 359.5) {
            yaw = 0;
        }
        return yaw;
    }

    function currentAzimuth() {
        return root.normalizedYaw(cube.desktopAzimuth(root.currentDesktop));
    }

    function startSwitch() {
        if (effect.interactive) {
            return;
        }
        if (root.width <= 0 || root.height <= 0 || root.gridWidth < 2 || !effect.toDesktop) {
            return;
        }
        if (root.lastToken === effect.animationToken && root.running) {
            return;
        }
        if (!root.running && !effect.fromDesktop) {
            return;
        }

        const from = root.running ? cube.desktopAt(root.switchYaw) : effect.fromDesktop;
        const to = effect.toDesktop;
        const steps = cube.ringSteps(from, to, effect.rotateAllTheWay);
        const fromRow = effect.desktopRow(from);
        const toRow = effect.desktopRow(to);
        effect.viewRow = fromRow;
        if (!root.running) {
            effect.rowShift = fromRow;
        }

        const close = root.desktopRadius;
        const far = root.distantRadius;
        const startYaw = root.normalizedYaw(root.running ? root.switchYaw : cube.desktopAzimuth(from));
        const endYaw = startYaw + steps * root.angleTick;

        switchAnimation.stop();
        effect.switchRunning = true;
        root.running = true;
        root.switchYaw = startYaw;
        cameraController.snapOrientation(effect.switchElevation, startYaw);
        if (root.lastToken !== effect.animationToken) {
            cameraController.radius = close;
        }

        yawAnimation.from = startYaw;
        yawAnimation.to = endYaw;
        rowAnimation.from = effect.rowShift;
        rowAnimation.to = toRow;
        zoomOutAnimation.from = cameraController.radius;
        zoomOutAnimation.to = far;
        zoomInAnimation.from = far;
        zoomInAnimation.to = close;

        root.lastToken = effect.animationToken;
        switchAnimation.start();
    }

    Keys.onEscapePressed: effect.deactivate()
    Keys.onEnterPressed: {
        if (effect.interactive) {
            root.switchToSelected();
        }
    }
    Keys.onReturnPressed: {
        if (effect.interactive) {
            root.switchToSelected();
        }
    }
    Keys.onSpacePressed: {
        if (effect.interactive) {
            root.switchToSelected();
        }
    }
    Keys.onPressed: (event) => {
        if (!effect.interactive) {
            return;
        }
        if (event.key === Qt.Key_Left) {
            cameraController.rotateToLeft();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            cameraController.rotateToRight();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            effect.shiftViewRow(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            effect.shiftViewRow(1);
            event.accepted = true;
        }
    }

    Connections {
        target: effect
        function onAnimationTokenChanged() {
            root.startSwitch();
        }
        function onVisibleChanged() {
            if (effect.visible) {
                if (effect.interactive) {
                    cameraController.snapOrientation(effect.overviewElevation, root.currentAzimuth());
                    root.forceActiveFocus();
                } else {
                    root.startSwitch();
                }
            } else {
                switchAnimation.stop();
                root.running = false;
                effect.switchRunning = false;
            }
        }
        function onInteractiveChanged() {
            if (effect.interactive) {
                switchAnimation.stop();
                root.running = false;
                effect.switchRunning = false;
                cameraController.snapOrientation(effect.overviewElevation, root.currentAzimuth());
                root.forceActiveFocus();
            } else {
                effect.setCenteredRow(effect.desktopRow(root.currentDesktop));
            }
        }
        function onCommitViewedChanged() {
            if (effect.interactive) {
                root.switchToSelected();
            }
        }
    }

    Connections {
        target: KWinComponents.Workspace
        function onCurrentDesktopChanged() {
            if (!effect.interactive || root.running) {
                return;
            }
            effect.setCenteredRow(effect.desktopRow(root.currentDesktop));
            cameraController.setOrientation(cameraController.pitch(), cube.desktopAzimuth(root.currentDesktop));
        }
    }

    Component.onCompleted: {
        effect.setCenteredRow(effect.desktopRow(root.currentDesktop));
        if (effect.interactive) {
            cameraController.snapOrientation(effect.overviewElevation, root.currentAzimuth());
        } else {
            root.startSwitch();
        }
    }
}
