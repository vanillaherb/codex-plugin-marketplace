param(
  [string]$Branch = "main",
  [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

$repo = "vanillaherb/codex-plugin-marketplace"
$pluginName = "github-pages-deploy"
$zipUrl = "https://github.com/$repo/archive/refs/heads/$Branch.zip"
$fallbackZipUrl = "https://codeload.github.com/$repo/zip/refs/heads/$Branch"

$homeDir = [Environment]::GetFolderPath("UserProfile")
$pluginsRoot = Join-Path $homeDir "plugins"
$targetPlugin = Join-Path $pluginsRoot $pluginName
$marketplacePath = Join-Path $homeDir ".agents\plugins\marketplace.json"
$marketplaceRoot = Split-Path -Parent $marketplacePath

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-plugin-install-" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "marketplace.zip"
$extractPath = Join-Path $tempRoot "extract"

function Write-JsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )

  $json = $Value | ConvertTo-Json -Depth 30
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Save-WithRetry {
  param(
    [Parameter(Mandatory = $true)][string[]]$Urls,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [int]$Attempts = 3
  )

  $lastError = $null
  foreach ($url in $Urls) {
    for ($i = 1; $i -le $Attempts; $i++) {
      try {
        Write-Host "Downloading package ($i/$Attempts): $url"
        Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing
        return
      } catch {
        $lastError = $_
        if ($i -lt $Attempts) {
          Start-Sleep -Seconds (2 * $i)
        }
      }
    }
  }

  throw $lastError
}

try {
  Write-Host "Installing Codex plugin: $pluginName" -ForegroundColor Cyan

  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
  New-Item -ItemType Directory -Force -Path $pluginsRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $marketplaceRoot | Out-Null

  Save-WithRetry -Urls @($zipUrl, $fallbackZipUrl) -OutFile $zipPath

  Write-Host "Extracting package..."
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

  $sourcePlugin = Get-ChildItem -LiteralPath $extractPath -Directory |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "plugins\$pluginName" }

  if (-not $sourcePlugin -or -not (Test-Path -LiteralPath (Join-Path $sourcePlugin ".codex-plugin\plugin.json"))) {
    throw "Could not find plugin manifest in downloaded package."
  }

  if (Test-Path -LiteralPath $targetPlugin) {
    Remove-Item -LiteralPath $targetPlugin -Recurse -Force
  }

  Write-Host "Installing plugin files..."
  Copy-Item -LiteralPath $sourcePlugin -Destination $targetPlugin -Recurse -Force

  if (Test-Path -LiteralPath $marketplacePath) {
    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
    if (-not $marketplace.name) {
      $marketplace | Add-Member -NotePropertyName name -NotePropertyValue "personal"
    }
    if (-not $marketplace.interface) {
      $marketplace | Add-Member -NotePropertyName interface -NotePropertyValue ([pscustomobject]@{ displayName = "Personal" })
    }
    if (-not $marketplace.plugins) {
      $marketplace | Add-Member -NotePropertyName plugins -NotePropertyValue @()
    }
  } else {
    $marketplace = [pscustomobject]@{
      name = "personal"
      interface = [pscustomobject]@{
        displayName = "Personal"
      }
      plugins = @()
    }
  }

  $otherPlugins = @($marketplace.plugins | Where-Object { $_.name -ne $pluginName })
  $entry = [pscustomobject]@{
    name = $pluginName
    source = [pscustomobject]@{
      source = "local"
      path = "./plugins/$pluginName"
    }
    policy = [pscustomobject]@{
      installation = "AVAILABLE"
      authentication = "ON_INSTALL"
    }
    category = "Productivity"
  }

  $marketplace.plugins = @($otherPlugins) + $entry
  Write-JsonFile -Path $marketplacePath -Value $marketplace

  $encodedPath = [uri]::EscapeDataString($marketplacePath)
  $viewUrl = "codex://plugins/$pluginName`?marketplacePath=$encodedPath"

  Write-Host ""
  Write-Host "Installed successfully." -ForegroundColor Green
  Write-Host "Plugin: $targetPlugin"
  Write-Host "Marketplace: $marketplacePath"
  Write-Host ""
  Write-Host "Restart Codex or open a new Codex thread if the plugin does not appear immediately."
  Write-Host "Codex link: $viewUrl"

  if (-not $NoOpen) {
    try {
      Start-Process $viewUrl
    } catch {
      Write-Host "Could not open Codex link automatically. Open it manually after Codex restarts."
    }
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
