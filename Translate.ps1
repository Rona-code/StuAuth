param(
	[Parameter(Mandatory=$true)]
	[ValidateSet("Generate", "Translate", "Complete")]
	[string]$Target
)

$ProjectName = (Split-Path $PSScriptRoot -Leaf).ToLower()
$Path = "$PSScriptRoot/resources"
echo $Path

function Generates {
	Start-Process wsl.exe -ArgumentList "-d Ubuntu-24.04"

	while ($true) {
		curl.exe http://localhost:5000/ --silent --fail > $null 2>&1

		if ($LASTEXITCODE -eq 0) {
			Write-Host "Service disponible"
			break
		}

		Write-Host "Service indisponible, nouvelle tentative..."
		Start-Sleep -Seconds 2
	}

	if (Test-Path "$Path/translations"){
		Remove-Item "$Path/translations" -Recurse -Force
	}

	mkdir "$Path/translations"

	$PathTranslate = "$PSScriptRoot/resources/translations"

	lupdate . -ts "$PathTranslate/${ProjectName}_fr.ts" "$PathTranslate/${ProjectName}_en.ts" "$PathTranslate/${ProjectName}_ja.ts" "$PathTranslate/${ProjectName}_bz.ts"
}

function AutoTrad {
	$PathTranslate = "$PSScriptRoot/resources/translations"

	$languages = @{
    "fr" = "français"
    "en" = "anglais"
    "ja" = "japonais"
	}

	foreach ($lang in $languages.Keys) {
		& "C:/!tool/QtLingo.exe" $languages[$lang] "$PathTranslate/${ProjectName}_${lang}.ts"
	}

		wsl -t Ubuntu-24.04
}

function Translates {
	if (-not (Test-Path "$Path/translations")){
		Write-host "Aucun fichier de traductions trouver veuillez d'abord faire Generate"
		return
	}

	$PathTranslate = "$PSScriptRoot/resources/translations"

	lrelease "$PathTranslate/${ProjectName}_fr.ts" "$PathTranslate/${ProjectName}_en.ts" "$PathTranslate/${ProjectName}_ja.ts" "$PathTranslate/${ProjectName}_bz.ts"
}

switch ($Target) {
	"Generate" { Generates; AutoTrad }
	"Translate" { Translates }
	"Complete" { Generates; AutoTrad; Translates }
}