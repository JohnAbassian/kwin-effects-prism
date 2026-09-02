/*
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

function copyDesktops(list) {
    const out = [];
    if (!list) {
        return out;
    }
    for (let i = 0; i < list.length; ++i) {
        out.push(list[i]);
    }
    return out;
}

function primaryDesktop(list) {
    if (!list || list.length !== 1) {
        return null;
    }
    return list[0];
}

function sameDesktop(a, b) {
    if (!a || !b) {
        return false;
    }
    if (a === b) {
        return true;
    }
    if (a.id && b.id && a.id === b.id) {
        return true;
    }
    return a.x11DesktopNumber > 0 && a.x11DesktopNumber === b.x11DesktopNumber;
}

function isOnDesktop(window, target) {
    if (!window || !target) {
        return false;
    }
    const desktops = window.desktops;
    if (!desktops || desktops.length === 0) {
        return true;
    }
    for (let i = 0; i < desktops.length; ++i) {
        if (sameDesktop(desktops[i], target)) {
            return true;
        }
    }
    return false;
}

function screenX(window, screen) {
    if (!window || !screen) {
        return 0;
    }
    return window.x - screen.geometry.x;
}

function screenY(window, screen) {
    if (!window || !screen) {
        return 0;
    }
    return window.y - screen.geometry.y;
}

function clamp01(value) {
    return Math.max(0, Math.min(1, value));
}

function wrapIndex(i, n) {
    if (n < 1) {
        return 0;
    }
    return ((i % n) + n) % n;
}

// Overlap of a sliding window with one face on an unwrapped strip.
function flightOverlap1D(fromIndex, index, steps, count, span, origin, size, t) {
    if (!count || !(span > 0) || !(size > 0)) {
        return null;
    }
    const window0 = origin + t * steps * span;
    const window1 = window0 + size;
    const dir = steps < 0 ? -1 : 1;
    const kStart = steps === 0 ? 0 : -1;
    const kEnd = steps === 0 ? 0 : Math.abs(steps) + 1;
    for (let k = kStart; k <= kEnd; ++k) {
        const signed = steps === 0 ? 0 : k * dir;
        if (wrapIndex(fromIndex + signed, count) !== index) {
            continue;
        }
        const face0 = signed * span;
        const face1 = face0 + span;
        const a = Math.max(window0, face0);
        const b = Math.min(window1, face1);
        if (b - a < 1) {
            continue;
        }
        return {
            local0: a - face0,
            local1: b - face0,
            src: a - window0,
            crosses0: window0 < face0 - 0.5,
            crosses1: window1 > face1 + 0.5
        };
    }
    return null;
}

function flightPiece(job, col, row, gridWidth, gridHeight, screenW, screenH, winX, winY, winW, winH, prismPitch) {
    if (!job) {
        return null;
    }
    const t = clamp01(job.t);
    const pitch = prismPitch > 0 ? prismPitch : screenH;
    const x = flightOverlap1D(job.fromCol, col, job.colSteps, gridWidth, screenW, winX, winW, t);
    const y = flightOverlap1D(job.fromRow, row, job.rowSteps, gridHeight, pitch, winY, winH, t);
    if (!x || !y) {
        return null;
    }
    return {
        left: x.local0,
        right: x.local1,
        top: y.local0,
        bottom: y.local1,
        srcX: x.src,
        srcY: y.src,
        crossesLeft: x.crosses0,
        crossesRight: x.crosses1
    };
}

function isDesktopChrome(window) {
    return !!(window && (window.desktopWindow === true || window.dock === true));
}

// Fully maximized or fullscreen windows stay on the prism face texture.
// MaximizeFull is KWin::MaximizeVertical | MaximizeHorizontal == 3.
function stuckOnFace(window) {
    if (!window || isDesktopChrome(window)) {
        return false;
    }
    if (window.fullScreen === true || window.maximized === true) {
        return true;
    }
    const mode = window.maximizeMode;
    return mode === 3 || mode === "MaximizeFull";
}