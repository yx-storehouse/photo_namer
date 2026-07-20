Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactDir = Join-Path $repoRoot 'build\release_publish'
$notesTempDir = Join-Path $artifactDir 'gui_temp'
$buildScriptPath = Join-Path $repoRoot 'build_release_package.bat'
$publishScriptPath = Join-Path $repoRoot 'publish_built_release.bat'
$repairScriptPath = Join-Path $repoRoot 'repair_release_manifest.bat'

function Ensure-ToolDirs {
  if (-not (Test-Path $artifactDir)) {
    New-Item -Path $artifactDir -ItemType Directory | Out-Null
  }
  if (-not (Test-Path $notesTempDir)) {
    New-Item -Path $notesTempDir -ItemType Directory | Out-Null
  }
}

function Get-PubspecVersionInfo {
  $pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
  $content = Get-Content $pubspecPath -Raw -Encoding UTF8
  $match = [regex]::Match(
    $content,
    '(?m)^version:\s*([0-9A-Za-z\.\-_]+)\+([0-9]+)\s*$'
  )
  if (-not $match.Success) {
    throw '无法从 pubspec.yaml 读取版本号'
  }

  return @{
    VersionName = $match.Groups[1].Value
    VersionCode = [int]$match.Groups[2].Value
  }
}

function Quote-Arg {
  param([string]$Value)
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Add-ValueArgument {
  param(
    [System.Collections.Generic.List[string]]$Arguments,
    [string]$Name,
    [string]$Value
  )

  if (-not [string]::IsNullOrWhiteSpace($Value)) {
    $Arguments.Add($Name)
    $Arguments.Add((Quote-Arg $Value.Trim()))
  }
}

function Write-NotesTempFile {
  param([string]$NotesText)

  Ensure-ToolDirs
  $filePath = Join-Path $notesTempDir ('release_notes_{0}.txt' -f [DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff'))
  [System.IO.File]::WriteAllText($filePath, $NotesText, (New-Object System.Text.UTF8Encoding($true)))
  return $filePath
}

function Show-UiError {
  param(
    [string]$Title,
    [System.Exception]$Exception
  )

  $message = if ($Exception -and $Exception.Message) {
    $Exception.Message
  } else {
    '发生未知错误'
  }

  [System.Windows.Forms.MessageBox]::Show(
    $message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error
  ) | Out-Null
}

function Refresh-VersionInfo {
  $info = Get-PubspecVersionInfo
  $script:currentVersionLabel.Text = '当前 pubspec 版本号：{0}，版本码：{1}' -f $info.VersionName, $info.VersionCode
}

function Get-SharedArguments {
  param([ValidateSet('build', 'publish', 'repair')][string]$Mode)

  $arguments = New-Object 'System.Collections.Generic.List[string]'

  Add-ValueArgument -Arguments $arguments -Name '-VersionName' -Value $script:versionNameBox.Text
  Add-ValueArgument -Arguments $arguments -Name '-VersionCode' -Value $script:versionCodeBox.Text

  if ($Mode -eq 'build') {
    if ($script:buildTargetCombo.SelectedIndex -eq 1) {
      $arguments.Add('-UniversalApk')
    }
    if ($script:skipPubGetCheck.Checked) {
      $arguments.Add('-SkipPubGet')
    }
    return @{
      ArgumentString = ($arguments -join ' ')
    }
  }

  Add-ValueArgument -Arguments $arguments -Name '-Title' -Value $script:titleBox.Text

  $notes = $script:notesBox.Text.Trim()
  if (-not [string]::IsNullOrWhiteSpace($notes)) {
    $notesFile = Write-NotesTempFile -NotesText $notes
    $arguments.Add('-NotesFile')
    $arguments.Add((Quote-Arg $notesFile))
  }

  if ($script:forceUpdateCheck.Checked) {
    $arguments.Add('-ForceUpdate')
  }

  return @{
    ArgumentString = ($arguments -join ' ')
  }
}

function Start-ToolWindow {
  param(
    [string]$ScriptPath,
    [ValidateSet('build', 'publish', 'repair')][string]$Mode,
    [string]$ActionName
  )

  if (-not (Test-Path $ScriptPath)) {
    throw "脚本不存在：$ScriptPath"
  }

  Ensure-ToolDirs
  $payload = Get-SharedArguments -Mode $Mode
  if ([string]::IsNullOrWhiteSpace($payload.ArgumentString)) {
    Start-Process -FilePath $ScriptPath -WorkingDirectory $repoRoot | Out-Null
  } else {
    Start-Process -FilePath $ScriptPath -WorkingDirectory $repoRoot -ArgumentList $payload.ArgumentString | Out-Null
  }

  $message = switch ($Mode) {
    'build' {
      if ($script:buildTargetCombo.SelectedIndex -eq 1) {
        '已打开独立命令行窗口开始打包通用 APK。版本号留空时会自动按当前 pubspec + 1。'
      } else {
        '已打开独立命令行窗口开始打包 64 位 APK（arm64-v8a）。版本号留空时会自动按当前 pubspec + 1。'
      }
    }
    'publish' { '已打开独立命令行窗口开始发布。发布模式会使用当前 pubspec 版本，不会重新打包。' }
    'repair' { '已打开独立命令行窗口开始修复云端版本清单。' }
  }

  [System.Windows.Forms.MessageBox]::Show(
    $message,
    $ActionName,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  ) | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'PhotoNamer 发布面板'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(900, 600)
$form.MinimumSize = New-Object System.Drawing.Size(900, 600)

$script:currentVersionLabel = New-Object System.Windows.Forms.Label
$script:currentVersionLabel.Location = New-Object System.Drawing.Point(20, 20)
$script:currentVersionLabel.Size = New-Object System.Drawing.Size(620, 24)
$script:currentVersionLabel.Text = '当前 pubspec 版本号：读取中...'
$form.Controls.Add($script:currentVersionLabel)

$tipLabel = New-Object System.Windows.Forms.Label
$tipLabel.Location = New-Object System.Drawing.Point(20, 48)
$tipLabel.Size = New-Object System.Drawing.Size(840, 40)
$tipLabel.Text = '这是轻量启动面板：点按钮后会打开独立命令行窗口执行。现在支持明确选择 64 位 arm64 打包或通用 APK；版本号/版本码留空时，打包默认使用当前 pubspec 并自动把 VersionCode + 1。'
$form.Controls.Add($tipLabel)

$labels = @(
  @{ Text = '版本号（可留空）'; X = 20; Y = 100 },
  @{ Text = '版本码（可留空）'; X = 320; Y = 100 },
  @{ Text = '更新提示标题'; X = 520; Y = 100 },
  @{ Text = '打包类型'; X = 20; Y = 156 },
  @{ Text = '更新说明'; X = 20; Y = 186 }
)

foreach ($entry in $labels) {
  $label = New-Object System.Windows.Forms.Label
  $label.Text = $entry.Text
  $label.Location = New-Object System.Drawing.Point($entry.X, $entry.Y)
  $label.Size = New-Object System.Drawing.Size(220, 20)
  $form.Controls.Add($label)
}

$script:versionNameBox = New-Object System.Windows.Forms.TextBox
$script:versionNameBox.Location = New-Object System.Drawing.Point(20, 126)
$script:versionNameBox.Size = New-Object System.Drawing.Size(240, 28)
$form.Controls.Add($script:versionNameBox)

$script:versionCodeBox = New-Object System.Windows.Forms.TextBox
$script:versionCodeBox.Location = New-Object System.Drawing.Point(320, 126)
$script:versionCodeBox.Size = New-Object System.Drawing.Size(140, 28)
$form.Controls.Add($script:versionCodeBox)

$script:titleBox = New-Object System.Windows.Forms.TextBox
$script:titleBox.Location = New-Object System.Drawing.Point(520, 126)
$script:titleBox.Size = New-Object System.Drawing.Size(320, 28)
$script:titleBox.Text = '发现新版本'
$form.Controls.Add($script:titleBox)

$script:buildTargetCombo = New-Object System.Windows.Forms.ComboBox
$script:buildTargetCombo.Location = New-Object System.Drawing.Point(20, 156)
$script:buildTargetCombo.Size = New-Object System.Drawing.Size(260, 28)
$script:buildTargetCombo.DropDownStyle = 'DropDownList'
[void]$script:buildTargetCombo.Items.Add('64 位 APK（arm64-v8a，推荐）')
[void]$script:buildTargetCombo.Items.Add('通用 APK（体积更大）')
$script:buildTargetCombo.SelectedIndex = 0
$form.Controls.Add($script:buildTargetCombo)

$script:skipPubGetCheck = New-Object System.Windows.Forms.CheckBox
$script:skipPubGetCheck.Location = New-Object System.Drawing.Point(320, 156)
$script:skipPubGetCheck.Size = New-Object System.Drawing.Size(150, 24)
$script:skipPubGetCheck.Text = '跳过 pub get'
$form.Controls.Add($script:skipPubGetCheck)

$script:forceUpdateCheck = New-Object System.Windows.Forms.CheckBox
$script:forceUpdateCheck.Location = New-Object System.Drawing.Point(520, 156)
$script:forceUpdateCheck.Size = New-Object System.Drawing.Size(160, 24)
$script:forceUpdateCheck.Text = '强制更新'
$form.Controls.Add($script:forceUpdateCheck)

$script:notesBox = New-Object System.Windows.Forms.TextBox
$script:notesBox.Location = New-Object System.Drawing.Point(20, 212)
$script:notesBox.Size = New-Object System.Drawing.Size(820, 200)
$script:notesBox.Multiline = $true
$script:notesBox.ScrollBars = 'Vertical'
$form.Controls.Add($script:notesBox)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Location = New-Object System.Drawing.Point(20, 440)
$refreshButton.Size = New-Object System.Drawing.Size(140, 36)
$refreshButton.Text = '刷新版本信息'
$refreshButton.Add_Click({
  try {
    Refresh-VersionInfo
  } catch {
    Show-UiError -Title '刷新失败' -Exception $_.Exception
  }
})
$form.Controls.Add($refreshButton)

$buildButton = New-Object System.Windows.Forms.Button
$buildButton.Location = New-Object System.Drawing.Point(190, 440)
$buildButton.Size = New-Object System.Drawing.Size(210, 36)
$buildButton.Text = '1. 打包所选 APK'
$buildButton.Add_Click({
  try {
    Start-ToolWindow -ScriptPath $buildScriptPath -Mode 'build' -ActionName '开始打包'
  } catch {
    Show-UiError -Title '打包失败' -Exception $_.Exception
  }
})
$form.Controls.Add($buildButton)

$publishButton = New-Object System.Windows.Forms.Button
$publishButton.Location = New-Object System.Drawing.Point(420, 440)
$publishButton.Size = New-Object System.Drawing.Size(220, 36)
$publishButton.Text = '2. 发布当前已打好的包'
$publishButton.Add_Click({
  try {
    Start-ToolWindow -ScriptPath $publishScriptPath -Mode 'publish' -ActionName '开始发布'
  } catch {
    Show-UiError -Title '发布失败' -Exception $_.Exception
  }
})
$form.Controls.Add($publishButton)

$repairButton = New-Object System.Windows.Forms.Button
$repairButton.Location = New-Object System.Drawing.Point(650, 440)
$repairButton.Size = New-Object System.Drawing.Size(190, 36)
$repairButton.Text = '3. 仅修复云端清单'
$repairButton.Add_Click({
  try {
    Start-ToolWindow -ScriptPath $repairScriptPath -Mode 'repair' -ActionName '开始修复'
  } catch {
    Show-UiError -Title '修复失败' -Exception $_.Exception
  }
})
$form.Controls.Add($repairButton)

$openArtifactsButton = New-Object System.Windows.Forms.Button
$openArtifactsButton.Location = New-Object System.Drawing.Point(20, 494)
$openArtifactsButton.Size = New-Object System.Drawing.Size(180, 36)
$openArtifactsButton.Text = '打开产物目录'
$openArtifactsButton.Add_Click({
  try {
    Ensure-ToolDirs
    Start-Process explorer.exe $artifactDir
  } catch {
    Show-UiError -Title '打开目录失败' -Exception $_.Exception
  }
})
$form.Controls.Add($openArtifactsButton)

$hintBox = New-Object System.Windows.Forms.Label
$hintBox.Location = New-Object System.Drawing.Point(230, 492)
$hintBox.Size = New-Object System.Drawing.Size(610, 42)
$hintBox.Text = '推荐顺序：先选“64 位 APK（arm64-v8a）”再点“打包所选 APK”，确认命令行窗口提示成功后，再点“发布当前已打好的包”。如果安装包已上传但云端版本清单没更新，再点“仅修复云端清单”。'
$form.Controls.Add($hintBox)

$form.Add_Shown({
  try {
    Ensure-ToolDirs
    Refresh-VersionInfo
  } catch {
    Show-UiError -Title '初始化失败' -Exception $_.Exception
  }
})

[void]$form.ShowDialog()
