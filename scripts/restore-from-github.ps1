#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automated configuration restoration from GitHub repository
.DESCRIPTION
    This script handles complete infrastructure restoration from a GitHub repository.
    It clones the repository, restores configurations, and prepares the environment for deployment.
.PARAMETER RepositoryUrl
    The GitHub repository URL to restore from (optional, uses .env if available)
.PARAMETER Branch
    The branch to restore from (default: main)
.PARAMETER Force
    Force restoration even if local files exist
.EXAMPLE
    .\restore-from-github.ps1
    .\restore-from-github.ps1 -RepositoryUrl "https://github.com/user/repo.git" -Force
    .\restore-from-github.ps1 -Branch "develop"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RepositoryUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$Branch = "main",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check if git is installed
    try {
        $gitVersion = git --version
        Write-Log "Git found: $gitVersion"
    } catch {
        Write-Log "Git is not installed or not in PATH" "ERROR"
        return $false
    }
    
    # Check if Docker is installed
    try {
        $dockerVersion = docker --version
        Write-Log "Docker found: $dockerVersion"
    } catch {
        Write-Log "Docker is not installed or not running" "ERROR"
        return $false
    }
    
    # Check if Docker Compose is available
    try {
        $composeVersion = docker-compose --version
        Write-Log "Docker Compose found: $composeVersion"
    } catch {
        Write-Log "Docker Compose is not installed" "ERROR"
        return $false
    }
    
    return $true
}

function Get-GitHubConfiguration {
    # Try to load from existing .env file
    if (Test-Path ".env") {
        Write-Log "Loading GitHub configuration from existing .env file..."
        Get-Content ".env" | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
            }
        }
        
        return @{
            Username = $env:GITHUB_USERNAME
            Token = $env:GITHUB_TOKEN
            Repo = $env:GITHUB_REPO
            RepoUrl = $env:GITHUB_REPO_URL
        }
    }
    
    # If no .env file, try to get from parameters or prompt
    if (-not $RepositoryUrl) {
        Write-Log "No repository URL provided and no .env file found" "ERROR"
        Write-Log "Please provide repository URL with -RepositoryUrl parameter" "ERROR"
        return $null
    }
    
    return @{
        RepoUrl = $RepositoryUrl
    }
}

function Backup-ExistingConfiguration {
    Write-Log "Backing up existing configuration..."
    
    $backupDir = "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    $filesToBackup = @(
        ".env",
        "docker-compose.yml",
        "config/",
        "data/"
    )
    
    $hasFiles = $false
    foreach ($file in $filesToBackup) {
        if (Test-Path $file) {
            if (-not $hasFiles) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                $hasFiles = $true
            }
            
            if (Test-Path $file -PathType Container) {
                Copy-Item -Path $file -Destination $backupDir -Recurse -Force
            } else {
                Copy-Item -Path $file -Destination $backupDir -Force
            }
            Write-Log "Backed up: $file"
        }
    }
    
    if ($hasFiles) {
        Write-Log "Backup created in: $backupDir"
        return $backupDir
    } else {
        Write-Log "No existing files to backup"
        return $null
    }
}

function Clone-Repository {
    param(
        [string]$RepoUrl,
        [string]$Username,
        [string]$Token,
        [string]$TargetBranch
    )
    
    Write-Log "Cloning repository from GitHub..."
    
    # Prepare authenticated URL if credentials are available
    $cloneUrl = $RepoUrl
    if ($Username -and $Token) {
        $cloneUrl = $RepoUrl -replace "https://", "https://${Username}:${Token}@"
    }
    
    $tempDir = "temp-clone-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    try {
        # Clone repository to temporary directory
        git clone --branch $TargetBranch $cloneUrl $tempDir
        Write-Log "Repository cloned successfully"
        
        return $tempDir
    } catch {
        Write-Log "Failed to clone repository: $_" "ERROR"
        return $null
    }
}

function Restore-Configuration {
    param([string]$SourceDir)
    
    Write-Log "Restoring configuration files..."
    
    # Files and directories to restore
    $restoreItems = @(
        @{ Source = "docker-compose.yml"; Required = $true },
        @{ Source = ".env.template"; Required = $true },
        @{ Source = ".gitignore"; Required = $false },
        @{ Source = "README.md"; Required = $false },
        @{ Source = "config"; Required = $true },
        @{ Source = "scripts"; Required = $false },
        @{ Source = "docs"; Required = $false },
        @{ Source = ".kiro"; Required = $false }
    )
    
    $restored = 0
    $failed = 0
    
    foreach ($item in $restoreItems) {
        $sourcePath = Join-Path $SourceDir $item.Source
        $destPath = $item.Source
        
        if (Test-Path $sourcePath) {
            try {
                if (Test-Path $sourcePath -PathType Container) {
                    # Directory
                    if (Test-Path $destPath) {
                        Remove-Item -Path $destPath -Recurse -Force
                    }
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                } else {
                    # File
                    Copy-Item -Path $sourcePath -Destination $destPath -Force
                }
                
                Write-Log "Restored: $($item.Source)"
                $restored++
            } catch {
                Write-Log "Failed to restore $($item.Source): $_" "ERROR"
                $failed++
                
                if ($item.Required) {
                    Write-Log "Required file $($item.Source) failed to restore. Aborting." "ERROR"
                    return $false
                }
            }
        } else {
            if ($item.Required) {
                Write-Log "Required file $($item.Source) not found in repository" "ERROR"
                $failed++
            } else {
                Write-Log "Optional file $($item.Source) not found in repository" "WARN"
            }
        }
    }
    
    Write-Log "Restoration complete: $restored restored, $failed failed"
    return $failed -eq 0 -or $restored -gt 0
}

