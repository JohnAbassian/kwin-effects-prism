/*
    SPDX-FileCopyrightText: 2022 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick3D
import org.kde.kwin as KWinComponents

// One prism hull. Maximized windows stay on the face texture with the
// wallpaper. Windowed cards float in front. In-flight windows slide on
// the faces and wrap around the edges.
Node {
    id: cube

    property real faceDisplacement: 0
    required property size faceSize
    property int viewRow: 0
    property real rowShift: 0
    property real cameraYaw: 0
    property real prismPitch: faceSize.height
    property real windowFloat: 40

    readonly property int gridWidth: Math.max(1, KWinComponents.Workspace.desktopGridWidth || 1)
    readonly property int gridHeight: Math.max(1, KWinComponents.Workspace.desktopGridHeight || 1)
    readonly property real angleTick: 360 / cube.gridWidth
    readonly property real faceDistance: 0.5 * faceSize.width / Math.tan(angleTick * Math.PI / 360) + faceDisplacement

    property var flightMap: ({})
    property int flightRev: 0

    function setFlight(id, state) {
        if (!id) {
            return;
        }
        const next = Object.assign({}, cube.flightMap);
        if (state) {
            next[id] = state;
        } else {
            delete next[id];
        }
        cube.flightMap = next;
        cube.flightRev += 1;
    }

    function flightOf(window) {
        const _ = cube.flightRev;
        const id = effect.windowId(window);
        return (id && cube.flightMap[id]) ? cube.flightMap[id] : null;
    }

    function linearIndex(desktop) {
        if (!desktop) {
            return 0;
        }
        const number = desktop.x11DesktopNumber;
        if (typeof number === "number" && number > 0) {
            return number - 1;
        }
        const desktops = KWinComponents.Workspace.desktops;
        for (let i = 0; i < desktops.length; ++i) {
            if (desktops[i] === desktop) {
                return i;
            }
            if (desktop.id && desktops[i].id === desktop.id) {
                return i;
            }
        }
        return 0;
    }

    function columnOf(desktop) {
        return cube.linearIndex(desktop) % cube.gridWidth;
    }

    function rowOf(desktop) {
        return Math.floor(cube.linearIndex(desktop) / cube.gridWidth);
    }

    function desktopAtColumn(row, column) {
        const desktops = KWinComponents.Workspace.desktops;
        const index = row * cube.gridWidth + column;
        if (index < 0 || index >= desktops.length) {
            return null;
        }
        return desktops[index];
    }

    function neighborDesktop(desktop, delta) {
        if (!desktop) {
            return null;
        }
        const n = cube.gridWidth;
        const column = ((cube.columnOf(desktop) + delta) % n + n) % n;
        return cube.desktopAtColumn(cube.rowOf(desktop), column);
    }

    function desktopAzimuth(desktop) {
        return cube.angleTick * cube.columnOf(desktop);
    }

    function radialAt(azimuth) {
        const transform = Qt.matrix4x4();
        transform.rotate(azimuth, Qt.vector3d(0, 1, 0));
        return transform.times(Qt.vector3d(0, 0, cube.faceDistance));
    }

    function desktopAt(azimuth) {
        const n = cube.gridWidth;
        let column = Math.round(azimuth / cube.angleTick) % n;
        if (column < 0) {
            column += n;
        }
        return cube.desktopAtColumn(cube.viewRow, column);
    }

    function signedSteps(fromIndex, toIndex, count, rotateAllTheWay) {
        if (count < 2) {
            return 0;
        }
        const forward = (toIndex - fromIndex + count) % count;
        const backward = (fromIndex - toIndex + count) % count;
        if (forward === 0) {
            return 0;
        }
        if (rotateAllTheWay) {
            if (forward === backward) {
                return forward;
            }
            return forward > backward ? forward : -backward;
        }
        if (forward <= backward) {
            return forward;
        }
        return -backward;
    }

    function ringSteps(fromDesktop, toDesktop, rotateAllTheWay) {
        const n = cube.gridWidth;
        if (n < 2) {
            return 0;
        }
        return cube.signedSteps(cube.columnOf(fromDesktop), cube.columnOf(toDesktop), n, rotateAllTheWay);
    }

    Repeater3D {
        model: KWinComponents.VirtualDesktopModel {}
        delegate: Node {
            id: faceNode

            required property QtObject desktop
            required property int index

            readonly property int faceRow: cube.rowOf(desktop)
            readonly property vector3d radial: cube.radialAt(cube.desktopAzimuth(desktop))

            eulerRotation.y: cube.desktopAzimuth(desktop)
            x: radial.x
            y: (cube.rowShift - faceRow) * cube.prismPitch
            z: radial.z

            CubeFace {
                faceSize: cube.faceSize
                desktop: faceNode.desktop
                leftDesktop: cube.neighborDesktop(faceNode.desktop, -1)
                rightDesktop: cube.neighborDesktop(faceNode.desktop, 1)
                scale: Qt.vector3d(cube.faceSize.width / 100, cube.faceSize.height / 100, 1)
            }

            Repeater3D {
                model: KWinComponents.WindowFilterModel {
                    activity: KWinComponents.Workspace.currentActivity
                    screenName: targetScreen.name
                    windowModel: KWinComponents.WindowModel {}
                }
                delegate: WindowPieces {
                    faceSize: cube.faceSize
                    desktop: faceNode.desktop
                    leftDesktop: cube.neighborDesktop(faceNode.desktop, -1)
                    rightDesktop: cube.neighborDesktop(faceNode.desktop, 1)
                    floatOffset: cube.windowFloat
                    angleTick: cube.angleTick
                }
            }
        }
    }

    Repeater3D {
        model: KWinComponents.WindowFilterModel {
            activity: KWinComponents.Workspace.currentActivity
            screenName: targetScreen.name
            windowModel: KWinComponents.WindowModel {}
        }
        delegate: WindowFlight {
            faceSize: cube.faceSize
        }
    }
}