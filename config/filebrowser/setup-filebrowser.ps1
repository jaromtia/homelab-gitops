# FileBrowser Setup PowerShell Script
# This script sets up FileBrowser with proper configuration for the homelab environment

param(
    [string]$AdminUser = $env:FILEBROWSER_ADMIN_USER ?? "admin",
    [string]$AdminPassword = $env:FILEBROWSER_ADMIN_PASSWORD ?? "changeme",
    [switch]$Force
)

Write-Host "=== FileBrowser Setup Script ===" -ForegroundColor Green

# Check if Docker is running
try {
    docker version | Out-Null
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running or not installed" -ForegroundColor Red
    exit 1
}

# Check if FileBrowser container exists
$containerExists = docker ps -a --filter "name=filebrowser" --format "{{.Names}}" | Select-String "filebrowser"

if ($containerExists -and -not $Force) {
    Write-Host "FileBrowser container already exists. Use -Force to recreate." -ForegroundColor Yellow
    Write-Host "Current container status:"
    docker ps -a --filter "name=filebrowser" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 0
}

# Create necessary directories
Write-Host "Creating directory structure..." -ForegroundColor Blue
$directories = @(
    "data/files/shared",
    "data/files/users", 
    "data/files/uploads",
    "data/files/public",
    "data/files/.quarantine"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  Created: $dir" -ForegroundColor Gray
    }
}

# Create sample files
Write-Host "Creating sample files..." -ForegroundColor Blue

$readmeContent = @"
# Homelab File Manager

Welcome to your homelab file management system!

## Features

- **Web-based Interface**: Access your files from anywhere through your browser
- **Secure Sharing**: Create secure links to share files with others
- **User Management**: Multiple users with different permission levels
- **File Upload/Download**: Easy drag-and-drop file operations
- **Search**: Find files quickly with built-in search functionality

## Directory Structure

- `/public/` - Files accessible to all users
- `/shared/` - Shared files between users
- `/users/` - Personal user directories
- `/uploads/` - Temporary upload area

## Getting Started

1. Log in with your credentials
2. Navigate through the directory structure
3. Upload files by dragging them into the browser
4. Create shares by right-clicking on files
5. Manage users through the admin interface (admin users only)

## Security

- All file transfers are encrypted via HTTPS
- Shares can be password protected and have expiration dates
- User access is controlled through granular permissions
- File uploads are scanned for security

For support, contact your system administrator.
"@

$welcomeContent = @"
Welcome to the shared directory!

This directory is accessible to all authenticated users.
Use this space to share files between different users.

Guidelines:
- Keep files organized in subdirectories
- Use descriptive filenames
- Clean up old files regularly
- Respect storage quotas
"@

$readmeContent | Out-File -FilePath "data/files/public/README.md" -Encoding UTF8
$welcomeContent | Out-File -FilePath "data/files/shared/welcome.txt" -Encoding UTF8

# Create subdirectories
$subdirs = @(
    "data/files/shared/documents",
    "data/files/shared/images", 
    "data/files/shared/archives",
    "data/files/uploads/temp"
)

foreach ($subdir in $subdirs) {
    if (-not (Test-Path $subdir)) {
        New-Item -ItemType Directory -Path $subdir -Force | Out-Null
    }
}

Write-Host "✓ Directory structure and sample files created" -ForegroundColor Green

# Check if FileBrowser service is defined in docker-compose.yml
Write-Host "Checking docker-compose configuration..." -ForegroundColor Blue

if (Test-Path "docker-compose.yml") {
    $composeContent = Get-Content "docker-compose.yml" -Raw
    if ($composeContent -match "filebrowser:") {
        Write-Host "✓ FileBrowser service found in docker-compose.yml" -ForegroundColor Green
    } else {
        Write-Host "✗ FileBrowser service not found in docker-compose.yml" -ForegroundColor Red
        Write-Host "Please ensure FileBrowser is properly configured in your docker-compose.yml" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "✗ docker-compose.yml not found" -ForegroundColor Red
    exit 1
}

# Start or restart FileBrowser service
Write-Host "Starting FileBrowser service..." -ForegroundColor Blue

if ($Force -and $containerExists) {
    Write-Host "Stopping existing container..." -ForegroundColor Yellow
    docker-compose stop filebrowser
    docker-compose rm -f filebrowser
}

# Start the service
docker-compose up -d filebrowser

# Wait for service to be ready
Write-Host "Waiting for FileBrowser to start..." -ForegroundColor Blue
$maxAttempts = 30
$attempt = 0

do {
    Start-Sleep -Seconds 2
    $attempt++
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8082" -TimeoutSec 5 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Host "✓ FileBrowser is running and accessible" -ForegroundColor Green
            break
        }
    } catch {
        if ($attempt -eq $maxAttempts) {
            Write-Host "✗ FileBrowser failed to start within timeout" -ForegroundColor Red
            Write-Host "Check container logs: docker-compose logs filebrowser" -ForegroundColor Yellow
            exit 1
        }
    }
} while ($attempt -lt $maxAttempts)

# Display access information
Write-Host ""
Write-Host "=== FileBrowser Setup Complete ===" -ForegroundColor Green
Write-Host "Local Access: http://localhost:8082" -ForegroundColor Cyan
Write-Host "External Access: https://files.$env:DOMAIN" -ForegroundColor Cyan
Write-Host "Admin User: $AdminUser" -ForegroundColor Cyan
Write-Host "Admin Password: $AdminPassword" -ForegroundColor Cyan
Write-Host ""
Write-Host "Default Users Created:" -ForegroundColor Yellow
Write-Host "  - admin (full access)" -ForegroundColor Gray
Write-Host "  - user (personal directory access)" -ForegroundColor Gray  
Write-Host "  - guest (public directory read-only)" -ForegroundColor Gray
Write-Host ""
Write-Host "Management Commands:" -ForegroundColor Yellow
Write-Host "  View logs: docker-compose logs filebrowser" -ForegroundColor Gray
Write-Host "  Restart: docker-compose restart filebrowser" -ForegroundColor Gray
Write-Host "  Stop: docker-compose stop filebrowser" -ForegroundColor Gray
Write-Host ""
Write-Host "File Locations:" -ForegroundColor Yellow
Write-Host "  Files: ./data/files/" -ForegroundColor Gray
Write-Host "  Config: ./config/filebrowser/" -ForegroundColor Gray
Write-Host "  Database: Docker volume (filebrowser_data)" -ForegroundColor Gray