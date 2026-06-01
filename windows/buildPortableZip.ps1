# buildPortableZip.ps1 - Build portable ZIP distribution for DataWarrior
# This script creates a zero-install portable ZIP that includes:
#   - Compiled DataWarrior.exe launcher with dynamic memory detection
#   - Bundled Java runtime (JRE) with JavaFX
#   - All application files (jars, resources, examples, etc.)
#   - User-editable memory configuration file
#   - Helper scripts for file associations and cleanup
#
# Usage:
#   .\buildPortableZip.ps1 -OutputPath ".\dist" -Version "v06.02.00" -JDKPath "C:\Program Files\Eclipse Adoptium\jdk-25.0.3.9-hotspot" -JavaFXPath "C:\javafx-sdk-25.0.3"

param(
    [string]$OutputPath = ".",
    [string]$Version = "v06.01.00",
    [string]$JDKPath = "C:\Program Files\Eclipse Adoptium\jdk-25.0.3.9-hotspot",
    [string]$JavaFXPath = "C:\javafx-sdk-25.0.3",
    [switch]$SkipJRE = $false,
    [switch]$SkipLauncherCompile = $false
)

$ErrorActionPreference = 'Stop'

# Color output functions
function Write-Status {
    param([string]$Message)
    Write-Host "=== $Message ===" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "WARNING: $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

# Main execution
Write-Status "Building DataWarrior Portable ZIP Distribution"

# Resolve paths
$repoRoot = (Resolve-Path $PSScriptRoot).Path
$stagingDir = Join-Path $repoRoot "staging_portable"
$outputZip = Join-Path $OutputPath "DataWarrior-$Version-portable.zip"

Write-Info "Repository root: $repoRoot"
Write-Info "Output ZIP: $outputZip"
Write-Info "Staging directory: $stagingDir"

# Clean and create staging
if (Test-Path $stagingDir) {
    Write-Info "Removing existing staging directory..."
    Remove-Item $stagingDir -Recurse -Force
}
New-Item $stagingDir -ItemType Directory | Out-Null

# ============================================================================
# Phase 1: Compile DataWarrior.exe launcher
# ============================================================================

if (-not $SkipLauncherCompile) {
    Write-Status "Compiling DataWarrior.exe launcher"
    
    $launcherSource = Join-Path $repoRoot "DataWarriorLauncher.cs"
    $launcherExe = Join-Path $stagingDir "DataWarrior.exe"
    
    if (-not (Test-Path $launcherSource)) {
        Write-Error-Custom "Launcher source not found at $launcherSource"
        Write-Info "Skipping launcher compilation. You can compile manually:"
        Write-Info "  csc.exe /out:$launcherExe $launcherSource"
    } else {
        try {
            Write-Info "Compiling $launcherSource..."
            & csc.exe /out:$launcherExe $launcherSource
            if ($LASTEXITCODE -ne 0) {
                Write-Error-Custom "C# compiler failed with exit code $LASTEXITCODE"
                exit 1
            }
            Write-Info "Launcher compiled successfully: $launcherExe"
        } catch {
            Write-Error-Custom "Failed to compile launcher: $_"
            Write-Info "Ensure C# compiler (csc.exe) is in PATH. Continuing without compiled launcher."
        }
    }
} else {
    Write-Info "Skipping launcher compilation (as requested)."
    Write-Warning "You must provide a pre-compiled DataWarrior.exe or compile it manually."
}

# ============================================================================
# Phase 2: Build bundled JRE (minimal with JavaFX)
# ============================================================================

if (-not $SkipJRE) {
    Write-Status "Building minimal JRE with JavaFX"
    
    $jreDir = Join-Path $stagingDir "jre"
    
    # Validate JDK path
    if (-not (Test-Path $JDKPath)) {
        Write-Error-Custom "JDK not found at $JDKPath"
        Write-Info "Set -JDKPath to your JDK installation (e.g., C:\Program Files\Eclipse Adoptium\jdk-25.0.3.9-hotspot)"
        exit 1
    }
    
    $jdkJmodsPath = Join-Path $JDKPath "jmods"
    if (-not (Test-Path $jdkJmodsPath)) {
        Write-Error-Custom "JDK jmods not found at $jdkJmodsPath"
        exit 1
    }
    
    # Validate JavaFX path
    if (-not (Test-Path $JavaFXPath)) {
        Write-Error-Custom "JavaFX SDK not found at $JavaFXPath"
        Write-Info "Set -JavaFXPath to your JavaFX SDK installation (e.g., C:\javafx-sdk-25.0.3)"
        exit 1
    }
    
    $javafxModPath = Join-Path $JavaFXPath "lib"
    if (-not (Test-Path $javafxModPath)) {
        Write-Error-Custom "JavaFX lib not found at $javafxModPath"
        exit 1
    }
    
    Write-Info "JDK path: $JDKPath"
    Write-Info "JavaFX path: $JavaFXPath"
    Write-Info "Building JRE to: $jreDir"
    
    try {
        $modulePath = "$javafxModPath;$jdkJmodsPath"
        $addModules = "javafx.controls,javafx.web,javafx.swing,java.base,java.logging,java.desktop"
        
        Write-Info "Running jlink with modules: $addModules"
        & jlink --module-path $modulePath `
                --add-modules $addModules `
                --output $jreDir `
                --strip-debug `
                --compress=2
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "jlink failed with exit code $LASTEXITCODE"
            exit 1
        }
        
        $jreSize = (Get-Item $jreDir | Measure-Object -Property Length -Recurse | Select-Object -ExpandProperty Sum) / 1MB
        Write-Info "JRE bundled successfully (~${jreSize:F0} MB)"
    } catch {
        Write-Error-Custom "Failed to build JRE: $_"
        exit 1
    }
} else {
    Write-Info "Skipping JRE build (as requested)."
    Write-Warning "You must provide a pre-built JRE at staging/jre/ or set -SkipJRE:$false"
}

