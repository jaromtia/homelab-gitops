# Comprehensive Troubleshooting Guide

This guide provides solutions for common issues encountered in the homelab infrastructure, organized by category and severity.

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Service-Specific Issues](#service-specific-issues)
3. [Network and Connectivity Issues](#network-and-connectivity-issues)
4. [Docker and Container Issues](#docker-and-container-issues)
5. [Cloudflare Tunnel Issues](#cloudflare-tunnel-issues)
6. [Authentication and Access Issues](#authentication-and-access-issues)
7. [Data and Backup Issues](#data-and-backup-issues)
8. [Performance Issues](#performance-issues)
9. [Emergency Recovery Procedures](#emergency-recovery-procedures)

## Quick Diagnostics

### System Health Check

```powershell
# Run comprehensive health check
.\scripts\run-health-tests.ps1 -Detailed

# Quick service status check
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Check system resources
Get-Counter "\Processor(_Total)\% Processor Time","\Memory\Available MBytes"
```

### Common Commands

```powershell
# View all service logs
docker-compose logs --tail=50

# Check specific service
docker-compose logs <service-name> --tail=100

# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart <service-name>

# Check Docker system status
docker system info
docker system df
```

## Service-Specific Issues

### Grafana Issues

#### Problem: Grafana won't start or shows errors

**Symptoms:**
- Container exits immediately
- "Permission denied" errors in logs
- Database connection errors

**Solutions:**

1. **Check permissions:**
   ```powershell
   # Fix Grafana data permissions
   docker-compose down
   docker run --rm -v homelab_grafana_data:/data alpine chown -R 472:472 /data
   docker-compose up -d grafana
   ```

2. **Reset Grafana data:**
   ```powershell
   # WARNING: This will delete all Grafana data
   docker-compose down
   docker volume rm homelab_grafana_data
   docker-compose up -d grafana
   ```

3. **Check environment variables:**
   ```powershell
   # Verify Grafana environment
   docker-compose exec grafana env | Select-String "GF_"
   ```

#### Problem: Can't login to Grafana

**Solutions:**

1. **Reset admin password:**
   ```powershell
   # Reset to default password
   docker-compose exec grafana grafana-cli admin reset-admin-password admin
   
   # Or set custom password
   docker-compose exec grafana grafana-cli admin reset-admin-password "newpassword"
   ```

2. **Check environment variables:**
   ```powershell
   # Verify admin password setting
   Get-Content .env | Select-String "GRAFANA_ADMIN_PASSWORD"
   ```

### Prometheus Issues

#### Problem: Prometheus targets are down

**Symptoms:**
- Targets showing as "DOWN" in Prometheus UI
- No metrics being collected
- Scrape errors in logs

**Solutions:**

1. **Check target connectivity:**
   ```powershell
   # Test connectivity to targets
   docker-compose exec prometheus wget -qO- http://node-exporter:9100/metrics
   docker-compose exec prometheus wget -qO- http://cadvisor:8080/metrics
   ```

2. **Verify Prometheus configuration:**
   ```powershell
   # Check configuration syntax
   docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
   ```

3. **Restart Prometheus:**
   ```powershell
   docker-compose restart prometheus
   ```

### Portainer Issues

#### Problem: Portainer setup screen doesn't appear

**Solutions:**

1. **Reset Portainer:**
   ```powershell
   # Remove Portainer data and restart
   docker-compose down
   docker volume rm homelab_portainer_data
   docker-compose up -d portainer
   
   # Access within 5 minutes at http://localhost:9000
   Start-Process "http://localhost:9000"
   ```

2. **Check container logs:**
   ```powershell
   docker-compose logs portainer
   ```

### FileBrowser Issues

#### Problem: Can't find FileBrowser password

**Solutions:**

1. **Find generated password:**
   ```powershell
   # Look for password in logs
   docker-compose logs filebrowser | Select-String "randomly generated password"
   ```

2. **Reset FileBrowser:**
   ```powershell
   # Reset FileBrowser data
   docker-compose down
   docker volume rm homelab_filebrowser_data
   docker-compose up -d filebrowser
   
   # Check logs for new password
   Start-Sleep -Seconds 10
   docker-compose logs filebrowser | Select-String "randomly generated password"
   ```

### Linkding Issues

#### Problem: Linkding database errors

**Solutions:**

1. **Check database integrity:**
   ```powershell
   # Access Linkding container
   docker-compose exec linkding python manage.py check
   ```

2. **Reset database:**
   ```powershell
   # WARNING: This will delete all bookmarks
   docker-compose down
   docker volume rm homelab_linkding_data
   docker-compose up -d linkding
   ```

### Actual Budget Issues

#### Problem: Actual Budget won't start or crashes

**Solutions:**

1. **Check logs:**
   ```powershell
   docker-compose logs actual
   ```

2. **Reset Actual data:**
   ```powershell
   # WARNING: This will delete all budget data
   docker-compose down
   docker volume rm homelab_actual_data
   docker-compose up -d actual
   ```

### Duplicati Issues

#### Problem: Backup jobs failing

**Solutions:**

1. **Check backup logs:**
   ```powershell
   # Access Duplicati web interface
   Start-Process "http://localhost:8200"
   # Check job logs in the interface
   ```

2. **Test backup destination:**
   ```powershell
   # Test connectivity to backup destination
   docker-compose exec duplicati duplicati-cli test-filters
   ```

3. **Repair backup database:**
   ```powershell
   # Repair Duplicati database
   docker-compose exec duplicati duplicati-cli repair
   ```

## Network and Connectivity Issues

### Internal Network Issues

#### Problem: Services can't communicate with each other

**Solutions:**

1. **Check Docker networks:**
   ```powershell
   # List networks
   docker network ls | Select-String "homelab"
   
   # Inspect network configuration
   docker network inspect homelab_frontend
   docker network inspect homelab_backend
   ```

2. **Test network connectivity:**
   ```powershell
   # Test connectivity between services
   docker-compose exec prometheus ping grafana
   docker-compose exec grafana ping prometheus
   ```

3. **Recreate networks:**
   ```powershell
   # Recreate Docker networks
   docker-compose down
   docker network prune -f
   docker-compose up -d
   ```

### External Access Issues

#### Problem: Services not accessible from outside

**Solutions:**

1. **Check Cloudflare tunnel status:**
   ```powershell
   # Check tunnel logs
   docker-compose logs cloudflared
   
   # Test tunnel connectivity
   .\scripts\test-tunnel-connectivity.ps1
   ```

2. **Verify DNS configuration:**
   ```powershell
   # Test DNS resolution
   nslookup dashboard.yourdomain.com
   nslookup grafana.yourdomain.com
   ```

3. **Check tunnel configuration:**
   ```powershell
   # Validate tunnel config
   docker-compose exec cloudflared cloudflared tunnel ingress validate
   ```

## Docker and Container Issues

### Container Won't Start

#### Problem: Container exits immediately or fails to start

**Solutions:**

1. **Check container logs:**
   ```powershell
   # View container logs
   docker logs <container-name>
   
   # Follow logs in real-time
   docker logs -f <container-name>
   ```

2. **Check resource constraints:**
   ```powershell
   # Check system resources
   docker system df
   docker stats --no-stream
   ```

3. **Verify image integrity:**
   ```powershell
   # Pull fresh images
   docker-compose pull
   docker-compose up -d --force-recreate
   ```

### Port Conflicts

#### Problem: Port already in use errors

**Solutions:**

1. **Identify conflicting processes:**
   ```powershell
   # Find what's using the port
   netstat -ano | findstr ":9090"
   netstat -ano | findstr ":3000"
   
   # Kill conflicting process
   Stop-Process -Id <PID> -Force
   ```

2. **Change service ports:**
   ```yaml
   # Edit docker-compose.yml to use different ports
   ports:
     - "3001:3000"  # Change from 3000:3000
   ```

### Volume Issues

#### Problem: Data not persisting or volume errors

**Solutions:**

1. **Check volume status:**
   ```powershell
   # List volumes
   docker volume ls | Select-String "homelab"
   
   # Inspect volume
   docker volume inspect homelab_grafana_data
   ```

2. **Fix volume permissions:**
   ```powershell
   # Fix permissions for specific service
   docker run --rm -v homelab_grafana_data:/data alpine chown -R 472:472 /data
   ```

3. **Recreate volumes:**
   ```powershell
   # WARNING: This will delete all data
   docker-compose down -v
   docker-compose up -d
   ```

## Cloudflare Tunnel Issues

### Tunnel Connection Problems

#### Problem: Tunnel won't connect or frequently disconnects

**Solutions:**

1. **Check tunnel credentials:**
   ```powershell
   # Verify credentials file exists
   Test-Path "config\cloudflared\credentials.json"
   
   # Check credentials format
   Get-Content "config\cloudflared\credentials.json" | ConvertFrom-Json
   ```

2. **Validate tunnel configuration:**
   ```powershell
   # Test tunnel config
   docker-compose exec cloudflared cloudflared tunnel ingress validate
   ```

3. **Recreate tunnel:**
   ```powershell
   # Delete and recreate tunnel
   cloudflared tunnel delete homelab
   cloudflared tunnel create homelab-new
   
   # Update config with new tunnel ID
   ```

### DNS Issues

#### Problem: Subdomains not resolving

**Solutions:**

1. **Check DNS records:**
   ```powershell
   # Test DNS resolution
   nslookup dashboard.yourdomain.com
   nslookup grafana.yourdomain.com
   ```

2. **Update DNS records:**
   - Log into Cloudflare dashboard
   - Verify CNAME records point to `<tunnel-id>.cfargotunnel.com`
   - Check DNS propagation

3. **Clear DNS cache:**
   ```powershell
   # Clear local DNS cache
   ipconfig /flushdns
   ```

## Authentication and Access Issues

### Password Problems

#### Problem: Forgotten or incorrect passwords

**Solutions:**

1. **Check environment variables:**
   ```powershell
   # View current passwords (be careful with output)
   Get-Content .env | Select-String "PASSWORD"
   ```

2. **Reset service passwords:**
   ```powershell
   # Grafana
   docker-compose exec grafana grafana-cli admin reset-admin-password newpassword
   
   # FileBrowser - check logs for generated password
   docker-compose logs filebrowser | Select-String "randomly generated password"
   ```

3. **Update environment file:**
   ```powershell
   # Edit .env file with new passwords
   notepad .env
   
   # Restart services to apply changes
   docker-compose restart
   ```

### Session Issues

#### Problem: Frequent logouts or session timeouts

**Solutions:**

1. **Check service configuration:**
   - Review session timeout settings in service configs
   - Verify cookie settings for HTTPS access

2. **Clear browser data:**
   - Clear cookies and cache for the domain
   - Try incognito/private browsing mode

## Data and Backup Issues

### Backup Failures

#### Problem: Duplicati backups failing

**Solutions:**

1. **Check backup logs:**
   ```powershell
   # Access Duplicati web interface
   Start-Process "http://localhost:8200"
   # Review job logs and error messages
   ```

2. **Test backup destination:**
   ```powershell
   # Test connectivity to backup storage
   docker-compose exec duplicati duplicati-cli test-filters
   ```

3. **Repair backup database:**
   ```powershell
   # Repair Duplicati database
   docker-compose exec duplicati duplicati-cli repair
   ```

### Data Loss Recovery

#### Problem: Service data appears to be lost

**Solutions:**

1. **Check volume status:**
   ```powershell
   # Verify volumes exist
   docker volume ls | Select-String "homelab"
   
   # Check volume contents
   docker run --rm -v homelab_grafana_data:/data alpine ls -la /data
   ```

2. **Restore from backup:**
   ```powershell
   # Use Duplicati to restore data
   Start-Process "http://localhost:8200"
   # Follow restore procedure in Duplicati interface
   ```

3. **Restore from GitHub:**
   ```powershell
   # Restore configuration from GitHub
   .\scripts\restore-from-github.ps1 -Force
   ```

## Performance Issues

### High Resource Usage

#### Problem: System running slowly or high CPU/memory usage

**Solutions:**

1. **Monitor resource usage:**
   ```powershell
   # Check container resource usage
   docker stats --no-stream
   
   # Check system resources
   Get-Counter "\Processor(_Total)\% Processor Time","\Memory\Available MBytes"
   ```

2. **Optimize container resources:**
   ```yaml
   # Add resource limits to docker-compose.yml
   deploy:
     resources:
       limits:
         memory: 512M
         cpus: '0.5'
   ```

3. **Clean up Docker resources:**
   ```powershell
   # Clean up unused resources
   docker system prune -f
   docker volume prune -f
   docker image prune -f
   ```

### Slow Response Times

#### Problem: Services responding slowly

**Solutions:**

1. **Check network latency:**
   ```powershell
   # Test internal network latency
   docker-compose exec prometheus ping -c 4 grafana
   ```

2. **Optimize service configuration:**
   - Review service-specific performance settings
   - Increase memory limits if needed
   - Check for resource contention

3. **Monitor service health:**
   ```powershell
   # Check service health status
   docker inspect --format='{{.State.Health.Status}}' <container-name>
   ```

## Emergency Recovery Procedures

### Complete System Recovery

#### When: Total system failure or corruption

**Procedure:**

1. **Stop all services:**
   ```powershell
   docker-compose down -v
   ```

2. **Clean Docker system:**
   ```powershell
   docker system prune -a -f
   docker volume prune -f
   ```

3. **Restore from GitHub:**
   ```powershell
   .\scripts\restore-from-github.ps1 -Force
   ```

4. **Restore data from backups:**
   ```powershell
   # Use Duplicati to restore service data
   # Follow backup restoration procedures
   ```

5. **Redeploy services:**
   ```powershell
   .\scripts\deploy-with-github.ps1 -Mode fresh
   ```

### Partial Service Recovery

#### When: Individual service failure

**Procedure:**

1. **Identify failed service:**
   ```powershell
   docker-compose ps
   docker-compose logs <service-name>
   ```

2. **Attempt service restart:**
   ```powershell
   docker-compose restart <service-name>
   ```

3. **If restart fails, recreate service:**
   ```powershell
   docker-compose stop <service-name>
   docker-compose rm -f <service-name>
   docker-compose up -d <service-name>
   ```

4. **Restore service data if needed:**
   ```powershell
   # Use Duplicati to restore specific service data
   ```

### Configuration Recovery

#### When: Configuration files corrupted or lost

**Procedure:**

1. **Backup current state:**
   ```powershell
   # Create backup of current config
   Copy-Item -Recurse config config-backup-$(Get-Date -Format "yyyyMMdd-HHmmss")
   ```

2. **Restore from GitHub:**
   ```powershell
   .\scripts\restore-from-github.ps1
   ```

3. **Merge configurations if needed:**
   ```powershell
   # Compare and merge configurations manually
   # Use git diff to identify changes
   ```

4. **Test configuration:**
   ```powershell
   docker-compose config
   .\scripts\validate-configuration.ps1
   ```

## Getting Help

### Log Collection

When seeking help, collect these logs:

```powershell
# Collect all service logs
docker-compose logs > homelab-logs-$(Get-Date -Format "yyyyMMdd-HHmmss").txt

# Collect system information
docker system info > docker-info.txt
docker-compose config > compose-config.txt

# Collect validation results
.\scripts\run-health-tests.ps1 -Detailed > health-check.txt
```

### Support Channels

1. **GitHub Issues**: Create an issue in the repository
2. **Documentation**: Review all documentation in `docs/` directory
3. **Community Forums**: Docker, Grafana, Prometheus communities
4. **Service-Specific Support**: Check individual service documentation

### Information to Include

When reporting issues, include:

- Error messages and logs
- Steps to reproduce the issue
- System information (OS, Docker version)
- Configuration files (sanitized of secrets)
- Output from validation scripts

## Prevention

### Regular Maintenance

```powershell
# Weekly maintenance script
.\scripts\run-health-tests.ps1
.\scripts\test-backup-integrity.ps1
docker system prune -f

# Monthly maintenance
.\scripts\validate-configuration.ps1
# Update container images
docker-compose pull
docker-compose up -d
```

### Monitoring

- Set up Grafana alerts for critical metrics
- Monitor backup job success rates
- Review logs regularly for warnings
- Monitor disk space and resource usage

### Documentation

- Keep this troubleshooting guide updated
- Document any custom configurations
- Maintain change logs for modifications
- Update contact information and procedures