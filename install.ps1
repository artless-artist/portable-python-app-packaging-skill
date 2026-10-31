<#
  install.ps1 - 把本 skill 装进某个 agent 的 skills 目录。

  写入位置：<skills 根目录>\portable-python-app-packaging\SKILL.md

  运行后按提示走三步：选层级 -> 选工具 -> 确认。没有任何命令行参数。

  注意：本文件必须保存成「UTF-8 带 BOM」。Windows PowerShell 5.1 会把无 BOM
  的 UTF-8 当 ANSI 解析，中文一出现就解析报错，一行都跑不了。
#>

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Skill = 'portable-python-app-packaging'

# key | 显示名 | 用户级目录 | 项目级目录 | 探测用配置目录 | 可执行文件名
# 路径取自开源生态 npx skills（vercel-labs/skills）维护的注册表，
# 只有 WorkBuddy 是按同族目录补的。
$Registry = @(
    @{ K = 'agents';     N = 'Universal .agents';  U = '.agents/skills';             P = '.agents/skills';           D = '.agents' }
    @{ K = 'workbuddy';  N = 'WorkBuddy';          U = '.workbuddy/skills';          P = '.workbuddy/skills';        D = '.workbuddy' }
    @{ K = 'claude';     N = 'Claude Code';        U = '.claude/skills';             P = '.claude/skills';           D = '.claude';     B = 'claude' }
    @{ K = 'codebuddy';  N = 'CodeBuddy';          U = '.codebuddy/skills';          P = '.codebuddy/skills';        D = '.codebuddy';  B = 'codebuddy' }
    @{ K = 'cursor';     N = 'Cursor';             U = '.cursor/skills';             P = '.agents/skills';           D = '.cursor';     B = 'cursor' }
    @{ K = 'gemini';     N = 'Gemini CLI';         U = '.gemini/skills';             P = '.agents/skills';           D = '.gemini';     B = 'gemini' }
    @{ K = 'copilot';    N = 'GitHub Copilot';     U = '.copilot/skills';            P = '.agents/skills';           D = '.copilot' }
    @{ K = 'codex';      N = 'Codex';              U = '.agents/skills';             P = '.agents/skills';           D = '.codex';      B = 'codex' }
    @{ K = 'cline';      N = 'Cline';              U = '.agents/skills';             P = '.agents/skills';           D = '.cline';      B = 'cline' }
    @{ K = 'warp';       N = 'Warp';               U = '.agents/skills';             P = '.agents/skills';           D = '.warp';       B = 'warp' }
    @{ K = 'zed';        N = 'Zed';                U = '.agents/skills';             P = '.agents/skills';           D = '.config/zed'; B = 'zed' }
    @{ K = 'kimi';       N = 'Kimi Code CLI';      U = '.agents/skills';             P = '.agents/skills';           D = '.kimi';       B = 'kimi' }
    @{ K = 'droid';      N = 'Droid';              U = '.factory/skills';            P = '.agents/skills';           D = '.factory';    B = 'droid' }
    @{ K = 'opencode';   N = 'OpenCode';           U = '.config/opencode/skills';    P = '.agents/skills';           D = '.config/opencode'; B = 'opencode' }
    @{ K = 'amp';        N = 'Amp';                U = '.config/agents/skills';      P = '.agents/skills';           D = '.config/agents';   B = 'amp' }
    @{ K = 'windsurf';   N = 'Windsurf';           U = '.codeium/windsurf/skills';   P = '.windsurf/skills';         D = '.codeium/windsurf' }
    @{ K = 'trae';       N = 'Trae';               U = '.trae/skills';               P = '.trae/skills';             D = '.trae' }
    @{ K = 'trae-cn';    N = 'Trae CN';            U = '.trae-cn/skills';            P = '.trae/skills';             D = '.trae-cn' }
    @{ K = 'qwen';       N = 'Qwen Code';          U = '.qwen/skills';               P = '.qwen/skills';             D = '.qwen';       B = 'qwen' }
    @{ K = 'roo';        N = 'Roo Code';           U = '.roo/skills';                P = '.roo/skills';              D = '.roo' }
    @{ K = 'continue';   N = 'Continue';           U = '.continue/skills';           P = '.continue/skills';         D = '.continue' }
    @{ K = 'kiro';       N = 'Kiro CLI';           U = '.kiro/skills';               P = '.kiro/skills';             D = '.kiro';       B = 'kiro' }
    @{ K = 'kilo';       N = 'Kilo Code';          U = '.kilo/skills';               P = '.agents/skills';           D = '.kilo';       B = 'kilo' }
    @{ K = 'goose';      N = 'Goose';              U = '.config/goose/skills';       P = '.goose/skills';            D = '.config/goose';    B = 'goose' }
    @{ K = 'aider';      N = 'AiderDesk';          U = '.aider-desk/skills';         P = '.aider-desk/skills';       D = '.aider-desk' }
    @{ K = 'augment';    N = 'Augment';            U = '.augment/skills';            P = '.augment/skills';          D = '.augment' }
    @{ K = 'openhands';  N = 'OpenHands';          U = '.openhands/skills';          P = '.openhands/skills';        D = '.openhands' }
    @{ K = 'junie';      N = 'Junie';              U = '.junie/skills';              P = '.junie/skills';            D = '.junie' }
    @{ K = 'qoder';      N = 'Qoder';              U = '.qoder/skills';              P = '.qoder/skills';            D = '.qoder' }
    @{ K = 'lingma';     N = 'Lingma';             U = '.lingma/skills';             P = '.lingma/skills';           D = '.lingma' }
)

