param(
	[Parameter(Mandatory=$true)]
	[ValidateSet("all_static", "all_secure_static", "all_dynamic", "all_secure_dynamic")]
	[string]$Target,

	[Parameter(Mandatory=$true)]
	[string]$ProjectName
)

if (Test-Path "Deploy"){
	Remove-Item "Deploy" -Recurse -Force
}

mkdir "Deploy"

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

#=========================== Configuration commune ===========================
$WslDistro       = "AlmaLinux-9"
$WslUser         = "echo"
$WslRoot         = "/home/echo/Projet/$ProjectName"
$PruneName       = ".prune-appdir.tmp.sh"
$MetaDesktopName = ".meta.tmp.desktop"
$MetaXmlName     = ".meta.tmp.appdata.xml"

function Invoke-Wsl {
	param([Parameter(Mandatory=$true)][string]$Command)

	wsl --distribution $WslDistro --user $WslUser -- bash -lc ($Command -replace "`r", "") | Out-Host
	if ($LASTEXITCODE -ne 0) {
		throw "Échec de la commande WSL (code $LASTEXITCODE)"
	}
}

function Export-WslFile {
	param([string]$From, [string]$To)
	Invoke-Wsl "cat $From > Deploy/$To"
}

function Write-TempFile {
	param([string]$Name, [string]$Content)

	$path = Join-Path (Get-Location).Path $Name
	[System.IO.File]::WriteAllText($path, ($Content -replace "`r", ""), (New-Object System.Text.UTF8Encoding($false)))
	return $path
}

#=========================== Utilitaires ===========================
function Get-CMakeVersion {
    $cmakeFile = "CMakeLists.txt"

    if (!(Test-Path $cmakeFile)) {
        Write-Host "CMakeLists.txt introuvable, version par défaut 1.0.0"
        return "1.0.0"
    }

    $line = Select-String -Path $cmakeFile -Pattern 'set\(APP_VERSION\s+"([0-9\.]+)"\)' | Select-Object -First 1

    if ($line) {
        $match = [regex]::Match($line.Line, '"([0-9\.]+)"')
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }

    Write-Host "Version non trouvée dans CMakeLists.txt, version par défaut 1.0.0"
    return "1.0.0"
}

function Get-CMakeValue {
	param([string]$Name, [string]$Default)

	if (Test-Path "CMakeLists.txt") {
		$pattern = 'set\(' + $Name + '\s+"([^"]*)"\)'
		$line = Select-String -Path "CMakeLists.txt" -Pattern $pattern -Encoding UTF8 | Select-Object -First 1
		if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
	}
	return $Default
}

function Get-OrCreate-AppId {
    $path = "AppId.txt"

    if (Test-Path $path) {
        return (Get-Content $path -Raw).Trim()
    }

    $guid = [guid]::NewGuid().ToString("B")
    Set-Content $path $guid

    return $guid
}

