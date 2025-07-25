#!/usr/bin/env pwsh
<#
.SYNOPSIS
    GitHub repository synchronization script for homelab infrastructure
.DESCRIPTION
    This script handles pushing configuration changes to GitHub and pulling updates from the repository.
    It manages configuration files, compose files, and deployment scripts while excluding sensitive data.
.PARAMETER Action
    The action to perform: push, pull, or status
.PARAMETER Message
    Commit message for push operations (optional)
.EXAMPLE
    .\github-sync.ps1 -Action push -Message "Updated monitoring configuration"
    .\github-sync.ps1 -Action pull
    .\github-sync.ps1 -Action status
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("push", "pull", "status", "init")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$Message = "Automated configuration update"
)

# Load environment variables
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^#][^=]+)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
} else {
    Write-Error ".env file not found. Please ensure you're running from the project root."
    exit 1
}

# GitHub configuration
$GITHUB_USERNAME = $env:GITHUB_USERNAME
$GITHUB_TOKEN = $env:GITHUB_TOKEN
$GITHUB_REPO = $env:GITHUB_REPO
$GITHUB_REPO_URL = $env:GITHUB_REPO_URL

if (-not $GITHUB_USERNAME -or -not $GITHUB_TOKEN -or -not $GITHUB_REPO) {
    Write-Error "GitHub configuration missing. Please set GITHUB_USERNAME, GITHUB_TOKEN, and GITHUB_REPO in .env file."
    exit 1
}

# Files and directories to include in version control
$IncludePatterns = @(
    "docker-compose.yml",
    "docker-compose.*.yml",
    ".env.template",
    ".gitignore",
    "README.md",
    "config/",
    "scripts/",
    "docs/",
    ".kiro/"
)

