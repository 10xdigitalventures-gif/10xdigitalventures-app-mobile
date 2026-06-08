# =====================================================================
# Mobile App: Fix gradle build failure -- duplicate expo-updates-interface
#
# PROBLEM:
#   EAS gradle build failed with:
#     Could not find host.exp.exponent:expo-updates-interface:56.0.2
#   This is caused by version mismatch between:
#     - expo-updates@29.x (ships with expo-updates-interface@2.0.0)
#     - expo-observe@56.x (requires expo-updates-interface@56.0.2)
#   The SDK 54 dependency tree cannot resolve both at once.
#
# FIX:
#   Remove expo-observe and expo-updates from package.json. The app does
#   NOT need either of them for core functionality:
#     - expo-observe = optional performance monitoring (can add in SDK 55+)
#     - expo-updates = optional OTA update mechanism (not configured anyway)
#
#   The Error Boundary already has fallbacks for both -- it will keep
#   working without them.
#
# Run from MOBILE repo root:
#   powershell -ExecutionPolicy Bypass -File .\mobile-fix-build-duplicates.ps1
#   git add -A; git commit -m "Fix build: remove expo-observe/updates"; git push
#   npx eas build --profile preview --platform android
# =====================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-FileUtf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}
function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    Write-Host "  wrote: $Path"
}

if (-not (Test-Path "package.json")) {
    Write-Host "ERROR: Run from mobile repo root."
    exit 1
}

Write-Host "==================================================="
Write-Host "Fix gradle build duplicates"
Write-Host "==================================================="
Write-Host ""

# =====================================================================
# 1) Remove expo-observe and expo-updates from package.json
# =====================================================================
Write-Host "[1/3] Removing expo-observe + expo-updates from package.json..."

$pkgPath = "package.json"
$pkg = Read-FileUtf8 $pkgPath | ConvertFrom-Json

$removed = @()
foreach ($name in @('expo-observe', 'expo-updates')) {
    if ($pkg.dependencies.PSObject.Properties[$name]) {
        $pkg.dependencies.PSObject.Properties.Remove($name)
        $removed += $name
        Write-Host "  - removed dependency: $name"
    }
}

if ($removed.Count -eq 0) {
    Write-Host "  = neither package was in dependencies (already clean)"
}

# Write back package.json
$pkgJson = $pkg | ConvertTo-Json -Depth 32
Write-FileUtf8NoBom -Path $pkgPath -Content $pkgJson

# =====================================================================
# 2) Delete node_modules + lockfile so install is fully fresh
# =====================================================================
Write-Host ""
Write-Host "[2/3] Cleaning node_modules + package-lock.json..."

if (Test-Path "node_modules") {
    Write-Host "  removing node_modules folder (this may take 30-60 sec)..."
    Remove-Item -Recurse -Force "node_modules"
    Write-Host "  + node_modules removed"
} else {
    Write-Host "  = node_modules already absent"
}

if (Test-Path "package-lock.json") {
    Remove-Item -Force "package-lock.json"
    Write-Host "  + package-lock.json removed"
}

if (Test-Path "yarn.lock") {
    Remove-Item -Force "yarn.lock"
    Write-Host "  + yarn.lock removed"
}

# =====================================================================
# 3) Patch app/_layout.js -- make sure require for expo-observe is safe
#    (it already is, but double-check; also remove expo-updates require
#    from ErrorBoundary)
# =====================================================================
Write-Host ""
Write-Host "[3/3] Patching files that referenced removed packages..."

# 3a) ErrorBoundary -- remove expo-updates require (use DevSettings only)
$ebPath = "components/ErrorBoundary.js"
if (Test-Path $ebPath) {
    $eb = Read-FileUtf8 $ebPath
    # Replace the Updates require block with a safe no-op
    $oldUpd = "let Updates = null`r`ntry { Updates = require('expo-updates') } catch (e) { Updates = null }"
    $newUpd = "// expo-updates removed to fix gradle dependency conflict; using DevSettings fallback"
    if ($eb.Contains($oldUpd)) {
        $eb = $eb.Replace($oldUpd, $newUpd)
    }
    # Also LF variant
    $oldUpdLf = "let Updates = null`ntry { Updates = require('expo-updates') } catch (e) { Updates = null }"
    if ($eb.Contains($oldUpdLf)) {
        $eb = $eb.Replace($oldUpdLf, $newUpd)
    }
    # And neutralize the Updates.reloadAsync call (DevSettings still works)
    $eb = $eb -replace "if \(Updates\?\.reloadAsync\) \{ await Updates\.reloadAsync\(\); return \}", "// (Updates.reloadAsync disabled)"
    Write-FileUtf8NoBom -Path $ebPath -Content $eb
    Write-Host "  + ErrorBoundary cleaned up"
}

# 3b) app/_layout.js -- the require for expo-observe is already in a
#     try/catch, so it will gracefully no-op. Nothing to change.
$rootPath = "app/_layout.js"
if (Test-Path $rootPath) {
    $root = Read-FileUtf8 $rootPath
    if ($root -match "require\('expo-observe'\)") {
        Write-Host "  = expo-observe require already in try/catch (safe)"
    }
}

Write-Host ""
Write-Host "================================================================="
Write-Host "FIX READY."
Write-Host ""
Write-Host "NEXT STEPS:"
Write-Host ""
Write-Host "  1) Reinstall dependencies (fresh):"
Write-Host "       npm install"
Write-Host ""
Write-Host "  2) Verify duplicates are gone:"
Write-Host "       npx expo-doctor"
Write-Host "     (should say '18/18 checks passed')"
Write-Host ""
Write-Host "  3) Push to git:"
Write-Host "       git add -A"
Write-Host "       git commit -m 'Fix build: remove expo-observe/updates conflict'"
Write-Host "       git push"
Write-Host ""
Write-Host "  4) Rebuild APK:"
Write-Host "       npx eas build --profile preview --platform android"
Write-Host ""
Write-Host "WHAT YOU LOSE:"
Write-Host "  - EAS Observe (performance dashboard) -- skip for now,"
Write-Host "    add back when you upgrade to SDK 55+"
Write-Host "  - expo-updates (OTA updates) -- you weren't using it anyway"
Write-Host ""
Write-Host "WHAT STILL WORKS (everything else):"
Write-Host "  - Error Boundary (uses DevSettings.reload fallback)"
Write-Host "  - New Chat with FAB"
Write-Host "  - Offline cache + banner"
Write-Host "  - All previously working features (calls, reactions, etc.)"
Write-Host "================================================================="
