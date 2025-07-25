# Container Management Utilities for Portainer
# This script provides utilities for managing containers through Portainer API

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("list", "start", "stop", "restart", "logs", "stats", "inspect")]
    [string]$Action = "list",
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerName = "",
    
    [Parameter(Mandatory=$false)]
    [int]$LogLines = 100,
    
    [Parameter(Mandatory=$false)]
    [switch]$Follow = $false
)

$PortainerUrl = "http://localhost:9000"
$ApiBase = "$PortainerUrl/api"

Write-Host "=== Portainer Container Management ===" -ForegroundColor Green

# Function to get container list
function Get-ContainerList {
    try {
        $containers = docker ps -a --format "json" | ConvertFrom-Json
        
        Write-Host "`nContainer Status Overview:" -ForegroundColor Yellow
        Write-Host ("=" * 80) -ForegroundColor Gray
        Write-Host ("{0,-20} {1,-15} {2,-20} {3,-20}" -f "NAME", "STATUS", "IMAGE", "PORTS") -ForegroundColor Cyan
        Write-Host ("=" * 80) -ForegroundColor Gray
        
        foreach ($container in $containers) {
            $status = if ($container.Status -like "*Up*") { "Running" } else { "Stopped" }
            $statusColor = if ($status -eq "Running") { "Green" } else { "Red" }
            
            Write-Host ("{0,-20}" -f $container.Names) -NoNewline -ForegroundColor White
            Write-Host ("{0,-15}" -f $status) -NoNewline -ForegroundColor $statusColor
            Write-Host ("{0,-20}" -f $container.Image.Split(":")[0]) -NoNewline -ForegroundColor White
            Write-Host ("{0,-20}" -f $container.Ports) -ForegroundColor White
        }
        
        Write-Host ("=" * 80) -ForegroundColor Gray
        Write-Host "Total containers: $($containers.Count)" -ForegroundColor Yellow
        
    } catch {
        Write-Host "✗ Failed to get container list: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to start container
function Start-Container {
    param([string]$Name)
    
    if (-not $Name) {
        Write-Host "✗ Container name is required" -ForegroundColor Red
        return
    }
    
    try {
        Write-Host "Starting container: $Name" -ForegroundColor Yellow
        docker start $Name
        
        # Wait for container to be running
        $maxAttempts = 10
        $attempt = 0
        
        do {
            Start-Sleep -Seconds 1
            $status = docker inspect $Name --format='{{.State.Status}}' 2>$null
            $attempt++
            
            if ($status -eq "running") {
                Write-Host "✓ Container $Name started successfully" -ForegroundColor Green
                return
            }
        } while ($attempt -lt $maxAttempts)
        
        Write-Host "⚠ Container $Name may not have started properly" -ForegroundColor Yellow
        
    } catch {
        Write-Host "✗ Failed to start container $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to stop container
function Stop-Container {
    param([string]$Name)
    
    if (-not $Name) {
        Write-Host "✗ Container name is required" -ForegroundColor Red
        return
    }
    
    try {
        Write-Host "Stopping container: $Name" -ForegroundColor Yellow
        docker stop $Name
        Write-Host "✓ Container $Name stopped successfully" -ForegroundColor Green
        
    } catch {
        Write-Host "✗ Failed to stop container $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to restart container
function Restart-Container {
    param([string]$Name)
    
    if (-not $Name) {
        Write-Host "✗ Container name is required" -ForegroundColor Red
        return
    }
    
    try {
        Write-Host "Restarting container: $Name" -ForegroundColor Yellow
        docker restart $Name
        Write-Host "✓ Container $Name restarted successfully" -ForegroundColor Green
        
    } catch {
        Write-Host "✗ Failed to restart container $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to view container logs
function Get-ContainerLogs {
    param(
        [string]$Name,
        [int]$Lines = 100,
        [bool]$FollowLogs = $false
    )
    
    if (-not $Name) {
        Write-Host "✗ Container name is required" -ForegroundColor Red
        return
    }
    
    try {
        Write-Host "Retrieving logs for container: $Name" -ForegroundColor Yellow
        Write-Host "Lines: $Lines, Follow: $FollowLogs" -ForegroundColor Gray
        Write-Host ("=" * 80) -ForegroundColor Gray
        
        if ($FollowLogs) {
            docker logs -f --tail $Lines $Name
        } else {
            docker logs --tail $Lines $Name
        }
        
    } catch {
        Write-Host "✗ Failed to get logs for container $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to get container stats
function Get-ContainerStats {
    param([string]$Name)
    
    if (-not $Name) {
        Write-Host "Getting stats for all containers..." -ForegroundColor Yellow
        docker stats --no-stream
    } else {
        Write-Host "Getting stats for container: $Name" -ForegroundColor Yellow
        docker stats --no-stream $Name
    }
}

# Function to inspect container
function Get-ContainerInspect {
    param([string]$Name)
    
    if (-not $Name) {
        Write-Host "✗ Container name is required" -ForegroundColor Red
        return
    }
    
    try {
        Write-Host "Inspecting container: $Name" -ForegroundColor Yellow
        $inspection = docker inspect $Name | ConvertFrom-Json
        
        Write-Host "`nContainer Details:" -ForegroundColor Cyan
        Write-Host "Name: $($inspection.Name)" -ForegroundColor White
        Write-Host "Image: $($inspection.Config.Image)" -ForegroundColor White
        Write-Host "Status: $($inspection.State.Status)" -ForegroundColor White
        Write-Host "Started: $($inspection.State.StartedAt)" -ForegroundColor White
        Write-Host "Restart Count: $($inspection.RestartCount)" -ForegroundColor White
        
        if ($inspection.State.Health) {
            Write-Host "Health: $($inspection.State.Health.Status)" -ForegroundColor White
        }
        
        Write-Host "`nNetwork Settings:" -ForegroundColor Cyan
        foreach ($network in $inspection.NetworkSettings.Networks.PSObject.Properties) {
            Write-Host "  $($network.Name): $($network.Value.IPAddress)" -ForegroundColor White
        }
        
        Write-Host "`nPort Bindings:" -ForegroundColor Cyan
        if ($inspection.NetworkSettings.Ports) {
            foreach ($port in $inspection.NetworkSettings.Ports.PSObject.Properties) {
                if ($port.Value) {
                    Write-Host "  $($port.Name) -> $($port.Value.HostPort)" -ForegroundColor White
                }
            }
        }
        
    } catch {
        Write-Host "✗ Failed to inspect container $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution logic
switch ($Action.ToLower()) {
    "list" {
        Get-ContainerList
    }
    "start" {
        Start-Container -Name $ContainerName
    }
    "stop" {
        Stop-Container -Name $ContainerName
    }
    "restart" {
        Restart-Container -Name $ContainerName
    }
    "logs" {
        Get-ContainerLogs -Name $ContainerName -Lines $LogLines -FollowLogs $Follow
    }
    "stats" {
        Get-ContainerStats -Name $ContainerName
    }
    "inspect" {
        Get-ContainerInspect -Name $ContainerName
    }
    default {
        Write-Host "Invalid action. Available actions: list, start, stop, restart, logs, stats, inspect" -ForegroundColor Red
    }
}

Write-Host "`nPortainer Web Interface: $PortainerUrl" -ForegroundColor Cyan
Write-Host "Use the web interface for advanced container management features." -ForegroundColor Gray