# Prism

A Plasma 6 **Wayland** KWin effect that rotates a **prism** of the current pager row when you switch desktops left or right (including wrap).

I loved Compiz/Beryl/Fusion. When GNOME moved to Shell and KDE to Plasma, Compiz broke, and I left both. Nearly two decades later, I think KDE made the right call: compositing belongs in the window manager, not in a plugin stack on X11. [That argument is laid out well here.](https://www.reddit.com/r/linux/comments/75hxp6/why_did_compiz_die/) What I still missed was the cube: windows floating off the faces, the hull turning when you change desktops, the Compiz feel. Plasma’s built-in Cube never quite got there. So I made Prism.

Each pager row is its own prism (a square prism / cube when the row has 4 desktops, a hexagonal prism when it has 6, and so on). This is a switching animation **and** a zoom-out overview (Meta+C), in the same exclusive group as Slide.

## Origin

Prism started as a fork of Vlad Zahorodnii’s [kwin-effects-cube](https://github.com/zzag/kwin-effects-cube) (the Qt Quick 3D desktop cube later shipped in Plasma 6 via kdeplasma-addons). The camera, face geometry, live wallpaper/window thumbnails, and Meta+C overview come from that effect.

The original Cube is an **on-demand overview**: press Meta+C, look at every virtual desktop as one hull, pick a face. It does not run when you switch desktops, and it folds the whole pager into a single cube (3+ desktops).

Prism keeps that hull and adds a **desktop switcher** on top — the Compiz cube behaviors the built-in effect left out:

- **Switching animation**: left/right desktop changes (pager, shortcuts, wrap) turn the current row instead of sliding. Same exclusive group as Slide.
- **One prism per pager row**:  a 2×3 pager is two triangular prisms, not one 6-sided cube. Overview stacks those prisms; Up/Down slides which row is centered.
- **Two desktops** do a 180° flip, instead of Cube’s 3-desktop minimum.
- **Floating windows**: windowed cards sit in front of the face; maximized and fullscreen windows stay on the wallpaper.
- **Sending a window to another desktop** flies it around the prism (or between rows) instead of snapping.
- **Configurable**: zoom-out, tilt, fling inertia, face gap, background color, etc.

## Requirements

- KDE Plasma 6 / KWin
- `qt6-quick3d` (the official Cube effect uses the same)
- At least 2 virtual desktops (3+ looks like a prism; 2 is a 180° flip)

On Arch/CachyOS:

```sh
sudo pacman -S qt6-quick3d
```

## Install

```sh
./install.sh
```

Or:

```sh
kpackagetool6 --type KWin/Effect --install package/
qdbus6 org.kde.KWin /KWin reconfigure
```

Upgrade after changes with `--upgrade` instead of `--install`.

## Enable

1. Open **System Settings → Window Management → Desktop Effects**.
2. Find **Prism** under Virtual Desktop Switching Animation.
3. Enable it. **Slide** should turn off (same exclusive group).
4. Switch desktops with the pager, Ctrl+F1/F2, or a wrap-around shortcut.

If it does not appear, log out and back in (or restart KWin).

## Shortcuts

**Press Meta+C** to zoom out. Then:

- Drag left/right (or press Left/Right) to rotate the centered prism
- Drag up/down to tilt the camera
- **Left / Right** to turn one face, **Up / Down** to slide between pager rows
- Click a face or press Enter/Space/Meta+C to switch to that desktop and leave overview
- Escape to zoom back to the desktop you started from

Rebind the overview under System Settings → Shortcuts → KWin → **Toggle Prism**. The built-in Cube shortcut is cleared so Meta+C is freed.

## Uninstall

```sh
kpackagetool6 --type KWin/Effect --remove prism
kpackagetool6 --type KWin/Script --remove prism-toggle
```

