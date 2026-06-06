# Vanillaherb Codex Plugin Marketplace

## One-command install

Run this in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vanillaherb/codex-plugin-marketplace/main/install.ps1 | iex"
```

This downloads and installs `github-pages-deploy` into your Personal Codex marketplace. Restart Codex or open a new thread if it does not appear immediately.

## Manual marketplace install

Add this marketplace in Codex:

```text
vanillaherb/codex-plugin-marketplace
```

Then install `github-pages-deploy`.

If Codex asks for a sparse path, leave it empty unless your Codex version requires one. The marketplace file is at the repository root:

```text
marketplace.json
```
