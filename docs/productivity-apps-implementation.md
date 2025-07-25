# Productivity Applications Implementation Guide

This document describes the implementation of productivity applications (Linkding and Actual Budget) in the homelab infrastructure.

## Overview

The productivity applications provide essential personal management tools:

- **Linkding**: Self-hosted bookmark manager with tagging and search
- **Actual Budget**: Personal finance manager with budgeting and transaction tracking

Both services are integrated with the existing infrastructure for secure access, monitoring, and backup.

## Implementation Details

### Linkding Bookmark Manager

#### Service Configuration

```yaml
linkding:
  image: sissbruecker/linkding:latest
  container_name: linkding
  restart: unless-stopped
  
  networks:
    - frontend
    - backend
  
  ports:
    - "9091:9090"
  
  volumes:
    - linkding_data:/etc/linkding/data
  
  environment:
    - LD_SUPERUSER_NAME=${LINKDING_SUPERUSER_NAME:-admin}
    - LD_SUPERUSER_PASSWORD=${LINKDING_SUPERUSER_PASSWORD}
    - LD_DISABLE_BACKGROUND_TASKS=False
    - LD_DISABLE_URL_VALIDATION=False
```

#### Key Features Implemented

1. **Persistent Data Storage**
   - SQLite database stored in Docker volume `linkding_data`
   - Automatic data persistence across container restarts
   - Included in Duplicati backup jobs

2. **Network Configuration**
   - Connected to frontend network for external access
   - Connected to backend network for internal communication
   - Port 9091 exposed for local access

3. **Security Configuration**
   - Admin user configured via environment variables
   - Password protection enabled
   - URL validation enabled for bookmark integrity

4. **External Access**
   - Cloudflare tunnel routing: `bookmarks.${DOMAIN}` → `http://linkding:9090`
   - HTTPS access with automatic SSL termination
   - No port forwarding required

#### Environment Variables

```bash
# In .env file
LINKDING_SUPERUSER_NAME=admin
LINKDING_SUPERUSER_PASSWORD=your-secure-password
```

### Actual Budget Personal Finance Manager

#### Service Configuration

```yaml
actual:
  image: actualbudget/actual-server:latest
  container_name: actual
  restart: unless-stopped
  
  networks:
    - frontend
  
  ports:
    - "5006:5006"
  
  volumes:
    - actual_data:/data
  
  environment:
    - ACTUAL_PASSWORD=${ACTUAL_PASSWORD}
```

#### Key Features Implemented

1. **Secure Data Storage**
   - Encrypted data storage in Docker volume `actual_data`
   - Server password protection
   - Included in Duplicati backup jobs

2. **Network Configuration**
   - Connected to frontend network for external access
   - Port 5006 exposed for local access

3. **Security Configuration**
   - Server password protection
   - Data encryption at rest
   - Secure HTTPS access via tunnel

4. **External Access**
   - Cloudflare tunnel routing: `budget.${DOMAIN}` → `http://actual:5006`
   - HTTPS access with automatic SSL termination
   - Mobile app support

#### Environment Variables

```bash
# In .env file
ACTUAL_PASSWORD=your-secure-password
```

## Integration Points

### Monitoring Integration

Both services are integrated with the monitoring stack:

1. **Health Checks**
   - Docker health checks configured
   - Automatic restart on failure
   - Health status monitoring

2. **Logging**
   - Container logs collected by Promtail
   - Logs aggregated in Loki
   - Searchable via Grafana

3. **Metrics**
   - Container metrics via cAdvisor
   - Resource usage monitoring
   - Performance dashboards in Grafana

### Backup Integration

Both services are included in the Duplicati backup configuration:

```yaml
# In docker-compose.yml - duplicati service volumes
volumes:
  - linkding_data:/source/linkding:ro
  - actual_data:/source/actual:ro
```

#### Backup Features

1. **Automated Backups**
   - Scheduled backups via Duplicati
   - Incremental backup strategy
   - Encryption and deduplication

2. **Data Protection**
   - Database files backed up
   - Configuration preserved
   - Restoration procedures documented

### Dashboard Integration

Both services are included in the Dashy dashboard:

```yaml
# In config/dashy/conf-simple.yml
- name: Applications
  items:
    - title: Linkding
      description: Bookmark Manager
      icon: hl-linkding
      url: http://localhost:9091
      statusCheck: true
      
    - title: Actual Budget
      description: Personal Finance
      icon: hl-actual
      url: http://localhost:5006
      statusCheck: true
```

### Tunnel Integration

