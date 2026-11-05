---
title: Linux console ioctl requests used by TvTermOs
---

Facts of the Linux kernel user-space interface (UAPI headers of Linux v6.6, tag `v6.6` of
https://github.com/torvalds/linux). Only values and layouts are recorded.

| Name | Value | Header |
| --- | --- | --- |
| `KDFONTOP` | `0x4B72` | `include/uapi/linux/kd.h` |
| `KD_FONT_OP_GET` | `1` | `include/uapi/linux/kd.h` |
| `TIOCLINUX` | `0x541C` | `include/uapi/asm-generic/ioctls.h` |
| `TIOCL_GETSHIFTSTATE` | `6` | `include/uapi/linux/tiocl.h` |

`KDFONTOP` takes a pointer to `struct console_font_op`, in this order: `unsigned int op` (a `KD_FONT_OP_*` code),
`unsigned int flags`, `unsigned int width`, `unsigned int height`, `unsigned int charcount`, then a data pointer.
For `KD_FONT_OP_GET` the caller sets `width` and `height` to the largest font size it accepts and the kernel
returns the size of the current font in them.

`TIOCLINUX` takes a pointer to a byte whose value is a `TIOCL_*` subcode; with `TIOCL_GETSHIFTSTATE` the kernel
writes the shift state of the console keyboard into that byte. The request fails on a descriptor that is not a
Linux console.
