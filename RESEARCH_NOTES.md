# Research Notes — Yocto TinyAi CI Pipeline

## 1. Yocto DISTRO_FEATURES 机制分析

### 关键发现

`poky.conf` 设置 `DISTRO_FEATURES ?= ""`（空值），但 `base.bbclass` 中的 anonymous python 函数 `filter_default_features("DISTRO_FEATURES", d)` 会在解析时自动将 `DISTRO_FEATURES_DEFAULTS` 中未被 `DISTRO_FEATURES_OPTED_OUT` 排除的特性追加到 `DISTRO_FEATURES` 中。

### 数据流

1. `poky.conf`: `DISTRO_FEATURES ?= ""` — 条件赋值，如果未设置则为空
2. `default-distrovars.inc` (来自 openembedded-core): 定义 `DISTRO_FEATURES_DEFAULTS`，包含 26 个特性：
   - audio: alsa, pulseaudio
   - connectivity: bluetooth, wifi, 3g, nfc
   - display: x11, wayland
   - graphics: opengl, vulkan
   - filesystem: ext2, vfat
   - network: nfs, zeroconf
   - misc: usbgadget, usbhost, ptest, debuginfod, gobject-introspection-data, multiarch, ldconfig, largefile, ipv6, kvm, virtualization
3. `base.bbclass`: anonymous python 调用 `filter_default_features`，将 `DISTRO_FEATURES_DEFAULTS` 减去 `DISTRO_FEATURES_OPTED_OUT` 的结果追加到 `DISTRO_FEATURES`

### 对 TinyAi 的影响

当前 `tinyai.conf` 继承 `poky`，因此获取了所有 26 个默认 OE 特性，即使其中很多（如 x11, wayland, bluetooth, wifi, opengl, vulkan, pulseaudio 等）对嵌入式 AI 设备完全不需要。

### 解决方案：`DISTRO_FEATURES_OPTED_OUT`

参考 `poky-tiny.conf` 的模式：
- 先用 `DISTRO_FEATURES_OPTED_OUT = "*"` 排除所有默认特性
- 再在 `DISTRO_FEATURES` 中明确只保留需要的特性（如 usbhost, largefile, ipv6）

### TinyAi 建议保留的特性

基于嵌入式 AI 设备（带 llama-cpp 的 Raspberry Pi 3B）的需求：

| 特性 | 保留？ | 说明 |
|------|--------|------|
| usbhost | ✅ 保留 | USB 键盘/存储 |
| largefile | ✅ 保留 | 大模型文件 |
| ipv6 | ✅ 保留 | 网络连接 |
| ldconfig | ✅ 保留 | 动态库管理 |
| alsa | ❌ 排除 | 无音频需求 |
| pulseaudio | ❌ 排除 | 无音频需求 |
| bluetooth | ❌ 排除 | 无蓝牙需求 |
| wifi | ❌ 排除 | 有线网络 |
| 3g | ❌ 排除 | 无蜂窝需求 |
| nfc | ❌ 排除 | 无 NFC 需求 |
| x11 | ❌ 排除 | 无显示需求 |
| wayland | ❌ 排除 | 无显示需求 |
| opengl | ❌ 排除 | 无 GPU 加速需求 |
| vulkan | ❌ 排除 | 无 GPU 加速需求 |
| ext2 | ❌ 排除 | 使用 ext4/overlayfs |
| vfat | ❌ 排除 | 不需要 FAT 支持 |
| nfs | ❌ 排除 | 不需要 NFS |
| zeroconf | ❌ 排除 | 不需要 mDNS |
| ptest | ❌ 排除 | 目标设备不跑测试 |
| debuginfod | ❌ 排除 | 不需要调试信息服务器 |
| gobject-introspection-data | ❌ 排除 | GLib 相关，不需要 |
| multiarch | ❌ 排除 | 单架构设备 |
| usbgadget | ❌ 排除 | 不需要 USB gadget 模式 |
| kvm | ❌ 排除 | 不需要虚拟化 |
| virtualization | ❌ 排除 | 不需要虚拟化 |

---

## 2. TinyAi Python 依赖分析

### 结论

**TinyAi 目标文件系统中不含 Python 3。** 已确认所有相关 recipe 均不引入 python3。

### 检查清单

| Recipe | 是否有 python3 RDEPENDS？ | 备注 |
|--------|--------------------------|------|
| `llama-cpp` (meta-TinyAi) | ❌ 无 | 纯 C++ 编译，无 Python 依赖 |
| `tinyai-demo` (meta-TinyAi) | ❌ 无 | 无 Python 运行时依赖 |
| `tinyai-model-qwen` (meta-TinyAi) | ❌ 无 | 只下载模型文件 |
| `tinyai.conf` (distro) | ❌ 无 | 无 DISTRO_EXTRA_RDEPENDS 含 python |
| `layer.conf` (meta-TinyAi) | ❌ 无 | 仅添加路径和 BBFILES |

