#!/bin/bash

# Duplicati Restore Helper Script
# Assists with backup restoration procedures

set -euo pipefail

# Configuration
DUPLICATI_URL="http://localhost:8200"
BACKUP_BASE_DIR="/backups"
RESTORE_BASE_DIR="/tmp/duplicati-restore"
LOG_DIR="/var/log/duplicati"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_DIR}/restore-helper.log"
}

# List available backups
list_backups() {
    log "Listing available backups..."
    
    echo "Available Backup Sets:"
    echo "======================"
    
    for backup_dir in "${BACKUP_BASE_DIR}"/*; do
        if [[ -d "$backup_dir" && ! "$backup_dir" =~ -alt$ ]]; then
            local dir_name=$(basename "$backup_dir")
            local file_count=$(find "$backup_dir" -name "*.zip" -o -name "*.dblock" | wc -l)
            local latest_file=$(find "$backup_dir" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
            local latest_date=""
            
            if [[ -n "$latest_file" ]]; then
                latest_date=$(date -r "$latest_file" '+%Y-%m-%d %H:%M:%S')
            fi
            
            echo "  ${dir_name}:"
            echo "    Files: ${file_count}"
            echo "    Latest: ${latest_date:-'No files found'}"
            echo
        fi
    done
}

# Prepare restore environment
prepare_restore() {
    local backup_set="$1"
    
    log "Preparing restore environment for backup set: ${backup_set}"
    
    # Create restore directory
    mkdir -p "${RESTORE_BASE_DIR}/${backup_set}"
    chmod 755 "${RESTORE_BASE_DIR}/${backup_set}"
    
    # Verify backup set exists
    if [[ ! -d "${BACKUP_BASE_DIR}/${backup_set}" ]]; then
        log "ERROR: Backup set '${backup_set}' not found"
        return 1
    fi
    
    log "Restore environment prepared at: ${RESTORE_BASE_DIR}/${backup_set}"
}

# Validate backup integrity
validate_backup() {
    local backup_set="$1"
    
    log "Validating backup integrity for: ${backup_set}"
    
    local backup_path="${BACKUP_BASE_DIR}/${backup_set}"
    
    if [[ ! -d "$backup_path" ]]; then
        log "ERROR: Backup path not found: ${backup_path}"
        return 1
    fi
    
    # Check for backup files
    local backup_files=$(find "$backup_path" -name "*.dblock" -o -name "*.dindex" -o -name "*.dlist" | wc -l)
    
    if [[ $backup_files -eq 0 ]]; then
        log "ERROR: No backup files found in ${backup_path}"
        return 1
    fi
    
    log "Found ${backup_files} backup files in ${backup_set}"
    
    # Basic file integrity check
    local corrupted_files=0
    while IFS= read -r -d '' file; do
        if ! file "$file" | grep -q "data"; then
            log "WARNING: Potentially corrupted file: $file"
            ((corrupted_files++))
        fi
    done < <(find "$backup_path" -name "*.dblock" -print0)
    
    if [[ $corrupted_files -gt 0 ]]; then
        log "WARNING: Found ${corrupted_files} potentially corrupted files"
        return 1
    fi
    
    log "Backup validation completed successfully"
    return 0
}

# Generate restore instructions
generate_restore_instructions() {
    local backup_set="$1"
    local target_path="${2:-/tmp/restore-target}"
    
    log "Generating restore instructions for: ${backup_set}"
    
    local instructions_file="${RESTORE_BASE_DIR}/restore-instructions-${backup_set}-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Duplicati Restore Instructions"
        echo "=============================="
        echo "Backup Set: ${backup_set}"
        echo "Generated: $(date)"
        echo "Target Path: ${target_path}"
        echo
        echo "Prerequisites:"
        echo "1. Ensure Duplicati service is running"
        echo "2. Verify backup integrity before restore"
        echo "3. Stop related services if restoring active data"
        echo
        echo "Restore Steps:"
        echo "1. Access Duplicati web interface at: ${DUPLICATI_URL}"
        echo "2. Navigate to 'Restore' section"
        echo "3. Select backup configuration for: ${backup_set}"
        echo "4. Choose restore point (latest or specific date)"
        echo "5. Select files/folders to restore"
        echo "6. Set restore destination: ${target_path}"
        echo "7. Enter backup passphrase when prompted"
        echo "8. Start restore operation"
        echo
        echo "Post-Restore Steps:"
        echo "1. Verify restored files integrity"
        echo "2. Update file permissions if necessary"
        echo "3. Restart affected services"
        echo "4. Test application functionality"
        echo
        echo "Backup Set Details:"
        echo "Source Path: ${BACKUP_BASE_DIR}/${backup_set}"
        
        if [[ -d "${BACKUP_BASE_DIR}/${backup_set}" ]]; then
            echo "Backup Files: $(find "${BACKUP_BASE_DIR}/${backup_set}" -type f | wc -l)"
            echo "Total Size: $(du -sh "${BACKUP_BASE_DIR}/${backup_set}" | cut -f1)"
            echo "Latest File: $(find "${BACKUP_BASE_DIR}/${backup_set}" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2- | xargs -r date -r)"
        fi
        
        echo
        echo "Emergency Contact Information:"
        echo "- Check logs at: ${LOG_DIR}/"
        echo "- Backup manager script: ${0%/*}/backup-manager.sh"
        echo "- Duplicati documentation: https://duplicati.readthedocs.io/"
        
    } > "$instructions_file"
    
    log "Restore instructions generated: $instructions_file"
    echo "Restore instructions saved to: $instructions_file"
}

# Interactive restore wizard
restore_wizard() {
    echo "Duplicati Restore Wizard"
    echo "========================"
    echo
    
    # List available backups
    list_backups
    
    # Get backup set selection
    echo "Enter the backup set name to restore:"
    read -r backup_set
    
    if [[ -z "$backup_set" ]]; then
        echo "ERROR: No backup set specified"
        return 1
    fi
    
    # Validate backup
    if ! validate_backup "$backup_set"; then
        echo "ERROR: Backup validation failed"
        return 1
    fi
    
    # Get restore target
    echo "Enter restore target path (default: /tmp/restore-${backup_set}):"
    read -r restore_target
    restore_target="${restore_target:-/tmp/restore-${backup_set}}"
    
    # Prepare restore environment
    prepare_restore "$backup_set"
    
    # Generate instructions
    generate_restore_instructions "$backup_set" "$restore_target"
    
    echo
    echo "Restore preparation completed!"
    echo "Please follow the generated instructions to complete the restore process."
}

# Main function
main() {
    case "${1:-help}" in
        "list")
            list_backups
            ;;
        "validate")
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: Backup set name required"
                echo "Usage: $0 validate <backup-set-name>"
                return 1
            fi
            validate_backup "$2"
            ;;
        "prepare")
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: Backup set name required"
                echo "Usage: $0 prepare <backup-set-name>"
                return 1
            fi
            prepare_restore "$2"
            ;;
        "instructions")
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: Backup set name required"
                echo "Usage: $0 instructions <backup-set-name> [target-path]"
                return 1
            fi
            generate_restore_instructions "$2" "${3:-/tmp/restore-target}"
            ;;
        "wizard")
            restore_wizard
            ;;
        "help"|*)
            echo "Duplicati Restore Helper"
            echo "Usage: $0 {list|validate|prepare|instructions|wizard|help}"
            echo
            echo "Commands:"
            echo "  list                           - List available backup sets"
            echo "  validate <backup-set>          - Validate backup integrity"
            echo "  prepare <backup-set>           - Prepare restore environment"
            echo "  instructions <backup-set> [target] - Generate restore instructions"
            echo "  wizard                         - Interactive restore wizard"
            echo "  help                           - Show this help message"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"