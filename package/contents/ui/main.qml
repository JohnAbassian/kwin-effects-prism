/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import org.kde.kwin as KWinComponents
import "WindowState.js" as WindowState

// SceneEffect root. ScreenView is the per-output 3D scene.
// Peek is an IPC counter written by prism-toggle (Meta+C): odd/even edges
// toggle overview because the kcfg write is not a reliable QML notify.
KWinComponents.SceneEffect {
    id: effect

    delegate: ScreenView {}

    readonly property int animationDuration: Math.max(50, effect.finiteNumber(effect.configuration ? effect.configuration.Duration : NaN, 750) || 750)
    readonly property real overviewElevation: effect.finiteNumber(effect.configuration ? effect.configuration.OverviewElevation : NaN, 0)
    readonly property real switchElevation: effect.finiteNumber(effect.configuration ? effect.configuration.SwitchElevation : NaN, 0)
    readonly property int peekMirror: effect.finiteNumber(effect.configuration ? effect.configuration.Peek : NaN, 0)
    readonly property bool rotateAllTheWay: effect.isTruthy(effect.configuration ? effect.configuration.RotateAllTheWay : false)
    readonly property real inertia: {
        const n = effect.finiteNumber(effect.configuration ? effect.configuration.Inertia : NaN, 0);
        if (n <= 0) {
            return 0;
        }
        return Math.min(1, n);
    }
    readonly property int gridWidth: Math.max(1, KWinComponents.Workspace.desktopGridWidth || 1)
    readonly property int gridHeight: Math.max(1, KWinComponents.Workspace.desktopGridHeight || 1)

    property bool interactive: false
    property bool switchRunning: false
    property var fromDesktop: null
    property var toDesktop: null
    property int animationToken: 0
    property var lastDesktop: KWinComponents.Workspace.currentDesktop

    // viewRow is the integer pager row used for picking; rowShift is the
    // animated Y offset so up/down slides instead of snapping.
    property int viewRow: 0
    property real rowShift: 0

    Behavior on rowShift {
        enabled: effect.interactive && !effect.switchRunning
        NumberAnimation {
            duration: effect.animationDuration
            easing.type: Easing.InOutCubic
        }
    }

    property int commitViewed: 0
    property int lastPeek: -999999

    property var flightQueue: []
    property int flightToken: 0
    // flyingIds is a new object each update; flyingRev forces QML bindings
    // that call isFlying() to re-run (object mutation is not notifiable).
    property var flyingIds: ({})
    property int flyingRev: 0

    function finiteNumber(value, fallback) {
        const n = Number(value);
        return n === n ? n : fallback;
    }

    function isTruthy(value) {
        return value === true || value === 1 || value === "true" || value === "1";
    }

    function windowId(window) {
        if (!window || window.internalId === undefined || window.internalId === null) {
            return "";
        }
        return String(window.internalId);
    }

    function setFlying(window, on) {
        const id = effect.windowId(window);
        if (!id) {
            return;
        }
        const next = Object.assign({}, effect.flyingIds);
        if (on) {
            next[id] = true;
        } else {
            delete next[id];
        }
        effect.flyingIds = next;
        effect.flyingRev += 1;
    }

    function isFlying(window) {
        const _ = effect.flyingRev;
        const id = effect.windowId(window);
        return !!(id && effect.flyingIds[id]);
    }

    function queueWindowFlight(window, fromList, toList) {
        const fromDesktop = WindowState.primaryDesktop(fromList);
        const toDesktop = WindowState.primaryDesktop(toList);
        if (!window || !fromDesktop || !toDesktop || WindowState.sameDesktop(fromDesktop, toDesktop)) {
            return;
        }
        if (window.minimized || WindowState.isDesktopChrome(window)) {
            return;
        }
        const id = effect.windowId(window);
        const next = [];
        for (let i = 0; i < effect.flightQueue.length; ++i) {
            if (effect.windowId(effect.flightQueue[i].window) !== id) {
                next.push(effect.flightQueue[i]);
            }
        }
        next.push({
            window: window,
            fromDesktop: fromDesktop,
            toDesktop: toDesktop,
            at: Date.now()
        });
        effect.flightQueue = next;
        effect.setFlying(window, true);
        effect.flightToken += 1;
    }

    function takeFlightFor(window) {
        const id = effect.windowId(window);
        if (!id) {
            return null;
        }
        const now = Date.now();
        let found = null;
        const next = [];
        for (let i = 0; i < effect.flightQueue.length; ++i) {
            const job = effect.flightQueue[i];
            if (now - job.at > 1200) {
                effect.setFlying(job.window, false);
                continue;
            }
            if (!found && effect.windowId(job.window) === id) {
                found = job;
                continue;
            }
            next.push(job);
        }
        effect.flightQueue = next;
        return found;
    }

    Instantiator {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            windowModel: KWinComponents.WindowModel {}
        }
        delegate: Connections {
            required property var window
            target: window
            property var lastDesktops: []

            Component.onCompleted: {
                lastDesktops = WindowState.copyDesktops(window ? window.desktops : []);
            }

            function onDesktopsChanged() {
                effect.queueWindowFlight(window, lastDesktops, window.desktops);
                lastDesktops = WindowState.copyDesktops(window.desktops);
            }
        }
    }

    Timer {
        id: failsafeTimer
        interval: effect.animationDuration + 400
        onTriggered: {
            if (!effect.interactive) {
                effect.deactivate();
            }
        }
    }

    Timer {
        id: hideTimer
        interval: effect.animationDuration
        onTriggered: {
            if (!effect.interactive) {
                effect.visible = false;
                effect.fromDesktop = null;
                effect.toDesktop = null;
            }
        }
    }

    // kcfg Peek writes from the toggle script often skip configurationChanged.
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: effect.syncFromPeek()
    }

    function deactivate() {
        failsafeTimer.stop();
        if (effect.interactive) {
            effect.interactive = false;
            hideTimer.restart();
            return;
        }
        hideTimer.stop();
        effect.switchRunning = false;
        effect.visible = false;
        effect.fromDesktop = null;
        effect.toDesktop = null;
    }

    function desktopRow(desktop) {
        if (!desktop || !(desktop.x11DesktopNumber > 0)) {
            return 0;
        }
        return Math.floor((desktop.x11DesktopNumber - 1) / effect.gridWidth);
    }

    function setCenteredRow(row) {
        effect.viewRow = row;
        effect.rowShift = row;
    }

    function shiftViewRow(delta) {
        if (effect.gridHeight < 2) {
            return;
        }
        const height = effect.gridHeight;
        effect.setCenteredRow(((effect.viewRow + delta) % height + height) % height);
    }

    function activateInteractive() {
        failsafeTimer.stop();
        hideTimer.stop();
        effect.setCenteredRow(effect.desktopRow(KWinComponents.Workspace.currentDesktop));
        effect.visible = true;
        effect.interactive = true;
    }

    function syncFromPeek() {
        const peek = effect.peekMirror;
        if (effect.lastPeek === peek) {
            return;
        }
        const first = effect.lastPeek === -999999;
        effect.lastPeek = peek;
        if (first) {
            return;
        }
        if (effect.interactive) {
            effect.commitViewed += 1;
        } else {
            effect.activateInteractive();
        }
    }

    function startSwitch(fromDesktop, toDesktop) {
        if (effect.interactive) {
            return;
        }
        if (!fromDesktop || !toDesktop) {
            return;
        }
        const fromId = fromDesktop.x11DesktopNumber;
        const toId = toDesktop.x11DesktopNumber;
        if (fromDesktop === toDesktop || (fromId > 0 && fromId === toId)) {
            return;
        }
        if (KWinComponents.Workspace.desktops.length < 2) {
            return;
        }

        effect.fromDesktop = fromDesktop;
        effect.toDesktop = toDesktop;
        effect.animationToken += 1;
        failsafeTimer.restart();

        if (!visible) {
            visible = true;
        }
    }

    onPeekMirrorChanged: effect.syncFromPeek()
    Component.onCompleted: effect.syncFromPeek()

    Connections {
        target: effect
        function onConfigurationChanged() {
            effect.syncFromPeek();
        }
    }

    Connections {
        target: KWinComponents.Workspace

        function onCurrentDesktopChanged(previous, current, screen) {
            const to = KWinComponents.Workspace.currentDesktop;
            const from = effect.lastDesktop;
            effect.lastDesktop = to;
            if (effect.interactive) {
                effect.setCenteredRow(effect.desktopRow(to));
                return;
            }
            effect.startSwitch(from, to);
        }
    }
}