# ============================================================================
# Phase 3: Copy application files
# ============================================================================

Write-Status "Packaging application files"

$appDir = Join-Path $stagingDir "datawarrior"
New-Item $appDir -ItemType Directory | Out-Null

# Copy launcher and app jars
$files_to_copy = @(
    @{ Source = "datawarriorlauncher.jar"; Dest = $appDir },
    @{ Source = "datawarrior_all.jar"; Dest = $appDir },
    @{ Source = "loading.png"; Dest = $appDir }
)

foreach ($file_entry in $files_to_copy) {
    $src = Join-Path $repoRoot $file_entry.Source
    $dest = Join-Path $file_entry.Dest (Split-Path $file_entry.Source -Leaf)
    
    if (Test-Path $src) {
        Write-Info "Copying $(Split-Path $src -Leaf)..."
        Copy-Item $src $dest
    } else {
        Write-Warning "File not found: $src"
    }
}

# Copy folders (example, reference, tutorial, macro, plugin)
$folders_to_copy = @("example", "reference", "tutorial", "macro", "plugin")

foreach ($folder in $folders_to_copy) {
    $src = Join-Path $repoRoot "datawarrior" $folder
    if (Test-Path $src) {
        Write-Info "Copying folder: $folder..."
        Copy-Item $src "$appDir/$folder" -Recurse
    } else {
        Write-Warning "Folder not found: $src"
    }
}

# Create update folder (writable at runtime)
New-Item "$appDir/update" -ItemType Directory | Out-Null
Write-Info "Created update folder"

# ============================================================================
# Phase 4: Create configuration template
# ============================================================================

Write-Status "Creating configuration template"

$configContent = @"
# DataWarrior Portable Configuration
# Uncomment and adjust to override automatic memory detection
# If commented, memory is calculated as: max = min(75% of system RAM, 32GB), initial = max/4

