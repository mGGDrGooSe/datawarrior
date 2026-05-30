# buildDataWarrior.ps1 - Build DataWarrior JAR on Windows using PowerShell

# Set error action to stop on errors
$ErrorActionPreference = "Stop"

# Colors for output
$Green = [System.ConsoleColor]::Green
$Yellow = [System.ConsoleColor]::Yellow
$Red = [System.ConsoleColor]::Red

function Write-Status {
    param([string]$Message)
    Write-Host $Message -ForegroundColor $Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor $Red
    exit 1
}

try {
    Write-Status "=== DataWarrior Build Script for Windows ==="
    
    # Find Java installation
    Write-Status "`nDetecting Java installation..."
    
    $javacPath = $null
    $javaHome = $null
    
    # Try common installation locations for OpenJDK/Temurin
    $possiblePaths = @(
        "C:\Program Files\Eclipse Adoptium\temurin*\bin\javac.exe",
        "C:\Program Files\OpenJDK\jdk*\bin\javac.exe",
        "C:\Program Files (x86)\OpenJDK\jdk*\bin\javac.exe",
        "$env:JAVA_HOME\bin\javac.exe"
    )
    
    foreach ($pattern in $possiblePaths) {
        $found = @(Get-Item $pattern -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) {
            $javacPath = $found[0].FullName
            break
        }
    }
    
    # If still not found, try Windows registry
    if (-not $javacPath) {
        $regPaths = @(
            "HKLM:\SOFTWARE\JavaSoft\JDK",
            "HKLM:\SOFTWARE\JavaSoft\Java Development Kit"
        )
        
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $jdkVersion = (Get-ChildItem $regPath | Sort-Object | Select-Object -Last 1).PSChildName
                $javaHome = (Get-ItemProperty "$regPath\$jdkVersion" -ErrorAction SilentlyContinue).JavaHome
                if ($javaHome) {
                    $javacPath = "$javaHome\bin\javac.exe"
                    break
                }
            }
        }
    }
    
    # Final fallback: check PATH
    if (-not $javacPath) {
        try {
            $javacPath = (Get-Command javac -ErrorAction Stop).Source
        }
        catch {
            # Not in PATH
        }
    }
    
    if (-not $javacPath -or -not (Test-Path $javacPath)) {
        Write-Error-Custom @"
javac (Java Compiler) not found!

Please install OpenJDK or set JAVA_HOME environment variable.

To set JAVA_HOME:
1. Find your JDK installation path (e.g., C:\Program Files\Eclipse Adoptium\temurin-25.0.3+9)
2. Open Environment Variables (Win+X, then search for "Environment Variables")
3. Create a new System Variable:
   Name: JAVA_HOME
   Value: [Your JDK installation path]
4. Restart PowerShell

Or download Temurin OpenJDK from:
https://adoptium.net/
"@
    }
    
    Write-Status "  Found javac at: $javacPath"
    
    # Step 1: Create bin directory
    Write-Status "`nStep 1: Creating bin directory..."
    if (Test-Path "./bin") {
        Remove-Item -Recurse -Force "./bin" | Out-Null
        Write-Status "  Removed existing bin directory"
    }
    New-Item -ItemType Directory -Path "./bin" -Force | Out-Null
    
    # Step 2: Copy HTML and images
    Write-Status "Step 2: Copying HTML and images..."
    Copy-Item -Path "./src/html" -Destination "./bin/" -Recurse -Force
    Copy-Item -Path "./src/images" -Destination "./bin/" -Recurse -Force
    Write-Status "  Copied src/html and src/images"
    
    # Step 3: Compile Java source code
    Write-Status "Step 3: Compiling DataWarrior source code..."
    Write-Host "  This may take a few minutes..." -ForegroundColor $Yellow
    
    # Use a simple, fixed JavaFX lib path (can be overridden by JAVAFX_HOME)
    $defaultJavafxLib = 'C:\javafx-sdk-25.0.3\lib'
    if ($env:JAVAFX_HOME) {
        $javafxLib = Join-Path $env:JAVAFX_HOME 'lib'
    }
    else {
        $javafxLib = $defaultJavafxLib
    }

    $javacArgs = @(
        "--add-exports", "javafx.web/com.sun.webkit=ALL-UNNAMED",
        "--add-exports", "javafx.web/com.sun.webkit.dom=ALL-UNNAMED",
        "--add-exports", "java.base/jdk.internal.module=ALL-UNNAMED",
        "-nowarn",
        "-d", "./bin",
        "-sourcepath", "./src;./stubs",
        "-classpath", "./lib/*",
        "src/com/actelion/research/datawarrior/DataWarriorLinux.java",
        "src/com/actelion/research/datawarrior/DataWarriorOSX.java"
    )

    if ($javafxLib -and (Test-Path $javafxLib)) {
        Write-Status "  Using JavaFX SDK at: $javafxLib"
        $javacArgs = @("--module-path", $javafxLib, "--add-modules", "javafx.controls,javafx.web,javafx.swing") + $javacArgs
    }
    else {
        Write-Status "  JavaFX lib not found at $javafxLib — compilation may fail if JavaFX classes are required."
    }

    & $javacPath @javacArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Compilation failed"
    }
    Write-Status "  Compilation completed successfully"
    
    # Step 4: Extract all JAR files
    Write-Status "Step 4: Unpacking JAR dependencies..."
    
    # Find jar command (usually same directory as javac)
    $jarPath = if ($javacPath) { 
        Split-Path $javacPath | Join-Path -ChildPath "jar.exe"
    } else {
        "jar"
    }
    
    if (-not (Test-Path $jarPath)) {
        $jarPath = "jar"
    }
    
    Push-Location "./bin"
    
    $jarFiles = Get-ChildItem -Path "../lib/*.jar"
    foreach ($jar in $jarFiles) {
        Write-Host "  Unpacking $($jar.Name)..."
        & $jarPath -xf $jar.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Failed to extract $($jar.Name)"
        }
    }
    
    # Step 5: Remove signature files
    Write-Status "Step 5: Removing signature files..."
    $sigFiles = @("META-INF/*.SF", "META-INF/*.RSA", "META-INF/*.DSA")
    foreach ($pattern in $sigFiles) {
        Get-Item $pattern -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Write-Status "  Removed signature files"
    
    Pop-Location
    
    # Step 6: Create fat JAR
    Write-Status "Step 6: Building fat JAR file..."
    
    # Create build date file
    $buildDate = Get-Date -Format "d-MMM-yyyy"
    Set-Content -Path "./bin/resources/builtDate.txt" -Value $buildDate -NoNewline
    
    & $jarPath -cfm datawarrior_all.jar manifest_additions.txt -C ./bin .
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to create JAR file"
    }
    Write-Status "  Created datawarrior_all.jar"
    
    # Step 7: Cleanup
    Write-Status "Step 7: Cleaning up..."
    Remove-Item -Path "./bin" -Recurse -Force
    
    # Display results
    Write-Status "`n=== Build Complete ==="
    $jarInfo = Get-Item "datawarrior_all.jar"
    Write-Status "JAR File: $($jarInfo.Name)"
    Write-Status "Size: $([math]::Round($jarInfo.Length / 1MB, 2)) MB"
    Write-Status "Location: $(Resolve-Path 'datawarrior_all.jar')"
    Write-Status "`nTo run with increased memory, use:"
    Write-Status "  java --add-exports java.base/jdk.internal.module=ALL-UNNAMED -Xms2g -Xmx8g -jar datawarrior_all.jar"
    Write-Status "`nAdjust -Xmx8g to your desired memory (e.g., 16g, 32g)"
}
catch {
    Write-Error-Custom $_.Exception.Message
}
