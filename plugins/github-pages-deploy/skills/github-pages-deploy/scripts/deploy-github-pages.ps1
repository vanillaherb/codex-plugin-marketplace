param(
  [string]$Token = $env:GITHUB_TOKEN,
  [string]$Owner = $env:GITHUB_OWNER,
  [string]$RepoName = ("codex-pages-" + (Get-Date -Format "yyyyMMdd-HHmmss")),
  [string]$SourcePath = ".",
  [string]$Branch = "main",
  [switch]$Private,
  [int]$WaitSeconds = 180
)

$ErrorActionPreference = "Stop"

if (-not $Token) {
  throw "Missing GitHub token. Set `$env:GITHUB_TOKEN first, or pass -Token. The token needs repo and pages permissions."
}

$ApiBase = "https://api.github.com"
$Headers = @{
  Authorization = "Bearer $Token"
  Accept = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
  "User-Agent" = "codex-github-pages-deployer"
}

function ConvertTo-JsonBody {
  param([object]$Body)

  if ($null -eq $Body) {
    return $null
  }

  return ($Body | ConvertTo-Json -Depth 20)
}

function Read-ErrorBody {
  param([object]$ErrorRecord)

  $response = $ErrorRecord.Exception.Response
  if ($null -eq $response) {
    return $ErrorRecord.Exception.Message
  }

  try {
    $stream = $response.GetResponseStream()
    if ($null -eq $stream) {
      return $response.StatusDescription
    }

    $reader = New-Object System.IO.StreamReader($stream)
    return $reader.ReadToEnd()
  } catch {
    return $response.StatusDescription
  }
}

function Invoke-GitHub {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [object]$Body = $null
  )

  $uri = if ($Path.StartsWith("http")) { $Path } else { "$ApiBase$Path" }
  $jsonBody = ConvertTo-JsonBody -Body $Body

  try {
    if ($null -eq $jsonBody) {
      return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers
    }

    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers -ContentType "application/json" -Body $jsonBody
  } catch {
    $response = $_.Exception.Response
    $statusCode = if ($response) { [int]$response.StatusCode } else { 0 }
    $bodyText = Read-ErrorBody -ErrorRecord $_
    throw "GitHub API $Method $Path failed with HTTP $statusCode. $bodyText"
  }
}

function Invoke-GitHubOrNullOn404 {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    return Invoke-GitHub -Method $Method -Path $Path
  } catch {
    if ($_.Exception.Message -match "HTTP 404") {
      return $null
    }

    throw
  }
}

function ConvertTo-GitHubPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)

  $parts = $RelativePath.Replace("\", "/").Split("/")
  $encodedParts = foreach ($part in $parts) {
    [uri]::EscapeDataString($part)
  }
  return ($encodedParts -join "/")
}

function Get-DeployFiles {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $skipDirs = @(".git", ".github", "node_modules", ".next", "dist", "build", ".vercel")
  $skipFiles = @(".env", ".env.local", "deploy-github-pages.ps1")

  Get-ChildItem -LiteralPath $RootPath -Recurse -File | Where-Object {
    $fullName = $_.FullName
    $relative = $fullName.Substring($RootPath.Length).TrimStart("\", "/")
    $segments = $relative -split "[\\/]+"

    $hasSkippedDir = $false
    foreach ($segment in $segments) {
      if ($skipDirs -contains $segment) {
        $hasSkippedDir = $true
        break
      }
    }

    -not $hasSkippedDir -and -not ($skipFiles -contains $_.Name)
  }
}

$root = (Resolve-Path -LiteralPath $SourcePath).Path.TrimEnd("\", "/")
$authUser = Invoke-GitHub -Method GET -Path "/user"
if (-not $Owner) {
  $Owner = $authUser.login
}

Write-Host "GitHub account: $($authUser.login)"
Write-Host "Target repository: $Owner/$RepoName"
Write-Host "Source path: $root"

$repo = Invoke-GitHubOrNullOn404 -Method GET -Path "/repos/$Owner/$RepoName"
if ($null -eq $repo) {
  Write-Host "Creating repository..."
  $createBody = @{
    name = $RepoName
    private = [bool]$Private
    auto_init = $true
    description = "Static site deployed by deploy-github-pages.ps1"
  }

  if ($Owner -eq $authUser.login) {
    $repo = Invoke-GitHub -Method POST -Path "/user/repos" -Body $createBody
  } else {
    $repo = Invoke-GitHub -Method POST -Path "/orgs/$Owner/repos" -Body $createBody
  }

  if ($repo.default_branch) {
    $Branch = $repo.default_branch
  }
} else {
  Write-Host "Repository already exists; files will be created or updated."
  if ($repo.default_branch -and -not $PSBoundParameters.ContainsKey("Branch")) {
    $Branch = $repo.default_branch
  }
}

$files = @(Get-DeployFiles -RootPath $root)
if ($files.Count -eq 0) {
  throw "No deployable files found in $root."
}

Write-Host "Uploading $($files.Count) file(s) to branch '$Branch'..."
foreach ($file in $files) {
  $relative = $file.FullName.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  $contentPath = ConvertTo-GitHubPath -RelativePath $relative
  $existing = Invoke-GitHubOrNullOn404 -Method GET -Path "/repos/$Owner/$RepoName/contents/$contentPath`?ref=$Branch"

  $uploadBody = @{
    message = "Deploy $relative"
    content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.FullName))
    branch = $Branch
  }

  if ($null -ne $existing -and $existing.sha) {
    $uploadBody.sha = $existing.sha
  }

  Invoke-GitHub -Method PUT -Path "/repos/$Owner/$RepoName/contents/$contentPath" -Body $uploadBody | Out-Null
  Write-Host "Uploaded: $relative"
}

$pagesBody = @{
  source = @{
    branch = $Branch
    path = "/"
  }
}

Write-Host "Enabling GitHub Pages..."
try {
  Invoke-GitHub -Method POST -Path "/repos/$Owner/$RepoName/pages" -Body $pagesBody | Out-Null
} catch {
  if ($_.Exception.Message -match "HTTP 409|HTTP 422") {
    Invoke-GitHub -Method PUT -Path "/repos/$Owner/$RepoName/pages" -Body $pagesBody | Out-Null
  } else {
    throw
  }
}

$pages = Invoke-GitHub -Method GET -Path "/repos/$Owner/$RepoName/pages"
$pageUrl = if ($pages.html_url) { $pages.html_url.TrimEnd("/") + "/" } else { "https://$Owner.github.io/$RepoName/" }

Write-Host "Waiting for deployment: $pageUrl"
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$isReady = $false

while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
  $pages = Invoke-GitHub -Method GET -Path "/repos/$Owner/$RepoName/pages"

  try {
    $response = Invoke-WebRequest -Uri $pageUrl -Method Head -TimeoutSec 15 -UseBasicParsing
    if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
      $isReady = $true
      break
    }
  } catch {
    Write-Host "Still building... status=$($pages.status)"
  }
}

if ($isReady) {
  Write-Host ""
  Write-Host "Deployed successfully:"
  Write-Host $pageUrl
} else {
  Write-Host ""
  Write-Host "Upload finished, but GitHub Pages is still building. Check this link shortly:"
  Write-Host $pageUrl
}

