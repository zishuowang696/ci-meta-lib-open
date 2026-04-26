# Analysis Conclusions

> Saved on 2026-04-25. Do not modify — reference only.

## Problem

`/dev/ttyS0` (mini UART / uart1) is missing when booting the built image in QEMU (raspi3b model).

## Root Cause

### 1. Empty `uart1_pins` pinctrl in upstream RPi kernel DTS

At the kernel commit used by meta-raspberrypi (`bba53a117a4a5c29da892962332ff1605990e17a`, `rpi-6.6.y`), the file `arch/arm/boot/dts/broadcom/bcm2710-rpi-3-b.dts` contains:

```dts
&uart1 {
    pinctrl-0 = <&uart1_pins>;
    status = "okay";
};
```

But `uart1_pins` is defined with **empty pin assignments**:

```dts
uart1_pins: uart1_pins {
    brcm,pins;
    brcm,function;
    brcm,pull;
};
```

No actual GPIO pins (14/15) are configured.

### 2. No VideoCore firmware in QEMU

On real Raspberry Pi hardware, the GPU firmware (VideoCore) pre-configures GPIO 14/15 as ALT5 (UART1 function) **before Linux boots**. The empty pinctrl is harmless on real hardware.

In QEMU, there is **no VideoCore firmware**. The kernel's `pinctrl-bcm2835` driver receives a no-op pin request from the empty `uart1_pins` node. This likely causes the uart1 device probe to be skipped or fail, so `/dev/ttyS0` is never created.

### 3. Kernel driver is present

`CONFIG_SERIAL_8250_BCM2835AUX=y` is built-in. The compatible string `"brcm,bcm2835-aux-uart"` matches the driver. The issue is pinctrl, not the driver itself.

### 4. QEMU model supports AUX UART

QEMU's `raspi3b` model does emulate the AUX/mini UART — no issue on QEMU side.

## Correct pinctrl reference

`bcm283x.dtsi` defines three named pinctrl groups for uart1:

| Node              | Pins    | Function |
|-------------------|---------|----------|
| `uart1_gpio14`    | 14, 15  | ALT5     |
| `uart1_gpio32`    | 32, 33  | ALT5     |
| `uart1_gpio40`    | 40, 41  | ALT5     |

The fix should use `&uart1_gpio14` instead of `&uart1_pins` in the `pinctrl-0` reference.

**Note:** The older-style DTS (`bcm2837-rpi-3-b.dts`) already correctly uses `&uart1_gpio14`.

## Related issues in meta-TinyAi layer

### `cmdline.cfg`

Sets `CONFIG_CMDLINE="console=ttyAMA1,115200"` — **wrong**. There is no `ttyAMA1` on Pi 3B+. Only `ttyAMA0` (PL011 UART) exists.

**Fix:** Change to `CONFIG_CMDLINE="console=serial0,115200"` and let the kernel alias (`serial0 = &uart0`) resolve to the correct device.

### `sysvinit-inittab_%.bbappend`

Overrides `SERIAL_CONSOLES = "115200;ttyAMA1"` — same naming error.

**Fix:** Change to `"115200;ttyAMA0"` or keep the current `base.yaml` value `"115200;ttyAMA0 115200;ttyS0"`.

## SERIAL_CONSOLES in `configs/base.yaml`

Final confirmed value:

```yaml
SERIAL_CONSOLES: "115200;ttyAMA0 115200;ttyS0"
```

Both `ttyAMA0` (PL011) and `ttyS0` (mini UART) are included. This is correct — do not remove either.

## Fix Summary (planned, not yet applied)

| Item | File | Current (wrong) | Fix |
|------|------|-----------------|-----|
| DTS pinctrl | linux bbappend | `pinctrl-0 = <&uart1_pins>` | `pinctrl-0 = <&uart1_gpio14>` |
| kernel cmdline | `cmdline.cfg` | `console=ttyAMA1,115200` | `console=serial0,115200` |
| SERIAL_CONSOLES | sysvinit-inittab bbappend | `"115200;ttyAMA1"` | `"115200;ttyAMA0 115200;ttyS0"` |
