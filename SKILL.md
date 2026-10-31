---
name: portable-python-app-packaging
description: >
  把一个 Python 应用打包成「整个文件夹拷走就能跑」的 Windows 便携整合包，
  不依赖目标机已装 Python、不写注册表、不往系统盘散落缓存。
  覆盖：python-build-standalone 运行时装包、包内数据目录自定位（*_HOME/TEMP/APPDATA 全重定向）、
  pip 生成的 Scripts\*.exe 内嵌绝对路径导致搬移即废的替代方案、bat 入口必须纯 ASCII、
  以及原生库（llama.cpp/ggml、ONNX Runtime、torch）在非 ASCII 路径下加载失败的坑；
  附「可选组件/分档下载」的首启自举设计（询问闸门、偏好持久化、上游 UI 自带选择器时别重复问）；
  附「硬件加速核查」流程（后端识别、隔离测吞吐、逐阶段耗时占比、A/B 顺序污染陷阱）；
  附「对外分发」流程（可再生 vs 不可再生二分法定上传边界、GitHub 100MB 单文件上限、
  .gitignore 用 git add --dry-run 实测验证、锁表依赖可解析性核验、再分发许可证署名义务）；
  附两条 Windows 隐性硬限制（MAX_PATH 259/260 边界、控制台行宽正好占满会多出一空行）
  与「上游出新版就地升级而不重打包」。
  适用于"便携整合包""一键启动""不依赖本机环境""拷走就能用""绿色版""portable"，
  "这个包能不能用显卡加速/兼容性如何"，以及"怎么分享出去/上传哪些/写 README"这类追问。
  Triggers: 便携化、便携整合包、一键启动、免环境、绿色版、不依赖本机环境、portable、python-build-standalone、硬件加速、GPU 加速、分享整合包、打包上传、首启自举、分发边界、可选组件、分档下载、绿色部署、U盘运行、免安装。
agent_created: true
---

# Python 应用便携整合包（目录形态，非单文件 exe）

适用场景：程序带模型权重、带原生推理库（llama.cpp / ONNX Runtime / torch）、依赖一串在
别人机器上装不起来的 pip 包，或者要频繁跟着上游升级——这类程序**不适合**打单文件 exe
（小工具另说，PyInstaller 更省事），做成一个目录、双击 `.bat` 即用，升级只换几个包、模型不动。

## 先花一分钟定位你的项目

别从头顺读。这份手册有几节只在特定形态下成立，先对号入座：

| 你的项目 | 必读 | 可整节跳过 |
|---|---|---|
| 带模型权重、本地推理 | 全部 | — |
| 带模型 + 分档下载（小/大模型能分开装） | 全部，重点 §可选组件集 | — |
| 只有 pip 依赖、没有模型 | 硬规则 1/2/3/5、验收方法论、对外分发、MAX_PATH、控制台多空行 | 硬规则 6、可选组件集、硬件加速核查 |
| 依赖里有原生库（`.pyd`/`.dll`/`.so`） | 硬规则 4、硬件加速核查 | — |
| 要跟上游版本走、不能每次重打包 | §上游出新版 | — |

两个前置判断，决定后面近一半内容适不适用：

1. **有没有「按需下载的东西」**（模型分大小档、可选语言包、可分离的插件）？
   没有 → §可选组件集整节跳过。
2. **有没有原生推理后端**（llama.cpp / ONNX Runtime / torch / TensorRT）？
   没有 → §硬件加速核查整节跳过。

> **关于文中的 MinerU**：它是这份手册的贯穿案例（开源文档解析工具），代码片段是它的真实实现，
> 坑是它真踩过的，数字是实测的。案例一律用 `>` 引用块标出，可以整块跳过。
> 占位符约定：`<APP>` 环境变量前缀、`<app>` 命令前缀、`<依赖包>` 具体依赖名、`<KIT>` 包根目录、
> `<项目>` 上游项目名。看到占位符就换成你自己的。

## 目录形态

```
<包>\
  启动<名字>.bat          ← 纯 ASCII，入口（可再放一份 Start-<Name>.bat 别名）
  runtime\python\        ← python-build-standalone 解压出来的解释器（自带，勿删）
  app\                   ← 自己的启动器代码
    launcher.py          ← 菜单/交互，所有中文提示都在这里 print
    cli.py               ← 命令转发：python app\cli.py <命令名> [参数]
    env_setup.py         ← 环境隔离的唯一真相来源
    bin\*.bat            ← 每个官方命令一个外壳
  data\                  ← 包内「用户目录」：models\ logs\ temp\ appdata\ localappdata\ *-cache\
  output\                ← 默认输出
  使用说明.txt            ← 带 UTF-8 BOM + CRLF，否则老版记事本乱码
```

## 六条硬规则（第 6 条只对带模型的项目成立，其余五条谁都躲不掉）

1. **bat 必须纯 ASCII**（0 个非 ASCII 字节）。cmd.exe 按 OEM 代码页（zh-CN 下是 936）解析 bat，
   UTF-8 中文会把结尾 CRLF 吃掉、和下一行粘连，报 `'m' is not recognized as an internal command` 之类鬼错。
   开头 `chcp 65001 >nul 2>&1`，**中文提示全部由 Python 打印**
   （Python 侧 `sys.stdout.reconfigure(encoding="utf-8", errors="replace")`）。
   校验：`LC_ALL=C tr -d '\0-\177' < x.bat | wc -c` 必须是 0。

2. **不要用 pip 装出来的 `Scripts\*.exe`**。它们把安装时的 python.exe 绝对路径写死在自身，
   整包换个盘符/目录就失效。改为每个命令写一个 bat 外壳，走相对路径调包内解释器：
   ```bat
   set "ROOT=%~dp0..\.."
   "%ROOT%\runtime\python\python.exe" "%ROOT%\app\cli.py" <命令名> %*
   ```
   同时 **PATH 里 `app\bin` 必须排在 `Scripts` 之前**，否则用户敲命令会命中坏的 exe。

