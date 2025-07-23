#!/usr/bin/env pwsh
# Update Dashy Configuration Script
# This script replaces domain placeholders in the Dashy configuration

param(
    [string]$Domain = "tia-lab.org",
    [string]$ConfigFile = "config/dashy/conf.yml"
)

Write-Host "Updating Dashy configuration with domain: $Domain" -ForegroundColor Green

# Read the configuration file
$content = Get-Content $ConfigFile -Raw

# Replace all ${DOMAIN} placeholders with the actual domain
$updatedContent = $content -replace '\$\{DOMAIN\}', $Domain

# Write the updated configuration back
$updatedContent | Out-File -FilePath $ConfigFile -Encoding UTF8 -NoNewline

Write-Host "Dashy configuration updated successfully!" -ForegroundColor Green
Write-Host "Dashboard will be accessible at:" -ForegroundColor Cyan
Write-Host "  - https://dashboard.$Domain" -ForegroundColor White
Write-Host "  - https://$Domain" -ForegroundColor White