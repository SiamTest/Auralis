#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$Repository = $env:GITHUB_REPOSITORY
$Tag = $env:GITHUB_REF_NAME
if ($env:GITHUB_REF_TYPE -ne 'tag' -or $Tag -notmatch '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'Only stable vMAJOR.MINOR.PATCH tags can publish a release.'
}
if ($Repository -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub repository.' }
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Version = $Tag.Substring(1)
$Dist = Join-Path $ProjectRoot 'dist'
$Names = @("auralis-$Version-windows-x64.zip", "auralis-$Version-windows-x64-setup.exe", "auralis-$Version-source.zip", 'SHA256SUMS.txt')
$Files = $Names | ForEach-Object {
    $Path = Join-Path $Dist $_
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release asset missing: $_" }
    $Path
}
$Existing = $null
try { $Existing = gh release view $Tag --repo $Repository --json isDraft | ConvertFrom-Json } catch { }
if ($Existing -and -not $Existing.isDraft) {
    Write-Output 'This tag is already published. Published assets are never replaced.'
    exit 0
}
if (-not $Existing) { gh release create $Tag --repo $Repository --verify-tag --draft --title "Auralis $Version" --generate-notes }
gh release upload $Tag @Files --repo $Repository --clobber
# Keep the release private until every server-side digest matches the uploaded file.
$Release = gh api "repos/$Repository/releases/tags/$Tag" | ConvertFrom-Json
foreach ($Path in $Files) {
    $Name = [System.IO.Path]::GetFileName($Path)
    $Asset = @($Release.assets | Where-Object name -eq $Name)
    $Expected = 'sha256:' + (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Asset.Count -ne 1 -or $Asset[0].digest -ne $Expected) { throw "GitHub digest mismatch for $Name. Release remains a draft." }
}
gh release edit $Tag --repo $Repository --draft=false --latest
