# Duplicati Backup System Setup Guide

## Overview

This guide covers the complete setup and configuration of the Duplicati backup system for the homelab infrastructure. Duplicati provides automated, encrypted, and deduplicated backups of critical data volumes.

## Architecture

### Backup Strategy
- **Critical Data**: Daily backups at 2:00 AM (grafana, portainer, linkding, actual, filebrowser data)
- **Configuration Files**: Daily backups at 2:30 AM (all service configurations)
- **Metrics Data**: Weekly backups on Sunday at 3:00 AM (prometheus, loki data)
- **System Backups**: Weekly backups on Sunday at 4:00 AM (duplicati configuration)

### Storage Layout
```
data/backups/
├── critical-daily/          # Daily critical data backups
├── critical-daily-alt/      # Alternate storage for critical data
├── config-daily/            # Daily configuration backups
├── config-daily-alt/        # Alternate storage for config
├── metrics-weekly/          # Weekly metrics backups
├── metrics-weekly-alt/      # Alternate storage for metrics
├── system-weekly/           # Weekly system backups
└── system-weekly-alt/       # Alternate storage for system
```

## Configuration Files

### 1. Service Configuration (`settings.json`)
- Server settings and default options
- Encryption and compression settings
- UI preferences and security settings

### 2. Backup Job Configurations
- `critical-data-daily.json` - Critical application data
- `config-files-daily.json` - Service configuration files
- `metrics-weekly.json` - Monitoring and metrics data
- `system-backup-weekly.json` - Backup system configuration

### 3. Management Scripts
- `init-duplicati.ps1` - Initialize backup system
- `verify-backups.ps1` - Verify backup integrity
- `backup-manager.sh` - Backup management (Linux)
- `restore-helper.sh` - Restore assistance (Linux)

## Setup Instructions

### 1. Initialize Backup System
```powershell
# Run initialization script (requires execution policy adjustment)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\config\duplicati\backup-scripts\init-duplicati.ps1

# Or create directories manually
New-Item -ItemType Directory -Path "data\backups\critical-daily" -Force
New-Item -ItemType Directory -Path "data\backups\config-daily" -Force
New-Item -ItemType Directory -Path "data\backups\metrics-weekly" -Force
New-Item -ItemType Directory -Path "data\backups\system-weekly" -Force
```

### 2. Start Duplicati Service
```bash
# Start Duplicati container
docker-compose up -d duplicati

# Verify service is running
docker-compose ps duplicati
```

### 3. Access Web Interface
- URL: http://localhost:8200
- Set up admin password using DUPLICATI_PASSWORD environment variable
- Import backup job configurations

### 4. Configure Backup Jobs

#### Critical Data Daily Backup
- **Source**: `/source/grafana`, `/source/portainer`, `/source/linkding`, `/source/actual`, `/source/filebrowser`, `/source/data/files`
- **Destination**: `/backups/critical-daily`
- **Schedule**: Daily at 2:00 AM
- **Retention**: 1W:1D,4W:1W,12M:1M
- **Encryption**: AES-256 with DUPLICATI_PASSWORD

#### Configuration Files Daily Backup
- **Source**: `/source/data/config`
- **Destination**: `/backups/config-daily`
- **Schedule**: Daily at 2:30 AM
- **Filters**: Exclude temporary files, logs, credentials
- **Retention**: 1W:1D,4W:1W,12M:1M

#### Metrics Weekly Backup
- **Source**: `/source/prometheus`, `/source/loki`, `/source/dashy`, `/source/homer`
- **Destination**: `/backups/metrics-weekly`
- **Schedule**: Weekly on Sunday at 3:00 AM
- **Retention**: 4W:1W,12M:1M,5Y:1Y

#### System Backup Weekly
- **Source**: `/config` (Duplicati configuration)
- **Destination**: `/backups/system-weekly`
- **Schedule**: Weekly on Sunday at 4:00 AM
- **Retention**: 4W:1W,12M:1M,5Y:1Y

## Security Features