3. **环境隔离要一次到位**（集中写在一个 `env_setup.py`，别散落）。要重定向的变量分三类：
   - **程序私有**：上游认的"根目录变量"，如 `<APP>_HOME`。换项目就换名字——去源码
     `grep -i "os.environ"` 看它到底认哪些，别照别人的清单抄。
   - **系统级**：`TEMP`/`TMP`、`APPDATA`、`LOCALAPPDATA`，以及各种框架缓存根
     （`HF_HOME`、`TORCH_HOME`、`XDG_CACHE_HOME` …）全部指向包内。
   - **遥测开关**：`DO_NOT_TRACK`、`<框架>_ANALYTICS_ENABLED`、`HF_HUB_DISABLE_TELEMETRY`
     一类。便携包的默认立场是不上报，顺手关掉。

   案例（MinerU）：`MINERU_HOME`、`GRADIO_TEMP_DIR`、`MODELSCOPE_CACHE`、
   `GRADIO_ANALYTICS_ENABLED`、`HF_HUB_DISABLE_TELEMETRY`、`DO_NOT_TRACK` → 全部指向包内。

   Python 侧还要 `PYTHONUTF8=1`、`PYTHONIOENCODING=utf-8`、`PYTHONNOUSERSITE=1`，
   **`PYTHONPATH` / `PYTHONHOME` 必须 pop 掉**（宿主机注入的会污染便携解释器）。
   `LOCALAPPDATA` 改掉后，某些驱动会把 shader 缓存写进它的兄弟目录 `LocalLow` ——
   顺手在包内也建一个 `LocalLow\`，否则缓存会漏到真实用户目录。

4. **⚠️ 包所在路径必须能给出合法 ASCII 字符串（关键坑）**
   llama.cpp / ggml 系原生库（`.pyd`/`.dll`）在 Windows 上**打不开路径含非 ASCII 字符的模型文件**：
   ```
   RuntimeError: No mapping for the Unicode character exists in the target multi-byte code page.
   ```
   报错发生在 `Engine(...)` 构造、加载 `.gguf` 的那一刻，**和输入文档路径无关，只看模型文件的路径**。
   实测：路径含中文必挂；**路径含空格没问题**；同一台机器（ACP=936、`'中文'.encode('mbcs')` 正常）
   也照样挂，所以别指望"代码页对不对"能解释或绕过。
   对策：启动时检查包路径是否 `.isascii()`，不是就横幅显式告警 + 自动降级到不依赖原生库的模式
   （分档的项目就降一档；没有分档就只告警，让用户自己把包挪到纯英文路径），
   并在文档开头（不是 FAQ 深处）写清"请放到纯英文路径"。
   **不要指望 8.3 短路径救场**：`GetShortPathNameW` 可能原样返回中文（8.3 生成被关闭），
   且 `fsutil 8dot3name` 需要管理员权限；实测返回 `_迁移~1` 仍含中文，方案不可靠。

5. **子进程派生要复用 `sys.executable` / 包内解释器**。检查目标程序是否用 `sys.executable`
   拉 worker；如果是硬编码 `"python"`，便携环境下会命中宿主机的 Python。

6. **模型预置而不是运行时下载**（无模型的项目跳过本条）。
   用国内可达的源（ModelScope；`huggingface.co` 常不可达）预先拉到 `data\models\`，
   并**连上游的完成标记文件一起搬**——上游通常靠一个点文件判定"已就绪"，
   你只搬权重不搬标记，它照样重下一遍。

   > 案例（MinerU）：标记文件是 `data\models\` 下的 `.mineru_complete` 一类点文件，跟权重一起搬。

## 验收方法论（比"跑一遍看看"靠谱）

- **净化环境测试**：不要让子进程继承你的 shell 环境。手工只给
  `SystemRoot/windir/ComSpec/PATHEXT/PATH(=C:\Windows\System32;C:\Windows)/NUMBER_OF_PROCESSORS/
  PROCESSOR_ARCHITECTURE/OS`，再**故意注入 `PYTHONPATH=Z:\nope`、`PYTHONHOME=Z:\nope`**，
  把 `TEMP`/`TMP` 指到一个宿主机目录 —— 跑完这个目录必须是空的，才叫"零足迹"。
- **搬移测试**：同盘用 `cp -al`（硬链接）复制整包，秒级完成且几乎不占空间。
  前置条件：先清空可变的目录/文件（logs、temp、output、缓存、索引库），
  否则程序写这些文件会连带改到源包（同一 inode）。测试完删副本即可。
  测试路径要故意带**空格 + 中文 + 不同层级**，一次覆盖多种边界。
- **别用 `cmd | grep | head` 跑长任务**：原生库往 stdout 写日志时，管道缓冲会让进程看起来"卡死"，
  `head` 退出后还会 EPIPE。一律重定向到文件，跑完再读。
- **判断"卡死 vs 慢"**：采样进程 CPU 时间（`Get-Process ... | Select CPU`）。
  CPU 冻结 + 工作集很大 = 阻塞，不是在算。
  探针脚本"卡死"九成是自己的锅（管道缓冲 / 传了错的设备参数），先反查探针再怀疑程序。

## 改造交互层时，绝不碰上游源码

用户提的 UI / 默认值 / 提示文案改动，**先判断它落在哪一层**，再动手：

- **永远只改你自己的那层**（如 `app/launcher.py`、自写启动器）。上游包
  （`site-packages/<项目>/`）保持 `pip install` 原样，理由是：① 上游升级时能直接换 whl 重建，
  ② 再分发时许可证干净，③ 用户既定约束常是"上游源码禁改，只允许运行时 monkey-patch 实例方法"。
- **动手前先查上游 CLI 是否已支持**。想要的能力十有八九已经有参数了，只是你的封装层没暴露出来
  （案例：MinerU 的 `webui --api-server-tier` 早就存在，只是启动器把值写死成了按路径自动判定）。
  先 grep 上游 `--help` / typer Option，能省掉一整轮"改上游"的念头。
- **要改行为而 CLI 没留口子**：走 monkey-patch（运行时替换实例方法），不要编辑上游文件。
  真要给用户讲清楚，就说**"改文案不动行为"是零风险的**，"改行为"才升级为 monkey-patch。

**改完必须证明上游没被碰**（两条一起用，缺一不可）：

```bash
git status --short                    # 期望只列出你自己的文件（M app/launcher.py）
find runtime/python/Lib/site-packages/<项目> -name "*.py" -newermt "<今天日期>" | wc -l   # 期望 0
```

注意：`find ... -newer <某文件>` 会被解压时间戳误导（整包解压后所有文件时间戳相同），
**用 `-newermt <日期>` 按日期比较**，不要用 `-newer`。

### 交互改动的两个通用坑（实测踩到）

1. **改输入约定要向后兼容**。把"输入格式名"改成"输入序号"时，必须两种都接受：
   `{"1": "<格式A>", "2": "<格式B>", "3": "<格式C>"}.get(raw, raw)`，再接原有的合法性校验。
   否则老用户按文档里的字符串写法输入，会被**静默降级成默认值**——最难查的那类 bug。

   案例：MinerU 的三个格式名是 `markdown` / `zip` / `middle_json`。
2. **启动前自举的判定条件要跟随交互选择**。若 main() 阶段按"环境探测"决定下载哪一份资产，
   而菜单里又允许用户手选，两者会不一致（例：英文路径 + 精简包选了小份，
   自举仍按全份去下 1.2 GB 的 VLM 白下）。修法：在动作入口加一次**按当前选择就绪兜底**
   `if missing_modules() or not ready_for(choice): ensure_ready(choice=choice, ...)`，
   齐了零开销短路，不打扰用户。

### 验证交互改动：mock input，别真跑

用 `unittest.mock.patch('builtins.input', ...)` 喂输入序列 + patch 掉真正的执行函数
（下面案例叫 `run_upstream`，MinerU 里是 `run_mineru`）和 `pause`，
就能秒级把每条分支都走一遍，并断言最终拼出的命令行参数：

```python
inputs = iter(['2', '2'])
with m.patch('builtins.input', lambda p='': next(inputs)):
    with m.patch.object(launcher, 'run_upstream', lambda args, **k: (print(args), 0)[1]):
        launcher.action_webui()      # 断言输出里出现期望的那串参数
