# FileBrowser Validation Script
# This script validates the FileBrowser configuration and setup

param(
    [switch]$Detailed
)

Write-Host "=== FileBrowser Configuration Validation ===" -ForegroundColor Green

$errors = @()
$warnings = @()
$success = @()

# Check if required directories exist
Write-Host "`nChecking directory structure..." -ForegroundColor Blue

$requiredDirs = @(
    "config/filebrowser",
    "data/files",
    "data/files/shared",
    "data/files/users",
    "data/files/public",
    "data/files/uploads"
)

foreach ($dir in $requiredDirs) {
    if (Test-Path $dir) {
        $success += "OK Directory exists: $dir"
    } else {
        $errors += "ERROR Missing directory: $dir"
    }
}

# Check configuration files
Write-Host "`nChecking configuration files..." -ForegroundColor Blue

$configFiles = @{
    "config/filebrowser/filebrowser.json" = "Main configuration file"
    "config/filebrowser/security-config.json" = "Security configuration"
    "config/filebrowser/setup-filebrowser.ps1" = "Setup script"
    "config/filebrowser/manage-users.ps1" = "User management script"
    "config/filebrowser/README.md" = "Documentation"
}

foreach ($file in $configFiles.GetEnumerator()) {
    if (Test-Path $file.Key) {
        $success += "✓ Configuration file exists: $($file.Key)"
        
        # Validate JSON files
        if ($file.Key -like "*.json") {
            try {
                $content = Get-Content $file.Key -Raw | ConvertFrom-Json
                $success += "✓ Valid JSON format: $($file.Key)"
            } catch {
                $errors += "✗ Invalid JSON format: $($file.Key) - $($_.Exception.Message)"
            }
        }
    } else {
        $errors += "✗ Missing configuration file: $($file.Key)"
    }
}

# Check docker-compose.yml for FileBrowser service
Write-Host "`nChecking docker-compose configuration..." -ForegroundColor Blue

if (Test-Path "docker-compose.yml") {
    $composeContent = Get-Content "docker-compose.yml" -Raw
    
    if ($composeContent -match "filebrowser:") {
        $success += "✓ FileBrowser service defined in docker-compose.yml"
        
        # Check for required configuration
        $requiredConfig = @(
            "image: filebrowser/filebrowser",
            "container_name: filebrowser",
            "ports:",
            "volumes:",
            "networks:"
        )
        
        foreach ($config in $requiredConfig) {
            if ($composeContent -match [regex]::Escape($config)) {
                $success += "✓ Found configuration: $config"
            } else {
                $warnings += "⚠ Missing or different configuration: $config"
            }
        }
        
        # Check port mapping
        if ($composeContent -match '"8082:80"') {
            $success += "✓ Correct port mapping: 8082:80"
        } else {
            $warnings += "⚠ Port mapping may be different from expected 8082:80"
        }
        
        # Check volume mappings
        $requiredVolumes = @(
            "./data/files:/srv",
            "filebrowser_data:/database",
            "./config/filebrowser/filebrowser.json:/.filebrowser.json"
        )
        
        foreach ($volume in $requiredVolumes) {
            if ($composeContent -match [regex]::Escape($volume)) {
                $success += "✓ Found volume mapping: $volume"
            } else {
                $warnings += "⚠ Missing or different volume mapping: $volume"
            }
        }
        
    } else {
        $errors += "✗ FileBrowser service not found in docker-compose.yml"
    }
} else {
    $errors += "✗ docker-compose.yml file not found"
}

# Check environment variables
Write-Host "`nChecking environment configuration..." -ForegroundColor Blue

if (Test-Path ".env") {
    $envContent = Get-Content ".env" -Raw
    
    $requiredEnvVars = @(
        "FILEBROWSER_ADMIN_USER",
        "FILEBROWSER_ADMIN_PASSWORD",
        "DOMAIN"
    )
    
    foreach ($envVar in $requiredEnvVars) {
        if ($envContent -match "$envVar=") {
            $success += "✓ Environment variable defined: $envVar"
        } else {
            $warnings += "⚠ Environment variable not found: $envVar"
        }
    }
} else {
    $warnings += "⚠ .env file not found - using default values"
}

# Check Cloudflare tunnel configuration
Write-Host "`nChecking Cloudflare tunnel configuration..." -ForegroundColor Blue

if (Test-Path "config/cloudflared/config.yml") {
    $tunnelContent = Get-Content "config/cloudflared/config.yml" -Raw
    
    if ($tunnelContent -match "files\.\$\{DOMAIN\}") {
        $success += "✓ FileBrowser hostname configured in tunnel"
    } else {
        $warnings += "⚠ FileBrowser hostname not found in tunnel configuration"
    }
    
    if ($tunnelContent -match "http://filebrowser:80") {
        $success += "✓ FileBrowser service routing configured"
    } else {
        $warnings += "⚠ FileBrowser service routing not found in tunnel configuration"
    }
} else {
    $warnings += "⚠ Cloudflare tunnel configuration not found"
}

# Check sample files
Write-Host "`nChecking sample files..." -ForegroundColor Blue

$sampleFiles = @(
    "data/files/public/README.md",
    "data/files/shared/welcome.txt"
)

foreach ($file in $sampleFiles) {
    if (Test-Path $file) {
        $success += "✓ Sample file exists: $file"
    } else {
        $warnings += "⚠ Sample file missing: $file (will be created on first run)"
    }
}

# Display results
Write-Host "`n=== Validation Results ===" -ForegroundColor Green

if ($success.Count -gt 0) {
    Write-Host "`nSuccessful Checks ($($success.Count)):" -ForegroundColor Green
    if ($Detailed) {
        foreach ($item in $success) {
            Write-Host "  $item" -ForegroundColor Green
        }
    } else {
        Write-Host "  $($success.Count) checks passed" -ForegroundColor Green
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($item in $warnings) {
        Write-Host "  $item" -ForegroundColor Yellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host "`nErrors ($($errors.Count)):" -ForegroundColor Red
    foreach ($item in $errors) {
        Write-Host "  $item" -ForegroundColor Red
    }
}

# Overall status
Write-Host "`n=== Overall Status ===" -ForegroundColor Green

if ($errors.Count -eq 0) {
    if ($warnings.Count -eq 0) {
        Write-Host "✓ FileBrowser configuration is ready for deployment!" -ForegroundColor Green
        $exitCode = 0
    } else {
        Write-Host "⚠ FileBrowser configuration is mostly ready with some warnings" -ForegroundColor Yellow
        Write-Host "  You can proceed with deployment, but review the warnings above" -ForegroundColor Yellow
        $exitCode = 1
    }
} else {
    Write-Host "✗ FileBrowser configuration has errors that must be fixed" -ForegroundColor Red
    Write-Host "  Please address the errors above before deployment" -ForegroundColor Red
    $exitCode = 2
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Fix any errors shown above" -ForegroundColor Gray
Write-Host "  2. Run: .\config\filebrowser\setup-filebrowser.ps1" -ForegroundColor Gray
Write-Host "  3. Access FileBrowser at: http://localhost:8082" -ForegroundColor Gray
Write-Host "  4. Test file operations and sharing features" -ForegroundColor Gray

exit $exitCode