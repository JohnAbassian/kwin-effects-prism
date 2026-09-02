/*
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import "WindowState.js" as WindowState

// Animation clock for a window sent to another desktop. The card itself is
// drawn on the faces (WindowPieces) so it slides on the hull and wraps
// around the edge instead of cutting through the prism.
Node {
    id: flight

    required property var window
    required property size faceSize

    property bool active: false
    property real localT: 0
    property real fromAz: 0
    property real deltaAz: 0
    property real fromRow: 0
    property real deltaRow: 0
    property int fromCol: 0
    property int colSteps: 0
    property int rowSteps: 0
    property real startAt: 0

    readonly property real t: {
        if (!active) {
            return 0;
        }
        const prism = flight.prismT();
        if (prism !== null) {
            return WindowState.clamp01(prism);
        }
        return flight.localT;
    }

    function unwrapToward(value, target) {
        let out = value;
        while (out - target > 180) {
            out -= 360;
        }
        while (target - out > 180) {
            out += 360;
        }
        return out;
    }

    function azimuthT() {
        if (Math.abs(deltaAz) < 0.01) {
            return null;
        }
        const mid = fromAz + 0.5 * deltaAz;
        const yaw = flight.unwrapToward(cube.cameraYaw, mid);
        const progress = (yaw - fromAz) / deltaAz;
        if (progress < -0.08 || progress > 1.08) {
            return null;
        }
        if (effect.switchRunning || progress > 0.002) {
            return progress;
        }
        return null;
    }

    function rowT() {
        if (Math.abs(deltaRow) < 0.001) {
            return null;
        }
        const progress = (cube.rowShift - fromRow) / deltaRow;
        if (progress < -0.08 || progress > 1.08) {
            return null;
        }
        if (effect.switchRunning || Math.abs(progress) > 0.002) {
            return progress;
        }
        return null;
    }

    function prismT() {
        const az = flight.azimuthT();
        const row = flight.rowT();
        if (az !== null && Math.abs(deltaAz) >= Math.abs(deltaRow) * cube.angleTick) {
            return az;
        }
        if (row !== null) {
            return row;
        }
        return az;
    }

    function publish() {
        if (!active) {
            cube.setFlight(effect.windowId(window), null);
            return;
        }
        cube.setFlight(effect.windowId(window), {
            t: flight.t,
            fromCol: flight.fromCol,
            fromRow: flight.fromRow,
            colSteps: flight.colSteps,
            rowSteps: flight.rowSteps
        });
    }

    function finish() {
        if (!active) {
            return;
        }
        localAnim.stop();
        active = false;
        localT = 0;
        cube.setFlight(effect.windowId(window), null);
        effect.setFlying(window, false);
    }

    function tryStart() {
        const job = effect.takeFlightFor(flight.window);
        if (job) {
            flight.start(job.fromDesktop, job.toDesktop);
        }
    }

    function start(fromDesktop, toDesktop) {
        if (!window || !fromDesktop || !toDesktop || WindowState.sameDesktop(fromDesktop, toDesktop)) {
            return;
        }
        if (window.minimized || WindowState.isDesktopChrome(window)) {
            effect.setFlying(window, false);
            return;
        }
        fromCol = cube.columnOf(fromDesktop);
        fromRow = cube.rowOf(fromDesktop);
        colSteps = cube.ringSteps(fromDesktop, toDesktop, !effect.interactive && effect.rotateAllTheWay);
        rowSteps = cube.rowOf(toDesktop) - fromRow;
        fromAz = cube.desktopAzimuth(fromDesktop);
        deltaAz = colSteps * cube.angleTick;
        deltaRow = rowSteps;
        localT = 0;
        localAnim.stop();
        startAt = Date.now();
        active = true;
        effect.setFlying(window, true);
        flight.publish();
        if (flight.prismT() === null) {
            localAnim.restart();
        }
    }

    onTChanged: {
        if (!active) {
            return;
        }
        if (flight.prismT() !== null && localAnim.running) {
            localAnim.stop();
        }
        flight.publish();
        if (t >= 0.999 && Date.now() - startAt > 40) {
            finish();
        }
    }

    NumberAnimation {
        id: localAnim
        target: flight
        property: "localT"
        duration: effect.animationDuration
        from: 0
        to: 1
        easing.type: Easing.InOutCubic
        onFinished: {
            if (flight.active && flight.prismT() === null) {
                flight.finish();
            }
        }
    }

    Connections {
        target: effect
        function onFlightTokenChanged() {
            flight.tryStart();
        }
        function onSwitchRunningChanged() {
            if (!flight.active) {
                flight.tryStart();
                return;
            }
            if (effect.switchRunning) {
                localAnim.stop();
                return;
            }
            if (flight.t >= 0.999) {
                flight.finish();
            }
        }
    }

    Component.onCompleted: flight.tryStart()
}