```

必测分支：默认值（直接回车）、每个序号、**旧格式名**、冲突自动降级、组件缺失兜底、
组件齐全时零开销。注意 mock 时 `input` 的消耗顺序——"选哪份"和"选格式"各吃一个输入，
调试时容易把"格式"误喂给前者而得出错误结论（我踩过，表现是选了 zip 却出 markdown）。

## 可选组件集（分档下载）

**先判断**：你的程序有没有"按需下载的东西"——模型分大小档、可选语言包、可分离的插件？
没有就整节跳过，直接跳到 §硬件加速核查。

各地叫法不一样（档位 / tier / preset / profile / 精简版·完整版），下面统一叫**组件集**：
一个名字对应"要装哪些东西"的一份清单。常见是两档（lite / full），也可能像案例那样做成四档。

### 首启自举若要交互：选择必须提到下载之前，且**只问一次**

若自举里要加"选组件集"这类交互，**绝不能放在下载动作之后**——否则用户盯着进度条
跑完 2 GB 才发现能选，体验极差。正确顺序：

```
① 零开销探测：够用？→ 直接 return，一句不问（全量包/已补齐必须零打扰）
② 不够 → 【立刻问】（在任何下载动作之前）
③ 按选择下载，并【把选择持久化】
④ 以后每次启动：读回持久化的选择，直接按它检查补齐，不再问
```

#### 坑（血泪教训）：闸门不能用"资产是否齐全"

第一版把询问闸门写成"资产不齐就问"：

```python
assets_complete = small and vlm          # ✗ 错的闸门：把"全都有"当成"够用"
if chooser is not None and not assets_complete:
    choice = chooser()
```

（`small and vlm` 是案例的写法——小模型和大模型都在。你的项目换成实际清单即可。）

**这会让"只想装小份"的用户每次启动都被问一遍。** 因为小份用户的常态恰恰就是
「小模型在、大组件（VLM/大模型）故意不装」——这永远落在 `not assets_complete` 里。

根因是把两个不等价的概念混为一谈：

| 概念 | 含义 |
|---|---|
| 资产是否齐全 | 这个包"理论上"能装的东西都装了没 |
| **当前组件集是否够用** | 按**用户选定那份清单**检查，够用就不该打扰 |

正确做法：**把"用户的选择"持久化成一个标记文件**，询问闸门改成「从没选过 + 选定的那份真的缺件」。

```python
# pkg_info.py —— 标记文件与其它"完成标记"放同一层（随资产一起被 .gitignore 覆盖）
CHOICE_FILE = DATA_DIR / ".component_choice"     # 内容就一行：lite / full

def read_choice() -> str | None: ...             # 读不到返回 None
def write_choice(choice: str) -> None: ...       # 失败不抛，只是下次重新问