$Scope = 'user'
if ($env:USERPROFILE) { $Home_ = $env:USERPROFILE } elseif ($env:HOME) { $Home_ = $env:HOME } else { $Home_ = '.' }

function Get-Root($e) {
    if ($Scope -eq 'project') { $rel = $e.P } else { $rel = $e.U }
    $p = $rel -replace '/', [string][IO.Path]::DirectorySeparatorChar
    if ([IO.Path]::IsPathRooted($p)) { return $p }
    if ($Scope -eq 'project') { return [IO.Path]::Combine((Get-Location).Path, $p) }
    return [IO.Path]::Combine($Home_, $p)
}

function Test-Present($e) {
    $probe = $e.D -replace '/', [string][IO.Path]::DirectorySeparatorChar
    if (Test-Path -LiteralPath ([IO.Path]::Combine($Home_, $probe))) { return $true }
    if ($e.B) { if (Get-Command $e.B -ErrorAction SilentlyContinue) { return $true } }
    return $false
}

# 显示成 ~\... 或 .\...，免得用户名的长度把表格撑歪
function Get-Short([string]$path) {
    $p = $path.TrimEnd('\', '/')
    $h = $Home_.TrimEnd('\', '/')
    if ($p -eq $h) { return '~' }
    if ($p.StartsWith($h + [IO.Path]::DirectorySeparatorChar)) { return '~' + $p.Substring($h.Length) }
    if ($Scope -eq 'project') {
        $c = (Get-Location).Path.TrimEnd('\', '/')
        if ($p -eq $c) { return '.' }
        if ($p.StartsWith($c + [IO.Path]::DirectorySeparatorChar)) { return '.' + $p.Substring($c.Length) }
    }
    return $p
}

# 读一行输入。输入被重定向时（管道、自动化）用 Console.ReadLine，
# 否则用 Read-Host，两种情况下行为一致。
function Ask([string]$prompt) {
    Write-Host $prompt -NoNewline
    $line = $null
    if ([Console]::IsInputRedirected) {
        $line = [Console]::In.ReadLine()
    } else {
        $line = Read-Host
    }
    if ($null -eq $line) { return '' }
    return $line
}

function Show-All {
    Write-Host "   全部可装的工具："
    for ($i = 0; $i -lt $Registry.Count; $i++) {
        $e = $Registry[$i]
        if (Test-Present $e) { $mark = '*' } else { $mark = ' ' }
        Write-Host ("   {0,2}) {1} {2,-18} {3}" -f ($i + 1), $mark, $e.N, (Get-Short (Get-Root $e)))
    }
    Write-Host "        * 表示本机已检测到"
}

# ---------------------------------------------------------------- 前置检查与表头

$src = Join-Path $PSScriptRoot 'SKILL.md'
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host ""
    Write-Host "找不到 SKILL.md，它应该和脚本放在同一个目录：$PSScriptRoot"
    Write-Host "请确认 zip 是完整解压的，别只把脚本单独拎出来。"
    Write-Host ""
    [void](Ask "按回车退出: ")
    exit 1
}
$bytes = (Get-Item -LiteralPath $src).Length

Write-Host ""
Write-Host "============================================================"
Write-Host " $Skill"
Write-Host "============================================================"
Write-Host " 一个 SKILL.md，放到 agent 的 skills 目录下就生效。"
Write-Host " 下面三步，只做复制，不改别的东西。"

# ---------------------------------------------------------------- 第 1 步

Write-Host ""
Write-Host " [1/3] 装到哪一级？"
Write-Host "   1) 用户级   所有项目都能用（推荐）"
Write-Host "   2) 项目级   只在当前目录生效"
$ans = ''
while ($true) {
    $ans = Ask "   选择 [1/2]，回车=1: "
    if ([string]::IsNullOrWhiteSpace($ans)) { $ans = '1' }
    $ans = $ans.Trim()
    if ($ans -eq '1' -or $ans -eq '2') { break }
    Write-Host "   只能输入 1 或 2。"
}
if ($ans -eq '2') {
    $Scope = 'project'
    Write-Host "   项目级：写入 $($PWD.Path)"
} else {
    $Scope = 'user'
}

# ---------------------------------------------------------------- 第 2 步

Write-Host ""
Write-Host " [2/3] 装给哪些工具？"
$det = @()
for ($i = 0; $i -lt $Registry.Count; $i++) {
    if (Test-Present $Registry[$i]) { $det += ($i + 1) }
}
if ($det.Count -gt 0) {
    Write-Host "   本机已检测到："
    foreach ($n in $det) {
        $e = $Registry[$n - 1]
        Write-Host ("   {0,2}) {1,-18} {2}" -f $n, $e.N, (Get-Short (Get-Root $e)))
    }
} else {
    Write-Host "   本机没有检测到任何已知工具。"
}
Write-Host "   输入 o 看全部 $($Registry.Count) 个，a 全选"

$sel = @()
while ($true) {
    $raw = Ask "   序号（逗号分隔，回车=上面这些）: "
    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ($det.Count -eq 0) {
            Write-Host "   没检测到任何工具，得自己指定一个。输入 o 看全部。"
            continue
        }
        $sel = $det
        break
    }
    $raw = $raw.Trim()
    if ($raw -eq 'o' -or $raw -eq 'O') { Show-All; continue }
    if ($raw -eq 'a' -or $raw -eq 'A') {
        $sel = @()
        for ($i = 0; $i -lt $Registry.Count; $i++) { $sel += ($i + 1) }
        break
    }
    $picked = @()
    $bad = $false
    foreach ($tok in ($raw -split '[,，\s]+')) {
        if ($tok -eq '') { continue }
        $num = 0
        if (-not [int]::TryParse($tok, [ref]$num)) { $bad = $true; break }
        if ($num -lt 1 -or $num -gt $Registry.Count) { $bad = $true; break }
        if ($picked -notcontains $num) { $picked += $num }
    }
    if ($bad -or $picked.Count -eq 0) {
        Write-Host "   序号无效，请重新输入，例如 1,3,7。"
        continue
    }
    $sel = $picked
    break
}

# ---------------------------------------------------------------- 第 3 步

# 同一目录只写一次：十几家的全局目录都是 ~/.agents/skills
$targets = @()
$seen = @()
foreach ($n in $sel) {
    $e = $Registry[$n - 1]
    $root = (Get-Root $e).TrimEnd('\', '/')
    if ($seen -contains $root) { continue }
    $seen += $root
    $targets += [pscustomobject]@{ Name = $e.N; Root = $root }
}

Write-Host ""
Write-Host " [3/3] 确认"
Write-Host "   将写入 $($targets.Count) 个位置："
foreach ($t in $targets) {
    Write-Host "     $(Get-Short $t.Root)"
}
Write-Host "   每个位置下建 $Skill\SKILL.md（$bytes 字节）"

$go = ''
while ($true) {
    $go = Ask "   回车开始，输入 n 取消: "
    if ([string]::IsNullOrWhiteSpace($go)) { $go = 'y' }
    $go = $go.Trim().ToLower()
    if ($go -eq 'y' -or $go -eq 'n') { break }
    Write-Host "   回车表示开始，输入 n 表示取消。"
}
if ($go -eq 'n') {
    Write-Host ""
    Write-Host " 已取消，什么都没改。"
    Write-Host ""
    exit 0
}

# ---------------------------------------------------------------- 写入

Write-Host ""
$written = 0
foreach ($t in $targets) {
    $dest = [IO.Path]::Combine($t.Root, $Skill)
    $file = [IO.Path]::Combine($dest, 'SKILL.md')
    if (Test-Path -LiteralPath $file) {
        $old = (Get-Item -LiteralPath $file).Length
        Write-Host "   覆盖 $(Get-Short $file)（原有 $old 字节）"
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -LiteralPath $src -Destination $file -Force
    Write-Host "   写入 $(Get-Short $file)"
    $written++
}

Write-Host ""
Write-Host " 完成：$written 个位置，每个 $bytes 字节。"
Write-Host ""
Write-Host " 重启 agent 会话后直接说需求即可触发，例如："
Write-Host "   把这个项目做成便携整合包，双击就能用，不依赖本机 Python。"
Write-Host ""
if ($Scope -eq 'project') {
    Write-Host " 注意：项目级安装只对当前目录生效，换个目录就看不到了。"
    Write-Host ""
}
[void](Ask "按回车退出: ")
