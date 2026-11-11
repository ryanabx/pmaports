#!/usr/bin/env python3
"""Run plasma-keyboard only while a text field wants input (sheldonp).

KWin starts the input method named by kwinrc [Wayland] InputMethod at login
and keeps it running; plasma-keyboard then pins ~120 MiB of GPU memory on an
844 MiB device, shown or not. KWin (6.8) tracks whether a text field wants
input without any input method running (/VirtualKeyboard "active"), sends
"activate" to an input method that binds later, and reloads InputMethod at
runtime when kwinrc changes with a notification. So this switches the setting
on when "active" becomes true, and off again after OSK_IDLE seconds (default
120) without a text field, which makes KWin stop the process.

Installed by device-amazon-sheldonp as /usr/bin/osk-on-demand, with the
user unit osk-on-demand.service (enabled for plasma-workspace.target).
"""
import os
import signal
import subprocess
import sys

from gi.repository import Gio, GLib
try:
    from gi.repository import GLibUnix
    signal_add = GLibUnix.signal_add
except ImportError:
    signal_add = GLib.unix_signal_add

IM = os.environ.get("OSK_DESKTOP_FILE", "/usr/share/applications/org.kde.plasma.keyboard.desktop")
IDLE = int(os.environ.get("OSK_IDLE", "120"))
IFACE = "org.kde.kwin.VirtualKeyboard"

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
state = {"on": None, "timer": 0}


def log(*a):
    print(*a, flush=True)


def set_im(on):
    if state["on"] == on:
        return
    subprocess.run(["kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "Wayland",
                    "--key", "InputMethod", IM if on else ""], check=False)
    state["on"] = on
    log("keyboard", "on" if on else "off")


def active():
    try:
        v = bus.call_sync("org.kde.KWin", "/VirtualKeyboard", "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", (IFACE, "active")), GLib.VariantType("(v)"),
                          Gio.DBusCallFlags.NONE, 2000, None)
        return bool(v.unpack()[0])
    except GLib.Error as e:
        log("reading active failed:", e.message)
        return False


def cancel_timer():
    if state["timer"]:
        GLib.source_remove(state["timer"])
        state["timer"] = 0


def idle_off():
    state["timer"] = 0
    if not active():
        set_im(False)
    return False


def changed(*_):
    if active():
        cancel_timer()
        set_im(True)
    elif state["on"] and not state["timer"]:
        state["timer"] = GLib.timeout_add_seconds(IDLE, idle_off)


def main():
    bus.signal_subscribe("org.kde.KWin", IFACE, "activeChanged", "/VirtualKeyboard", None,
                         Gio.DBusSignalFlags.NONE, changed)
    loop = GLib.MainLoop()
    signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
    signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, loop.quit)
    set_im(active())   # off at start unless a text field already has focus
    loop.run()
    # Stopped: hand the setting back to the session's default, so the
    # keyboard works as before without this service.
    subprocess.run(["kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "Wayland",
                    "--key", "InputMethod", "--delete"], check=False)
    log("stopped; InputMethod back to the session default")


if __name__ == "__main__":
    sys.exit(main())