Both services are configured in the Cloudflare tunnel:

```yaml
# In config/cloudflared/config.yml
ingress:
  - hostname: bookmarks.${DOMAIN}
    service: http://linkding:9090
  - hostname: budget.${DOMAIN}
    service: http://actual:5006
```

## Configuration Files Created

### Linkding Configuration

1. **config/linkding/README.md** - Service documentation
2. **config/linkding/setup-linkding.ps1** - Setup and management script
3. **scripts/validate-linkding.ps1** - Validation script

### Actual Budget Configuration

1. **config/actual/README.md** - Service documentation
2. **config/actual/setup-actual.ps1** - Setup and management script
3. **scripts/validate-actual.ps1** - Validation script

## Deployment Instructions

### Prerequisites

1. Docker and Docker Compose installed
2. Environment variables configured in `.env` file
3. Cloudflare tunnel configured and running

### Deployment Steps

1. **Start Services**
   ```bash
   docker-compose up -d linkding actual
   ```

2. **Verify Health**
   ```bash
   docker ps --filter "name=linkding"
   docker ps --filter "name=actual"
   ```

3. **Test Access**
   - Local Linkding: http://localhost:9091
   - Local Actual: http://localhost:5006
   - External Linkding: https://bookmarks.${DOMAIN}
   - External Actual: https://budget.${DOMAIN}

4. **Configure Services**
   - Log into Linkding with admin credentials
   - Set up Actual Budget with server password
   - Import existing data if needed

## Usage Instructions

### Linkding Bookmark Manager

1. **Initial Setup**
   - Access https://bookmarks.${DOMAIN}
   - Log in with admin credentials from .env
   - Configure browser extension (optional)

2. **Adding Bookmarks**
   - Use web interface to add bookmarks manually
   - Install browser extension for one-click saving
   - Import bookmarks from browser export

3. **Organization**
   - Use tags to categorize bookmarks
   - Create descriptions for better searchability
   - Use search functionality to find bookmarks

### Actual Budget Personal Finance Manager

1. **Initial Setup**
   - Access https://budget.${DOMAIN}
   - Enter server password from .env
   - Create your first budget file

2. **Account Setup**
   - Add bank accounts and credit cards
   - Set up budget categories
   - Configure account types and balances

3. **Transaction Management**
   - Import historical transactions (CSV/OFX)
   - Set up categorization rules
   - Regular transaction entry and reconciliation

4. **Mobile Access**
   - Install Actual Budget mobile app
   - Connect to https://budget.${DOMAIN}
   - Sync data across devices

## Troubleshooting

### Common Issues

1. **Service Not Starting**
   - Check Docker logs: `docker logs linkding` or `docker logs actual`
   - Verify environment variables in .env
   - Check port conflicts

2. **External Access Issues**
   - Verify Cloudflare tunnel is running
   - Check tunnel configuration in config/cloudflared/config.yml
   - Verify DNS settings

3. **Data Loss Prevention**
   - Verify backup jobs in Duplicati
   - Test restoration procedures
   - Monitor volume health

### Validation Scripts

Use the provided validation scripts to check service health:

```powershell
# Linkding validation
./scripts/validate-linkding.ps1 -Detailed

# Actual Budget validation
./scripts/validate-actual.ps1 -Detailed
```

## Security Considerations

1. **Access Control**
   - Strong passwords configured via environment variables
   - HTTPS-only access via Cloudflare tunnel
   - No direct port exposure to internet

2. **Data Protection**
   - Encrypted data storage (Actual Budget)
   - Regular automated backups
   - Secure tunnel communication

3. **Network Security**
   - Isolated Docker networks
   - Internal communication only where needed
   - Firewall protection via Cloudflare

## Maintenance

### Regular Tasks

1. **Monitor Service Health**
   - Check Grafana dashboards
   - Review container logs
   - Verify backup completion

2. **Update Services**
   - Pull latest container images
   - Test updates in staging environment
   - Update documentation as needed

3. **Backup Verification**
   - Test backup restoration periodically
   - Verify backup integrity
   - Update retention policies as needed

## Conclusion

The productivity applications (Linkding and Actual Budget) have been successfully integrated into the homelab infrastructure with:

- ✅ Secure external access via Cloudflare tunnel
- ✅ Persistent data storage with Docker volumes
- ✅ Automated backup integration
- ✅ Health monitoring and logging
- ✅ Dashboard integration for easy access
- ✅ Comprehensive documentation and management scripts

Both services are ready for production use and provide essential personal productivity tools within the secure homelab environment.