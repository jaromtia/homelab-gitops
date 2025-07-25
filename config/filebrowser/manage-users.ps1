# FileBrowser User Management PowerShell Script
# This script provides utilities for managing users, permissions, and sharing in FileBrowser

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("add-user", "remove-user", "list-users", "update-permissions", "create-share", "list-shares", "remove-share", "reset-password", "help")]
    [string]$Action,
    
    [string]$Username,
    [string]$Password,
    [string]$Scope,
    [string]$FilePath,
    [string]$ShareId,
    [string]$Expires,
    [hashtable]$Permissions = @{}
)

# Function to display usage
function Show-Usage {
    Write-Host "FileBrowser User Management Script" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage: .\manage-users.ps1 -Action <action> [parameters]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Cyan
    Write-Host "  add-user        - Add a new user"
    Write-Host "  remove-user     - Remove an existing user"
    Write-Host "  list-users      - List all users"
    Write-Host "  update-permissions - Update user permissions"
    Write-Host "  create-share    - Create a file share"
    Write-Host "  list-shares     - List all shares"
    Write-Host "  remove-share    - Remove a share"
    Write-Host "  reset-password  - Reset user password"
    Write-Host "  help           - Show this help message"
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Cyan
    Write-Host "  -Username      - Username for user operations"
    Write-Host "  -Password      - Password for user creation/reset"
    Write-Host "  -Scope         - User's root directory (default: /srv/users/<username>)"
    Write-Host "  -FilePath      - File path for sharing operations"
    Write-Host "  -ShareId       - Share ID for share operations"
    Write-Host "  -Expires       - Share expiration (e.g., '24h', '7d', '30d')"
    Write-Host "  -Permissions   - Hashtable of permissions (see examples)"
    Write-Host ""
    Write-Host "Permission Keys:" -ForegroundColor Cyan
    Write-Host "  admin, create, delete, modify, rename, share, download"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\manage-users.ps1 -Action add-user -Username 'john' -Password 'password123'"
    Write-Host "  .\manage-users.ps1 -Action add-user -Username 'jane' -Password 'secret' -Permissions @{admin=$false; share=$true; create=$true}"
    Write-Host "  .\manage-users.ps1 -Action list-users"
    Write-Host "  .\manage-users.ps1 -Action create-share -Username 'john' -FilePath '/srv/shared/document.pdf' -Expires '7d'"
    Write-Host "  .\manage-users.ps1 -Action reset-password -Username 'john' -Password 'newpassword'"
}

# Function to execute FileBrowser command in container
function Invoke-FileBrowserCommand {
    param([string]$Command)
    
    try {
        $result = docker exec filebrowser filebrowser -d /database/filebrowser.db $Command
        return $result
    } catch {
        Write-Host "Error executing FileBrowser command: $_" -ForegroundColor Red
        return $null
    }
}

# Function to check if container is running
function Test-FileBrowserContainer {
    try {
        $status = docker ps --filter "name=filebrowser" --filter "status=running" --format "{{.Names}}"
        return $status -eq "filebrowser"
    } catch {
        return $false
    }
}

# Function to add a new user
function Add-User {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Scope,
        [hashtable]$Permissions
    )
    
    if (-not $Username -or -not $Password) {
        Write-Host "Error: Username and password are required for adding a user" -ForegroundColor Red
        return
    }
    
    if (-not $Scope) {
        $Scope = "/srv/users/$Username"
    }
    
    # Build permission parameters
    $permParams = ""
    if ($Permissions.Count -gt 0) {
        foreach ($perm in $Permissions.GetEnumerator()) {
            $permParams += " --perm.$($perm.Key)=$($perm.Value)"
        }
    } else {
        # Default permissions for regular user
        $permParams = " --perm.admin=false --perm.create=true --perm.delete=true --perm.modify=true --perm.rename=true --perm.share=true --perm.download=true"
    }
    
    $command = "users add `"$Username`" `"$Password`" --scope `"$Scope`"$permParams"
    
    Write-Host "Adding user: $Username with scope: $Scope" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        Write-Host "✓ User $Username added successfully" -ForegroundColor Green
        
        # Create user directory on host
        $hostPath = "data/files/users/$Username"
        if (-not (Test-Path $hostPath)) {
            New-Item -ItemType Directory -Path $hostPath -Force | Out-Null
            Write-Host "✓ Created user directory: $hostPath" -ForegroundColor Green
        }
    } else {
        Write-Host "✗ Failed to add user $Username" -ForegroundColor Red
    }
}