# bootstrap.py
def ensure_ready(choice="full", argv=None, *, chooser=None, ask_if_missing=True):
    ...
    saved = read_choice()
    if saved is not None:
        choice = saved                            # ← 有偏好就以它为准

    if not missing and ready_for(choice):         # ← 关键：按【组件集】判，不是按"全不全"
        return True                               #   小份用户从此走这条路，零打扰

    if saved is None and chooser is not None and ask_if_missing:
        choice = chooser()
        write_choice(choice)                      # ← 问过就记住，绝不问第二次
```

> 案例（MinerU）里这套名字是 `TIER_CHOICE_FILE`、`.tier_choice`（取值 `basic` / `standard`）、
> `tier_chooser`、`models_ready_for(tier)`。三根桩一样，只是命名跟着"档位"走。

配套要点：

- **所有能选组件集的入口都要写盘**：首启询问、菜单里的向导、WebUI、手动补齐菜单——
  任何一处选了都 `write_choice()`，否则"记住偏好"会漏。
- **"回车沿用上次"**：询问函数的默认值取 `remembered_choice()`（读偏好，没读过再按环境推），
  提示文案动态显示 `回车=2`，让老用户一路回车即可。
- **无交互入口传 `ask_if_missing=False`**：拖文件到 bat 上直接解析（`argv` 传了路径）时没人能按回车，
  必须跳过询问、沿用记住的/推导的默认值。
- **别让状态提示误导小份用户**：横幅/自检里"组件不完整"的告警要用
  `ready_for(active_choice)` 判断，否则只装小份的用户每次启动都看到"缺 VLM"的红色提示，白担心。
- **`ask_if_missing` 这类开关比 `chooser=None` 更明确**：前者表达"允许问但这次不想问"，
  后者无法区分"没人问"和"问了但返回空"。

#### 必测的回归矩阵（每个场景连跑 3 次，数"被问了几次"）

| 场景 | 期望 |
|---|---|
| 全新用户 + 选小份（小模型在、大组件无）| 第 1 次问 1，第 2/3 次 **问 0**，零下载 |
| 全新用户 + 选全份（全缺）| 第 1 次问 1 且下全份，之后 **问 0** |
| 已选全份但大组件下载失败 | **从不问**，每次都静默尝试补齐 |
| 小份用户 + 小模型也缺了 | **从不问**，静默补小份（**不能误补大组件**）|
| 拖文件 headless（无 chooser）| 问 0，走默认选择 |
| 全份用户资产全齐（常用路径）| 问 0，零下载 |

**这组测试必须用真实的询问函数做回调**（`chooser=lambda: launcher.ask_choice(first_run=True)`，
案例里叫 `ask_tier`），不能直接 `lambda: 'lite'`——后者绕过 `input`，根本测不出"有没有被问"。
用 `mock.patch('builtins.input', fake_input)` 并在 **fake_input 里计数**才是有效测法。

#### 更隐蔽的坑：上游 UI 自带选择器时，启动前再问一遍是有害的

组件集/模式这类选项，**先查上游 UI 是不是自己就有一个选择器**。如果有，启动前的那一问
不只是多余，还会**把 UI 的选项砍掉**——因为很多上游是"服务端广告能力、前端据此渲染选项"的架构。

正确做法是**别问，改成按「本机装了什么」推导能力上限**：

```python
def advertised_capability() -> str:
    """只判断「最高能跑到哪」，具体选哪个交回界面里的选择器。"""
    small, vlm = models_ready()
    if small and vlm and path_is_ascii():
        return "standard"   # 让 UI 把所有选项都列出来
    return "basic"          # 没装大组件 / 路径非 ASCII：只广告跑得动的
```

> 案例（MinerU 4.0.10；4.1 起参数改名、取值语义也变了，见文末「上游出新版」）：
>
> ```python
> # mineru/types.py —— 服务端档位决定前端能列出哪些选项
> TIERS_BY_SERVER_TIER = {
>     "flash":    ("flash",),
>     "basic":    ("flash", "basic"),                          # 只剩 2 项
>     "standard": ("flash", "basic", "standard", "advanced"),   # 4 项全开
> }
> # mineru/kit/commands/webui.py
> api_server_tier: str = typer.Option("standard", "--api-server-tier", "--tier", ...)
> # mineru/kit/gradio/app.py —— 前端就是照抄广告出来的能力
> tier_choices = [tier for tier in TIERS if tier in capabilities.tiers]
> ```
>
> 也就是说：启动时传 `--api-server-tier basic`，**装全了模型的用户在界面里也找不到
> standard / advanced**。

配套：给被降级的用户一句**解释 + 出口**（"本机只装了 X，菜单 [5] 补下 Y 就能解锁"），
否则他会以为软件就这点功能。

**判据**：这个选项是"**下载决策**"还是"**运行期选择**"？
下载决策必须在启动前定（否则白下几个 GB）；运行期选择交给运行时 UI。
WebUI / 图形界面属于后者，CLI 向导（没有界面内选择器）属于前者。

**测试时注意同名导入的 patch 目标**：如果被测模块写的是
`from pkg_info import models_ready`（直接绑定名字），
patch `pkg_info.models_ready` **不生效**，必须 patch `launcher.models_ready`；
而 `env_setup.path_is_ascii()` 这种"模块属性调用"则 patch `env_setup.path_is_ascii` 才对。
一句话：**看它是"导入的名字"还是"模块属性"**。

### 顺带确认：分档下载命令会不会顺手下不需要的东西

"用户选了小份，之后走补齐流程，会不会把大组件也下了？"——**去上游源码找那一行 `if`**，
不要凭直觉答。要找的是"按组件集过滤清单"的那个判断函数，它长这样：

```python
repos = (small_model_repo(...),)                  # 基础组件：每份都有
if resolved_set == "full" and (...):              # ← 只有全份才追加
    repos += (large_model_repo(...),)
