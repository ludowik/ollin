# Downloads third-party dependencies required to build ollin.
# Run once after cloning, or to update to a new version.

$RAYLIB_VERSION = "6.0"
$RAYLIB_URL     = "https://github.com/raysan5/raylib/archive/refs/tags/$RAYLIB_VERSION.zip"
$DEST           = "$PSScriptRoot\..\third_party"
$RAYLIB_DIR     = "$DEST\raylib"

if (Test-Path "$RAYLIB_DIR\CMakeLists.txt") {
    Write-Host "raylib $RAYLIB_VERSION already present — skipping."
    exit 0
}

Write-Host "Downloading raylib $RAYLIB_VERSION..."
New-Item -ItemType Directory -Force $DEST | Out-Null
$zip = "$env:TEMP\raylib-$RAYLIB_VERSION.zip"
Invoke-WebRequest -Uri $RAYLIB_URL -OutFile $zip -UseBasicParsing

Write-Host "Extracting..."
Expand-Archive -Path $zip -DestinationPath $DEST -Force
Rename-Item "$DEST\raylib-$RAYLIB_VERSION" "raylib"
Remove-Item $zip

Write-Host "Done — raylib $RAYLIB_VERSION ready in third_party\raylib\"
