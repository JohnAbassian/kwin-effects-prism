#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
package="$root/package"
script="$root/script"
effect_id="prism"
script_id="prism-toggle"

if ! command -v kpackagetool6 >/dev/null; then
    echo "kpackagetool6 is required (install plasma-framework / kpackage)." >&2
    exit 1
fi

if kpackagetool6 --type KWin/Effect --show "$effect_id" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Effect --upgrade "$package"
else
    kpackagetool6 --type KWin/Effect --install "$package"
fi

if kpackagetool6 --type KWin/Script --show "$script_id" >/dev/null 2>&1; then
    kpackagetool6 --type KWin/Script --upgrade "$script"
else
    kpackagetool6 --type KWin/Script --install "$script"
fi

script_home="${XDG_DATA_HOME:-$HOME/.local/share}/kwin/scripts/${script_id}"
toggle_py="$script_home/contents/code/toggle.py"
chmod +x "$toggle_py" 2>/dev/null || true

unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$unit_dir"
cat > "$unit_dir/${script_id}.service" <<EOF
[Unit]
Description=Toggle Prism overview

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $toggle_py
EOF
if command -v systemctl >/dev/null; then
    systemctl --user daemon-reload
fi

if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kglobalshortcutsrc --group kwin --key Cube "none,none,Toggle Cube"
    kwriteconfig6 --file kglobalshortcutsrc --group kwin --key PrismToggle "Meta+C,Meta+C,Toggle Prism"
    kwriteconfig6 --file kwinrc --group Plugins --key cubeEnabled false
    kwriteconfig6 --file kwinrc --group Plugins --key "${script_id}Enabled" true
    kwriteconfig6 --file kwinrc --group "Effect-${effect_id}" --key Peek 0
    kwriteconfig6 --file kwinrc --group "Effect-${effect_id}" --key PeekFile --delete 2>/dev/null || true
fi

reload_effect() {
    local dbus="$1"
    "$dbus" org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect cube >/dev/null 2>&1 || true
    "$dbus" org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.reloadConfig >/dev/null 2>&1 || true
    "$dbus" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$script_id" >/dev/null 2>&1 || true
    "$dbus" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    "$dbus" org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$effect_id" >/dev/null 2>&1 || true
    sleep 0.3
    "$dbus" org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$effect_id" >/dev/null 2>&1 || true
    "$dbus" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$script_home/contents/code/main.js" "$script_id" >/dev/null 2>&1 || true
}

if command -v qdbus6 >/dev/null; then
    reload_effect qdbus6
elif command -v qdbus >/dev/null; then
    reload_effect qdbus
fi

python3 - <<'PY' || true
import time
try:
    import dbus
except ImportError:
    raise SystemExit(0)

META_C = 0x10000043
bus = dbus.SessionBus()
ga = dbus.Interface(
    bus.get_object("org.kde.kglobalaccel", "/kglobalaccel"),
    "org.kde.KGlobalAccel",
)
comp = dbus.Interface(
    bus.get_object("org.kde.kglobalaccel", "/component/kwin"),
    "org.kde.kglobalaccel.Component",
)

def action(name, text):
    return dbus.Array(["kwin", name, "KWin", text], signature="s")

def empty_keys():
    return dbus.Array([], signature="(ai)")

def meta_c_keys():
    seq = dbus.Array([dbus.Int32(META_C), dbus.Int32(0), dbus.Int32(0), dbus.Int32(0)], signature="i")
    return dbus.Array([dbus.Struct((seq,), signature=None)], signature="(ai)")

try:
    ga.setShortcutKeys(action("Cube", "Toggle Cube"), empty_keys(), 0)
except Exception:
    pass
try:
    ga.unregister("kwin", "Cube")
except Exception:
    pass

registered = False
for _ in range(20):
    try:
        names = [str(n) for n in comp.shortcutNames()]
    except Exception:
        names = []
    if "PrismToggle" in names:
        registered = True
        break
    time.sleep(0.2)

try:
    ga.setShortcutKeys(action("PrismToggle", "Toggle Prism"), meta_c_keys(), 0)
except Exception as exc:
    print("Could not bind Meta+C:", exc)
else:
    if registered:
        print("Bound Meta+C to Toggle Prism.")
    else:
        print("Prism Toggle shortcut is not live yet; log out or restart KWin if Meta+C does nothing.")
PY

echo "Installed Prism."
echo "Enable it in System Settings → Window Management → Desktop Effects"
echo "(Virtual Desktop Switching Animation). Disable Slide if both are on."
echo "Meta+C zooms out to the prism. Requires qt6-quick3d."
echo "Log out and back in once (or restart KWin) so the new QML is loaded."