```

> 案例（MinerU 4.0.10 实测）：`mineru/model/registry.py :: model_repos_for_tier()` 里就是
> 上面这个形状，判断条件看的是 `resolved_tier == "standard"`。

结论：**只要传对那个参数，小份不会下大组件**。自举层把记住的选择透传给
`models download --tier <选择>` 一类命令即可，无需额外拦截。

## 硬件加速核查（带原生推理后端的包必做）

打包完"能不能跑"只是及格线；用户常会追问"能不能自动用显卡"。别凭印象答，按下面顺序实测：

1. **确认后端类型**。先看包内动态库名：`ggml-cuda.dll`=CUDA、`ggml-vulkan.dll`=Vulkan、
   `ggml-hip.dll`=ROCm、`cudnn64_*.dll` / `torch_cuda.dll`=torch 的 CUDA 版；
   再问后端自己——`onnxruntime.get_available_providers()`（CPU 版只有 `CPUExecutionProvider`）、
   `torch.cuda.is_available()`、`torch.backends.mps.is_available()`。
   注意**同一程序里不同阶段可能用不同后端**（案例：ONNX 小模型跑 CPU、llama.cpp 的 VLM 跑 Vulkan），
   要分开回答。
2. **读源码确认是否写死**。优先找 provider/device 选择函数，别信文档。
   见过 `ort_providers()` 把通用模型硬编码为 CPU、只有个别模型（表格）才允许 CUDA 的设计。
3. **让后端自己报设备**，别查注册表：
   `llama-server.exe --list-devices` 直接列出可用 Vulkan 设备（`--version` 不打印设备，别用）；
   torch 用 `torch.cuda.get_device_properties(0)`；纯 CUDA 环境用 `nvidia-smi -L`。
   还可以看 `.dll` 里的字符串（用 Python `re.finditer(rb"PREFIX_[A-Z_]+", data)` 代替 `strings`，
   Git Bash 里没有 strings）挖出后端支持的环境变量。
4. **隔离测吞吐**，而不是只看端到端：
   - 直接实例化引擎跑固定长度的 prefill + decode，比对 `n_gpu_layers` / 可见设备不同的组合；
   - 同时后台每秒 `nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits` 采样，
     **显存台阶式上涨**（如 1893→3489 MiB）就是模型真的进了显存，比 GPU 利用率可靠得多
     （Vulkan + WDDM 下利用率常报 0%）。
5. **算端到端占比再下结论**。把各阶段耗时拆出来：如果瓶颈阶段跑在 CPU（如公式识别 91s / 总计 137s），
   那么 GPU 快 20 倍对端到端也只有百分之几 —— 这种话必须用数字讲清楚。

**两个必须避开的坑**：
- **顺序污染**：多组合 A/B 连着跑，首轮冷启动（shader/ONNX graph/页缓存）会让先跑的那组虚高
  （实测差了 15s，比被测配置的差异大 4 倍）。要么打乱顺序，要么重复跑取稳定值。
- **环境变量传空/无效值**：`GGML_VK_VISIBLE_DEVICES=""` 或随便一个无效设备名，会让后端**静默回落 CPU**
  （不报错、不崩溃、结果照出）。这既是好事（稳健的 fallback），也是陷阱
  （A/B 时很容易把"设错了变量"当成"这个配置就这样"）。写测试脚本时注意区分
  "未设置" 与 "设为无效值"，别像我一样把 `__UNSET__` 这个字面量 export 进去。
- 顺手把探测结果做进自检菜单（调 `--list-devices` 打印设备列表 + ONNX provider 列表），
  让用户在目标机上一眼看到"显卡有没有被用上"，比写文档有用。

## 对外分发（分享 / 上传 GitHub）

用户说"想分享出去"时，真正的活不是压缩上传，而是**先做二分法**：哪些可再生、哪些不可再生。

### 1. 先把包拆成「不可再生 / 可再生」两类

判据只有一条：**能不能从公开源自动重新拿到？**

| 类别 | 典型内容 | 处置 |
|---|---|---|
| 不可再生（你写的） | 启动器 `app/`、引导脚本、`.bat`、文档、依赖锁表 | **必须上传**（通常只有几十~几百 KB） |
| 可再生（公开大件） | 便携运行时、PyPI 依赖、公开模型权重 | **不要上传**，首启自动下 |
| 纯垃圾 | `__pycache__`、`*.pdb`、日志/临时/缓存/输出目录 | **绝不上传**，gitignore |

实测一例：2.6 GB 的包里**只有 86 KB 是不可再生的**。把这个结论先摆给用户，
他才知道"分享"到底要传多少。

### 2. GitHub 的硬限制会否掉"传全量包"这条路

- **单文件 > 100 MB 直接拒收**（普通仓库）。带 GGUF/ONNX 权重时必然超
  （实见单个 `mmproj-*.gguf` 677 MB）→ 全量包**不能**用普通 git 仓库分发，走
  Releases / 网盘 / 对象存储。
- 权重若本来就在公开模型站（ModelScope / HuggingFace）上，**重复托管没有意义**，
  仓库只放精简包 + 首启自举即可。
- 结论：给用户**两种交付形态**（精简包 ≈ 几 MB / 全量包 ≈ 几 GB），并写清各自的适用场景。

### 3. 首启自举：三步幂等，缺什么补什么

把"跑起来需要什么 / 齐了没有"抽成**单一真相来源**模块（如 `pkg_info.py`），
由启动器（自检、横幅）和引导模块（下载）共用，避免清单在两处漂移。

三个必守点：
- **幂等**：每次先检查，齐了就静默跳过（全量包首启应当 0 提示、0 下载）。
- **只补缺的**：不覆盖已装依赖、不重下已有模型。
- **源逐个回退 + 国内优先**：如 CPython 走 NJU→USTC→GitHub；pip 走清华→阿里→PyPI；
  模型走 ModelScope。任一源成功即停。
- 必须留**逃生开关**（`APP_SKIP_SETUP=1` 或 `--skip-setup`）。
- 步骤 0（下载解释器本身）只能靠 PowerShell/bat，因为那时**还没有 Python**——
  这个脚本必须**纯 ASCII、只输出英文**（见"六条硬规则"第 1 条）。

### 4. 分享前必须实测的三件事

1. **锁表的可解析性**：`pip freeze` 出的锁表里往往有不常见的包。
   逐个核验它们在公开 PyPI 上真的存在，否则别人装不起来：
   ```bash
   python -m pip index versions <pkg> -i https://pypi.tuna.tsinghua.edu.cn/simple
   ```
2. **`.gitignore` 真的挡住了**——别肉眼看，用 git 自己算：
   ```bash
   git init -q && git add -A --dry-run | wc -l       # 期望是几十，不是几万
   git add -A --dry-run | sed "s/^add '//;s/'$//" | while IFS= read -r f; do stat -c%s "$f"; done \
     | awk '{s+=$1} END {printf "%.2f MB\n", s/1048576}'
   ```
   验证完 `rm -rf .git`，别给用户留下半个仓库。
3. **清理后功能仍完好**：删完 `__pycache__`/`.pdb` 要**重跑一次冒烟 + 一次真实端到端**，
   别只凭"这些文件本来就可再生"下结论。

### 5. 清缓存：分清楚"包内"和"本机"

- **包内**：`__pycache__`（解释器会自动重建）、`*.pdb`（调试符号，运行不需要）、
  运行期目录。实测一例清出 11714 个文件 / 229.9 MB。
  注意启动器里加 `PYTHONDONTWRITEBYTECODE=1`，否则清完一跑又回来了。
- **本机**：`pip cache purge` 是官方且零风险的方式（缓存按定义可再生），
  比 `rm -rf AppData\...\pip\cache` 稳妥，也规避了"别乱删用户目录"的红线。
  但要**先说清它不在包内、不会被上传**——用户嘴上说"清缓存"，真正关心的往往是"别传垃圾"。
- 坑：`pip cache purge` **本体干完活后进程会挂住不返回**（实见 12 分钟无输出）。
  别死等，另起一个进程 `du -sh <cache dir>` 量目录确认体积掉了就 kill 掉。

### 6. 再分发前查许可证（尤其是"在线服务署名义务"）

把上游项目的 LICENSE 读一遍，别默认 Apache/MIT 就万事大吉。最常见的是两类附加条款：
**商用门槛**（按 MAU / 营收划线）和**署名义务**（对外提供在线服务时必须在界面或公开文档
显著位置署名，违反则许可自动终止）。

处理方式：把上游 LICENSE 原文一并放进包（如 `LICENSE-<项目>.md`），
并在 README 里用一句话点明署名义务 —— 这属于"你替用户想到了他不知道的坑"。

> 案例（MinerU）：自定义许可 = Apache 2.0 + 附加条款，上面两类都有——
> 商用按 MAU / 营收划线，且基于它对外提供在线服务必须在界面或公开文档显著位置署名。

### 7. README 必备章节（按这个顺序）

一句话定位 → 快速开始（3~5 步）→ **两种分发包对照表** → 首次启动流程图 →
**上传/下载边界表** → 硬件要求与加速（带实测数字）→ **路径要求（若原生库怕非 ASCII，放显眼处）** →
目录结构 → 高级用法 → FAQ（`<details>` 折叠）→ 纯离线部署 → 如何自己构建 → 许可证与致谢。
英文 summary 放最后一段折叠即可（中文用户为主时）。

### 8. 想被 Agent 驱动？随包附一份 skill

便携包天然适合当「Agent 的执行体」——用户不想开 GUI、不想敲命令，只想要结果。做法是**把上游的
skill 适配一份放进包里**（`skills/<app>-portable/SKILL.md`），随包一起分发。

适配时**只改调用层，不动上游 skill 的领域知识**（档位、隐私、错误语义、引用规范该留就留）：

| 上游 skill 的写法 | 便携包要改成 |
|---|---|
| `command -v <app>` / `uv tool install` / 升级流程 | 删掉；改「定位包根目录 → 提示词里给出调用形式」 |
| `<app> ...`（假定在 PATH） | `<KIT>/runtime/python/python.exe <KIT>/app/cli.py <app> ...` |
| 上游的 `--json` / 错误码 / 定位符契约 | **逐个实测确认是否还成立**，不成立就换成退出码 + 产物文件 |
| 上游「后台服务 + 缓存」那套 | 若便携包里跑不通，单列一节写清「症状 + 已排除因素 + 替代路径」 |

**必须实测后写进 skill 的几件事**（凭 help 猜会写错）：

- 输出参数是**目录还是文件**、产物命名规则（跑一次看真实文件名）
- 省略关键参数时的**默认值**（这类包常在省略时回落到最重的那档 / 最全的组件集，直接导致低配机失败）
- 失败长什么样：退出码、错误文案是结构化还是散文
- 有没有 `--json`（很多"包"形态的子命令是没有的，与上游主命令不一致）

**三个可复用设计点**：

1. **单行覆盖点**：skill 顶部留 `KIT_ROOT: \`<KIT>\``，README 让用户改成实际路径。
   装到全局 skills 目录后 skill 自身位置推不出包根，这一行能免掉每次探测/反问。
