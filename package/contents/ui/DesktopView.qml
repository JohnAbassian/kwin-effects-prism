/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import org.kde.kwin as KWinComponents
import "WindowState.js" as WindowState

// Wallpaper plus maximized/fullscreen thumbnails for one face. Overflow
// strips paint the bit of a maximized neighbor that hangs around the corner.
Item {
    id: desktopView

    required property QtObject desktop
    property QtObject leftDesktop: null
    property QtObject rightDesktop: null

    clip: true

    readonly property real screenW: Math.max(1, width)
    readonly property real screenH: Math.max(1, height)

    component EdgeOverflow: Item {
        required property var window
        required property bool fromLeft

        readonly property real wx: WindowState.screenX(window, targetScreen)
        readonly property real wy: WindowState.screenY(window, targetScreen)
        readonly property real overflow: {
            if (!window) {
                return 0;
            }
            return fromLeft ? wx + window.width - desktopView.screenW : -wx;
        }
        readonly property bool show: window && !window.minimized && !window.skipSwitcher
                                     && WindowState.stuckOnFace(window)
                                     && !effect.isFlying(window)
                                     && (fromLeft ? desktopView.leftDesktop : desktopView.rightDesktop)
                                     && !WindowState.isOnDesktop(window, desktopView.desktop)
                                     && overflow >= 1

        x: fromLeft ? 0 : desktopView.screenW - (show ? Math.min(overflow, desktopView.screenW) : 0)
        y: Math.max(wy, 0)
        z: window ? window.stackingOrder : 0
        width: show ? Math.min(overflow, desktopView.screenW) : 0
        height: show ? Math.min(wy + window.height, desktopView.screenH) - Math.max(wy, 0) : 0
        visible: show && height >= 1
        clip: true

        KWinComponents.WindowThumbnail {
            wId: parent.window.internalId
            client: parent.window
            x: parent.fromLeft ? parent.wx - desktopView.screenW : 0
            y: Math.min(parent.wy, 0)
            width: Math.max(1, parent.window.width)
            height: Math.max(1, parent.window.height)
        }
    }

    KWinComponents.DesktopBackground {
        anchors.fill: parent
        opacity: effect.desktopOpacity
        activity: KWinComponents.Workspace.currentActivity
        desktop: desktopView.desktop
        output: targetScreen
        outputName: targetScreen.name
    }

    Repeater {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            desktop: desktopView.desktop
            screenName: targetScreen.name
            windowModel: KWinComponents.WindowModel {}
        }

        KWinComponents.WindowThumbnail {
            wId: model.window.internalId
            client: model.window
            x: WindowState.screenX(model.window, targetScreen)
            y: WindowState.screenY(model.window, targetScreen)
            z: model.window.stackingOrder
            width: Math.max(1, model.window.width)
            height: Math.max(1, model.window.height)
            visible: WindowState.stuckOnFace(model.window) && !effect.isFlying(model.window)
                     && !model.window.minimized && !model.window.skipSwitcher
        }
    }

    Repeater {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            desktop: desktopView.leftDesktop
            screenName: targetScreen.name
            windowModel: KWinComponents.WindowModel {}
        }
        delegate: EdgeOverflow {
            window: model.window
            fromLeft: true
        }
    }

    Repeater {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            desktop: desktopView.rightDesktop
            screenName: targetScreen.name
            windowModel: KWinComponents.WindowModel {}
        }
        delegate: EdgeOverflow {
            window: model.window
            fromLeft: false
        }
    }
}