### 约束（已保存到 memory）

> TinyAi distro 的任何 recipe 都不得引入 python3 到 target rootfs。如果未来需要添加 recipe，必须确认其不依赖 python3 运行时。

---

## 3. Yocto 6.0 (Scarthgap) UNPACKDIR 变更

### 背景

Yocto 6.0 引入了 `UNPACKDIR` 变量，将源文件解包位置从 `${WORKDIR}` 改为 `${UNPACKDIR}`（默认 `${WORKDIR}/sources`）。所有使用 `file://` SRC_URI 的 recipe 需要更新。

### 已应用的补丁

| 文件 | 变更 | 状态 |
|------|------|------|
| `meta-TinyAi/recipes-support/fmt/fmt_9.1.0.bbappend` | 将 `${WORKDIR}/fmt-9.1.0` 改为 `${UNPACKDIR}` | ✅ 已应用 |
| `ci-meta-lib-open/layers/meta-raspberrypi/recipes-kernel/linux/linux-raspberrypi_%.bbappend` | 将 `${WORKDIR}/` 改为 `${UNPACKDIR}/` | ✅ 已应用 |
| `meta-TinyAi/recipes-init/udev-init-scripts/udev-init-scripts_35.bbappend` | 使用 `${UNPACKDIR}` | ✅ 已应用 |
| `meta-raspberrypi/recipes-connectivity/bluez5/bluez5` | 搜索到此目录也有 UNPACKDIR 问题 | 📌 可能也需要补丁 |

---

## 4. CI/CD 管道设计

### GitHub Actions Workflow

**文件**: `ci-meta-lib-open/.github/workflows/build.yml`

### 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 触发方式 | workflow_dispatch（手动触发） | 构建耗时数小时，不自动触发 |
| 构建矩阵 | 3 个 config（poky, poky-tiny, tinyai） | 一次性测试所有目标 |
| 超时时间 | 480 分钟 | 首次构建可能需要 6-8 小时 |
| 缓存策略 | downloads + sstate，save-always: true | 避免缓存浪费，确保每次都有缓存 |
| sstate 缓存键 | `yocto-sstate-v1-${{ runner.os }}-${{ matrix.config }}` | 按配置隔离 sstate，避免冲突 |
| downloads 缓存键 | `yocto-downloads-v1-${{ runner.os }}` | 下载源在所有配置间共享 |
| restore-keys | 有 prefix fallback | 缓存未命中时回退到旧缓存 |

### 缓存注意事项

- `save-always: true` 是 GitHub Actions cache v2 的特性，即使步骤失败也保存缓存
- 这是关键设置：4 小时构建如果最后一步失败，没有 save-always 会导致之前的构建缓存全部丢失
- sstate 按 config 隔离很重要，因为不同 distro 的 sstate 签名不同

---

## 5. 本地开发工作流

### kas-container 使用

| 用途 | 命令 |
|------|------|
| 完整构建 | `kas-container build local-llamcpp.yaml` |
| 单 recipe 构建 | `kas-container shell local-llamcpp.yaml -c 'bitbake llama-cpp'` |
| 交互式 shell | `kas-container shell local-llamcpp.yaml` |

### 项目结构

```
/home/wb/labopen/
├── ci-meta-lib-open/       # CI 配置和层管理
│   ├── .github/workflows/build.yml
│   ├── local-llamcpp.yaml  # 本地调试用 kas 配置
│   ├── raspi-3b64-*.yaml   # CI 构建配置（3 个）
│   └── layers/             # 检出的各层
│       ├── bitbake/
│       ├── openembedded-core/
│       ├── meta-yocto/
│       ├── meta-raspberrypi/
│       └── meta-TinyAi/     # 符号链接或克隆
├── meta-TinyAi/             # 独立仓库（自定义层）
│   ├── conf/distro/tinyai.conf
│   ├── recipes-core/tinyai-demo/
│   ├── recipes-support/llama-cpp/
│   ├── recipes-support/llama-cpp-model-qwen/
│   └── recipes-init/udev-init-scripts/
```

---

## 6. 状态快照（2026-04-26）

| 项目 | 状态 |
|------|------|
| CI workflow 文件 | ✅ 已推送 |
| 所有 layer checkout | ✅ 完成 |
| UNPACKDIR 补丁 | ✅ 关键补丁已应用 |
| DISTRO_FEATURES 优化 | ⏳ 待用户确认 |
| CI 运行 24959677566 | 🔄 进行中（~2h） |
| 本地 kas 构建 | 🔄 后台运行中（heuristic_kowalevski） |

### 待办

- [ ] 获得用户确认后添加 `DISTRO_FEATURES_OPTED_OUT` 到 `tinyai.conf`
- [ ] 检查 CI 运行结果（成功/失败）
- [ ] 检查本地构建进度
- [ ] 如果 CI 成功：检查 sdimg 大小，发布 Release
- [ ] 如果构建失败：诊断并修复