function Initialize-Environment {
    Write-Log "Initializing environment..."
    
    # Create .env from template if it doesn't exist
    if (-not (Test-Path ".env") -and (Test-Path ".env.template")) {
        Copy-Item ".env.template" ".env"
        Write-Log "Created .env from template"
        Write-Log "IMPORTANT: Please edit .env file with your specific configuration" "WARN"
    }
    
    # Create required directories
    $requiredDirs = @(
        "data/files",
        "data/backups",
        "data/logs"
    )
    
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Created directory: $dir"
            
            # Create .gitkeep files
            $gitkeepPath = Join-Path $dir ".gitkeep"
            "# This file ensures the $dir directory is tracked in git" | Out-File -FilePath $gitkeepPath -Encoding UTF8
        }
    }
    
    # Set executable permissions on scripts (if on Unix-like system)
    if ($IsLinux -or $IsMacOS) {
        Get-ChildItem "scripts/*.sh" -ErrorAction SilentlyContinue | ForEach-Object {
            chmod +x $_.FullName
            Write-Log "Set executable permission: $($_.Name)"
        }
    }
}

function Test-RestoredConfiguration {
    Write-Log "Testing restored configuration..."
    
    $errors = @()
    
    # Check required files
    $requiredFiles = @(
        "docker-compose.yml",
        ".env.template"
    )
    
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            $errors += "Missing required file: $file"
        }
    }
    
    # Test docker-compose configuration
    try {
        $composeTest = docker-compose config 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errors += "Docker Compose configuration invalid: $composeTest"
        } else {
            Write-Log "Docker Compose configuration is valid"
        }
    } catch {
        $errors += "Failed to validate Docker Compose configuration: $_"
    }
    
    # Check .env file
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $templateVars = Get-Content ".env.template" | Where-Object { $_ -match "^[A-Z_]+=.*your-.*" }
        
        if ($templateVars.Count -gt 0) {
            Write-Log "WARNING: .env file contains template values that need to be updated:" "WARN"
            $templateVars | ForEach-Object { Write-Log "  $_" "WARN" }
        }
    }
    
    if ($errors.Count -gt 0) {
        Write-Log "Configuration validation failed:" "ERROR"
        $errors | ForEach-Object { Write-Log "  $_" "ERROR" }
        return $false
    }
    
    Write-Log "Configuration validation passed"
    return $true
}

# Main execution
Write-Log "Starting automated configuration restoration from GitHub"

# Check prerequisites
if (-not (Test-Prerequisites)) {
    Write-Log "Prerequisites check failed. Please install required tools." "ERROR"
    exit 1
}

# Check if we should proceed with existing files
if (-not $Force -and (Test-Path "docker-compose.yml")) {
    Write-Log "Existing configuration detected. Use -Force to overwrite." "WARN"
    $response = Read-Host "Continue with restoration? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Log "Restoration cancelled by user"
        exit 0
    }
}

# Get GitHub configuration
$githubConfig = Get-GitHubConfiguration
if (-not $githubConfig) {
    exit 1
}

# Use provided repository URL or from configuration
$repoUrl = if ($RepositoryUrl) { $RepositoryUrl } else { $githubConfig.RepoUrl }
if (-not $repoUrl) {
    Write-Log "No repository URL available" "ERROR"
    exit 1
}

# Backup existing configuration
$backupDir = Backup-ExistingConfiguration

# Clone repository
$tempCloneDir = Clone-Repository -RepoUrl $repoUrl -Username $githubConfig.Username -Token $githubConfig.Token -TargetBranch $Branch
if (-not $tempCloneDir) {
    Write-Log "Failed to clone repository" "ERROR"
    exit 1
}

try {
    # Restore configuration
    $restoreSuccess = Restore-Configuration -SourceDir $tempCloneDir
    if (-not $restoreSuccess) {
        Write-Log "Configuration restoration failed" "ERROR"
        exit 1
    }
    
    # Initialize environment
    Initialize-Environment
    
    # Test restored configuration
    $testSuccess = Test-RestoredConfiguration
    if (-not $testSuccess) {
        Write-Log "Configuration validation failed" "ERROR"
        exit 1
    }
    
    Write-Log "Configuration restoration completed successfully!" "INFO"
    Write-Log ""
    Write-Log "Next steps:" "INFO"
    Write-Log "1. Edit .env file with your specific configuration" "INFO"
    Write-Log "2. Configure Cloudflare tunnel credentials" "INFO"
    Write-Log "3. Run 'docker-compose up -d' to start services" "INFO"
    
    if ($backupDir) {
        Write-Log ""
        Write-Log "Previous configuration backed up to: $backupDir" "INFO"
    }
    
} finally {
    # Clean up temporary clone directory
    if (Test-Path $tempCloneDir) {
        Remove-Item -Path $tempCloneDir -Recurse -Force
        Write-Log "Cleaned up temporary files"
    }
}

Write-Log "Restoration process completed"