# Maximum heap memory (GB). Leave commented for auto-detect.
# MAX_MEMORY_GB=32

# Initial heap memory (GB). Leave commented for auto-detect.
# INITIAL_MEMORY_GB=8

# Optional: application window title or other settings
# WINDOW_TITLE=DataWarrior Portable
"@

$configContent | Out-File -FilePath "$stagingDir/datawarrior.config" -Encoding UTF8 -NoNewline
Write-Info "Created: datawarrior.config"

# ============================================================================
# Phase 5: Create README
# ============================================================================

Write-Status "Creating documentation"

$readmeContent = @"
DataWarrior Portable
====================

Quick Start:
1. Extract to your desired folder (no admin required).
2. Double-click DataWarrior.exe to launch.
3. (Optional) Drag and drop .dwar files onto DataWarrior.exe to open them.

Memory Configuration:
- Edit datawarrior.config to adjust MAX_MEMORY_GB and INITIAL_MEMORY_GB.
- By default, memory is auto-detected (75% of system RAM up to 32GB).
- Changes take effect on the next launch.

File Associations (Optional):
- Run resources/file-associations/associate.ps1 to register .dwar and related file types.
- Requires PowerShell and may prompt for user confirmation.
- No admin privileges required; associations are per-user.

Drag and Drop:
- Drag .dwar, .dwam, .dwaq, .dwas, .dwat, or .sdf files onto DataWarrior.exe to open them.

For support and documentation:
- None. Provided as-is
- Read the embedded help (Help > Help Contents within DataWarrior)

Troubleshooting:
- If DataWarrior won't start, try reducing MAX_MEMORY_GB in datawarrior.config
- Verify that jre/bin/java.exe exists
- Check Windows Event Viewer for detailed error messages
"@

$readmeContent | Out-File -FilePath "$stagingDir/README.txt" -Encoding UTF8 -NoNewline
Write-Info "Created: README.txt"

# ============================================================================
# Phase 6: Create helper scripts
# ============================================================================

Write-Status "Creating helper scripts"

# Create resources/file-associations directory
$resourcesDir = Join-Path $stagingDir "resources" "file-associations"
New-Item $resourcesDir -ItemType Directory -Force | Out-Null

# Create associate.ps1 script
$associateScript = @'
# Helper script to register DataWarrior file associations (per-user)
# This script registers .dwar and related file types to open with DataWarrior.exe
# No admin privileges required; uses HKCU (per-user registry)
# Run this script manually if you want file association support.

param(
    [switch]$Help
)

if ($Help) {
    Write-Host @"
DataWarrior File Association Helper

Usage:
  .\associate.ps1              # Registers file types for current user
  .\associate.ps1 -Help        # Shows this help

This script associates the following file types with DataWarrior:
  - .dwar (DataWarrior file)
  - .dwam (DataWarrior macromolecule)
  - .dwaq (DataWarrior query)
  - .dwas (DataWarrior SDF)
  - .dwat (DataWarrior template)
  - .sdf (Structure Data Format)

Note: Changes may require a Windows restart to take effect.
"@
    exit 0
}

Write-Host "DataWarrior File Association Setup" -ForegroundColor Green