2. **自动定位兜底**：从 skill 自身位置往上找 `<KIT>/启动…bat` 或 `app/bin/<cmd>.bat`；
   都不成立就**问用户**，不要猜。
3. **写清「不可用」而不是省略**：跑不通的能力要显式标注症状与替代路径，否则 Agent 会照上游
   skill 的描述去试，然后拿到一堆看不懂的报错。同时明确「**不要改上游源码来修**」。

**调用形式的坑（Git Bash 环境）**：`.bat` 外壳经 `cmd //c` 调用时**路径不能内嵌引号**
（`cmd //c "...bat \"path with space\""` 会把引号当字面量传给 bat）。所以给 Agent 的**首选形式是
直连解释器**（`python.exe app/cli.py ...`，引号处理正常），bat 只作等价备选。

**给 skill 做安全审计**：装之前扫一遍——目录里除了 `SKILL.md` 还有没有可执行文件/软链；
危险模式（`rm -rf`、管道到 shell、`Invoke-Expression`、`base64 -d`）；外联目标。
纯文档 skill 只需确认这三点，结论给 P2 即可。

## Windows MAX_PATH：便携包躲不掉的一条硬限制

**便携包会把"安装路径"变成长度的一部分**——这是它和普通安装版最容易被忽略的差异。
上游代码里任何"拼一个较长临时文件名再写盘"的地方，都会因为**包所在目录**而提前触线。

