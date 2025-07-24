#!/usr/bin/env pwsh
# Generate Dashy Configuration Script
# This script processes the Dashy configuration template and replaces environment variables

param(
    [string]$EnvFile = ".env",
    [string]$TemplateFile = "config/dashy/conf.yml.template",
    [string]$OutputFile = "config/dashy/conf.yml"
)

Write-Host "Generating Dashy configuration..." -ForegroundColor Green

# Check if .env file exists
if (-not (Test-Path $EnvFile)) {
    Write-Error ".env file not found. Please create it from .env.template"
    exit 1
}

# Load environment variables from .env file
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

# Get domain from environment
$domain = $env:DOMAIN
if (-not $domain) {
    Write-Error "DOMAIN environment variable not set in .env file"
    exit 1
}

Write-Host "Using domain: $domain" -ForegroundColor Yellow

# Read template and replace variables
$template = Get-Content $TemplateFile -Raw
$config = $template -replace '\$\{DOMAIN\}', $domain

# Write the processed configuration
$config | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "Dashy configuration generated successfully at $OutputFile" -ForegroundColor Green
Write-Host "Services will be accessible at:" -ForegroundColor Cyan
Write-Host "  - Dashboard: https://dashboard.$domain or https://$domain" -ForegroundColor White
Write-Host "  - Grafana: https://grafana.$domain" -ForegroundColor White
Write-Host "  - Prometheus: https://prometheus.$domain" -ForegroundColor White
Write-Host "  - Portainer: https://portainer.$domain" -ForegroundColor White
Write-Host "  - Files: https://files.$domain" -ForegroundColor White
Write-Host "  - Bookmarks: https://bookmarks.$domain" -ForegroundColor White
Write-Host "  - Budget: https://budget.$domain" -ForegroundColor White
Write-Host "  - Backup: https://backup.$domain" -ForegroundColor White