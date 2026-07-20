param(
  [string]$VersionName,
  [int]$VersionCode,
  [string]$Title = 'New version available',
  [string]$Notes,
  [string]$NotesFile,
  [switch]$ForceUpdate,
  [switch]$BuildOnly,
  [switch]$PublishOnly,
  [switch]$RepairManifestOnly,
  [switch]$UniversalApk,
  [switch]$SkipBuild,
  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  Write-Host "[publish] $Message" -ForegroundColor Cyan
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Command not found: $Name"
  }
}

function Get-PubspecVersionInfo {
  param([string]$PubspecPath)
  $content = Get-Content $PubspecPath -Raw -Encoding UTF8
  $match = [regex]::Match(
    $content,
    '(?m)^version:\s*([0-9A-Za-z\.\-_]+)\+([0-9]+)\s*$'
  )
  if (-not $match.Success) {
    throw 'Failed to read version from pubspec.yaml'
  }

  return @{
    VersionName = $match.Groups[1].Value
    VersionCode = [int]$match.Groups[2].Value
    Raw = $match.Value
  }
}

function Set-PubspecVersionInfo {
  param(
    [string]$PubspecPath,
    [string]$ResolvedVersionName,
    [int]$ResolvedVersionCode
  )

  $content = Get-Content $PubspecPath -Raw -Encoding UTF8
  $updated = [regex]::Replace(
    $content,
    '(?m)^version:\s*([0-9A-Za-z\.\-_]+)\+([0-9]+)\s*$',
    "version: $ResolvedVersionName+$ResolvedVersionCode",
    1
  )
  if ($updated -eq $content) {
    throw 'Failed to update version in pubspec.yaml'
  }
  [System.IO.File]::WriteAllText(
    $PubspecPath,
    $updated,
    (New-Object System.Text.UTF8Encoding($false))
  )
}

function Get-DartConstString {
  param(
    [string]$DartPath,
    [string]$ConstName
  )

  $content = Get-Content $DartPath -Raw -Encoding UTF8
  $pattern = "static const String $ConstName\s*=\s*'([^']+)';"
  $match = [regex]::Match($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $match.Success) {
    throw "Failed to read config from cloud_sync_page.dart: $ConstName"
  }
  return $match.Groups[1].Value
}

function Get-CloudPublishConfig {
  param([string]$DartPath)

  return @{
    AccessToken = Get-DartConstString -DartPath $DartPath -ConstName 'accessToken'
    RepoOwner = Get-DartConstString -DartPath $DartPath -ConstName 'repoOwner'
    RepoName = Get-DartConstString -DartPath $DartPath -ConstName 'repoName'
    Branch = Get-DartConstString -DartPath $DartPath -ConstName 'branch'
    AppUpdateFilePath = Get-DartConstString -DartPath $DartPath -ConstName 'appUpdateFilePath'
  }
}

function Get-ReleaseNotes {
  param(
    [string]$RepoRoot,
    [string]$InlineNotes,
    [string]$FilePath
  )

  if (-not [string]::IsNullOrWhiteSpace($InlineNotes)) {
    return ($InlineNotes -split "(`r`n|`n|;)" |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ })
  }

  if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
    if (-not (Test-Path $FilePath)) {
      throw "Release notes file not found: $FilePath"
    }
    return (Get-Content $FilePath -Encoding UTF8 |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ })
  }

  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $gitNotes = & $git.Source -C $RepoRoot log --pretty=format:%s -n 5 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitNotes) {
      $lines = $gitNotes -split "(`r`n|`n)" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
      if ($lines.Count -gt 0) {
        return $lines
      }
    }
  }

  return @('General update')
}

function ConvertTo-JsonBytesBase64 {
  param([object]$Data)
  $json = $Data | ConvertTo-Json -Depth 20
  return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
}

function Format-ByteSize {
  param([double]$Bytes)

  if ($Bytes -lt 1KB) {
    return ('{0:N0} B' -f $Bytes)
  }
  if ($Bytes -lt 1MB) {
    return ('{0:N1} KB' -f ($Bytes / 1KB))
  }
  if ($Bytes -lt 1GB) {
    return ('{0:N1} MB' -f ($Bytes / 1MB))
  }
  return ('{0:N2} GB' -f ($Bytes / 1GB))
}

