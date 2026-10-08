# No GPU driver for the SGX540 in mainline: let wlroots compositors (phoc,
# sway, ...) composite with pixman instead of failing to create an EGL
# renderer. Same as device-nokia-n900.
export WLR_RENDERER=pixman
