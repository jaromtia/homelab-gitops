#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple Git operations wrapper for homelab infrastructure
.DESCRIPTION
    Provides easy-to-use commands for common Git operations in the homelab infrastructure.
    This is a simplified interface to the more comprehensive github-sync.ps1 script.
.PARAMETER Command
    The Git operation to perform: save, load, status, or setup
.PARAMETER Message
    Commit message for save operations (optional)
.EXAMPLE
    .\git-ops.ps1 save "Updated monitoring configuration"
    .\git-ops.ps1 load
    .\git-ops.ps1 status
    .\git-ops.ps1 setup
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("save", "load", "status", "setup")]
    [string]$Command,
    
    [Parameter(Mandatory=$false)]
    [string]$Message = "Configuration update"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$githubSyncScript = Join-Path $scriptDir "github-sync.ps1"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Show-Help {
    Write-Host "Git Operations for Homelab Infrastructure" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  save    - Save current configuration to GitHub" -ForegroundColor White
    Write-Host "  load    - Load latest configuration from GitHub" -ForegroundColor White
    Write-Host "  status  - Show Git repository status" -ForegroundColor White
    Write-Host "  setup   - Initialize Git repository" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\git-ops.ps1 save 'Updated monitoring config'" -ForegroundColor White
    Write-Host "  .\git-ops.ps1 load" -ForegroundColor White
    Write-Host "  .\git-ops.ps1 status" -ForegroundColor White
    Write-Host "  .\git-ops.ps1 setup" -ForegroundColor White
}

# Check if github-sync.ps1 exists
if (-not (Test-Path $githubSyncScript)) {
    Write-Log "GitHub sync script not found: $githubSyncScript" "ERROR"
    Write-Log "Please ensure all scripts are properly installed." "ERROR"
    exit 1
}

# Execute the appropriate command
switch ($Command) {
    "save" {
        Write-Log "Saving configuration to GitHub..."
        & $githubSyncScript -Action push -Message $Message
    }
    "load" {
        Write-Log "Loading configuration from GitHub..."
        & $githubSyncScript -Action pull
    }
    "status" {
        Write-Log "Checking Git status..."
        & $githubSyncScript -Action status
    }
    "setup" {
        Write-Log "Setting up Git repository..."
        & $githubSyncScript -Action init
    }
    default {
        Show-Help
    }
}

Write-Log "Git operation completed: $Command"