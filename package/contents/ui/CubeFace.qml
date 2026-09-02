/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D

Model {
    id: face

    required property QtObject desktop
    required property size faceSize
    property QtObject leftDesktop: null
    property QtObject rightDesktop: null

    pickable: true
    castsShadows: false
    receivesShadows: false
    source: "#Rectangle"
    materials: [
        PrincipledMaterial {
            lighting: PrincipledMaterial.NoLighting
            cullMode: Material.NoCulling
            alphaMode: effect.desktopOpacity >= 0.999 ? PrincipledMaterial.Opaque : PrincipledMaterial.Blend
            depthDrawMode: effect.desktopOpacity >= 0.999 ? Material.AlwaysDepthDraw : Material.OpaqueOnlyDepthDraw
            baseColor: "#ffffff"
            baseColorMap: Texture {
                sourceItem: DesktopView {
                    desktop: face.desktop
                    leftDesktop: face.leftDesktop
                    rightDesktop: face.rightDesktop
                    width: faceSize.width
                    height: faceSize.height
                }
            }
        }
    ]
}