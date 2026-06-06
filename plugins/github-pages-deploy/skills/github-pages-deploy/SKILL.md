---
name: github-pages-deploy
description: Deploy static websites or browser apps to GitHub Pages by uploading local files through the GitHub REST API. Use when the user asks to automatically upload files to GitHub, publish a static site, enable GitHub Pages, or return a deployed Pages URL without relying on local git or gh commands.
---

# GitHub Pages Deploy

## Overview

Use this skill to publish a local static site to GitHub Pages with the bundled PowerShell script. The script creates or reuses a GitHub repository, uploads files through the GitHub REST API, enables Pages from the repository root, waits for the page to become reachable, and prints the final URL.

## Workflow

1. Identify the static site root. Prefer the current project directory when it contains `index.html`; otherwise ask the user which folder to deploy.
2. Confirm the user has a GitHub Personal Access Token available. The script reads `GITHUB_TOKEN` or accepts `-Token`; do not ask the user to paste secrets into chat if they can set an environment variable locally.
3. Run `scripts/deploy-github-pages.ps1` from this skill, passing `-SourcePath`, `-RepoName`, and optionally `-Owner`.
4. If network access or external GitHub API calls are restricted, request approval for the script run.
5. Return the URL printed by the script. If Pages is still building, return the generated URL and tell the user it may need a short wait.

## Script Usage

The bundled script is:

```text
scripts/deploy-github-pages.ps1
```

Typical run from a project directory:

```powershell
$env:GITHUB_TOKEN = "github_pat_..."
& "<skill-path>\scripts\deploy-github-pages.ps1" -SourcePath "." -RepoName "my-static-site"
```

Use `-Owner` when deploying under an organization:

```powershell
& "<skill-path>\scripts\deploy-github-pages.ps1" -SourcePath "." -Owner "my-org" -RepoName "my-static-site"
```

Use `-Private` only when the user explicitly wants a private repository and their GitHub plan supports Pages for private repos.

## Operational Notes

- The token must be allowed to create or update repositories, write repository contents, and manage GitHub Pages.
- The script does not require local `git` or GitHub CLI `gh`.
- The script excludes common non-deployable or sensitive paths such as `.git`, `node_modules`, `.env`, build cache folders, and itself.
- The script uploads files from the source directory root to the repository root, so `index.html` should be at the source root for a normal Pages site.
- Prefer a short, URL-safe repository name, for example `portfolio-site`, `game-demo`, or `codex-pages-demo`.

## Verification

After running the script, treat a reachable `https://<owner>.github.io/<repo>/` URL as successful deployment. If the script reports that Pages is still building, optionally check the URL again after one or two minutes before declaring the deployment failed.
