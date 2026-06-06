param(
  [string]$PluginRoot = $PSScriptRoot,
  [string]$PluginName = "github-pages-deploy"
)

$ErrorActionPreference = "Stop"

$source = (Resolve-Path -LiteralPath $PluginRoot).Path
$homeDir = [Environment]::GetFolderPath("UserProfile")
$pluginsRoot = Join-Path $homeDir "plugins"
$target = Join-Path $pluginsRoot $PluginName
$marketplacePath = Join-Path $homeDir ".agents\plugins\marketplace.json"
$marketplaceRoot = Split-Path -Parent $marketplacePath

if (-not (Test-Path -LiteralPath (Join-Path $source ".codex-plugin\plugin.json"))) {
  throw "This script must be run from the plugin root, or pass -PluginRoot."
}

New-Item -ItemType Directory -Force -Path $pluginsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $marketplaceRoot | Out-Null

if (Test-Path -LiteralPath $target) {
  Remove-Item -LiteralPath $target -Recurse -Force
}

Copy-Item -LiteralPath $source -Destination $target -Recurse -Force

if (Test-Path -LiteralPath $marketplacePath) {
  $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
} else {
  $marketplace = [pscustomobject]@{
    name = "personal"
    interface = [pscustomobject]@{
      displayName = "Personal"
    }
    plugins = @()
  }
}

$existing = @($marketplace.plugins | Where-Object { $_.name -ne $PluginName })
$entry = [pscustomobject]@{
  name = $PluginName
  source = [pscustomobject]@{
    source = "local"
    path = "./plugins/$PluginName"
  }
  policy = [pscustomobject]@{
    installation = "AVAILABLE"
    authentication = "ON_INSTALL"
  }
  category = "Productivity"
}

$marketplace.plugins = @($existing) + $entry
$json = $marketplace | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($marketplacePath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "Installed Codex plugin:"
Write-Host $target
Write-Host ""
Write-Host "Marketplace:"
Write-Host $marketplacePath
Write-Host ""
Write-Host "Restart Codex or open a new Codex thread, then install/view the plugin from the Personal marketplace."
