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
    readonly property bool desktopOpacityPreviewOnly: effect.isTruthy(effect.configuration ? effect.configuration.DesktopOpacityPreviewOnly : false)
    readonly property real desktopOpacity: {
        const n = effect.finiteNumber(effect.configuration ? effect.configuration.DesktopOpacity : NaN, 100);
        const configured = Math.max(0, Math.min(1, n / 100));
        if (effect.desktopOpacityPreviewOnly && !effect.interactive) {
            return 1;
        }
        return configured;
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
    property var flightGeoms: ({})
    property var snapRetries: []
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
        const geoms = Object.assign({}, effect.flightGeoms);
        if (on) {
            next[id] = true;
        } else {
            delete next[id];
            delete geoms[id];
        }
        effect.flyingIds = next;
        effect.flightGeoms = geoms;
        effect.flyingRev += 1;
    }

    function isFlying(window) {
        const _ = effect.flyingRev;
        const id = effect.windowId(window);
        return !!(id && effect.flyingIds[id]);
    }

    function setFlightGeom(window, geom) {
        const id = effect.windowId(window);
        if (!id) {
            return;
        }
        const geoms = Object.assign({}, effect.flightGeoms);
        if (geom) {
            geoms[id] = geom;
        } else {
            delete geoms[id];
        }
        effect.flightGeoms = geoms;
        effect.flyingRev += 1;
    }

    function flightGeomOf(window) {
        const _ = effect.flyingRev;
        const id = effect.windowId(window);
        return (id && effect.flightGeoms[id]) ? effect.flightGeoms[id] : null;
    }

    function destRootTile(window, desktop) {
        if (!window || !desktop || !window.output) {
            return null;
        }
        const workspace = KWinComponents.Workspace;
        if (typeof workspace.rootTile === "function") {
            return workspace.rootTile(window.output, desktop);
        }
        return null;
    }

    // Per-desktop tiling drops the snap when a window changes desktop.
    // Do not unmanage() here: that restores the pre-tile (centered) rect.
    // Wait until the old tile is gone, then put the frame back — and retry
    // for a few frames because KWin untiles after desktopsChanged.
    function keepSnapped(window, snap) {
        if (!window || !snap || !(snap.width > 0) || !(snap.height > 0)) {
            return;
        }
        if (window.minimized || WindowState.isDesktopChrome(window) || WindowState.stuckOnFace(window)) {
            return;
        }
        if (window.move === true || window.resize === true) {
            return;
        }
        if (WindowState.geometryMatches(window, snap, 2)) {
            return;
        }
        const dest = WindowState.primaryDesktop(window.desktops)
                     || (window.output && typeof KWinComponents.Workspace.currentDesktopForScreen === "function"
                         ? KWinComponents.Workspace.currentDesktopForScreen(window.output)
                         : KWinComponents.Workspace.currentDesktop);
        const root = dest ? effect.destRootTile(window, dest) : null;
        const tile = WindowState.findMatchingTile(root, snap);
        if (tile && typeof tile.manage === "function" && window.tile !== tile) {
            tile.manage(window);
            if (WindowState.geometryMatches(window, snap, 2)) {
                return;
            }
        }
        if (window.tile) {
            return;
        }
        window.frameGeometry = Qt.rect(snap.x, snap.y, snap.width, snap.height);
    }

    function holdSnap(window, snap) {
        if (!window || !snap) {
            return;
        }
        const id = effect.windowId(window);
        const next = [];
        for (let i = 0; i < effect.snapRetries.length; ++i) {
            if (effect.windowId(effect.snapRetries[i].window) !== id) {
                next.push(effect.snapRetries[i]);
            }
        }
        next.push({
            window: window,
            snap: snap,
            tries: 0
        });
        effect.snapRetries = next;
        effect.keepSnapped(window, snap);
        snapRetryTimer.restart();
    }

    function isHoldingSnap(window) {
        const id = effect.windowId(window);
        if (!id) {
            return false;
        }
        for (let i = 0; i < effect.snapRetries.length; ++i) {
            if (effect.windowId(effect.snapRetries[i].window) === id) {
                return true;
            }
        }
        return false;
    }

    function queueWindowFlight(window, fromList, toList, snap) {
        const fromDesktop = WindowState.primaryDesktop(fromList);
        const toDesktop = WindowState.primaryDesktop(toList);
        if (!window || !fromDesktop || !toDesktop || WindowState.sameDesktop(fromDesktop, toDesktop)) {
            return;
        }
        if (window.minimized || WindowState.isDesktopChrome(window)) {
            return;
        }
        const id = effect.windowId(window);
        const geom = snap || WindowState.captureSnap(window);
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
            geom: geom,
            at: Date.now()
        });
        effect.flightQueue = next;
        effect.setFlying(window, true);
        effect.setFlightGeom(window, geom);
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
        delegate: QtObject {
            id: tracker
            required property var window
            property var lastDesktops: []
            // Last frame while the window was actually tiled. Never store the
            // post-untile restore rect here — that is the small centered one.
            property var snapGeom: null

            function rememberSnap() {
                if (window && window.tile) {
                    snapGeom = WindowState.captureSnap(window);
                }
            }

            function forgetSnapIfUserUntiled() {
                if (!window || window.tile || !snapGeom) {
                    return;
                }
                const desks = WindowState.copyDesktops(window.desktops);
                Qt.callLater(function () {
                    if (!tracker.window || tracker.window.tile || !tracker.snapGeom) {
                        return;
                    }
                    if (!WindowState.sameDesktopList(desks, tracker.window.desktops)) {
                        return;
                    }
                    if (effect.isHoldingSnap(tracker.window)) {
                        return;
                    }
                    tracker.snapGeom = null;
                });
            }

            function snapForMove() {
                if (window && window.tile) {
                    rememberSnap();
                }
                return snapGeom;
            }

            Component.onCompleted: {
                lastDesktops = WindowState.copyDesktops(window ? window.desktops : []);
                rememberSnap();
            }

            property var windowWatch: Connections {
                target: tracker.window
                function onTileChanged() {
                    if (tracker.window && tracker.window.tile) {
                        tracker.rememberSnap();
                    } else {
                        tracker.forgetSnapIfUserUntiled();
                    }
                }
                function onFrameGeometryChanged() {
                    tracker.rememberSnap();
                }
                function onDesktopsChanged() {
                    const snap = tracker.snapForMove();
                    effect.queueWindowFlight(tracker.window, tracker.lastDesktops, tracker.window.desktops, snap);
                    tracker.lastDesktops = WindowState.copyDesktops(tracker.window.desktops);
                    effect.holdSnap(tracker.window, snap);
                }
            }

            property var desktopWatch: Connections {
                target: KWinComponents.Workspace
                function onCurrentDesktopChanged() {
                    if (!tracker.window) {
                        return;
                    }
                    const desks = tracker.window.desktops;
                    if (desks && desks.length > 0) {
                        return;
                    }
                    effect.holdSnap(tracker.window, tracker.snapForMove());
                }
            }
        }
    }

    Timer {
        id: snapRetryTimer
        interval: 16
        repeat: true
        onTriggered: {
            const keep = [];
            for (let i = 0; i < effect.snapRetries.length; ++i) {
                const item = effect.snapRetries[i];
                item.tries += 1;
                effect.keepSnapped(item.window, item.snap);
                if (!WindowState.geometryMatches(item.window, item.snap, 2) && item.tries < 10) {
                    keep.push(item);
                }
            }
            effect.snapRetries = keep;
            if (keep.length === 0) {
                stop();
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
