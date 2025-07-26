# Backup and Restoration Procedures

This document provides comprehensive procedures for backing up and restoring the homelab infrastructure, including configuration files, service data, and complete disaster recovery.

## Table of Contents

1. [Backup Strategy Overview](#backup-strategy-overview)
2. [Configuration Backup (GitHub)](#configuration-backup-github)
3. [Data Backup (Duplicati)](#data-backup-duplicati)
4. [Manual Backup Procedures](#manual-backup-procedures)
5. [Restoration Procedures](#restoration-procedures)
6. [Disaster Recovery](#disaster-recovery)
7. [Backup Verification](#backup-verification)
8. [Maintenance and Monitoring](#maintenance-and-monitoring)

## Backup Strategy Overview

The homelab infrastructure uses a multi-layered backup strategy:

### Backup Types

1. **Configuration Backup (GitHub)**
   - All configuration files
   - Docker Compose files
   - Scripts and documentation
   - Version controlled with Git

2. **Data Backup (Duplicati)**
   - Service data volumes
   - User files and documents
   - Database files
   - Encrypted and deduplicated

3. **System Backup (Manual)**
   - Environment files (without secrets)
   - Custom configurations
   - SSL certificates and keys

### Backup Schedule

| Backup Type | Frequency | Retention | Method |
|-------------|-----------|-----------|---------|
| Configuration | On change | Unlimited | Git commits |
| Service Data | Daily | 30 days | Duplicati automated |
| User Files | Daily | 90 days | Duplicati automated |
| Full System | Weekly | 4 weeks | Manual snapshot |
| Critical Data | Hourly | 7 days | Duplicati incremental |

## Configuration Backup (GitHub)

### Automated Configuration Backup

Configuration files are automatically backed up to GitHub using Git version control.

#### Files Included

- `docker-compose.yml` and related compose files
- `config/` directory (excluding secrets)
- `scripts/` directory
- `docs/` directory
- `.env.template` (template only, not actual .env)
- `.gitignore` and other Git configuration

#### Files Excluded

- `.env` (contains secrets)
- `data/` directory (service data)
- `config/cloudflared/credentials.json` (tunnel credentials)
- Log files and temporary files
- Any file matching patterns: `*password*`, `*secret*`, `*key*`, `*token*`

### Manual Configuration Backup

```powershell
# Save current configuration to GitHub
.\scripts\git-ops.ps1 save "Manual backup - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

# Check backup status
.\scripts\git-ops.ps1 status

# View backup history
git log --oneline -10
```

### Automated Configuration Backup

```powershell
# Set up automated daily configuration backup
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$PWD\scripts\git-ops.ps1`" save `"Automated daily backup`""
$trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "HomelabConfigBackup" -Action $action -Trigger $trigger -Settings $settings
```

## Data Backup (Duplicati)

### Duplicati Configuration

Duplicati handles automated backup of service data volumes and user files.

#### Backup Jobs Configuration

1. **Service Data Backup**
   ```
   Source: Docker volumes
   - /var/lib/docker/volumes/homelab_grafana_data
   - /var/lib/docker/volumes/homelab_prometheus_data
   - /var/lib/docker/volumes/homelab_loki_data
   - /var/lib/docker/volumes/homelab_portainer_data
   - /var/lib/docker/volumes/homelab_linkding_data
   - /var/lib/docker/volumes/homelab_actual_data
   - /var/lib/docker/volumes/homelab_filebrowser_data
   
   Schedule: Daily at 01:00 AM
   Retention: 30 days
   ```

2. **User Files Backup**
   ```
   Source: ./data/files/
   Schedule: Daily at 03:00 AM
   Retention: 90 days
   ```

3. **Configuration Backup**
   ```
   Source: ./config/ (excluding secrets)
   Schedule: On change (manual trigger)
   Retention: Unlimited
   ```

### Setting Up Duplicati Backups

#### 1. Access Duplicati Web Interface

```powershell
# Start Duplicati if not running
docker-compose up -d duplicati

# Access web interface
Start-Process "http://localhost:8200"
```

#### 2. Configure Backup Destination

**Local Storage:**
```
Type: File
Path: ./data/backups/
```

**Cloud Storage (Recommended):**
```
Type: S3 Compatible
Server: your-s3-endpoint
Bucket: homelab-backups
Access Key: your-access-key
Secret Key: your-secret-key
```

#### 3. Create Service Data Backup Job

1. Click "Add backup"
2. Configure general settings:
   - Name: "Service Data Backup"
   - Description: "Daily backup of all service data volumes"
   - Encryption: AES-256 with passphrase from .env

3. Configure destination (as above)

4. Configure source files:
   ```
   # Add these paths (adjust for your Docker volume location)
   C:\ProgramData\Docker\volumes\homelab_grafana_data\_data
   C:\ProgramData\Docker\volumes\homelab_prometheus_data\_data
   C:\ProgramData\Docker\volumes\homelab_loki_data\_data
   C:\ProgramData\Docker\volumes\homelab_portainer_data\_data
   C:\ProgramData\Docker\volumes\homelab_linkding_data\_data
   C:\ProgramData\Docker\volumes\homelab_actual_data\_data
   C:\ProgramData\Docker\volumes\homelab_filebrowser_data\_data
   ```

5. Configure schedule:
   - Run daily at 01:00 AM
   - Keep backups for 30 days

6. Configure options:
   - Compression: LZMA2
   - Deduplication: Enabled
   - Verification: After upload

#### 4. Create User Files Backup Job

1. Click "Add backup"
2. Configure general settings:
   - Name: "User Files Backup"
   - Description: "Daily backup of user files and documents"

3. Configure source:
   ```
   .\data\files\
   ```

4. Configure schedule:
   - Run daily at 03:00 AM
   - Keep backups for 90 days

### Manual Backup Operations

#### Trigger Manual Backup

```powershell
# Access Duplicati container
docker-compose exec duplicati bash

# Run backup job manually
duplicati-cli backup file://backups/service-data /source/volumes --encryption-module=aes --passphrase=$BACKUP_ENCRYPTION_PASSWORD

# Check backup status
duplicati-cli list file://backups/service-data
```

#### Backup Verification

```powershell
# Test backup integrity
docker-compose exec duplicati duplicati-cli test file://backups/service-data

# List backup contents
docker-compose exec duplicati duplicati-cli list file://backups/service-data

# Verify specific backup
docker-compose exec duplicati duplicati-cli verify file://backups/service-data --version=0
```

## Manual Backup Procedures

### Complete System Backup

```powershell
# Create complete system backup
$backupDate = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = ".\backups\system-backup-$backupDate"

# Create backup directory
New-Item -ItemType Directory -Force -Path $backupPath

# Backup configuration files
Copy-Item -Recurse -Path "config" -Destination "$backupPath\config"
Copy-Item -Recurse -Path "scripts" -Destination "$backupPath\scripts"
Copy-Item -Recurse -Path "docs" -Destination "$backupPath\docs"
Copy-Item -Path "docker-compose.yml" -Destination "$backupPath\"
Copy-Item -Path ".env.template" -Destination "$backupPath\"

# Backup environment file (sanitized)
Get-Content .env | Where-Object { $_ -notmatch "PASSWORD|SECRET|TOKEN|KEY" } | Out-File "$backupPath\.env.sanitized"

# Create backup manifest
@{
    BackupDate = Get-Date
    BackupType = "Complete System"
    Services = (docker-compose ps --services)
    Volumes = (docker volume ls --filter "name=homelab" --format "{{.Name}}")
    GitCommit = (git rev-parse HEAD)
} | ConvertTo-Json | Out-File "$backupPath\backup-manifest.json"

Write-Host "System backup created at: $backupPath"
```

### Service-Specific Backup

```powershell
# Backup specific service data
function Backup-ServiceData {
    param(
        [string]$ServiceName,
        [string]$BackupPath = ".\backups"
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $serviceBackupPath = "$BackupPath\$ServiceName-$timestamp"
    
    # Create backup directory
    New-Item -ItemType Directory -Force -Path $serviceBackupPath
    
    # Stop service
    docker-compose stop $ServiceName
    
    # Backup volume data
    $volumeName = "homelab_${ServiceName}_data"
    docker run --rm -v ${volumeName}:/source -v ${PWD}/${serviceBackupPath}:/backup alpine tar czf /backup/data.tar.gz -C /source .
    
    # Backup service configuration
    if (Test-Path "config\$ServiceName") {
        Copy-Item -Recurse -Path "config\$ServiceName" -Destination "$serviceBackupPath\config"
    }
    
    # Restart service
    docker-compose start $ServiceName
    
    Write-Host "Service backup created at: $serviceBackupPath"
}

# Example usage
Backup-ServiceData -ServiceName "grafana"
Backup-ServiceData -ServiceName "prometheus"
```

## Restoration Procedures

### Configuration Restoration

#### From GitHub Repository

```powershell
# Complete configuration restoration
.\scripts\restore-from-github.ps1 -Force

# Restore from specific branch
.\scripts\restore-from-github.ps1 -Branch "backup-branch"

# Restore specific commit
git checkout <commit-hash>
```

#### Manual Configuration Restoration

```powershell
# Restore from local backup
$backupPath = ".\backups\system-backup-20241225-120000"

# Stop services
docker-compose down

# Restore configuration files
Copy-Item -Recurse -Force -Path "$backupPath\config" -Destination "."
Copy-Item -Recurse -Force -Path "$backupPath\scripts" -Destination "."
Copy-Item -Force -Path "$backupPath\docker-compose.yml" -Destination "."

# Restore environment template
Copy-Item -Force -Path "$backupPath\.env.template" -Destination "."

# Recreate .env file (you'll need to add secrets manually)
Copy-Item -Path ".env.template" -Destination ".env"
Write-Host "WARNING: Update .env file with actual passwords and secrets"

# Restart services
docker-compose up -d
```

### Data Restoration

#### Using Duplicati Web Interface

1. **Access Duplicati:**
   ```powershell
   Start-Process "http://localhost:8200"
   ```

2. **Navigate to Restore:**
   - Click on backup job
   - Click "Restore files"
   - Select backup version
   - Choose files to restore

3. **Configure Restoration:**
   - Select destination path
   - Choose restore options
   - Start restoration process

#### Command Line Restoration

```powershell
# Stop services before restoration
docker-compose down

# Restore service data
docker-compose exec duplicati duplicati-cli restore file://backups/service-data /restore/volumes --encryption-module=aes --passphrase=$BACKUP_ENCRYPTION_PASSWORD

# Restore specific service
docker-compose exec duplicati duplicati-cli restore file://backups/service-data /restore/grafana --include="*grafana*" --encryption-module=aes --passphrase=$BACKUP_ENCRYPTION_PASSWORD

# Restore user files
docker-compose exec duplicati duplicati-cli restore file://backups/user-files ./data/files/ --encryption-module=aes --passphrase=$BACKUP_ENCRYPTION_PASSWORD
```

#### Manual Data Restoration

```powershell
# Restore service data from manual backup
function Restore-ServiceData {
    param(
        [string]$ServiceName,
        [string]$BackupPath
    )
    
    # Stop service
    docker-compose stop $ServiceName
    
    # Remove existing volume
    $volumeName = "homelab_${ServiceName}_data"
    docker volume rm $volumeName
    
    # Create new volume
    docker volume create $volumeName
    
    # Restore data
    docker run --rm -v ${volumeName}:/target -v ${PWD}/${BackupPath}:/backup alpine tar xzf /backup/data.tar.gz -C /target
    
    # Restart service
    docker-compose start $ServiceName
    
    Write-Host "Service data restored for: $ServiceName"
}

# Example usage
Restore-ServiceData -ServiceName "grafana" -BackupPath "backups\grafana-20241225-120000"
```

### Complete Service Restoration

```powershell
# Complete restoration procedure
function Restore-CompleteService {
    param(
        [string]$ServiceName,
        [string]$ConfigBackupPath,
        [string]$DataBackupPath
    )
    
    Write-Host "Starting complete restoration for $ServiceName"
    
    # Stop service
    docker-compose stop $ServiceName
    
    # Restore configuration
    if (Test-Path "$ConfigBackupPath\config\$ServiceName") {
        Copy-Item -Recurse -Force -Path "$ConfigBackupPath\config\$ServiceName" -Destination "config\"
    }
    
    # Restore data
    Restore-ServiceData -ServiceName $ServiceName -BackupPath $DataBackupPath
    
    # Restart service
    docker-compose up -d $ServiceName
    
    # Wait for service to start
    Start-Sleep -Seconds 30
    
    # Verify service health
    $health = docker inspect --format='{{.State.Health.Status}}' $ServiceName
    Write-Host "$ServiceName health status: $health"
}
```

## Disaster Recovery

### Complete Infrastructure Recovery

#### Scenario: Complete system loss

**Prerequisites:**
- Access to GitHub repository
- Access to Duplicati backups
- New system with Docker installed

**Recovery Steps:**

1. **Restore Configuration:**
   ```powershell
   # Clone repository
   git clone https://github.com/your-username/homelab-infrastructure.git
   cd homelab-infrastructure
   
   # Restore from GitHub
   .\scripts\restore-from-github.ps1
   ```

2. **Recreate Environment:**
   ```powershell
   # Copy environment template
   Copy-Item .env.template .env
   
   # Edit .env with actual values (passwords, tokens, etc.)
   notepad .env
   ```

3. **Restore Cloudflare Tunnel:**
   ```powershell
   # Recreate tunnel credentials
   # Copy credentials.json to config/cloudflared/
   # Update tunnel ID in .env and config files
   ```

4. **Deploy Infrastructure:**
   ```powershell
   # Deploy services
   .\scripts\deploy-with-github.ps1 -Mode fresh
   ```

5. **Restore Data:**
   ```powershell
   # Access Duplicati
   Start-Process "http://localhost:8200"
   
   # Configure backup source
   # Restore all service data
   # Verify data integrity
   ```

6. **Verify Recovery:**
   ```powershell
   # Run health checks
   .\scripts\run-health-tests.ps1 -Detailed
   
   # Test all services
   .\scripts\test-service-health.ps1
   ```

### Partial Recovery Scenarios

#### Single Service Recovery

```powershell
# Recover single service (example: Grafana)
function Recover-SingleService {
    param([string]$ServiceName)
    
    Write-Host "Recovering service: $ServiceName"
    
    # Stop service
    docker-compose stop $ServiceName
    
    # Remove container and volume
    docker-compose rm -f $ServiceName
    docker volume rm "homelab_${ServiceName}_data"
    
    # Restore from backup
    # (Use Duplicati or manual backup restoration)
    
    # Recreate service
    docker-compose up -d $ServiceName
    
    # Verify recovery
    Start-Sleep -Seconds 30
    docker-compose ps $ServiceName
}
```

#### Configuration-Only Recovery

```powershell
# Recover only configuration files
.\scripts\restore-from-github.ps1

# Restart services to apply configuration
docker-compose restart
```

## Backup Verification

### Automated Verification

```powershell
# Run backup integrity tests
.\scripts\test-backup-integrity.ps1 -Detailed

# Verify Duplicati backups
docker-compose exec duplicati duplicati-cli test file://backups/service-data

# Verify GitHub backup
git fsck --full
```

### Manual Verification

```powershell
# Test restoration in isolated environment
function Test-BackupRestoration {
    param(
        [string]$BackupPath,
        [string]$TestPath = ".\test-restore"
    )
    
    # Create test environment
    New-Item -ItemType Directory -Force -Path $TestPath
    
    # Copy backup to test location
    Copy-Item -Recurse -Path $BackupPath -Destination "$TestPath\backup"
    
    # Test restoration process
    # (Implement specific restoration tests)
    
    # Verify restored data
    # (Implement verification checks)
    
    # Clean up test environment
    Remove-Item -Recurse -Force -Path $TestPath
}
```

### Backup Health Monitoring

```powershell
# Monitor backup job status
function Get-BackupStatus {
    # Check Duplicati job status
    $duplicatiStatus = Invoke-RestMethod -Uri "http://localhost:8200/api/v1/backups" -Method GET
    
    # Check GitHub sync status
    $gitStatus = git status --porcelain
    
    # Check backup storage usage
    $storageUsage = Get-ChildItem -Recurse ".\data\backups" | Measure-Object -Property Length -Sum
    
    return @{
        DuplicatiJobs = $duplicatiStatus
        GitStatus = $gitStatus
        StorageUsage = $storageUsage.Sum
        LastBackup = (Get-ChildItem ".\data\backups" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }
}

# Generate backup report
Get-BackupStatus | ConvertTo-Json | Out-File "backup-status-$(Get-Date -Format 'yyyyMMdd').json"
```

## Maintenance and Monitoring

### Regular Maintenance Tasks

#### Daily Tasks

```powershell
# Daily backup verification
.\scripts\test-backup-integrity.ps1

# Check backup job status
Get-BackupStatus

# Monitor storage usage
Get-ChildItem -Recurse ".\data\backups" | Measure-Object -Property Length -Sum
```

#### Weekly Tasks

```powershell
# Test restoration procedure
# (Perform test restoration in isolated environment)

# Clean old backups
docker-compose exec duplicati duplicati-cli delete file://backups/service-data --keep-versions=30

# Update backup documentation
# (Review and update this document)
```

#### Monthly Tasks

```powershell
# Full backup verification
# (Restore complete system in test environment)

# Review backup retention policies
# (Adjust retention based on storage usage)

# Update backup encryption keys
# (Rotate encryption passwords)

# Test disaster recovery procedures
# (Full disaster recovery simulation)
```

### Monitoring and Alerting

#### Grafana Dashboard

Create Grafana dashboard to monitor:
- Backup job success/failure rates
- Backup storage usage
- Time since last successful backup
- Restoration test results

#### Prometheus Alerts

```yaml
# Example alert rules for backup monitoring
groups:
  - name: backup.rules
    rules:
      - alert: BackupJobFailed
        expr: duplicati_backup_success == 0
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "Backup job failed"
          description: "Duplicati backup job has failed for {{ $labels.job_name }}"
      
      - alert: BackupStorageFull
        expr: (backup_storage_used / backup_storage_total) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Backup storage nearly full"
          description: "Backup storage is {{ $value }}% full"
```

### Backup Security

#### Encryption

- All Duplicati backups encrypted with AES-256
- Encryption passwords stored in .env file
- Regular password rotation (quarterly)

#### Access Control

- Backup storage access restricted to backup service
- GitHub repository access via personal access tokens
- Regular audit of backup access logs

#### Compliance

- Backup retention policies documented
- Data classification and handling procedures
- Regular security reviews of backup procedures

## Troubleshooting Backup Issues

### Common Backup Problems

1. **Backup Job Fails:**
   - Check Duplicati logs
   - Verify storage connectivity
   - Check disk space
   - Verify encryption passwords

2. **Restoration Fails:**
   - Verify backup integrity
   - Check restoration permissions
   - Verify encryption passwords
   - Check available disk space

3. **GitHub Sync Issues:**
   - Check Git credentials
   - Verify network connectivity
   - Check repository permissions
   - Review Git configuration

### Emergency Contacts

- **System Administrator:** [Contact Information]
- **Backup Service Provider:** [Contact Information]
- **Cloud Storage Provider:** [Contact Information]

## Documentation Updates

This document should be reviewed and updated:
- After any changes to backup procedures
- Following disaster recovery tests
- When new services are added
- Quarterly as part of maintenance review

**Last Updated:** [Current Date]
**Next Review:** [Next Review Date]