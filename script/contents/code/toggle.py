#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 John Abassian <john@abassian.net>
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

import shutil
import subprocess


def read_peek():
    kread = shutil.which("kreadconfig6") or shutil.which("kreadconfig")
    if not kread:
        return 0
    result = subprocess.run(
        [kread, "--file", "kwinrc", "--group", "Effect-prism", "--key", "Peek"],
        check=False,
        capture_output=True,
        text=True,
    )
    try:
        return int((result.stdout or "0").strip() or "0")
    except ValueError:
        return 0


def main():
    peek = read_peek() + 1
    kwrite = shutil.which("kwriteconfig6") or shutil.which("kwriteconfig")
    if kwrite:
        subprocess.run(
            [kwrite, "--file", "kwinrc", "--group", "Effect-prism", "--key", "Peek", str(peek)],
            check=False,
        )
    qdbus = shutil.which("qdbus6") or shutil.which("qdbus")
    if qdbus:
        subprocess.run(
            [qdbus, "org.kde.KWin", "/Effects", "org.kde.kwin.Effects.reconfigureEffect", "prism"],
            check=False,
        )


if __name__ == "__main__":
    main()