实测边界（Windows 10/11，`LongPathsEnabled=0` 的默认机器）：

```
259 字符 -> 可写      260 字符 -> FileNotFoundError: [Errno 2] No such file or directory: '<完整路径>'
```

注意报错**长得像"文件不存在"**，极易被误判成"路径写错/被删了"，实际是长度超限。

**两个反直觉的点**（都实测过）：

1. **`\\?\` 扩展前缀不管用**。CPython 的 `open()` / `zipfile` 走 CRT，实测加前缀后仍报
   `WinError 3 系统找不到指定的路径`。所以别指望在自写层加前缀绕过。
2. **原子写模式会额外吃长度**。上游常见的「先写临时目录再 rename」写法（如
   `TemporaryDirectory(prefix=".bundle-", dir=target.parent)` + `pending.replace(target)`）
   会在路径里多插一段 18 字符的 `.bundle-xxxxxxxx\`，**恰好把本来能过的路径顶过线**。
   表现极具迷惑性：同一目录下的短文件名产物（`xxx.html`）成功，长文件名产物（`xxx_markdown.zip`）失败。

**排查手法**（5 分钟定位，别猜）：

```python
# 1) 量长度：报错路径 len() 是否 > 259
# 2) 二分边界：同一目录下 259 字符 ✅ / 260 字符 ❌ 即确诊
# 3) 查开关：注册表 HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled（0=禁用）
# 4) 找对照：同一次任务里成功与失败的两条路径只差哪一段
```

**给用户的三档解法**（写进 README 常见问题）：

| 代价 | 做法 |
|---|---|
| 0 | 绕开那个产物：直接取目录里已生成好的本体文件（如 `markdown.md` + `images/`），不点"下载 zip" |
| 一次 | 启用长路径：注册表 `LongPathsEnabled=1`（DWORD），管理员 + 重启；Win10 1607+ 支持 |
| 安装时 | 让用户把整合包放在**根目录级短路径**（`C:\App` 而非 `C:\Users\...\Desktop\某项目\App`），并写进 README 的"路径要求"里 |

**自写层能做的**：启动时读一下 `LongPathsEnabled`，为 0 就提示"处理长标题文档时下载可能失败"。
注意**不要**为此去 patch 上游的命名逻辑——那属于改上游行为，得先跟用户确认。

## 控制台输出：「某一行正好占满窗口列数」会凭空多一个空行

便携包的首启菜单/向导都是纯 `print` 的中文文本，容易被一条**很反直觉的 Windows 控制台规则**
咬到：**一行的显示宽度正好等于窗口列数时，控制台会多做一次换行**。真控制台实测（`chcp 65001`）：

```
67 列窗口：`  提示：选 basic 可省下约 1.2 GB；以后想升级，菜单 [5] 可随时补下。`（正好 67 格）
           -> 后面凭空多出一个空行，提示符被挤低一行
68 列窗口：同一屏、同一份代码 -> 没有那个空行
```

**危害**：菜单里往往有若干条正好占满整行的文案（本例的显示宽度是 52 / 63 / 66 / 67 / 71 列），
只要使用者的窗口列数正好落在其中某个值上，整屏就**整体漂一格**。再叠加"某些终端会自己镜像
控制台缓冲区"（ConEmu/Cmder/ansicon 之类），就会表现成使用者投诉的那种
**"我敲的字跑到上一行去了"**——而脚本这边其实一行光标定位都没做过。

**排查**：拿每行文案的显示宽度（CJK 算 2 列）去比窗口列数，
`sum(2 if east_asian_width(c) in ("W","F") else 1 for c in line)`；相等即命中。

**自写层修法**（不动上游，且正常宽度下逐字节等价）：

```python
# 装到 builtins.print：任何一行都折到 width-1 列以内，永远碰不到那条规则
def install():
    import builtins
    builtins.print = out      # out(*args, ...) 逐行 wrap_line 后 write