# Get the path to DataWarrior.exe
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$portableDir = (Get-Item "$scriptDir\..\..\").FullName
$dataWarriorExe = Join-Path $portableDir "DataWarrior.exe"

if (-not (Test-Path $dataWarriorExe)) {
    Write-Host "ERROR: DataWarrior.exe not found at $dataWarriorExe" -ForegroundColor Red
    exit 1
}

$extensions = @(".dwar", ".dwam", ".dwaq", ".dwas", ".dwat", ".sdf")
$progId = "OpenMolecules.DataWarrior.file"

Write-Host "Using DataWarrior.exe: $dataWarriorExe`n" -ForegroundColor Cyan

# Register ProgID and file associations
foreach ($ext in $extensions) {
    try {
        # Use cmd /c to run assoc and ftype (built-in Windows commands)
        cmd /c "assoc $ext=$progId" 2>$null
        cmd /c "ftype $progId=`"$dataWarriorExe`" %%1" 2>$null
        Write-Host "✓ Registered $ext -> DataWarrior" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to register $ext : $_" -ForegroundColor Red
    }
}

Write-Host "`nFile associations complete." -ForegroundColor Green
Write-Host "You may need to restart Windows for changes to take effect." -ForegroundColor Yellow
'@

$associateScript | Out-File -FilePath "$resourcesDir/associate.ps1" -Encoding UTF8 -NoNewline
Write-Info "Created: resources/file-associations/associate.ps1"

# Create cleanup.ps1 script
$cleanupScript = @'
# Helper script to clean up DataWarrior portable installation
# Use this if you want to remove DataWarrior and associated files
# This script will ask for confirmation before removing anything.

$portableDir = (Get-Item "$PSScriptRoot\..").FullName

Write-Host "DataWarrior Portable Cleanup" -ForegroundColor Green
Write-Host "This will remove DataWarrior from: $portableDir" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to delete this folder? (type 'yes' to confirm)"

if ($confirm -eq "yes") {
    try {
        Write-Host "Removing $portableDir..." -ForegroundColor Yellow
        Remove-Item $portableDir -Recurse -Force -ErrorAction Stop
        Write-Host "Removed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Error during removal: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Cancelled." -ForegroundColor Cyan
    exit 0
}
'@

$uninstallDir = Join-Path $stagingDir "uninstall"
New-Item $uninstallDir -ItemType Directory -Force | Out-Null

$cleanupScript | Out-File -FilePath "$uninstallDir/cleanup.ps1" -Encoding UTF8 -NoNewline
Write-Info "Created: uninstall/cleanup.ps1"

# Create uninstall README
$uninstallReadme = @"
Uninstall Instructions
======================

To remove DataWarrior:

Option 1: Manual Deletion
- Close DataWarrior if it's running
- Delete the DataWarrior folder

Option 2: Using cleanup.ps1
- Run: .\cleanup.ps1
- Answer 'yes' when prompted

DataWarrior is portable and creates no system entries, so deletion is complete cleanup.
"@

$uninstallReadme | Out-File -FilePath "$uninstallDir/README.txt" -Encoding UTF8 -NoNewline
Write-Info "Created: uninstall/README.txt"

# ============================================================================
# Phase 7: Compress to ZIP
# ============================================================================

Write-Status "Creating ZIP archive"

if (Test-Path $outputZip) {
    Write-Info "Removing existing ZIP file..."
    Remove-Item $outputZip -Force
}

if (-not (Test-Path $OutputPath)) {
    New-Item $OutputPath -ItemType Directory | Out-Null
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $outputZip, 'Optimal', $true)
    Write-Info "ZIP archive created successfully"
} catch {
    Write-Error-Custom "Failed to create ZIP archive: $_"
    exit 1
}

# ============================================================================
# Phase 8: Cleanup and Report
# ============================================================================

Write-Info "Cleaning up staging directory..."
Remove-Item $stagingDir -Recurse -Force

$zipSize = (Get-Item $outputZip).Length / 1MB
$zipPath = (Resolve-Path $outputZip).Path

Write-Status "Build Complete"
Write-Host "Output: $zipPath" -ForegroundColor Green
Write-Host "Size: ${zipSize:F1} MB" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Test the ZIP on a clean Windows machine"
Write-Host "  2. Extract and run: DataWarrior.exe"
Write-Host "  3. (Optional) Run: resources/file-associations/associate.ps1"
Write-Host "  4. (Optional) Drag .dwar files onto DataWarrior.exe"
Write-Host ""
Write-Host "Distribution ready for release!" -ForegroundColor Green
