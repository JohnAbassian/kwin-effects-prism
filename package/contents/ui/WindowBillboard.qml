/*
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

Model {
    id: billboard

    required property var window
    required property size faceSize
    property QtObject desktop: null  // read by ScreenView.pickDesktop
    property real floatOffset: 40
    property real pieceLeft: 0
    property real pieceRight: 1
    property real pieceTop: 0
    property real pieceBottom: 1
    property real srcX: 0
    property real srcY: 0
    property real srcW: 1
    property real srcH: 1
    property real clientW: 0
    property real clientH: 0
    property bool pieceVisible: true

    readonly property real liftZ: {
        const t = Math.max(0, floatOffset);
        const order = billboard.window ? Math.max(0, Number(billboard.window.stackingOrder) || 0) : 0;
        const animated = t * (1 + order * 0.35);
        // Keep stacked cards off the wallpaper and off each other for as long
        // as the effect is visible. Collapsing to z=0 on the last frames of
        // zoom-in makes overlapping windows clip before the real desktop shows.
        return Math.max(animated, 2 + order * 0.5);
    }
    readonly property real mappedLeft: pieceLeft - faceSize.width / 2
    readonly property real mappedRight: pieceRight - faceSize.width / 2

    pickable: true
    castsShadows: false
    receivesShadows: false
    depthBias: -1
    visible: pieceVisible && window && !window.minimized && !window.skipSwitcher && srcW >= 1 && srcH >= 1
    source: "#Rectangle"
    x: (mappedLeft + mappedRight) / 2
    y: faceSize.height / 2 - (pieceTop + pieceBottom) / 2
    z: liftZ
    scale: Qt.vector3d(Math.max(1, mappedRight - mappedLeft) / 100,
                       Math.max(1, pieceBottom - pieceTop) / 100,
                       1)

    materials: [
        PrincipledMaterial {
            lighting: PrincipledMaterial.NoLighting
            cullMode: Material.NoCulling
            alphaMode: PrincipledMaterial.Opaque
            depthDrawMode: Material.AlwaysDepthDraw
            baseColor: "#ffffff"
            baseColorMap: Texture {
                sourceItem: Item {
                    width: Math.max(1, billboard.srcW)
                    height: Math.max(1, billboard.srcH)
                    clip: true

                    KWinComponents.WindowThumbnail {
                        client: billboard.window
                        wId: billboard.window ? billboard.window.internalId : ""
                        x: -billboard.srcX
                        y: -billboard.srcY
                        width: Math.max(1, billboard.clientW > 0 ? billboard.clientW
                                                                : (billboard.window ? billboard.window.width : 1))
                        height: Math.max(1, billboard.clientH > 0 ? billboard.clientH
                                                                 : (billboard.window ? billboard.window.height : 1))
                    }
                }
            }
        }
    ]
}
