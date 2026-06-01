# runDataWarrior.ps1 - Run DataWarrior on Windows with custom memory allocation
# Usage: ./runDataWarrior.ps1 -MaxMemory 32g

param(
    [string]$MaxMemory = "54g",
    [string]$InitialMemory = "8g"
)

# Validate memory format
if ($MaxMemory -notmatch '^\d+[kmg]$') {
    Write-Host "Error: MaxMemory must be in format like '8g', '512m', etc." -ForegroundColor Red
    exit 1
}

if ($InitialMemory -notmatch '^\d+[kmg]$') {
    Write-Host "Error: InitialMemory must be in format like '2g', '512m', etc." -ForegroundColor Red
    exit 1
}

# Check if JAR exists
if (-not (Test-Path "./datawarrior_all.jar")) {
    Write-Host "Error: datawarrior_all.jar not found in current directory" -ForegroundColor Red
    Write-Host "Please run buildDataWarrior.ps1 first" -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Running DataWarrior ===" -ForegroundColor Green
Write-Host "Initial Memory (-Xms): $InitialMemory" -ForegroundColor Cyan
Write-Host "Maximum Memory (-Xmx): $MaxMemory" -ForegroundColor Cyan
Write-Host ""

# Detect JavaFX SDK for runtime (JAVAFX_HOME or common locations)
# Use fixed JavaFX lib path (override with JAVAFX_HOME if set)
$defaultJavafxLib = 'C:\javafx-sdk-25.0.3\lib'
if ($env:JAVAFX_HOME) { $javafxLib = Join-Path $env:JAVAFX_HOME 'lib' } else { $javafxLib = $defaultJavafxLib }

# Build java arguments
$javaArgs = @(
    "--add-exports", "java.base/jdk.internal.module=ALL-UNNAMED",
    "-Xms$InitialMemory",
    "-Xmx$MaxMemory"
)

if ($javafxLib -and (Test-Path $javafxLib)) {
    Write-Host "Using JavaFX runtime from: $javafxLib" -ForegroundColor Cyan
    $javaArgs += @("--module-path", $javafxLib, "--add-modules", "javafx.controls,javafx.web,javafx.swing")
}
else {
    Write-Host "Warning: JavaFX lib not found at $javafxLib — runtime may fail." -ForegroundColor Yellow
}

$javaArgs += @("-jar", "datawarrior_all.jar")

& java @javaArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "DataWarrior exited with error code: $LASTEXITCODE" -ForegroundColor Red
}