### Encryption
- All backups encrypted with AES-256
- Password stored in DUPLICATI_PASSWORD environment variable
- Encryption keys managed by Duplicati

### Deduplication
- Block-level deduplication reduces storage requirements
- Configurable block size (10MB-100MB depending on data type)
- Compression with ZIP format

### Access Control
- Web interface password protection
- Container network isolation
- Read-only source volume mounts

## Monitoring and Verification

### Health Checks
- Docker health check on port 8200
- Backup verification scripts
- Automated integrity testing

### Verification Script
```powershell
# Run backup verification
.\config\duplicati\backup-scripts\verify-backups.ps1 -GenerateReport

# Check specific backup set
.\config\duplicati\backup-scripts\verify-backups.ps1 -Detailed
```

### Log Monitoring
- Backup logs: `data/logs/duplicati/`
- Service logs: `docker-compose logs duplicati`
- Verification reports: HTML format with detailed status

## Disaster Recovery

### Backup Restoration
1. Access Duplicati web interface
2. Navigate to Restore section
3. Select backup configuration
4. Choose restore point and files
5. Set destination path
6. Enter backup passphrase
7. Execute restore operation

### Restore Helper Script
```bash
# Interactive restore wizard
./config/duplicati/backup-scripts/restore-helper.sh wizard

# List available backups
./config/duplicati/backup-scripts/restore-helper.sh list

# Generate restore instructions
./config/duplicati/backup-scripts/restore-helper.sh instructions critical-daily
```

## Maintenance

### Regular Tasks
- Weekly backup verification
- Monthly cleanup of old backup files
- Quarterly restore testing
- Annual backup strategy review

### Automated Maintenance
```bash
# Run full maintenance cycle
./config/duplicati/backup-scripts/backup-manager.sh full-maintenance

# Generate status report
./config/duplicati/backup-scripts/backup-manager.sh status
```

## Troubleshooting

### Common Issues
1. **Service not responding**: Check Docker container status and logs
2. **Backup failures**: Verify source paths and permissions
3. **Storage full**: Check backup retention policies and cleanup
4. **Slow backups**: Adjust thread limits and compression settings

### Log Analysis
```bash
# View Duplicati service logs
docker-compose logs duplicati

# Check backup manager logs
tail -f data/logs/duplicati/backup-manager.log

# Review verification results
cat data/logs/duplicati/backup-verification.log
```

## Environment Variables

Required environment variables in `.env` file:
```bash
# Duplicati configuration
DUPLICATI_PASSWORD=your-secure-backup-password
TZ=America/New_York

# Backup settings
BACKUP_SCHEDULE=0 2 * * *
BACKUP_RETENTION_DAYS=30
```

## Volume Mappings

Docker Compose volume configuration:
```yaml
volumes:
  - duplicati_data:/config                    # Duplicati configuration
  - ./data/backups:/backups                   # Backup storage
  - ./data:/source/data:ro                    # Source data (read-only)
  - prometheus_data:/source/prometheus:ro     # Prometheus data
  - grafana_data:/source/grafana:ro           # Grafana data
  - loki_data:/source/loki:ro                 # Loki data
  - portainer_data:/source/portainer:ro       # Portainer data
  - linkding_data:/source/linkding:ro         # Linkding data
  - actual_data:/source/actual:ro             # Actual Budget data
  - filebrowser_data:/source/filebrowser:ro   # File Browser data
```

## Performance Tuning

### Backup Optimization
- **Block Size**: 50MB for critical data, 10MB for config files
- **Compression**: Level 6 for daily, Level 9 for weekly
- **Threads**: 4 concurrent for critical, 2 for others
- **Upload Limits**: Configurable throttling available

### Storage Optimization
- **Deduplication**: Enabled for all backup sets
- **Retention Policies**: Graduated retention (daily → weekly → monthly)
- **Cleanup**: Automated cleanup of expired backups
- **Compaction**: Regular database compaction

This completes the Duplicati backup system configuration with automated scheduling, encryption, deduplication, and comprehensive monitoring capabilities.