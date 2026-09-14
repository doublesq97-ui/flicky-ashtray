#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
VERSION="0.5.0-preview.1"
PUBLISH_DIR="$ROOT_DIR/dist/windows-x64"
STAGE_DIR="$ROOT_DIR/dist/Flicky-Ashtray-Windows-x64"
ZIP_PATH="$ROOT_DIR/dist/Flicky-Ashtray-$VERSION-windows-x64.zip"

if [[ -x "$ROOT_DIR/tmp/dotnet/dotnet" ]]; then
    DOTNET="$ROOT_DIR/tmp/dotnet/dotnet"
elif command -v dotnet >/dev/null 2>&1; then
    DOTNET="$(command -v dotnet)"
else
    print -u2 "需要 .NET 10 SDK：https://dotnet.microsoft.com/download"
    exit 1
fi

cd "$ROOT_DIR"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

"$DOTNET" run \
    --project "$ROOT_DIR/Windows/FlickyAshtray.Core.Tests/FlickyAshtray.Core.Tests.csproj" \
    --configuration Release \
    --nologo

rm -rf "$PUBLISH_DIR" "$STAGE_DIR"
rm -f "$ZIP_PATH"

"$DOTNET" publish \
    "$ROOT_DIR/Windows/FlickyAshtray.Windows/FlickyAshtray.Windows.csproj" \
    --configuration Release \
    --runtime win-x64 \
    --self-contained true \
    --nologo \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:DebugType=None \
    -p:DebugSymbols=false \
    --output "$PUBLISH_DIR"

mkdir -p "$STAGE_DIR"
ditto --norsrc --noextattr --noqtn --noacl "$PUBLISH_DIR" "$STAGE_DIR"
cp "$ROOT_DIR/Windows/README.md" "$STAGE_DIR/README-Windows.md"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$STAGE_DIR" "$ZIP_PATH"

file "$STAGE_DIR/FlickyAshtray.exe"
shasum -a 256 "$ZIP_PATH"
print "Built $ZIP_PATH"
