# ============================================================
# check_dual_copy.ps1 — DSH「双副本崩溃」体检脚本（只读，不改任何文件）
#
# 症状：DSH 所有工具调用失败，报
#   Cannot read properties of undefined (reading 'prepare')
# 本脚本检查三层目录，判断是否存在「核心包被实体化复制」的问题。
#
# 用法（二选一）：
#   1) 打开 PowerShell，把本文件全部内容粘贴进去，回车
#   2) powershell -ExecutionPolicy Bypass -File "本文件的完整路径"
# ============================================================

$ErrorActionPreference = 'SilentlyContinue'

Write-Host ''
Write-Host '=== DSH 双副本体检（只读模式） ===' -ForegroundColor Cyan
Write-Host ''

$sick = $false
$profilesDir = Join-Path $env:USERPROFILE '.dsh\profiles'
$profileCore = Join-Path $profilesDir 'web\node_modules\@deepseek-ai'
$globalCore  = Join-Path $profilesDir 'node_modules\@deepseek-ai'
$healBlocker = Join-Path $profilesDir 'node_modules\html-void-elements'

function Show-Entries {
    param([string]$Path, [string]$ExpectHint)
    if (-not (Test-Path $Path)) {
        Write-Host "    目录不存在：$Path" -ForegroundColor DarkGray
        Write-Host "    （如果对应安装方式没用过，这属于正常）" -ForegroundColor DarkGray
        return
    }
    $items = Get-ChildItem $Path
    if (-not $items) {
        Write-Host "    目录为空" -ForegroundColor DarkGray
        return
    }
    foreach ($it in $items) {
        if ($it.LinkType) {
            Write-Host ("    [OK] {0}  LinkType={1}  Target={2}" -f $it.Name, $it.LinkType, ($it.LinkTarget -join ';')) -ForegroundColor Green
        } else {
            Write-Host ("    [X ] {0}  实体目录（LinkType 为空）{1}" -f $it.Name, $ExpectHint) -ForegroundColor Red
            $script:sick = $true
        }
    }
}

Write-Host '[1/3] profile 层（web）核心包 —— 这里出现实体目录 = 双副本崩溃根源'
Show-Entries -Path $profileCore -ExpectHint '<- 祸根，按 README 第 7 节修复'

Write-Host ''
Write-Host '[2/3] 全局 profile 层核心包 —— 这里应该是 Junction，指向 npm 全局安装'
Show-Entries -Path $globalCore -ExpectHint '<- 应为软链，按 README 第 7 节修复'

Write-Host ''
Write-Host '[3/3] 卡自愈的空目录检查（html-void-elements 是已确认的常见案例）'
$blockerItem = Get-Item $healBlocker
if ($blockerItem -and -not $blockerItem.LinkType) {
    Write-Host ("    [X ] {0}  非软链目录存在，会卡住 DSH 软链自愈，建议删除" -f $healBlocker) -ForegroundColor Red
    $script:sick = $true
} else {
    Write-Host '    [OK] 未发现卡自愈的空目录' -ForegroundColor Green
}

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
if ($sick) {
    Write-Host '体检结论：发现实体化核心包，符合双副本崩溃条件。' -ForegroundColor Red
    Write-Host '处理方法：按仓库 README 第 7 节「修复：四步走」逐步操作。'
} else {
    Write-Host '体检结论：三层全部健康，本次问题大概率不是双副本。' -ForegroundColor Green
    Write-Host '提示：若症状仍符合「所有工具报 prepare 崩溃」，请重读 README 第 6 节。'
}
Write-Host ''
