// amazon-suez: render at the panel's fractional scale (1.5) instead of 2x
// and letting KWin scale down: Firefox's main pass 28 -> 15.8 ms of GPU,
// 720p30 video drops 15.0 -> 10.9 frames/s (suez-work
// notes/BROWSER-PERF-2026-11-16.md). A default: a profile can override it.
pref("widget.wayland.fractional-scale.enabled", true);