# Files and directories to exclude (sensitive data)
$ExcludePatterns = @(
    ".env",
    "data/",
    "*.log",
    "*.pid",
    "config/cloudflared/credentials.json",
    "config/*/secrets/",
    "**/*password*",
    "**/*secret*",
    "**/*key*",
    "**/*token*"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Initialize-GitRepository {
    Write-Log "Initializing Git repository..."
    
    # Initialize git if not already done
    if (-not (Test-Path ".git")) {
        git init
        Write-Log "Git repository initialized"
    }
    
    # Configure git user if not set
    $gitUser = git config user.name
    $gitEmail = git config user.email
    
    if (-not $gitUser) {
        git config user.name $GITHUB_USERNAME
        Write-Log "Git user.name set to $GITHUB_USERNAME"
    }
    
    if (-not $gitEmail) {
        $email = "${GITHUB_USERNAME}@users.noreply.github.com"
        git config user.email $email
        Write-Log "Git user.email set to $email"
    }
    
    # Add remote origin if not exists
    $remotes = git remote
    if ($remotes -notcontains "origin") {
        $authUrl = $GITHUB_REPO_URL -replace "https://", "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@"
        git remote add origin $authUrl
        Write-Log "Remote origin added: $GITHUB_REPO"
    }
    
    # Create initial .gitignore if it doesn't exist
    if (-not (Test-Path ".gitignore")) {
        @"
# Environment files
.env
*.env.local

# Data directories
data/files/*
data/backups/*
!data/files/.gitkeep
!data/backups/.gitkeep

# Logs
*.log
logs/

# Sensitive configuration
config/cloudflared/credentials.json
config/*/secrets/
**/passwords.txt
**/secrets.yml

# Temporary files
*.tmp
*.temp
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo

# Docker
.docker/
"@ | Out-File -FilePath ".gitignore" -Encoding UTF8
        Write-Log ".gitignore created"
    }
}

function Get-GitStatus {
    Write-Log "Checking Git repository status..."
    
    if (-not (Test-Path ".git")) {
        Write-Log "Not a Git repository. Run with -Action init first." "ERROR"
        return
    }
    
    Write-Host "`n=== Git Status ===" -ForegroundColor Cyan
    git status --porcelain
    
    Write-Host "`n=== Remote Status ===" -ForegroundColor Cyan
    try {
        git fetch origin 2>$null
        $behind = git rev-list --count HEAD..origin/main 2>$null
        $ahead = git rev-list --count origin/main..HEAD 2>$null
        
        if ($behind -gt 0) {
            Write-Host "Behind remote by $behind commits" -ForegroundColor Yellow
        }
        if ($ahead -gt 0) {
            Write-Host "Ahead of remote by $ahead commits" -ForegroundColor Green
        }
        if ($behind -eq 0 -and $ahead -eq 0) {
            Write-Host "Up to date with remote" -ForegroundColor Green
        }
    } catch {
        Write-Host "Could not fetch remote status" -ForegroundColor Red
    }
    
    Write-Host "`n=== Last 5 Commits ===" -ForegroundColor Cyan
    git log --oneline -5
}

function Push-ConfigurationChanges {
    param([string]$CommitMessage)
    
    Write-Log "Pushing configuration changes to GitHub..."
    
    if (-not (Test-Path ".git")) {
        Write-Log "Git repository not initialized. Run with -Action init first." "ERROR"
        return
    }
    
    # Check for changes
    $changes = git status --porcelain
    if (-not $changes) {
        Write-Log "No changes to commit" "INFO"
        return
    }
    
    Write-Log "Found changes to commit:"
    $changes | ForEach-Object { Write-Log "  $_" }
    
    # Add all tracked files and new files matching include patterns
    git add .
    
    # Remove files matching exclude patterns
    $ExcludePatterns | ForEach-Object {
        try {
            git reset HEAD $_ 2>$null
        } catch {
            # Ignore errors for non-existent files
        }
    }
    
    # Commit changes
    try {
        git commit -m $CommitMessage
        Write-Log "Changes committed: $CommitMessage"
    } catch {
        Write-Log "Failed to commit changes: $_" "ERROR"
        return
    }
    
    # Push to remote
    try {
        git push origin main
        Write-Log "Changes pushed to GitHub successfully"
    } catch {
        Write-Log "Failed to push to GitHub: $_" "ERROR"
        
        # Try to set upstream if it's the first push
        try {
            git push --set-upstream origin main
            Write-Log "Upstream set and changes pushed successfully"
        } catch {
            Write-Log "Failed to push with upstream: $_" "ERROR"
        }
    }
}

function Pull-ConfigurationChanges {
    Write-Log "Pulling configuration changes from GitHub..."
    
    if (-not (Test-Path ".git")) {
        Write-Log "Git repository not initialized. Run with -Action init first." "ERROR"
        return
    }
    
    # Check for local changes
    $localChanges = git status --porcelain
    if ($localChanges) {
        Write-Log "Local changes detected. Stashing before pull..." "WARN"
        git stash push -m "Auto-stash before pull $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    
    # Pull changes
    try {
        git pull origin main
        Write-Log "Configuration pulled from GitHub successfully"
        
        # Apply stashed changes if any
        if ($localChanges) {
            Write-Log "Applying stashed local changes..."
            try {
                git stash pop
                Write-Log "Local changes restored"
            } catch {
                Write-Log "Conflict applying stashed changes. Manual resolution required." "WARN"
                Write-Log "Use 'git stash list' and 'git stash apply' to resolve manually."
            }
        }
    } catch {
        Write-Log "Failed to pull from GitHub: $_" "ERROR"
    }
}

# Main execution
Write-Log "Starting GitHub sync operation: $Action"

switch ($Action) {
    "init" {
        Initialize-GitRepository
    }
    "status" {
        Get-GitStatus
    }
    "push" {
        Push-ConfigurationChanges -CommitMessage $Message
    }
    "pull" {
        Pull-ConfigurationChanges
    }
}

Write-Log "GitHub sync operation completed: $Action"