function Get-GiteeAuthHeaders {
  param([string]$AccessToken)
  return @{
    Authorization = "Bearer $AccessToken"
    Accept = 'application/json'
  }
}

function Get-GiteeReleaseList {
  param(
    [string]$Owner,
    [string]$RepoName,
    [string]$AccessToken
  )

  $uri = "https://gitee.com/api/v5/repos/$Owner/$RepoName/releases?page=1&per_page=100"
  $response = Invoke-RestMethod -Uri $uri -Method Get -Headers (Get-GiteeAuthHeaders -AccessToken $AccessToken)
  if ($response -is [System.Array]) {
    return $response
  }
  if ($null -eq $response) {
    return @()
  }
  return @($response)
}

function Get-GiteeReleaseByTag {
  param(
    [string]$Owner,
    [string]$RepoName,
    [string]$AccessToken,
    [string]$TagName
  )

  $releases = Get-GiteeReleaseList -Owner $Owner -RepoName $RepoName -AccessToken $AccessToken
  foreach ($release in $releases) {
    if (($release.tag_name | Out-String).Trim() -eq $TagName) {
      return $release
    }
  }
  return $null
}

function Get-OrCreate-GiteeRelease {
  param(
    [string]$Owner,
    [string]$RepoName,
    [string]$AccessToken,
    [string]$Branch,
    [string]$TagName,
    [string]$ReleaseName,
    [string[]]$Notes
  )

  $releases = Get-GiteeReleaseList -Owner $Owner -RepoName $RepoName -AccessToken $AccessToken
  foreach ($release in $releases) {
    if (($release.tag_name | Out-String).Trim() -eq $TagName) {
      return $release
    }
  }

  $body = @{
    tag_name = $TagName
    target_commitish = $Branch
    name = $ReleaseName
    body = ($Notes -join "`n")
    prerelease = 'false'
  }

  $uri = "https://gitee.com/api/v5/repos/$Owner/$RepoName/releases"
  return Invoke-RestMethod -Uri $uri -Method Post -Body $body -Headers (Get-GiteeAuthHeaders -AccessToken $AccessToken) -ContentType 'application/x-www-form-urlencoded'
}

