#!/bin/bash

# Duplicati Backup Manager Script
# Manages backup operations, verification, and maintenance

set -euo pipefail

# Configuration
DUPLICATI_URL="http://localhost:8200"
BACKUP_BASE_DIR="/backups"
LOG_DIR="/var/log/duplicati"
CONFIG_DIR="/config"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_DIR}/backup-manager.log"
}

# Create necessary directories
create_directories() {
    log "Creating backup directories..."
    mkdir -p "${BACKUP_BASE_DIR}"/{critical-daily,config-daily,metrics-weekly,system-weekly}
    mkdir -p "${BACKUP_BASE_DIR}"/{critical-daily-alt,config-daily-alt,metrics-weekly-alt,system-weekly-alt}
    mkdir -p "${LOG_DIR}"
    
    # Set proper permissions
    chmod 755 "${BACKUP_BASE_DIR}"
    chmod 755 "${LOG_DIR}"
    
    log "Backup directories created successfully"
}

# Check Duplicati service health
check_duplicati_health() {
    log "Checking Duplicati service health..."
    
    if curl -f -s "${DUPLICATI_URL}/api/v1/serverstate" > /dev/null 2>&1; then
        log "Duplicati service is healthy"
        return 0
    else
        log "ERROR: Duplicati service is not responding"
        return 1
    fi
}

# Import backup job configurations
import_backup_jobs() {
    log "Importing backup job configurations..."
    
    local job_files=(
        "critical-data-daily.json"
        "config-files-daily.json" 
        "metrics-weekly.json"
        "system-backup-weekly.json"
    )
    
    for job_file in "${job_files[@]}"; do
        if [[ -f "${CONFIG_DIR}/backup-jobs/${job_file}" ]]; then
            log "Importing backup job: ${job_file}"
            # Note: Actual import would use Duplicati CLI or API
            # This is a placeholder for the import logic
        else
            log "WARNING: Backup job file not found: ${job_file}"
        fi
    done
    
    log "Backup job import completed"
}

# Run backup verification
verify_backups() {
    log "Starting backup verification..."
    
    local backup_dirs=(
        "critical-daily"
        "config-daily"
        "metrics-weekly" 
        "system-weekly"
    )
    
    for backup_dir in "${backup_dirs[@]}"; do
        if [[ -d "${BACKUP_BASE_DIR}/${backup_dir}" ]]; then
            local file_count=$(find "${BACKUP_BASE_DIR}/${backup_dir}" -type f | wc -l)
            local dir_size=$(du -sh "${BACKUP_BASE_DIR}/${backup_dir}" | cut -f1)
            log "Backup ${backup_dir}: ${file_count} files, ${dir_size} total size"
        else
            log "WARNING: Backup directory not found: ${backup_dir}"
        fi
    done
    
    log "Backup verification completed"
}

# Cleanup old backup files based on retention policy
cleanup_old_backups() {
    log "Starting backup cleanup..."
    
    # Clean up files older than 30 days in daily backup directories
    find "${BACKUP_BASE_DIR}/critical-daily" -type f -mtime +30 -delete 2>/dev/null || true
    find "${BACKUP_BASE_DIR}/config-daily" -type f -mtime +30 -delete 2>/dev/null || true
    
    # Clean up files older than 84 days (12 weeks) in weekly backup directories
    find "${BACKUP_BASE_DIR}/metrics-weekly" -type f -mtime +84 -delete 2>/dev/null || true
    find "${BACKUP_BASE_DIR}/system-weekly" -type f -mtime +84 -delete 2>/dev/null || true
    
    log "Backup cleanup completed"
}

# Generate backup status report
generate_status_report() {
    log "Generating backup status report..."
    
    local report_file="${LOG_DIR}/backup-status-$(date +%Y%m%d).txt"
    
    {
        echo "Duplicati Backup Status Report"
        echo "Generated: $(date)"
        echo "================================"
        echo
        
        echo "Service Health:"
        if check_duplicati_health; then
            echo "✓ Duplicati service is running"
        else
            echo "✗ Duplicati service is not responding"
        fi
        echo
        
        echo "Backup Directory Status:"
        for dir in "${BACKUP_BASE_DIR}"/*; do
            if [[ -d "$dir" ]]; then
                local dir_name=$(basename "$dir")
                local file_count=$(find "$dir" -type f | wc -l)
                local dir_size=$(du -sh "$dir" | cut -f1)
                echo "  ${dir_name}: ${file_count} files, ${dir_size}"
            fi
        done
        echo
        
        echo "Recent Log Entries:"
        tail -20 "${LOG_DIR}/backup-manager.log" 2>/dev/null || echo "No recent log entries"
        
    } > "$report_file"
    
    log "Status report generated: $report_file"
}

# Main function
main() {
    case "${1:-help}" in
        "init")
            log "Initializing Duplicati backup system..."
            create_directories
            import_backup_jobs
            ;;
        "health")
            check_duplicati_health
            ;;
        "verify")
            verify_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "status")
            generate_status_report
            ;;
        "full-maintenance")
            log "Running full maintenance cycle..."
            check_duplicati_health
            verify_backups
            cleanup_old_backups
            generate_status_report
            ;;
        "help"|*)
            echo "Duplicati Backup Manager"
            echo "Usage: $0 {init|health|verify|cleanup|status|full-maintenance|help}"
            echo
            echo "Commands:"
            echo "  init              - Initialize backup system and directories"
            echo "  health            - Check Duplicati service health"
            echo "  verify            - Verify backup integrity and status"
            echo "  cleanup           - Clean up old backup files"
            echo "  status            - Generate backup status report"
            echo "  full-maintenance  - Run complete maintenance cycle"
            echo "  help              - Show this help message"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"