#=========================== Compilation Windows ===========================
function Build-Windows {
	param([switch]$Static, [switch]$OpenSSL)

	Write-Host "=== Compilation Windows ==="

	$qt = if ($Static) { "C:/Qt/6.10.2/Static/msvc" } else { "C:/Qt/6.10.2/msvc2022_64" }

	$cmakeArgs = @("-DCMAKE_PREFIX_PATH=$qt")
	if ($OpenSSL) {
		$cmakeArgs += "-DOPENSSL_ROOT_DIR=C:/dev/vcpkg/installed/x64-windows-static"
		$cmakeArgs += "-DOPENSSL_USE_STATIC_LIBS=ON"
	}

	Remove-Item "build" -Recurse -Force -ErrorAction SilentlyContinue

	cmake -B build -S . -G "Visual Studio 17 2022" -T v143 @cmakeArgs
	cmake --build build --config Release

	mkdir -p Deploy/Windows
	cp build/Release/*.exe Deploy/Windows

	if (-not $Static) {
		$env:Path = "$qt/bin;" + $env:PATH
		windeployqt --release --no-translations "Deploy/Windows/$ProjectName.exe"
	}

	Write-Host "=== Exécutable généré ==="
}

#=========================== Setup ===========================
function Build-InnoSetup {
	Write-Host "=== Génération de l'installeur Inno Setup ==="

    $InnoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    $ScriptPath = "$(PWD)\Installer\setup.iss"

    if (!(Test-Path $InnoPath)) {
        Write-Host "Erreur : ISCC.exe introuvable"
        exit 1
    }

    if (!(Test-Path $ScriptPath)) {
        Write-Host "Erreur : script Inno Setup introuvable : $ScriptPath"
        exit 1
    }

	$Version = Get-CMakeVersion
	$AppId= Get-OrCreate-AppId

    & "$InnoPath" "/dProjectName=$ProjectName" "/dProjectVersion=$Version" "/dAppId=$AppId" "$ScriptPath"

    Write-Host "=== Installeur généré ==="
}

#=========================== Métadonnées AppImage (commun x86 + ARM) ===========================
function Write-MetaFiles {
	$version = Get-CMakeVersion
	$author  = Get-CMakeValue "APP_AUTHOR"  "Inconnu"
	$summary = Get-CMakeValue "APP_SUMMARY" $ProjectName
	$date    = Get-Date -Format "yyyy-MM-dd"

	$authorXml  = [System.Security.SecurityElement]::Escape($author)
	$summaryXml = [System.Security.SecurityElement]::Escape($summary)

	$desktop = @"
[Desktop Entry]
Name=$ProjectName
Comment=$summary
Exec=$ProjectName
Icon=$ProjectName
Type=Application
Categories=Utility;
X-AppImage-Version=$version
"@

	$xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$ProjectName</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <name>$ProjectName</name>
  <summary>$summaryXml</summary>
  <description>
    <p>$summaryXml</p>
  </description>
  <developer_name>$authorXml</developer_name>
  <launchable type="desktop-id">$ProjectName.desktop</launchable>
  <provides>
    <binary>$ProjectName</binary>
  </provides>
  <releases>
    <release version="$version" date="$date"/>
  </releases>
</component>
"@

	return @(
		(Write-TempFile $MetaDesktopName $desktop),
		(Write-TempFile $MetaXmlName $xml)
	)
}

#=========================== Nettoyage AppDir (commun x86 + ARM) ===========================
# Retire d'un AppDir les plugins Qt dont le module n'est pas utilisé par l'appli, puis leurs libs orphelines.
function Get-PruneScript {
	return @'
#!/bin/bash
set -euo pipefail

APPDIR=$1
APP=$2
KEEP_PLUGINS=${3:-}
LIB=$APPDIR/usr/lib
PLUG=$APPDIR/usr/plugins

echo "Taille AppDir avant nettoyage : $(du -sh "$APPDIR" | cut -f1)"

needed() { readelf -d "$1" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'; }

closure() {
  local -n ref=$2
  local n
  for n in $(needed "$1"); do
    if [[ -n ${ref[$n]:-} ]]; then continue; fi
    if [ ! -e "$LIB/$n" ]; then continue; fi
    ref[$n]=1
    closure "$LIB/$n" "$2"
  done
}

declare -A BASE=()
closure "$APPDIR/usr/bin/$APP" BASE
while read -r f; do closure "$f" BASE; done < <(find "$PLUG/platforms" -name '*.so' 2>/dev/null)

declare -A REMOVED=()
while read -r f; do
  if [[ -n $KEEP_PLUGINS && $(basename "$f") =~ $KEEP_PLUGINS ]]; then continue; fi
  for n in $(needed "$f"); do
    if [[ $n == libQt6* && -z ${BASE[$n]:-} ]]; then
      echo "Plugin retiré : ${f#$PLUG/} (exige $n)"
      closure "$f" REMOVED
      rm -f "$f"
      break
    fi
  done
done < <(find "$PLUG" -name '*.so' 2>/dev/null)

declare -A KEEP=()
closure "$APPDIR/usr/bin/$APP" KEEP
while read -r f; do closure "$f" KEEP; done < <(find "$PLUG" -name '*.so' 2>/dev/null)
for n in "${!REMOVED[@]}"; do
  if [[ -z ${KEEP[$n]:-} ]]; then
    echo "Lib retirée : $n"
    rm -f "$LIB/$n"
  fi
done

rm -rf "$APPDIR/usr/translations"
find "$PLUG" -type d -empty -delete 2>/dev/null || true

echo "Taille AppDir après nettoyage : $(du -sh "$APPDIR" | cut -f1)"
'@
}

#=========================== Compilation Linux x86 ===========================
function Build-Linux {
	param([switch]$OpenSSL)

	Write-Host "=== Compilation Linux Dynamic ==="

	$ssl = ""
	if ($OpenSSL) {
		$ssl = "-DOPENSSL_ROOT_DIR=/usr -DOPENSSL_CRYPTO_LIBRARY=/usr/lib64/libcrypto.so -DOPENSSL_SSL_LIBRARY=/usr/lib64/libssl.so"
	}

	$version = Get-CMakeVersion
	$appName = "$ProjectName-$version-x64.AppImage"

	$prunePath = Write-TempFile $PruneName (Get-PruneScript)
	$metaPaths = Write-MetaFiles

	try {
		Invoke-Wsl "rm -rf $WslRoot/build-linux $WslRoot/AppDir $WslRoot/$ProjectName.AppImage"

		Invoke-Wsl @"
set -e
mkdir -p $WslRoot
cmake -B $WslRoot/build-linux -S . -DCMAKE_BUILD_TYPE=Release $ssl
cmake --build $WslRoot/build-linux

mkdir -p $WslRoot/AppDir/usr/bin
mkdir -p $WslRoot/AppDir/usr/share/applications
mkdir -p $WslRoot/AppDir/usr/share/metainfo
mkdir -p $WslRoot/AppDir/usr/share/icons/hicolor/256x256/apps

cp $WslRoot/build-linux/$ProjectName $WslRoot/AppDir/usr/bin/
cp $WslRoot/build-linux/resources/Icone.png $WslRoot/AppDir/usr/share/icons/hicolor/256x256/apps/$ProjectName.png

cp ./$MetaDesktopName $WslRoot/AppDir/usr/share/applications/$ProjectName.desktop
cp ./$MetaXmlName $WslRoot/AppDir/usr/share/metainfo/$ProjectName.appdata.xml

export QMAKE=/usr/bin/qmake6
export QML_SOURCES_PATHS=.
export NO_STRIP=1

cp ./$PruneName $WslRoot/$PruneName
cd $WslRoot

/home/echo/Tools/linuxdeploy/usr/bin/linuxdeploy --appdir AppDir --plugin qt
bash ./$PruneName AppDir $ProjectName
rm -f ./$PruneName
/home/echo/Tools/linuxdeploy/usr/bin/linuxdeploy --appdir AppDir --output appimage

mv $ProjectName-x86_64.AppImage $appName
"@
	}
	finally {
		Remove-Item (@($prunePath) + $metaPaths) -Force -ErrorAction SilentlyContinue
	}

	Export-WslFile "$WslRoot/$appName" $appName

	Write-Host "=== Binaire généré ==="
}

#=========================== Compilation Linux ARM64 ===========================
# Les jetons @@PRUNE@@, @@DESKTOP@@ et @@XML@@ sont remplacés par Build-Linux-Arm.
function Get-AppImageArmScript {
	return @'
#!/bin/bash
set -euo pipefail

APP=$1
VER=$2
SYSROOT=$HOME/sysroot-aarch64
BUILD=$HOME/Projet/$APP/build-linux-arm
APPDIR=$BUILD/AppDir
TOOLS=$HOME/appimage-tools
QTPLUG=$SYSROOT/usr/lib64/qt6/plugins
OUT=$BUILD/$APP-$VER-aarch64.AppImage

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/plugins" "$TOOLS"

[ -x "$TOOLS/appimagetool" ] || {
  curl -fL -o "$TOOLS/appimagetool" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOLS/appimagetool"
}
[ -f "$TOOLS/runtime-aarch64" ] || \
  curl -fL -o "$TOOLS/runtime-aarch64" \
    https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-aarch64

EXCLUDE='^(libc|libm|libdl|libpthread|librt|libutil|libresolv|libnsl|ld-linux-aarch64|libstdc\+\+|libgcc_s|libGL|libGLX|libOpenGL|libEGL|libGLdispatch|libdrm|libX11|libX11-xcb|libxcb|libfontconfig|libfreetype|libharfbuzz|libz|libgpg-error|libSM|libICE|libuuid|libcom_err)\.so'
declare -A SEEN

add_deps() {
  local n
  for n in $(readelf -d "$1" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
    [[ $n =~ $EXCLUDE ]] && continue
    [[ -n ${SEEN[$n]:-} ]] && continue
    SEEN[$n]=1
    cp -L "$SYSROOT/usr/lib64/$n" "$APPDIR/usr/lib/$n"
    add_deps "$SYSROOT/usr/lib64/$n"
  done
}

cp "$BUILD/$APP" "$APPDIR/usr/bin/$APP"
add_deps "$APPDIR/usr/bin/$APP"

for d in platforms platforminputcontexts imageformats iconengines xcbglintegrations styles; do
  cp -rL "$QTPLUG/$d" "$APPDIR/usr/plugins/"
done
while read -r f; do add_deps "$f"; done < <(find "$APPDIR/usr/plugins" -name '*.so')

bash ./@@PRUNE@@ "$APPDIR" "$APP"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="$HERE/usr/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$HERE/usr/plugins/platforms"
exec "$HERE/usr/bin/@APP@" "$@"
EOF
sed -i "s/@APP@/$APP/" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

mkdir -p "$APPDIR/usr/share/metainfo"
cp ./@@DESKTOP@@ "$APPDIR/$APP.desktop"
cp ./@@XML@@ "$APPDIR/usr/share/metainfo/$APP.appdata.xml"

cp "$BUILD/resources/Icone.png" "$APPDIR/$APP.png"

rm -f "$OUT"
ARCH=aarch64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOLS/appimagetool" --no-appstream \
  --runtime-file "$TOOLS/runtime-aarch64" "$APPDIR" "$OUT"

file "$OUT"
'@
}

function Build-Linux-Arm {
	param([switch]$OpenSSL)

	Write-Host "=== Compilation croisée Linux ARM64 ==="

	$ssl = ""
	if ($OpenSSL) { $ssl = '-DOPENSSL_ROOT_DIR=$HOME/sysroot-aarch64/usr' }

	$version = Get-CMakeVersion
	$tmpName = ".make-appimage-arm64.tmp.sh"
	$appName = "$ProjectName-$version-aarch64.AppImage"

	$armScript = (Get-AppImageArmScript).Replace('@@PRUNE@@', $PruneName).Replace('@@DESKTOP@@', $MetaDesktopName).Replace('@@XML@@', $MetaXmlName)

	$tmpPath   = Write-TempFile $tmpName $armScript
	$prunePath = Write-TempFile $PruneName (Get-PruneScript)
	$metaPaths = Write-MetaFiles

	try {
		Invoke-Wsl "rm -rf $WslRoot/build-linux-arm"

		Invoke-Wsl @"
set -e
mkdir -p $WslRoot
cmake -B $WslRoot/build-linux-arm -S . -G Ninja -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja -DCMAKE_BUILD_TYPE=Release -DTARGET_ARM64=ON -DQT_HOST_PATH=/usr -DQT_HOST_PATH_CMAKE_DIR=/usr/lib64/cmake -DCMAKE_PREFIX_PATH=\`$HOME/sysroot-aarch64/usr $ssl
cmake --build $WslRoot/build-linux-arm -j \`$(nproc)
bash ./$tmpName $ProjectName $version
"@
	}
	finally {
		Remove-Item (@($tmpPath, $prunePath) + $metaPaths) -Force -ErrorAction SilentlyContinue
	}

	Export-WslFile "$WslRoot/build-linux-arm/$appName" $appName

	Write-Host "=== Binaire généré ==="
}

#=========================== Cibles ===========================
switch ($Target) {
	"all_static"         { Build-Windows -Static;           Build-Linux; Build-Linux-Arm  }
	"all_secure_static"  { Build-Windows -Static -OpenSSL;  Build-Linux -OpenSSL; Build-Linux-Arm -OpenSSL }
	"all_dynamic"        { Build-Windows; Build-InnoSetup;  Build-Linux; Build-Linux-Arm }
	#"all_dynamic"       { Build-Linux-Arm }
	"all_secure_dynamic" { Build-Windows -OpenSSL; Build-InnoSetup; Build-Linux -OpenSSL; Build-Linux-Arm -OpenSSL }
}
