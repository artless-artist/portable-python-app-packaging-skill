# portable-python-app-packaging

**把 Python 应用做成「整个文件夹拷走就能跑」的 Windows 便携整合包**，不用装 Python、不写注册表、不往系统盘漏缓存。

一般来说，在 Windows 机器上，Python 应用要跑起来通常需要：装 Python、装一堆依赖、处理版本冲突、处理与其他 Python 应用依赖产生的兼容问题

而使用整合包则是更方便的做法（把应用连解释器一起塞进一个文件夹，双击就能用），本SKILL记录了制作整合包的方法，方便借助AI自行打包应用（同时记载了一些我实际踩过的坑）

## 适用范围

**适用**：带模型权重或原生推理后端（llama.cpp / ONNX / torch）的 Python 应用；依赖一堆、在别人机器上装不起来的工具；需要绿色部署（U 盘、内网机、客户机器）；要跟着上游版本走、不想每次重打包。

**不适用**：单文件小工具（走 PyInstaller 更省事）；依赖少、`pip install` 就能用的库；macOS/Linux 为主的场景（手册里的坑大半是 Windows 控制台与路径语义特有的）


## 它解决什么

将原程序制作为 `.exe` 的路线在两种情况下会失效：程序要拖几百 MB 到几 GB 的模型权重（PyInstaller 打出来启动慢、杀软误报、解压占双倍空间），或者程序要跟着上游频繁升级（打一次包等于重做一次）。

如果制作为一个整合包就没有以上问题，但代价是一堆 Windows 特有的坑：

- `bat` 里写中文 → `cmd` 按 OEM 代码页解析，结尾 CRLF 被吃掉，报 `'m' is not recognized...`
- `pip` 生成的 `Scripts\*.exe` 把安装时的绝对路径写死在自身 → 整包换个盘就废
- llama.cpp / ggml 系原生库打不开**路径含非 ASCII**的模型文件，报 `No mapping for the Unicode character...`，而且和输入文档路径无关
- 便携包会把安装路径变长 → 撞 Windows 的 259 字符上限，报错却是 `FileNotFoundError`（看起来像文件被删了）

这些麻烦会浪费我们的时间去调试解决，因此在本SKILL中把它们写成可执行的检查步骤

## 安装方法

装的就是一个文件。所有支持 Agent Skills 的工具都读同一个位置：

```
<skills 根目录>/portable-python-app-packaging/SKILL.md
```

### 1. 自己复制

把 `SKILL.md` 放进任意一个 skills 根目录下的 `portable-python-app-packaging/` 子目录里，没有子目录就自己建：

| 工具 | 根目录 |
|---|---|
| WorkBuddy / CodeBuddy | `~/.workbuddy/skills`、`~/.codebuddy/skills` |
| Claude Code | `~/.claude/skills` |
| Cursor | `~/.cursor/skills` |
| GitHub Copilot | `~/.copilot/skills` |
| Codex / Cline / Warp / Zed / Kimi | `~/.agents/skills`（共用） |

如果只希望在一个项目中使用这个 skill , 换成 `<项目>/.claude/skills` 之类。

### 2. 用安装脚本

双击 `install.bat` 

按提示走三步：选用户级还是项目级 → 选装给哪些工具（本机已装的会自动列出来，回车即默认）→ 确认。全程只复制文件，中途关窗口就什么都不改。

### 3. 让 AI 代装

下载后把 Skill.md 交给 agent，然后说：

> 安装这个 SKILL.md


## 使用方法

装好之后不用记任何命令，直接把需求说出来，Agent 会自己去读这份手册：

> 帮我把这个项目做成便携整合包，双击就能用，不要依赖本机环境

或者不必找到具体的项目，可以先说所需功能，待AI找到项目后再说将这个项目制作为整合包

会被自动匹配的说法：便携化、便携整合包、一键启动、免环境、绿色版、不依赖本机环境、portable、python-build-standalone、硬件加速、GPU 加速、分享整合包、打包上传、首启自举、分发边界。

## 里面有什么

| 章节 | 讲什么 |
|---|---|
| 先花一分钟定位你的项目 | 按项目形态给出必读/可跳清单：有没有"按需下载的东西"、有没有原生推理后端 |
| 目录形态 + 六条硬规则 | bat 纯 ASCII、弃用 `Scripts\*.exe`、环境隔离一次到位、非 ASCII 路径红线、子进程复用包内解释器、模型预置而非运行时下载 |
| 验收方法论 | 净化环境测试（故意注入脏 `PYTHONPATH`）、`cp -al` 硬链接秒级搬移测试、"卡死 vs 慢"的判据 |
| 改造交互层 | 只改自己那层、先查上游 CLI 是否已支持、monkey-patch 而非改源码，以及"证明上游没被碰"的两条命令 |
| 可选组件集（分档下载）| 询问闸门不能按"资产齐不齐"判、偏好持久化、只问一次、必测的 6×3 回归矩阵；上游 UI 自带选择器时为什么不能重复问 |
| 硬件加速核查 | 后端类型识别（ggml / ONNX / torch）、隔离测吞吐、显存台阶比 GPU 利用率可靠、A/B 顺序污染陷阱 |
| 对外分发 | 可再生 / 不可再生二分法、GitHub 100MB 单文件红线、`.gitignore` 用 `git add --dry-run` 实测、锁表可解析性、许可证署名义务、README 必备章节 |
| Windows MAX_PATH | 259/260 实测边界、`\\?\` 为什么不管用、原子写多吃的 18 字符、5 分钟定位法、给用户的三档解法 |
| 控制台多空行 | 行宽正好等于窗口列数会多换一行、显示宽度计算、装到 `builtins.print` 的折行修法 |
| 上游出新版 | 就地升级而非重打包、`--dry-run` 先看动几个包、四处必查、"照旧版写死"的三类常量、CLI 参数改名与同名不同义的探测法 |

文中案例全部标在 `>` 引用块里（贯穿案例是 MinerU），可以整块跳过，不影响规则本身的通用性。

## 案例说明

Skill基于我制作的 **MinerU**（开源 PDF/文档解析工具）整合包为案例，记录了制作整合包时可能的坑作为示例，换成其他 Python 项目，套路一样