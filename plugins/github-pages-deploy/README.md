# GitHub Pages Deploy Codex Plugin

Codex plugin that adds a skill for publishing static sites to GitHub Pages.

## Install

Clone or download this repository, then run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-local.ps1
```

Restart Codex or open a new thread, then install `github-pages-deploy` from the Personal marketplace.

## Use

Ask Codex:

```text
Deploy this static site to GitHub Pages and return the published URL.
```

The bundled skill uses GitHub's REST API and can create/update a repository, upload static files, enable GitHub Pages, and return the live URL. It needs a GitHub token or GitHub CLI authentication available on the user's machine.
