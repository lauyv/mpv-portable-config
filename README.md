# mpv-portable-config

个人 [mpv](https://mpv.io/) 便携配置，带 AI 超分（GLSL shader）、补帧（FFmpeg `fruc_vulkan` / NVIDIA Optical Flow）、浮动 OSC、本地字幕自动加载与字体目录识别，**零外部滤镜环境依赖（无 VapourSynth）**。所有配置集中在 `portable_config/`，放在 mpv 可执行文件旁即可便携使用，macOS / Windows 通用。

## 特性

- **高质量播放** — Vulkan GPU API + `high-quality` profile
- **AI 超分** — ArtCNN GLSL shader（Ani4K / AniSD，mpv 渲染器内直接运行，零依赖）
- **补帧** — FFmpeg `fruc_vulkan` 调用 NVIDIA Optical Flow 硬件生成中间帧，低帧率视频自动补至 60 fps
- **OSC** — 浮动布局、窗口标题与原生右键菜单
- **字幕** — 模糊自动加载 + 字体目录自动解析
- **便携** — 配置 / shader 全部自包含
- **自动更新** — `update-mpv.sh` 拉取最新 macOS nightly

## 目录结构

```
portable_config/
├── mpv.conf                     # 主配置（Vulkan、OSC、缓存、字幕、在线视频）
├── input.conf                   # 按键绑定
├── scripts/
│   └── sub-fonts-dir-auto.lua   # 字幕字体目录自动解析
├── shaders/                     # 超分 shader（ArtCNN GLSL）
├── _cache/                      # 运行时缓存（git 忽略）
└── _watch_later/                # 播放位置记忆（git 忽略）
update-mpv.sh                    # macOS nightly 更新脚本
```

## 快速开始

### macOS

```bash
# 1. 克隆到 mpv 可执行文件旁（mpv.app bundle 的同级目录）
git clone https://github.com/srk24/mpv-portable-config.git
# 2. 下载 / 更新最新 macOS nightly
./update-mpv.sh
# 3. 直接使用
mpv 你的视频文件
```

mpv 会自动识别可执行文件旁的 `portable_config/`。超分 shader（Alt+1/2/3）即开即用，无需额外环境。

### Windows

1. 下载 mpv 的 Windows 构建（nightly 或 shinchiro 版），把本仓库 `portable_config/` 放在 mpv.exe 同级目录。
2. NVIDIA 用户使用 2026-09-02 之后构建、且包含 `fruc_vulkan` 的 mpv/FFmpeg，并安装最新显卡驱动：见 [补帧](#补帧)。

## 补帧

### Windows + NVIDIA：fruc_vulkan

本项目不使用 NVIDIA App 的 Smooth Motion，也不依赖 VapourSynth。Windows 下检测到低于 60 fps 的视频时，配置会自动加载 FFmpeg 的 `fruc_vulkan` 滤镜。1080p 及以下使用最高质量的 `perf=slow`，高于 1080p（包括 2160p）使用更注重实时性能的 `perf=fast`：

```ini
[fruc-vulkan]
profile-cond=platform == "windows" and container_fps > 0 and container_fps < 60 and height <= 1080
profile-restore=copy
vf-append=@frc-input:format=fmt=vulkan
vf-append=@frc:fruc_vulkan=fps=60:perf=slow

[fruc-vulkan-2160p]
profile-cond=platform == "windows" and container_fps > 0 and container_fps < 60 and height > 1080
profile-restore=copy
vf-append=@frc-input:format=fmt=vulkan
vf-append=@frc:fruc_vulkan=fps=60:perf=fast
```

`fruc_vulkan` 是 FFmpeg libavfilter 内置滤镜，通过 Vulkan 的 `VK_NV_optical_flow` 扩展在 NVIDIA Optical Flow Accelerator 上计算双向光流，并合成运动补偿中间帧，目标帧率为 60 fps。本项目为 1080p 及以下使用最高质量的 `perf=slow`，为高于 1080p（包括 2160p）使用更注重实时性能的 `perf=fast`；两个档位均不显式指定 `grid`，使用滤镜默认值。

- **硬件**：需要支持 Vulkan Optical Flow 的 NVIDIA 显卡；建议 Ampere / RTX 30 系及更新架构
- **软件**：需要 2026-09-02 之后构建、且包含 `fruc_vulkan` 的 mpv/FFmpeg，以及最新 NVIDIA 驱动。可用 `mpv --vf=help | findstr fruc_vulkan` 检查滤镜是否存在
- **数据路径**：`@frc-input` 使用 `format=fmt=vulkan` 为 FRC 准备输入帧；需要时会执行格式转换或上传，再交给 `fruc_vulkan`
- **质量/性能**：`perf` 是光流计算的性能预设：`slow` 计算更充分、质量较高但开销最大，`medium` 在质量与速度间折中，`fast` 最快，但复杂运动和遮挡区域更容易出现扭曲或重影。`grid` 是光流矢量网格粒度：`grid=1` 最精细、开销最大，`grid=2` 和 `grid=4` 会依次使用更粗的网格来降低开销，但小物体和运动边缘的精度可能下降。因此，4K 等高分辨率若无法实时播放，可先把 `perf=slow` 改为 `medium` 或 `fast`，仍不流畅时再把 `grid` 增加到 `2` 或 `4`
- **临时开关**：`Alt+4` 原子切换 FRC 输入准备和 FRUC 两个滤镜
- 此处的 FFmpeg 指 mpv 内部链接的库；无需另外安装 `ffmpeg` 命令行程序，FRUC 也不会启动额外进程

如使用 VRR 显示器，或更看重整数倍插帧的一致性，可将 NVIDIA profile 改为下面的可选方案：输入帧率不高于 30 fps 时补至 3 倍，高于 30 且不高于 60 fps 时补至 2 倍。

```ini
[fruc-vulkan]
profile-cond=platform == "windows" and container_fps > 0 and container_fps <= 60
profile-restore=copy
vf-append=@frc-input:format=fmt=vulkan
vf-append=@frc:fruc_vulkan=fps=[source_fps*if(lte(source_fps,30),3,2)]:perf=slow
```

### Windows + AMD：amf_frc（替代方案）

AMD 显卡不支持 `fruc_vulkan`。`amf_frc` 当前只接受 D3D11 输入，因此不能直接沿用全局的 `gpu-api=vulkan`。AMD 用户需删除或注释 `[fruc-vulkan]` profile，并用下面的完整 profile 替换：

```ini
[amf-frc]
profile-cond=platform == "windows" and container_fps > 0 and container_fps <= 30
profile-restore=copy
gpu-api=d3d11
gpu-context=d3d11
hwdec=d3d11va
d3d11va-zero-copy=yes
vf-append=@frc-input:format=fmt=d3d11
vf-append=@frc:amf_frc=profile=auto
# 低性能 GPU/APU 可用下一行替换上一行：
# vf-append=@frc:amf_frc=profile=auto:mv-search=performance
```

`gpu-api=d3d11` 控制 mpv 的输出渲染后端，`format=fmt=d3d11` 则保证送入 AMF 的帧位于 D3D11 硬件表面；两者用途不同。`d3d11va-zero-copy=yes` 可减少解码、滤镜和渲染之间的 GPU 内部复制。

- **输出帧率**：AMF FRC 固定将输入帧率翻倍，因此 profile 只对不高于 30 fps 的视频自动启用（24→48、25→50、30→60），它不像 `fruc_vulkan` 那样可以指定固定的 60 fps
- **质量**：`profile=auto` 在低于 1440p 时选择 `high`，在 1440p 及更高分辨率时选择 `super`；也可手动指定 `low`、`high` 或 `super`
- **低性能 GPU/APU**：用示例中的注释行替换默认 `amf_frc` 行，以 `mv-search=performance` 降低运动搜索开销
- **临时开关**：AMD 与 NVIDIA profile 共用 `@frc-input` / `@frc` 标签，因此 `Alt+4` 无需修改即可切换当前 FRC 滤镜链

## 使用

### AI 超分 / 变速

| 按键    | 功能                                                    |
| ------- | ------------------------------------------------------- |
| `Alt+1` | 切换 ArtCNN C4F32_DS 超分 shader（官方模型，降噪+锐化） |
| `Alt+2` | 切换 ArtCNN Ani4K 超分 shader                           |
| `Alt+3` | 切换 ArtCNN AniSD 超分 shader                           |
| `Alt+4` | 切换当前 FRC 补帧链（NVIDIA FRUC / AMD AMF）            |

超分 shader 在 mpv 渲染器内直接运行（GPU 神经网，零外部依赖）；补帧方案详见 [补帧](#补帧)。

### 按键绑定

| 按键                | 功能                          |
| ------------------- | ----------------------------- |
| `Space` / 播放键    | 播放 / 暂停                   |
| `右键`              | 上下文菜单（mpv 内置，0.41+） |
| `Ctrl+V`            | 从剪贴板加载 URL 播放         |
| `l` / `L`           | 播放列表选择（mpv 内置）      |
| `←` / `→`           | 后退 / 前进 10 s              |
| `Ctrl+←` / `Ctrl+→` | 后退 / 前进 10 min            |
| 滚轮                | 音量 ±2                       |
| `m` / `M`           | 静音                          |
| `t` / `T`           | 播放统计                      |
| `` ` ``             | 控制台                        |
| `ESC`               | 退出全屏                      |
| `Enter` / 双击左键  | 全屏切换                      |
| `Ctrl+T`            | 窗口置顶                      |
| `Q` / `q`           | 退出                          |

### 右键菜单

`input.conf` 的右键绑定（`MBTN_RIGHT script-binding select/context-menu`）由 **mpv 内置脚本提供**（mpv 0.41+，nightly 已包含），**无需任何第三方脚本**：

- 内置 `select.lua` 注册 `select/context-menu` 绑定，弹出菜单（优先内置 context_menu.lua 的 ASS 菜单，部分平台走原生 `context-menu` 命令）
- `l` 键的播放列表选择（`select/select-playlist`）同样内置

### 在线视频

mpv 原生支持 yt-dlp 在线播放，`mpv.conf` 内置 cookies：

```bash
mpv "https://www.youtube.com/watch?v=xxxxxx"
mpv "https://www.bilibili.com/video/BVxxxxxx"
```

## 注意事项

- **无 VapourSynth**：AI 管线全部为 shader / 驱动级 / mpv 内置实现。