# Function to remove a user
function Remove-User {
    param([string]$Username)
    
    if (-not $Username) {
        Write-Host "Error: Username is required for removing a user" -ForegroundColor Red
        return
    }
    
    $command = "users rm `"$Username`""
    
    Write-Host "Removing user: $Username" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        Write-Host "✓ User $Username removed successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to remove user $Username" -ForegroundColor Red
    }
}

# Function to list all users
function Get-Users {
    Write-Host "Current FileBrowser users:" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand "users ls"
    
    if ($result) {
        $result | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    } else {
        Write-Host "✗ Failed to retrieve user list" -ForegroundColor Red
    }
}

# Function to update user permissions
function Update-UserPermissions {
    param(
        [string]$Username,
        [hashtable]$Permissions
    )
    
    if (-not $Username) {
        Write-Host "Error: Username is required for updating permissions" -ForegroundColor Red
        return
    }
    
    if ($Permissions.Count -eq 0) {
        Write-Host "Error: At least one permission must be specified" -ForegroundColor Red
        return
    }
    
    # Build permission parameters
    $permParams = ""
    foreach ($perm in $Permissions.GetEnumerator()) {
        $permParams += " --perm.$($perm.Key)=$($perm.Value)"
    }
    
    $command = "users update `"$Username`"$permParams"
    
    Write-Host "Updating permissions for user: $Username" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        Write-Host "✓ Permissions updated successfully for $Username" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to update permissions for $Username" -ForegroundColor Red
    }
}

# Function to create a file share
function New-Share {
    param(
        [string]$Username,
        [string]$FilePath,
        [string]$Expires
    )
    
    if (-not $Username -or -not $FilePath) {
        Write-Host "Error: Username and file path are required for creating a share" -ForegroundColor Red
        return
    }
    
    $command = "shares add `"$FilePath`""
    if ($Expires) {
        $command += " --expires $Expires"
    }
    
    Write-Host "Creating share for: $FilePath" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        Write-Host "✓ Share created successfully" -ForegroundColor Green
        Write-Host "Share details: $result" -ForegroundColor Gray
    } else {
        Write-Host "✗ Failed to create share" -ForegroundColor Red
    }
}

# Function to list shares
function Get-Shares {
    param([string]$Username)
    
    Write-Host "Current file shares:" -ForegroundColor Blue
    
    $command = "shares ls"
    if ($Username) {
        $command += " --username `"$Username`""
    }
    
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        $result | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    } else {
        Write-Host "✗ Failed to retrieve share list" -ForegroundColor Red
    }
}

# Function to remove a share
function Remove-Share {
    param([string]$ShareId)
    
    if (-not $ShareId) {
        Write-Host "Error: Share ID is required for removing a share" -ForegroundColor Red
        return
    }
    
    $command = "shares rm `"$ShareId`""
    
    Write-Host "Removing share: $ShareId" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        Write-Host "✓ Share removed successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to remove share $ShareId" -ForegroundColor Red
    }
}

# Function to reset user password
function Reset-UserPassword {
    param(
        [string]$Username,
        [string]$Password
    )
    
    if (-not $Username -or -not $Password) {
        Write-Host "Error: Username and new password are required" -ForegroundColor Red
        return
    }
    
    $command = "users update `"$Username`" --password `"$Password`""
    
    Write-Host "Resetting password for user: $Username" -ForegroundColor Blue
    $result = Invoke-FileBrowserCommand $command
    
    if ($result) {
        Write-Host "✓ Password reset successfully for $Username" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to reset password for $Username" -ForegroundColor Red
    }
}

# Main script execution
if (-not (Test-FileBrowserContainer)) {
    Write-Host "✗ FileBrowser container is not running" -ForegroundColor Red
    Write-Host "Please start the container first: docker-compose up -d filebrowser" -ForegroundColor Yellow
    exit 1
}

switch ($Action) {
    "add-user" {
        Add-User -Username $Username -Password $Password -Scope $Scope -Permissions $Permissions
    }
    "remove-user" {
        Remove-User -Username $Username
    }
    "list-users" {
        Get-Users
    }
    "update-permissions" {
        Update-UserPermissions -Username $Username -Permissions $Permissions
    }
    "create-share" {
        New-Share -Username $Username -FilePath $FilePath -Expires $Expires
    }
    "list-shares" {
        Get-Shares -Username $Username
    }
    "remove-share" {
        Remove-Share -ShareId $ShareId
    }
    "reset-password" {
        Reset-UserPassword -Username $Username -Password $Password
    }
    "help" {
        Show-Usage
    }
    default {
        Write-Host "Invalid action: $Action" -ForegroundColor Red
        Show-Usage
    }
}