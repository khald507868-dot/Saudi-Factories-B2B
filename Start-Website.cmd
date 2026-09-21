@echo off
cd /d "%~dp0"
powershell -NoProfile -Command "$siteNode = (Get-Command node -ErrorAction SilentlyContinue).Source; if (-not $siteNode) { $siteNode = Join-Path $env:ProgramFiles 'nodejs\node.exe' }; if (-not (Test-Path -LiteralPath $siteNode)) { throw 'Node.js is required.' }; if (-not (Get-NetTCPConnection -State Listen -LocalPort 4173 -ErrorAction SilentlyContinue)) { Start-Process -FilePath $siteNode -ArgumentList 'scripts/serve-web.mjs' -WorkingDirectory (Get-Location).Path -WindowStyle Hidden }; Write-Output 'http://127.0.0.1:4173/web-addresses.html'"
