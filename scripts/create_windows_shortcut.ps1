# Creates a desktop shortcut for the local MOYE build.
#
# The shortcut intentionally targets the stable dist/MOYE-Windows/moye.exe
# path. Rebuilding into that directory (the normal update flow) keeps the
# shortcut, its embedded icon and its keyboard hotkey valid.
param(
    [string]$ShortcutName = '墨页',
    [string]$Hotkey = 'CTRL+ALT+M'
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo 'dist\MOYE-Windows\moye.exe'
$workingDirectory = Split-Path -Parent $target

if (-not (Test-Path -LiteralPath $target)) {
    throw "找不到 $target。请先构建 Windows 版本。"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop "$ShortcutName.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $workingDirectory
$shortcut.IconLocation = "$target,0"
$shortcut.Description = '墨页 - 本地阅读与知识库'
$shortcut.Hotkey = $Hotkey
$shortcut.Save()

Write-Output "已创建：$shortcutPath"
Write-Output "目标：$target"
Write-Output "快捷键：$Hotkey"
