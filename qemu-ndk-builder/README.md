# qemu-ndk-builder

Cross-compile **[QEMU](https://www.qemu.org/)** for **Android aarch64** using the **Android NDK** Clang toolchain.

The tarball bundles QEMU system emulation (`qemu-system-aarch64`) and user-mode emulators (`qemu-aarch64`, `qemu-arm`) with required runtime shared libraries (GLib).

## Output

| File | Description |
|---|---|
| `qemu-<version>-aarch64-linux-android.tar.gz` | QEMU binaries + GLib shared libraries |

Download from [GitHub Pages](https://zishuowang696.github.io/qemu-ndk-builder/) (once Pages is configured):

```bash
wget https://zishuowang696.github.io/qemu-ndk-builder/qemu-11.0.0-aarch64-linux-android.tar.gz
tar xzf qemu-11.0.0-aarch64-linux-android.tar.gz
# ./bin/qemu-system-aarch64  (system emulation)
# ./bin/qemu-aarch64          (user-mode, 64-bit)
# ./bin/qemu-arm              (user-mode, 32-bit)
```

## Dependencies

| Dependency | Version | Source |
|---|---|---|
| QEMU | 11.0.0 | [download.qemu.org](https://download.qemu.org/) |
| GLib | 2.82.5 | [glib-ndk-builder](https://github.com/zishuowang696/glib-ndk-builder) |
| libfdt | 1.7.1 | Built from dtc source (static lib) |
| pixman | bundled | Built from QEMU subproject |
| NDK | r28 | [developer.android.com/ndk](https://developer.android.com/ndk) |

## Build locally

Requires: `wget`, `unzip`, `make`, `python3-pip`, `ninja-build`, `pkg-config`

```bash
git clone https://github.com/zishuowang696/ci-meta-lib-open.git
cd ci-meta-lib-open/qemu-ndk-builder
bash build-qemu.sh
```

The tarball will be in `output/`.

### GLib tarball

The script expects a pre-built GLib tarball from [glib-ndk-builder](https://github.com/zishuowang696/glib-ndk-builder).
It downloads it from the glib-ndk-builder GitHub Pages site by default.

If Pages is not available, set a custom URL:

```bash
GLIB_TARBALL_URL=<url> bash build-qemu.sh
```

### CI pipeline

```yaml
# Provide GLib tarball URL as a repo secret
GLIB_TARBALL_URL: ${{ secrets.GLIB_TARBALL_URL }}
```

## Target

- Architecture: aarch64 (arm64-v8a) + arm (32-bit compat)
- Android API level: 21
- C library: bionic (Android's native libc)
- Toolchain: NDK r28 LLVM/Clang

## Build targets

| Target | Emulator | Use case |
|---|---|---|
| `aarch64-softmmu` | `qemu-system-aarch64` | Full system emulation (boot a VM) |
| `aarch64-linux-user` | `qemu-aarch64` | Run aarch64 Linux binaries (user-mode) |
| `arm-linux-user` | `qemu-arm` | Run 32-bit ARM Linux binaries (user-mode) |

## Disabled features

The following features are disabled due to Android/bionic limitations or missing dependencies:

KVM, HVF, WHPX, Xen, GTK, SDL, OpenGL, virglrenderer, VNC, seccomp, Linux AIO, io-uring, libusb, SPICE, GnuTLS, tools, docs, slirp
