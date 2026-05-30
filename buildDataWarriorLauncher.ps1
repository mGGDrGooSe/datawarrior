# buildDataWarriorLauncher.ps1
# Simple PowerShell build script for the DataWarrior launcher.
# Uses explicit JDK and JavaFX paths.

$ErrorActionPreference = 'Stop'

$javacPath = 'C:\Program Files\Eclipse Adoptium\jdk-25.0.3.9-hotspot\bin\javac.exe'
$jarPath = 'C:\Program Files\Eclipse Adoptium\jdk-25.0.3.9-hotspot\bin\jar.exe'
$javafxLib = 'C:\javafx-sdk-25.0.3\lib'
$manifest = 'manifest_additions_launcher.txt'
$jarFile = 'datawarriorlauncher.jar'
$sourceFile = 'src/org/openmolecules/datawarrior/launcher/DataWarriorLauncher.java'
$binDir = 'bin'

Write-Host "Building DataWarrior launcher..."

if (Test-Path $binDir) {
    Remove-Item -Recurse -Force $binDir
}
New-Item -ItemType Directory -Path $binDir | Out-Null

$javacArgs = @(
    '--module-path', $javafxLib,
    '--add-modules', 'javafx.controls,javafx.web,javafx.swing',
    '-d', $binDir,
    '-sourcepath', './src',
    $sourceFile
)
& $javacPath @javacArgs

if (-not (Test-Path $manifest)) {
    Write-Host "Warning: $manifest not found; JAR manifest may be incomplete." -ForegroundColor Yellow
}

$jarArgs = @(
    '-cfm', $jarFile, $manifest,
    '-C', $binDir, '.'
)
& $jarPath @jarArgs

Remove-Item -Recurse -Force $binDir
Write-Host "Created $jarFile"
