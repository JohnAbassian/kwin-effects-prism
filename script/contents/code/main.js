/*
    SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>
    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

registerShortcut("PrismToggle", "Toggle Prism", "Meta+C", function () {
    callDBus(
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
        "StartUnit",
        "prism-toggle.service",
        "replace"
    );
});