function Select-GiteeReleaseApkAsset {
  param(
    [object]$Release,
    [string]$PreferredAssetName
  )

  $assets = @($Release.assets) | Where-Object {
    $name = [string]$_.name
    -not [string]::IsNullOrWhiteSpace($name) -and $name.ToLowerInvariant().EndsWith('.apk')
  }

  if ([string]::IsNullOrWhiteSpace($PreferredAssetName) -eq $false) {
    $exact = $assets | Where-Object { ([string]$_.name) -eq $PreferredAssetName } | Select-Object -First 1
    if ($null -ne $exact) {
      return $exact
    }
  }

  $dateStyles =
    [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
    [System.Globalization.DateTimeStyles]::AdjustToUniversal

  $sorted = $assets | Sort-Object `
    @{ Expression = {
        $candidates = @(
          (($_.created_at | Out-String).Trim()),
          (($_.updated_at | Out-String).Trim()),
          (($_.createdAt | Out-String).Trim()),
          (($_.updatedAt | Out-String).Trim())
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($candidate in $candidates) {
          $parsed = [System.DateTimeOffset]::MinValue
          if ([System.DateTimeOffset]::TryParse($candidate, [System.Globalization.CultureInfo]::InvariantCulture, $dateStyles, [ref]$parsed)) {
            return $parsed.UtcDateTime
          }
          if ([System.DateTimeOffset]::TryParse($candidate, [System.Globalization.CultureInfo]::CurrentCulture, $dateStyles, [ref]$parsed)) {
            return $parsed.UtcDateTime
          }
        }

        return [DateTime]::MinValue
      }; Descending = $true }, `
    @{ Expression = {
        $idValue = 0L
        $idText = (($_.id | Out-String).Trim())
        if ([Int64]::TryParse($idText, [ref]$idValue)) {
          return $idValue
        }
        return 0L
      }; Descending = $true }, `
    @{ Expression = { [string]$_.name }; Descending = $true }

  return $sorted | Select-Object -First 1
}

function Upload-GiteeReleaseAsset {
  param(
    [string]$Owner,
    [string]$RepoName,
    [string]$AccessToken,
    [int]$ReleaseId,
    [string]$FilePath
  )

  Add-Type -AssemblyName System.Net.Http

  $client = New-Object System.Net.Http.HttpClient
  $client.Timeout = [TimeSpan]::FromMinutes(30)
  $content = New-Object System.Net.Http.MultipartFormDataContent
  $stream = [System.IO.File]::OpenRead($FilePath)
  $progressActivity = 'Uploading APK to Gitee Release'
  $totalBytes = [double]$stream.Length

  try {
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $AccessToken)
    $client.DefaultRequestHeaders.Accept.Add((New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue('application/json')))

    $content.Add((New-Object System.Net.Http.StringContent($Owner)), 'owner')
    $content.Add((New-Object System.Net.Http.StringContent($RepoName)), 'repo')
    $content.Add((New-Object System.Net.Http.StringContent([string]$ReleaseId)), 'release_id')

    $fileContent = New-Object System.Net.Http.StreamContent($stream)
    $fileContent.Headers.ContentType =
      [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/vnd.android.package-archive')
    $content.Add(
      $fileContent,
      'file',
      [System.IO.Path]::GetFileName($FilePath)
    )

    $uri = "https://gitee.com/api/v5/repos/$Owner/$RepoName/releases/$ReleaseId/attach_files"
    Write-Step ("Uploading file {0} ({1})" -f [System.IO.Path]::GetFileName($FilePath), (Format-ByteSize $totalBytes))

    $uploadStartedAt = Get-Date
    $responseTask = $client.PostAsync($uri, $content)

    while (-not $responseTask.Wait(500)) {
      $uploadedBytes = [double][Math]::Min($stream.Position, $stream.Length)
      $elapsed = (Get-Date) - $uploadStartedAt
      $elapsedSeconds = [Math]::Max($elapsed.TotalSeconds, 1)
      $speedBytesPerSecond = $uploadedBytes / $elapsedSeconds

      if ($uploadedBytes -ge $totalBytes -and $totalBytes -gt 0) {
        Write-Progress `
          -Activity $progressActivity `
          -Status ("Uploaded {0} / {1}, waiting for server response..." -f (Format-ByteSize $uploadedBytes), (Format-ByteSize $totalBytes)) `
          -PercentComplete 100
      }
      else {
        $percent = if ($totalBytes -gt 0) {
          [Math]::Min([Math]::Floor(($uploadedBytes / $totalBytes) * 100), 99)
        }
        else {
          0
        }

        Write-Progress `
          -Activity $progressActivity `
          -Status ("{0}% ({1} / {2}) at {3}/s" -f $percent, (Format-ByteSize $uploadedBytes), (Format-ByteSize $totalBytes), (Format-ByteSize $speedBytesPerSecond)) `
          -PercentComplete $percent
      }
    }

    Write-Progress -Activity $progressActivity -Completed
    $response = $responseTask.GetAwaiter().GetResult()
    $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) {
      throw "Failed to upload APK to Gitee Release ($($response.StatusCode)): $responseText"
    }
    return $responseText | ConvertFrom-Json
  }
  finally {
    Write-Progress -Activity $progressActivity -Completed -ErrorAction SilentlyContinue
    $stream.Dispose()
    $content.Dispose()
    $client.Dispose()
  }
}

function Resolve-AssetDownloadUrl {
  param([object]$Asset)

  $candidates = @(
    $Asset.browser_download_url,
    $Asset.download_url,
    $Asset.html_url
  )

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
      return [string]$candidate
    }
  }

  return $null
}

function Build-AppUpdateManifest {
  param(
    [string]$ResolvedVersionName,
    [int]$ResolvedVersionCode,
    [string]$ResolvedTitle,
    [string]$ResolvedDownloadUrl,
    [string[]]$ResolvedNotes,
    [bool]$ResolvedForceUpdate,
    [string]$PublishedBy
  )

  return @{
    appId = 'photo_namer'
    versionName = $ResolvedVersionName
    versionCode = $ResolvedVersionCode
    title = $ResolvedTitle
    downloadUrl = $ResolvedDownloadUrl
    changelog = $ResolvedNotes
    forceUpdate = $ResolvedForceUpdate
    publishedAt = (Get-Date).ToString('o')
    publishedBy = $PublishedBy
  }
}

function Get-GiteeExistingFileSha {
  param(
    [string]$Owner,
    [string]$RepoName,
    [string]$AccessToken,
    [string]$Branch,
    [string]$FilePath
  )

  $normalized = $FilePath.Replace('\', '/').Trim('/')
  $headers = Get-GiteeAuthHeaders -AccessToken $AccessToken
  $headers['Cache-Control'] = 'no-cache'
  $escapedPath = (($normalized -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $uri = "https://gitee.com/api/v5/repos/$Owner/$RepoName/contents/$escapedPath?access_token=$AccessToken&ref=$Branch&t=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
  }
  catch {
    $statusCode = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -eq 404) {
      return $null
    }
    throw
  }

  if ($null -eq $response) {
    return $null
  }

  if ($response -is [System.Array]) {
    foreach ($item in $response) {
      if (([string]$item.path) -eq $normalized -or ([string]$item.name) -eq (($normalized -split '/')[-1])) {
        return [string]$item.sha
      }
    }
    return $null
  }

  return [string]$response.sha
}

function Upsert-GiteeJsonFile {
  param(
    [string]$Owner,
    [string]$RepoName,
    [string]$AccessToken,
    [string]$Branch,
    [string]$FilePath,
    [object]$JsonData,
    [string]$Message
  )

  $sha = Get-GiteeExistingFileSha `
    -Owner $Owner `
    -RepoName $RepoName `
    -AccessToken $AccessToken `
    -Branch $Branch `
    -FilePath $FilePath

  $body = @{
    access_token = $AccessToken
    content = ConvertTo-JsonBytesBase64 -Data $JsonData
    message = $Message
    branch = $Branch
  }

  if (-not [string]::IsNullOrWhiteSpace($sha)) {
    $body.sha = $sha
  }

  $normalized = $FilePath.Replace('\', '/').Trim('/')
  $uri = "https://gitee.com/api/v5/repos/$Owner/$RepoName/contents/$normalized"
  if ([string]::IsNullOrWhiteSpace($sha)) {
    try {
      Write-Step "Cloud manifest create mode: $normalized"
      Invoke-RestMethod -Uri $uri -Method Post -Body $body -Headers @{ 'Cache-Control' = 'no-cache' } -ContentType 'application/x-www-form-urlencoded' | Out-Null
    }
    catch {
      $postError = $_
      Write-Step 'Cloud manifest create failed, retrying as update'
      $sha = Get-GiteeExistingFileSha `
        -Owner $Owner `
        -RepoName $RepoName `
        -AccessToken $AccessToken `
        -Branch $Branch `
        -FilePath $FilePath

      if (-not [string]::IsNullOrWhiteSpace($sha)) {
        $body.sha = $sha
        Write-Step "Cloud manifest update mode: sha=$sha"
        Invoke-RestMethod -Uri $uri -Method Put -Body $body -Headers @{ 'Cache-Control' = 'no-cache' } -ContentType 'application/x-www-form-urlencoded' | Out-Null
        return
      }

      throw $postError
    }
  }
  else {
    Write-Step "Cloud manifest update mode: sha=$sha"
    Invoke-RestMethod -Uri $uri -Method Put -Body $body -Headers @{ 'Cache-Control' = 'no-cache' } -ContentType 'application/x-www-form-urlencoded' | Out-Null
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$dartConfigPath = Join-Path $repoRoot 'lib\cloud_sync_page.dart'
$artifactDir = Join-Path $repoRoot 'build\release_publish'

Push-Location $repoRoot
try {
  if (($BuildOnly -and $PublishOnly) -or
      ($BuildOnly -and $RepairManifestOnly) -or
      ($PublishOnly -and $RepairManifestOnly)) {
    throw 'BuildOnly, PublishOnly and RepairManifestOnly are mutually exclusive'
  }

  if ($PublishOnly) {
    $SkipBuild = $true
    $SkipPubGet = $true
  }

  if (-not $RepairManifestOnly -and (-not $SkipBuild -or -not $SkipPubGet)) {
    Require-Command 'flutter'
  }

  $pubspecVersion = Get-PubspecVersionInfo -PubspecPath $pubspecPath
  if ([string]::IsNullOrWhiteSpace($VersionName)) {
    $VersionName = $pubspecVersion.VersionName
  }
  if ($VersionCode -le 0) {
    if ($RepairManifestOnly -or $PublishOnly) {
      $VersionCode = $pubspecVersion.VersionCode
    }
    else {
      $VersionCode = $pubspecVersion.VersionCode + 1
    }
  }

  if ([string]::IsNullOrWhiteSpace($VersionName) -or $VersionCode -le 0) {
    throw 'Invalid version name or version code'
  }

  if ($PublishOnly -and ($VersionName -ne $pubspecVersion.VersionName -or $VersionCode -ne $pubspecVersion.VersionCode)) {
    throw 'PublishOnly must use the current pubspec version. Build first or refresh the version fields.'
  }

  if (-not $RepairManifestOnly -and ($VersionName -ne $pubspecVersion.VersionName -or $VersionCode -ne $pubspecVersion.VersionCode)) {
    Write-Step "Updating pubspec.yaml version to $VersionName+$VersionCode"
    Set-PubspecVersionInfo `
      -PubspecPath $pubspecPath `
      -ResolvedVersionName $VersionName `
      -ResolvedVersionCode $VersionCode
  }

  $tagName = "v$VersionName-$VersionCode"
  $releaseName = "PhotoNamer $VersionName ($VersionCode)"
  $releaseTitle = if ([string]::IsNullOrWhiteSpace($Title)) { 'New version available' } else { $Title.Trim() }

  if (-not (Test-Path $artifactDir)) {
    New-Item -Path $artifactDir -ItemType Directory | Out-Null
  }

  if ($RepairManifestOnly) {
    $config = Get-CloudPublishConfig -DartPath $dartConfigPath
    $notesList = Get-ReleaseNotes -RepoRoot $repoRoot -InlineNotes $Notes -FilePath $NotesFile
    Write-Step "Repairing cloud app update manifest from release: $tagName"
    $release = Get-GiteeReleaseByTag `
      -Owner $config.RepoOwner `
      -RepoName $config.RepoName `
      -AccessToken $config.AccessToken `
      -TagName $tagName

    if ($null -eq $release) {
      throw "Release not found: $tagName"
    }

    $asset = Select-GiteeReleaseApkAsset -Release $release
    if ($null -eq $asset) {
      throw "APK asset not found in release: $tagName"
    }

    if ([string]::IsNullOrWhiteSpace($Notes) -and
        [string]::IsNullOrWhiteSpace($NotesFile) -and
        -not [string]::IsNullOrWhiteSpace(([string]$release.body))) {
      $notesList = (([string]$release.body) -split "(`r`n|`n)") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    }

    $downloadUrl = Resolve-AssetDownloadUrl -Asset $asset
    if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
      throw "APK download URL not found in release: $tagName"
    }

    $updateManifest = Build-AppUpdateManifest `
      -ResolvedVersionName $VersionName `
      -ResolvedVersionCode $VersionCode `
      -ResolvedTitle $releaseTitle `
      -ResolvedDownloadUrl $downloadUrl `
      -ResolvedNotes $notesList `
      -ResolvedForceUpdate ([bool]$ForceUpdate) `
      -PublishedBy 'release_script_repair'

    Write-Step 'Updating cloud app update manifest'
    Upsert-GiteeJsonFile `
      -Owner $config.RepoOwner `
      -RepoName $config.RepoName `
      -AccessToken $config.AccessToken `
      -Branch $config.Branch `
      -FilePath $config.AppUpdateFilePath `
      -JsonData $updateManifest `
      -Message "photo_namer repair app update $((Get-Date).ToString('o'))"

    $summaryPath = Join-Path $artifactDir 'last_publish_summary.json'
    $summary = @{
      mode = 'repair_manifest_only'
      versionName = $VersionName
      versionCode = $VersionCode
      tagName = $tagName
      releaseName = $releaseName
      downloadUrl = $downloadUrl
      notes = $notesList
      publishedAt = $updateManifest.publishedAt
      forceUpdate = [bool]$ForceUpdate
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8

    Write-Host ''
    Write-Host 'Manifest repair completed' -ForegroundColor Green
    Write-Host "Version: $VersionName ($VersionCode)"
    Write-Host "Download URL: $downloadUrl"
    Write-Host "Summary: $summaryPath"
    return
  }

  $buildArgs = @('build', 'apk', '--release')
  $builtApkName = 'app-release.apk'
  $publishedApkFlavor = 'universal'
  if (-not $UniversalApk) {
    # Use split-per-abi for a much smaller arm64 package.
    $buildArgs += @('--target-platform', 'android-arm64', '--split-per-abi')
    $builtApkName = 'app-arm64-v8a-release.apk'
    $publishedApkFlavor = 'arm64-v8a'
  }

  if (-not $SkipPubGet) {
    Write-Step 'Running flutter pub get'
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
      throw 'flutter pub get failed'
    }
  }

  if (-not $SkipBuild) {
    Write-Step "Building $publishedApkFlavor release APK"
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
      throw "flutter $($buildArgs -join ' ') failed"
    }
  }

  $sourceApk = Join-Path $repoRoot "build\app\outputs\flutter-apk\$builtApkName"
  if (-not (Test-Path $sourceApk)) {
    throw "Release APK not found: $sourceApk"
  }

  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $versionedApkName = "photo_namer-$publishedApkFlavor-v$VersionName-$VersionCode-$timestamp.apk"
  $versionedApkPath = Join-Path $artifactDir $versionedApkName
  Copy-Item $sourceApk $versionedApkPath -Force

  if ($BuildOnly) {
    $summaryPath = Join-Path $artifactDir 'last_build_summary.json'
    $summary = @{
      mode = 'build_only'
      versionName = $VersionName
      versionCode = $VersionCode
      tagName = $tagName
      apkPath = $versionedApkPath
      sourceApkPath = $sourceApk
      apkFlavor = $publishedApkFlavor
      builtAt = (Get-Date).ToString('o')
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8

    Write-Host ''
    Write-Host 'Build completed' -ForegroundColor Green
    Write-Host "Version: $VersionName ($VersionCode)"
    Write-Host "APK: $versionedApkPath"
    Write-Host "Summary: $summaryPath"
    return
  }

  $config = Get-CloudPublishConfig -DartPath $dartConfigPath
  $notesList = Get-ReleaseNotes -RepoRoot $repoRoot -InlineNotes $Notes -FilePath $NotesFile

  Write-Step "Creating or reusing Gitee Release: $tagName"
  $release = Get-OrCreate-GiteeRelease `
    -Owner $config.RepoOwner `
    -RepoName $config.RepoName `
    -AccessToken $config.AccessToken `
    -Branch $config.Branch `
    -TagName $tagName `
    -ReleaseName $releaseName `
    -Notes $notesList

  if ($null -eq $release.id) {
    throw 'Failed to get Gitee Release ID'
  }

  Write-Step 'Uploading APK to Gitee Release'
  $asset = Upload-GiteeReleaseAsset `
    -Owner $config.RepoOwner `
    -RepoName $config.RepoName `
    -AccessToken $config.AccessToken `
    -ReleaseId ([int]$release.id) `
    -FilePath $versionedApkPath

  $downloadUrl = Resolve-AssetDownloadUrl -Asset $asset
  if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    throw 'Upload succeeded, but no download URL was returned by Gitee'
  }

  $updateManifest = Build-AppUpdateManifest `
    -ResolvedVersionName $VersionName `
    -ResolvedVersionCode $VersionCode `
    -ResolvedTitle $releaseTitle `
    -ResolvedDownloadUrl $downloadUrl `
    -ResolvedNotes $notesList `
    -ResolvedForceUpdate ([bool]$ForceUpdate) `
    -PublishedBy 'release_script'
  $publishedAt = $updateManifest.publishedAt

  Write-Step 'Updating cloud app update manifest'
  Upsert-GiteeJsonFile `
    -Owner $config.RepoOwner `
    -RepoName $config.RepoName `
    -AccessToken $config.AccessToken `
    -Branch $config.Branch `
    -FilePath $config.AppUpdateFilePath `
    -JsonData $updateManifest `
    -Message "photo_namer publish app update $publishedAt"

  $summaryPath = Join-Path $artifactDir 'last_publish_summary.json'
  $summary = @{
    versionName = $VersionName
    versionCode = $VersionCode
    tagName = $tagName
    releaseName = $releaseName
    downloadUrl = $downloadUrl
    apkPath = $versionedApkPath
    apkFlavor = $publishedApkFlavor
    notes = $notesList
    publishedAt = $publishedAt
    forceUpdate = [bool]$ForceUpdate
  }
  $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8

  Write-Host ''
  Write-Host 'Publish completed' -ForegroundColor Green
  Write-Host "Version: $VersionName ($VersionCode)"
  Write-Host "APK: $versionedApkPath"
  Write-Host "Download URL: $downloadUrl"
  Write-Host "Summary: $summaryPath"
}
finally {
  Pop-Location
}
