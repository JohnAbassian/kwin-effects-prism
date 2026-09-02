/*
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import "WindowState.js" as WindowState

// Windowed cards on one face. They float in front of the wallpaper, so a wrap
// has to meet at the offset corner (liftZ past the face edge), not at the
// wallpaper seam. Texture stays split on that seam; the extra geometry is a
// stretch so the two pieces share an edge and read as one window.
Node {
    id: pieces

    required property var window
    required property size faceSize
    required property QtObject desktop
    property QtObject leftDesktop: null
    property QtObject rightDesktop: null
    property real floatOffset: 40
    property real angleTick: 90

    readonly property real screenW: Math.max(1, faceSize.width)
    readonly property real screenH: Math.max(1, faceSize.height)
    readonly property real halfAngle: angleTick * Math.PI / 360
    readonly property bool stuck: WindowState.stuckOnFace(window)
    readonly property bool parked: stuck || WindowState.isDesktopChrome(window)
    readonly property bool flying: effect.isFlying(window)
    readonly property var flightJob: cube.flightOf(window)
    readonly property var flightDraw: {
        if (!flying) {
            return null;
        }
        return WindowState.flightPiece(flightJob, cube.columnOf(desktop), cube.rowOf(desktop),
                                       cube.gridWidth, cube.gridHeight, screenW, screenH,
                                       winX, winY, winW, winH, cube.prismPitch);
    }
    readonly property bool onThis: WindowState.isOnDesktop(window, desktop)
    readonly property bool onLeft: WindowState.isOnDesktop(window, leftDesktop)
    readonly property bool onRight: WindowState.isOnDesktop(window, rightDesktop)
    readonly property real winX: WindowState.screenX(window, targetScreen)
    readonly property real winY: WindowState.screenY(window, targetScreen)
    readonly property real winW: window ? window.width : 0
    readonly property real winH: window ? window.height : 0
    readonly property real overflowRight: winX + winW - screenW
    readonly property real overflowLeft: -winX
    readonly property real contentLeft: flying && flightDraw ? flightDraw.left : Math.max(winX, 0)
    readonly property real contentRight: flying && flightDraw ? flightDraw.right : Math.min(winX + winW, screenW)
    readonly property real contentTop: flying && flightDraw ? flightDraw.top : Math.max(winY, 0)
    readonly property real contentBottom: flying && flightDraw ? flightDraw.bottom : Math.min(winY + winH, screenH)
    readonly property bool crossLeft: flying ? !!(flightDraw && flightDraw.crossesLeft)
                                             : overflowLeft >= 1
    readonly property bool crossRight: flying ? !!(flightDraw && flightDraw.crossesRight)
                                              : overflowRight >= 1
    readonly property real overhang: {
        const z = nativeCard.liftZ;
        const tanHalf = Math.tan(halfAngle);
        if (!(z > 0) || !(tanHalf > 0) || tanHalf > 4) {
            return 0;
        }
        return z * tanHalf;
    }
    readonly property real nativeLeft: contentLeft - (showNative && crossLeft ? overhang : 0)
    readonly property real nativeRight: contentRight + (showNative && crossRight ? overhang : 0)
    readonly property real nativeSrcX: flying && flightDraw ? flightDraw.srcX : contentLeft - winX
    readonly property real nativeSrcY: flying && flightDraw ? flightDraw.srcY : contentTop - winY
    readonly property real nativeSrcW: contentRight - contentLeft
    readonly property real nativeSrcH: contentBottom - contentTop
    readonly property bool showNative: flying ? !!flightDraw
                                              : !parked && onThis && nativeSrcW >= 1 && nativeSrcH >= 1
    readonly property bool showWrapFromLeft: !flying && !parked && !onThis && onLeft && overflowRight >= 1
    readonly property bool showWrapFromRight: !flying && !parked && !onThis && onRight && overflowLeft >= 1
    readonly property real wrapFromLeftWidth: showWrapFromLeft ? Math.min(overflowRight, screenW) : 0
    readonly property real wrapFromRightWidth: showWrapFromRight ? Math.min(overflowLeft, screenW) : 0

    WindowBillboard {
        id: nativeCard
        window: pieces.window
        desktop: pieces.desktop
        faceSize: pieces.faceSize
        floatOffset: pieces.floatOffset
        pieceVisible: pieces.showNative
        pieceLeft: pieces.nativeLeft
        pieceRight: pieces.nativeRight
        pieceTop: pieces.contentTop
        pieceBottom: pieces.contentBottom
        srcX: pieces.nativeSrcX
        srcY: pieces.nativeSrcY
        srcW: pieces.nativeSrcW
        srcH: pieces.nativeSrcH
    }

    WindowBillboard {
        window: pieces.window
        desktop: pieces.desktop
        faceSize: pieces.faceSize
        floatOffset: pieces.floatOffset
        pieceVisible: pieces.showWrapFromLeft
        pieceLeft: -pieces.overhang
        pieceRight: pieces.wrapFromLeftWidth
        pieceTop: pieces.contentTop
        pieceBottom: pieces.contentBottom
        srcX: Math.max(0, pieces.screenW - pieces.winX)
        srcY: pieces.contentTop - pieces.winY
        srcW: pieces.wrapFromLeftWidth
        srcH: pieces.contentBottom - pieces.contentTop
    }

    WindowBillboard {
        window: pieces.window
        desktop: pieces.desktop
        faceSize: pieces.faceSize
        floatOffset: pieces.floatOffset
        pieceVisible: pieces.showWrapFromRight
        pieceLeft: pieces.screenW - pieces.wrapFromRightWidth
        pieceRight: pieces.screenW + pieces.overhang
        pieceTop: pieces.contentTop
        pieceBottom: pieces.contentBottom
        srcX: 0
        srcY: pieces.contentTop - pieces.winY
        srcW: pieces.wrapFromRightWidth
        srcH: pieces.contentBottom - pieces.contentTop
    }
}
