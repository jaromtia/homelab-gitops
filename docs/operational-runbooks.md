# Operational Runbooks for Maintenance Tasks

This document provides step-by-step procedures for routine maintenance tasks, system monitoring, and operational procedures for the homelab infrastructure.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Weekly Maintenance](#weekly-maintenance)
3. [Monthly Maintenance](#monthly-maintenance)
4. [Quarterly Reviews](#quarterly-reviews)
5. [Service-Specific Maintenance](#service-specific-maintenance)
6. [Emergency Procedures](#emergency-procedures)
7. [Performance Optimization](#performance-optimization)
8. [Security Maintenance](#security-maintenance)
9. [Monitoring and Alerting](#monitoring-and-alerting)
10. [Documentation Maintenance](#documentation-maintenance)

## Daily Operations

### Morning Health Check (5 minutes)

**Frequency:** Daily at 8:00 AM  
**Estimated Time:** 5 minutes  
**Prerequisites:** Access to Grafana dashboard and PowerShell

#### Procedure

1. **Check Service Status:**
   ```powershell
   # Quick service status check
   docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
   
   # Count running services
   $runningServices = docker-compose ps --services --filter "status=running" | Measure-Object -Line
   Write-Host "Running services: $($runningServices.Lines)"
   ```

2. **Review Grafana Dashboard:**
   ```powershell
   # Open main dashboard
   Start-Process "http://localhost:3000/d/homelab-overview"
   ```
   
   **Check these metrics:**
   - [ ] All services showing as "UP" in service status panel
   - [ ] CPU usage < 80% average
   - [ ] Memory usage < 85% average
   - [ ] Disk usage < 90% on all volumes
   - [ ] No critical alerts active

3. **Check Backup Status:**
   ```powershell
   # Check last backup completion
   docker-compose logs duplicati --tail=10 | Select-String "backup completed"
   
   # Verify backup storage
   Get-ChildItem ".\data\backups" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
   ```

4. **Review Logs for Errors:**
   ```powershell
   # Check for errors in the last 24 hours
   docker-compose logs --since="24h" | Select-String -Pattern "ERROR|FATAL|CRITICAL" | Select-Object -First 10
   ```

#### Success Criteria
- All services running and healthy
- No critical alerts
- Backup completed within last 24 hours
- No critical errors in logs

#### Escalation
If any issues found, follow [Emergency Procedures](#emergency-procedures)

---

### Evening Backup Verification (3 minutes)

**Frequency:** Daily at 6:00 PM  
**Estimated Time:** 3 minutes

#### Procedure

1. **Verify Backup Completion:**
   ```powershell
   # Check Duplicati backup status
   Start-Process "http://localhost:8200"
   # Navigate to backup jobs and verify completion status
   ```

2. **Check Configuration Sync:**
   ```powershell
   # Verify Git status
   .\scripts\git-ops.ps1 status
   
   # If changes detected, commit them
   if (git status --porcelain) {
       .\scripts\git-ops.ps1 save "Daily configuration sync"
   }
   ```

3. **Monitor Storage Usage:**
   ```powershell
   # Check backup storage usage
   $backupSize = (Get-ChildItem -Recurse ".\data\backups" | Measure-Object -Property Length -Sum).Sum / 1GB
   Write-Host "Backup storage usage: $([math]::Round($backupSize, 2)) GB"
   
   # Alert if over 80% of allocated space
   if ($backupSize -gt 80) {
       Write-Warning "Backup storage usage high: $backupSize GB"
   }
   ```

#### Success Criteria
- All backup jobs completed successfully
- Configuration changes committed to Git
- Storage usage within acceptable limits

---

## Weekly Maintenance

### System Health Review (15 minutes)

**Frequency:** Every Sunday at 10:00 AM  
**Estimated Time:** 15 minutes

#### Procedure

1. **Comprehensive Health Check:**
   ```powershell
   # Run full health test suite
   .\scripts\run-health-tests.ps1 -Detailed
   
   # Save results for trending
   .\scripts\run-health-tests.ps1 -Detailed > "health-reports\health-$(Get-Date -Format 'yyyyMMdd').txt"
   ```

2. **Performance Review:**
   ```powershell
   # Check container resource usage
   docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
   
   # Check system resources
   Get-Counter "\Processor(_Total)\% Processor Time","\Memory\Available MBytes","\LogicalDisk(_Total)\% Free Space"
   ```

3. **Log Analysis:**
   ```powershell
   # Analyze logs for patterns
   docker-compose logs --since="7d" | Select-String -Pattern "ERROR|WARN" | Group-Object | Sort-Object Count -Descending
   
   # Check for recurring issues
   docker-compose logs --since="7d" | Select-String -Pattern "restart|failed|timeout" | Measure-Object -Line
   ```

4. **Security Review:**
   ```powershell
   # Check for security updates
   docker-compose pull --dry-run
   
   # Review access logs (if available)
   # Check Cloudflare dashboard for security events
   ```

#### Success Criteria
- All health checks pass
- Performance metrics within normal ranges
- No recurring errors or security issues
- All services up to date

---

### Container Updates (20 minutes)

**Frequency:** Every Sunday at 2:00 PM  
**Estimated Time:** 20 minutes

#### Procedure

1. **Pre-Update Backup:**
   ```powershell
   # Create pre-update backup
   .\scripts\git-ops.ps1 save "Pre-update backup - $(Get-Date -Format 'yyyy-MM-dd')"
   
   # Trigger manual Duplicati backup
   # Access http://localhost:8200 and run backup jobs manually
   ```

2. **Check for Updates:**
   ```powershell
   # Check for image updates
   docker-compose pull
   
   # List images that were updated
   docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | Sort-Object CreatedAt -Descending
   ```

3. **Update Services:**
   ```powershell
   # Update services with new images
   docker-compose up -d --force-recreate
   
   # Wait for services to stabilize
   Start-Sleep -Seconds 60
   ```

4. **Post-Update Verification:**
   ```powershell
   # Verify all services are running
   docker-compose ps
   
   # Run health checks
   .\scripts\run-health-tests.ps1
   
   # Test external access
   .\scripts\test-tunnel-connectivity.ps1
   ```

5. **Cleanup:**
   ```powershell
   # Remove old images
   docker image prune -f
   
   # Remove unused volumes
   docker volume prune -f
   ```

#### Success Criteria
- All services updated successfully
- Health checks pass after update
- External access working
- No data loss or configuration issues

#### Rollback Procedure
If issues occur:
```powershell
# Stop services
docker-compose down

# Restore from backup if needed
.\scripts\restore-from-github.ps1

# Restart with previous configuration
docker-compose up -d
```

---

## Monthly Maintenance

### Comprehensive System Review (45 minutes)

**Frequency:** First Sunday of each month at 10:00 AM  
**Estimated Time:** 45 minutes

#### Procedure

1. **Performance Analysis:**
   ```powershell
   # Generate performance report
   $report = @{
       Date = Get-Date
       SystemInfo = docker system info
       ResourceUsage = docker stats --no-stream
       VolumeUsage = docker system df
       NetworkInfo = docker network ls
   }
   
   $report | ConvertTo-Json | Out-File "reports\monthly-performance-$(Get-Date -Format 'yyyyMM').json"
   ```

2. **Capacity Planning:**
   ```powershell
   # Check storage growth trends
   $storageUsage = @()
   Get-ChildItem "health-reports\health-*.txt" | ForEach-Object {
       $content = Get-Content $_.FullName
       $diskUsage = $content | Select-String "Disk usage" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
       $storageUsage += @{
           Date = $_.BaseName.Replace('health-', '')
           Usage = $diskUsage
       }
   }
   
   # Analyze trends and predict capacity needs
   ```

3. **Security Audit:**
   ```powershell
   # Review access logs
   # Check for unauthorized access attempts
   # Verify SSL certificate status
   # Review user accounts and permissions
   
   # Check for security updates
   docker-compose pull
   
   # Review Cloudflare security settings
   ```

4. **Backup Verification:**
   ```powershell
   # Test backup restoration
   .\scripts\test-backup-integrity.ps1 -Full
   
   # Verify backup retention policies
   # Check backup storage usage and costs
   ```

5. **Documentation Review:**
   ```powershell
   # Review and update documentation
   # Check for outdated procedures
   # Update contact information
   # Review and update runbooks
   ```

#### Success Criteria
- Performance within acceptable ranges
- Security audit passes
- Backup verification successful
- Documentation up to date

---

### Certificate and Credential Rotation (30 minutes)

**Frequency:** Every 3 months  
**Estimated Time:** 30 minutes

#### Procedure

1. **Review Current Credentials:**
   ```powershell
   # List current credentials (without exposing values)
   Get-Content .env | Select-String "PASSWORD|TOKEN|KEY" | ForEach-Object { $_.Split('=')[0] }
   ```

2. **Generate New Passwords:**
   ```powershell
   # Generate new secure passwords
   function New-SecurePassword {
       param([int]$Length = 16)
       $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
       $password = ""
       for ($i = 0; $i -lt $Length; $i++) {
           $password += $chars[(Get-Random -Maximum $chars.Length)]
       }
       return $password
   }
   
   # Generate new passwords for rotation
   $newPasswords = @{
       GRAFANA_ADMIN_PASSWORD = New-SecurePassword
       LINKDING_SUPERUSER_PASSWORD = New-SecurePassword
       ACTUAL_PASSWORD = New-SecurePassword
       DUPLICATI_PASSWORD = New-SecurePassword
       BACKUP_ENCRYPTION_PASSWORD = New-SecurePassword -Length 32
   }
   ```

3. **Update Credentials:**
   ```powershell
   # Backup current .env file
   Copy-Item .env ".env.backup.$(Get-Date -Format 'yyyyMMdd')"
   
   # Update .env file with new passwords
   # (Manual process - update each password individually)
   
   # Restart services to apply new credentials
   docker-compose restart
   ```

4. **Verify New Credentials:**
   ```powershell
   # Test login to each service with new credentials
   # Verify backup encryption with new password
   # Update any external systems that use these credentials
   ```

5. **Update Documentation:**
   ```powershell
   # Update password manager or secure documentation
   # Notify team members of credential changes
   # Update any automation that uses these credentials
   ```

#### Success Criteria
- All credentials successfully rotated
- All services accessible with new credentials
- Backup encryption working with new password
- Documentation updated

---

## Service-Specific Maintenance

### Grafana Maintenance

#### Dashboard Optimization (15 minutes)
**Frequency:** Monthly

```powershell
# Access Grafana
Start-Process "http://localhost:3000"

# Tasks to perform in Grafana UI:
# 1. Review dashboard performance
# 2. Optimize slow queries
# 3. Clean up unused dashboards
# 4. Update data source configurations
# 5. Review and update alert rules
```

#### Database Maintenance (10 minutes)
**Frequency:** Monthly

```powershell
# Check Grafana database size
docker-compose exec grafana du -sh /var/lib/grafana

# Clean up old sessions and temporary data
docker-compose exec grafana sqlite3 /var/lib/grafana/grafana.db "DELETE FROM session WHERE created_at < datetime('now', '-30 days');"

# Vacuum database to reclaim space
docker-compose exec grafana sqlite3 /var/lib/grafana/grafana.db "VACUUM;"
```

---

### Prometheus Maintenance

#### Data Retention Management (10 minutes)
**Frequency:** Weekly

```powershell
# Check Prometheus data size
docker-compose exec prometheus du -sh /prometheus

# Review retention settings in prometheus.yml
# Default retention is 15 days, adjust if needed

# Check for any storage issues
docker-compose logs prometheus | Select-String "storage"
```

#### Target Health Review (5 minutes)
**Frequency:** Weekly

```powershell
# Access Prometheus targets page
Start-Process "http://localhost:9090/targets"

# Review target health and scrape duration
# Investigate any targets showing as DOWN
# Optimize scrape intervals if needed
```

---

### Duplicati Maintenance

#### Backup Job Optimization (20 minutes)
**Frequency:** Monthly

```powershell
# Access Duplicati web interface
Start-Process "http://localhost:8200"

# Tasks to perform:
# 1. Review backup job performance
# 2. Optimize backup schedules
# 3. Clean up old backup versions
# 4. Test restoration procedures
# 5. Review storage usage and costs
```

#### Database Maintenance (10 minutes)
**Frequency:** Monthly

```powershell
# Repair Duplicati database
docker-compose exec duplicati duplicati-cli repair

# Compact database
docker-compose exec duplicati duplicati-cli compact

# Verify database integrity
docker-compose exec duplicati duplicati-cli verify
```

---

## Emergency Procedures

### Service Down Emergency Response

#### Immediate Response (5 minutes)

1. **Assess Impact:**
   ```powershell
   # Check which services are affected
   docker-compose ps | Where-Object { $_.Status -notmatch "Up" }
   
   # Check system resources
   Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
   ```

2. **Quick Recovery Attempt:**
   ```powershell
   # Restart affected services
   docker-compose restart <service-name>
   
   # If that fails, recreate the service
   docker-compose up -d --force-recreate <service-name>
   ```

3. **Escalation Decision:**
   - If service recovers: Continue with root cause analysis
   - If service doesn't recover: Escalate to full recovery procedure

#### Full Recovery Procedure (15 minutes)

1. **Stop All Services:**
   ```powershell
   docker-compose down
   ```

2. **Check System Health:**
   ```powershell
   # Check disk space
   Get-WmiObject -Class Win32_LogicalDisk | Select-Object DeviceID, @{Name="FreeSpace(GB)";Expression={[math]::Round($_.FreeSpace/1GB,2)}}
   
   # Check memory
   Get-WmiObject -Class Win32_ComputerSystem | Select-Object TotalPhysicalMemory
   
   # Check Docker daemon
   docker system info
   ```

3. **Restore from Backup if Needed:**
   ```powershell
   # If data corruption suspected
   .\scripts\restore-from-github.ps1
   
   # Restore service data from Duplicati if needed
   ```

4. **Restart Services:**
   ```powershell
   docker-compose up -d
   
   # Monitor startup
   docker-compose logs -f
   ```

5. **Verify Recovery:**
   ```powershell
   .\scripts\run-health-tests.ps1
   ```

---

### Data Corruption Emergency Response

#### Immediate Assessment (10 minutes)

1. **Stop Affected Services:**
   ```powershell
   # Stop services to prevent further corruption
   docker-compose stop <affected-services>
   ```

2. **Assess Damage:**
   ```powershell
   # Check volume integrity
   docker run --rm -v homelab_<service>_data:/data alpine ls -la /data
   
   # Check for corruption indicators
   docker-compose logs <service> | Select-String "corrupt|error|failed"
   ```

3. **Determine Recovery Strategy:**
   - Minor corruption: Attempt service-specific repair
   - Major corruption: Restore from backup
   - Complete loss: Full disaster recovery

#### Recovery Execution (30 minutes)

1. **Backup Current State:**
   ```powershell
   # Even if corrupted, backup current state for analysis
   $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
   docker run --rm -v homelab_<service>_data:/source -v ${PWD}/emergency-backup-${timestamp}:/backup alpine tar czf /backup/corrupted-data.tar.gz -C /source .
   ```

2. **Restore from Backup:**
   ```powershell
   # Remove corrupted volume
   docker volume rm homelab_<service>_data
   
   # Restore from Duplicati
   # (Follow backup restoration procedures)
   ```

3. **Verify Recovery:**
   ```powershell
   # Start service
   docker-compose up -d <service>
   
   # Verify data integrity
   # Test service functionality
   ```

---

## Performance Optimization

### Resource Optimization (30 minutes)

**Frequency:** Monthly or when performance issues detected

#### Procedure

1. **Analyze Resource Usage:**
   ```powershell
   # Monitor container resources
   docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
   
   # Identify resource-heavy containers
   docker stats --no-stream | Sort-Object CPUPerc -Descending
   ```

2. **Optimize Container Resources:**
   ```yaml
   # Add resource limits to docker-compose.yml
   services:
     grafana:
       deploy:
         resources:
           limits:
             memory: 512M
             cpus: '0.5'
           reservations:
             memory: 256M
             cpus: '0.25'
   ```

3. **Database Optimization:**
   ```powershell
   # Optimize Grafana database
   docker-compose exec grafana sqlite3 /var/lib/grafana/grafana.db "VACUUM;"
   
   # Optimize Prometheus data
   docker-compose exec prometheus promtool tsdb analyze /prometheus
   ```

4. **Network Optimization:**
   ```powershell
   # Check network performance
   docker network ls
   docker network inspect homelab_frontend
   
   # Optimize network configuration if needed
   ```

#### Success Criteria
- CPU usage < 70% average
- Memory usage < 80% average
- Response times improved
- No resource-related errors

---

### Storage Optimization (20 minutes)

**Frequency:** Monthly

#### Procedure

1. **Analyze Storage Usage:**
   ```powershell
   # Check Docker storage usage
   docker system df
   
   # Check volume usage
   docker volume ls | ForEach-Object { 
       $volume = $_.Split()[-1]
       $size = docker run --rm -v ${volume}:/data alpine du -sh /data
       Write-Host "$volume : $size"
   }
   ```

2. **Clean Up Unused Resources:**
   ```powershell
   # Remove unused images
   docker image prune -f
   
   # Remove unused volumes (be careful!)
   docker volume prune -f
   
   # Remove unused networks
   docker network prune -f
   
   # Remove build cache
   docker builder prune -f
   ```

3. **Optimize Log Rotation:**
   ```powershell
   # Configure log rotation in docker-compose.yml
   logging:
     driver: "json-file"
     options:
       max-size: "10m"
       max-file: "3"
   ```

4. **Archive Old Data:**
   ```powershell
   # Archive old Prometheus data
   # Archive old Grafana dashboards
   # Archive old backup files
   ```

#### Success Criteria
- Storage usage < 80% of available space
- Log files properly rotated
- Old data archived appropriately

---

## Security Maintenance

### Security Audit (45 minutes)

**Frequency:** Monthly

#### Procedure

1. **Review Access Logs:**
   ```powershell
   # Check Cloudflare access logs
   # Review service authentication logs
   # Look for suspicious access patterns
   ```

2. **Update Security Configurations:**
   ```powershell
   # Review Cloudflare security settings
   # Update firewall rules if needed
   # Review service security configurations
   ```

3. **Vulnerability Assessment:**
   ```powershell
   # Check for container vulnerabilities
   docker scout cves
   
   # Update to latest secure images
   docker-compose pull
   ```

4. **Access Control Review:**
   ```powershell
   # Review user accounts and permissions
   # Audit service access controls
   # Review API keys and tokens
   ```

#### Success Criteria
- No security vulnerabilities found
- All access controls properly configured
- Security configurations up to date

---

### SSL Certificate Management (15 minutes)

**Frequency:** Monthly

#### Procedure

1. **Check Certificate Status:**
   ```powershell
   # Check Cloudflare SSL status
   # Verify certificate expiration dates
   # Test SSL configuration
   ```

2. **Update Certificates if Needed:**
   ```powershell
   # Cloudflare handles SSL automatically
   # Verify automatic renewal is working
   # Update any custom certificates
   ```

3. **Test SSL Configuration:**
   ```powershell
   # Test SSL endpoints
   .\scripts\test-tunnel-connectivity.ps1
   
   # Verify SSL grades and security
   ```

#### Success Criteria
- All SSL certificates valid and current
- SSL configuration secure
- No SSL-related errors

---

## Monitoring and Alerting

### Alert Rule Maintenance (20 minutes)

**Frequency:** Monthly

#### Procedure

1. **Review Alert Rules:**
   ```powershell
   # Access Prometheus alerts
   Start-Process "http://localhost:9090/alerts"
   
   # Review alert rule effectiveness
   # Check for false positives
   # Identify missing alerts
   ```

2. **Update Alert Thresholds:**
   ```yaml
   # Update prometheus alert rules
   # Adjust thresholds based on historical data
   # Add new alert rules as needed
   ```

3. **Test Alert Delivery:**
   ```powershell
   # Test alert notification channels
   # Verify alert routing
   # Test escalation procedures
   ```

#### Success Criteria
- All alert rules functioning correctly
- No false positive alerts
- Alert delivery working properly

---

### Dashboard Maintenance (15 minutes)

**Frequency:** Monthly

#### Procedure

1. **Review Dashboard Performance:**
   ```powershell
   # Access Grafana dashboards
   Start-Process "http://localhost:3000"
   
   # Check dashboard load times
   # Identify slow queries
   # Review dashboard usage
   ```

2. **Optimize Dashboards:**
   ```powershell
   # Optimize slow queries
   # Remove unused panels
   # Update dashboard layouts
   # Add new monitoring panels as needed
   ```

3. **Update Data Sources:**
   ```powershell
   # Verify data source connectivity
   # Update data source configurations
   # Test data source performance
   ```

#### Success Criteria
- All dashboards load quickly
- Data sources functioning properly
- Dashboards provide useful insights

---

## Documentation Maintenance

### Documentation Review (30 minutes)

**Frequency:** Quarterly

#### Procedure

1. **Review All Documentation:**
   ```powershell
   # Review all files in docs/ directory
   Get-ChildItem docs/ -Filter "*.md" | ForEach-Object {
       Write-Host "Reviewing: $($_.Name)"
       # Check for outdated information
       # Verify procedures are current
       # Update contact information
   }
   ```

2. **Update Procedures:**
   ```powershell
   # Update any changed procedures
   # Add new procedures as needed
   # Remove obsolete procedures
   ```

3. **Verify Links and References:**
   ```powershell
   # Check all external links
   # Verify internal references
   # Update version numbers
   ```

4. **Update Change Log:**
   ```powershell
   # Document all changes made
   # Update version information
   # Note any breaking changes
   ```

#### Success Criteria
- All documentation current and accurate
- No broken links or references
- Change log updated

---

### Runbook Testing (60 minutes)

**Frequency:** Quarterly

#### Procedure

1. **Test Emergency Procedures:**
   ```powershell
   # Test service recovery procedures
   # Test backup restoration procedures
   # Test disaster recovery procedures
   ```

2. **Test Maintenance Procedures:**
   ```powershell
   # Test update procedures
   # Test optimization procedures
   # Test monitoring procedures
   ```

3. **Document Test Results:**
   ```powershell
   # Record test outcomes
   # Note any procedure failures
   # Update procedures based on test results
   ```

4. **Update Runbooks:**
   ```powershell
   # Fix any identified issues
   # Improve procedure clarity
   # Add missing steps
   ```

#### Success Criteria
- All procedures tested successfully
- Any issues identified and resolved
- Runbooks updated and improved

---

## Maintenance Schedule Summary

### Daily Tasks
- [ ] Morning health check (5 min)
- [ ] Evening backup verification (3 min)

### Weekly Tasks
- [ ] System health review (15 min)
- [ ] Container updates (20 min)

### Monthly Tasks
- [ ] Comprehensive system review (45 min)
- [ ] Performance optimization (30 min)
- [ ] Security audit (45 min)
- [ ] Alert rule maintenance (20 min)
- [ ] Dashboard maintenance (15 min)

### Quarterly Tasks
- [ ] Certificate and credential rotation (30 min)
- [ ] Documentation review (30 min)
- [ ] Runbook testing (60 min)

### Annual Tasks
- [ ] Complete infrastructure review
- [ ] Disaster recovery testing
- [ ] Security penetration testing
- [ ] Capacity planning review

---

## Contact Information

**System Administrator:** [Your Name]  
**Email:** [your.email@example.com]  
**Phone:** [Your Phone Number]  
**Emergency Contact:** [Emergency Contact]

**Service Providers:**
- **Cloud Storage:** [Provider Contact]
- **Domain Registrar:** [Registrar Contact]
- **Internet Service Provider:** [ISP Contact]

---

## Change Log

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| [Date] | 1.0 | Initial runbook creation | [Author] |

**Next Review Date:** [Date + 3 months]