# Duplicati Backup Configuration

This directory contains configuration files for Duplicati backup service.

## Files

- `backup-jobs.json` - Pre-configured backup jobs for critical volumes
- `settings.json` - Duplicati server settings and configuration
- `backup-scripts/` - Custom backup scripts and utilities

## Backup Strategy

### Critical Data Volumes
- **grafana_data** - Grafana dashboards and settings (daily backup)
- **portainer_data** - Container management data (daily backup)
- **linkding_data** - Bookmark database (daily backup)
- **actual_data** - Budget application data (daily backup)
- **filebrowser_data** - File browser database (daily backup)
- **duplicati_data** - Backup configurations (weekly backup)

### Important Data Volumes
- **prometheus_data** - Metrics time-series data (weekly backup)
- **dashy_data** - Dashboard configuration (weekly backup)
- **homer_data** - Homer dashboard data (weekly backup)

### Configuration Files
- **./config/** - All service configurations (daily backup)
- **./data/files** - User files (daily backup)

## Backup Schedule

- **Daily backups**: 2:00 AM for critical data
- **Weekly backups**: Sunday 3:00 AM for metrics and configurations
- **Retention**: 30 days for daily, 12 weeks for weekly

## Encryption

All backups are encrypted using AES-256 with the password from DUPLICATI_PASSWORD environment variable.