```

要点：`shutil.get_terminal_size()` 取宽度；折行按字符边界断（不劈汉字）+
最简禁则（`。，、）` 不落行首）；分隔线这种"单字符重复一整行"的**截断**而不是折行。
窗口 ≥ 最长文案宽度 +1 时，`wrap_line` 原样返回 -> **输出与改造前逐字节相同**，
所以这类改动可以放心合进已发布的包（用「装/不装各 dump 一次屏幕做 diff」验收）。

## 上游出新版时：就地升级，而不是重打包

便携包能做「就地升级」的前提是：自写层只依赖**对外契约**（命令入口名、CLI 参数、档位取值、
模型仓库名），而不依赖上游内部实现。满足这条时，升一次级通常只换几个包，模型权重（往往几个 GB）
完全不用重下。

```bat
rem 用包内解释器自己的 pip —— 不碰宿主环境，也不要用 Scripts\*.exe
runtime\python\python.exe -m pip install --upgrade <pkg>==<新版本> -i <国内镜像>
```

**动手前先 `--dry-run` 看清会动几个包**，这一步的产出直接决定要不要改自写层。
实例：某包 4.0.10 → 4.0.12 的解析结果是
`Would install docvortex-0.5.16 fastapi-offline-1.7.7 filelock-3.32.7 mineru-4.0.12` —— 4 个包，
而它依赖的 7 个命令入口名、`Requires-Python` 区间、模型注册表、档位常量**全部未变**，
所以「替换程序文件即可」成立。

**必查四处**（升级前对着新版 wheel 比一遍，比装完再试错省事）：

| 查什么 | 变了会怎样 |
|---|---|
| `*.dist-info/entry_points.txt` | 命令入口名/模块路径改了 → 自写层的命令映射表得跟着改 |
| `Requires-Python` | 比包内解释器版本高 → 得换整个 `runtime/` |
| 模型注册表（模型仓库名与权重文件名） | 变了才需要**重下模型**；没变就别重下 |
| 档位/枚举常量 | 自写层菜单里的档位名、服务端档位映射要跟着改 |

**最容易漏的坑：自写层里「照旧版写死」的常量。** 至少三类，升级动作必须一并处理：

1. 兜底安装目标，如 `<APP>_VERSION = "4.0.10"`（案例里是 `MINERU_VERSION`）
   —— 不改的话下次自举会去装回旧版；
2. **依赖锁定表**（`requirements.lock.txt` 之类）—— 如果首启自举的第一个安装计划就是
   `-r <锁表>`，那锁表里钉死的旧版本会把刚升上去的版本**降级回去**。改法：删掉，或
   按当前环境重新 `pip freeze` 生成。
3. **透传给上游的 CLI 参数**（下面单独讲）。

### 透传给上游的 CLI 参数：既要防改名，也要防"同名不同义"

真实教训：某包 4.0.x 调 `webui --api-server-tier standard` 让界面放出四档；
4.1.x 把它改名成 `--tier`，**同时**把档位上限拆细 —— 新的 `standard` 只到三档，
想放全部四档必须传 `advanced`。只按名字改成 `--tier standard` 会**静默少一档**，
比报错更难发现。

正确写法是**一样都不写死**，启动时向上游要答案：

```python
# ① 选项名：读上游命令声明的 typer 参数，而不是记版本号
sig = inspect.signature(upstream_cmd.webui_cmd)
for name, p in sig.parameters.items():
    flags = [d for d in (getattr(p.default, "param_decls", ()) or ()) if d.startswith("--")]
    if "--tier" in flags:  ...      # 4.1.x
    if "--api-server-tier" in flags: ...   # 4.0.x

# ② 取值：拿「想放出哪几档」去上游映射表里反查键，而不是硬编码档位名
for ceiling, covered in TIERS_BY_SERVER_TIER.items():
    if tuple(covered) == wanted: return ceiling     # 4.0.x→standard  4.1.x→advanced
```

**两样有一样探不到，就干脆不传**，退回上游默认值 —— 少传一个参数只会少几档，
传错一个参数是整条启动链挂掉。同理，别顺手改用上游的 `auto`：`auto` 通常只按硬件推档
（有 GPU 就放开最高档），**不看实际装了哪些模型**，会让只有小模型的用户选到跑不动的档，
也会让 CPU 机器的完整安装只剩两档。

**自检里加一项把它们打出来**（探测到的参数名 + 两种模型状态下的实际取值），
下游用户升级后一取自检就能看出上游又改名了，不用等启动失败才发现。

重新生成锁表时**必须把 `name @ file:///...` 改回 `name==版本`**：用本地 wheel 装的包，
pip freeze 会记成构建机上的绝对路径，随包分发到别的机器就装不上（`name==版本` 才可移植）。

**把升级做成交互菜单的一项更稳**，并且内置三件事：

- 升级后**逐个 import 自写层登记的命令入口**做冒烟测试 —— 模块路径变了 pip 不会报错，
  但菜单和命令行会当场失灵，这十几秒值得花；
- 失败时**能一键回退旧版**（旧版本号在升级前记下来）；
- 升级后**重新比对模型注册表**与自写层登记清单，变了就明确告诉用户要重下哪部分。

顺带：**镜像要留回退链**。实测清华源对个别项目的 wheel 文件会返 403（索引能读、payload 被拒），
只配一个源会在这种时候卡死。

## 交付清单

`使用说明.txt`（BOM+CRLF）至少写：快速开始、菜单说明、组件集/档位差异（分档时才有）、**路径要求放在最前面**、
目录结构、便携性说明（哪些变量重定向到哪）、常见问题（含原生库那条报错原文）、
硬件要求 + **硬件加速说明（哪一层吃显卡、实测吞吐、显存需求、回落行为、可选开关）**、
磁盘占用（给**实测**耗时数字，不要空口说"较快"）。

对外分发时另加：`README.md`（见上节章节顺序）、`.gitignore`（必须 `git add --dry-run` 实测过）、
上游 `LICENSE-<项目>.md` 原文，以及可选的 `skills/<app>-portable/SKILL.md`
（想让 Agent 驱动本包时——见上上节，README 里要写清怎么装、怎么改 `KIT_ROOT`）。
