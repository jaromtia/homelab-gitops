# HomeLab Infrastructure

A comprehensive containerized homelab infrastructure using Docker Compose with locally managed Cloudflare tunnels for secure external access.

## Architecture

This homelab uses a modern, secure architecture with:

- **Locally Managed Cloudflare Tunnels**: Secure external access without port forwarding or reverse proxy complexity
- **Direct Service Routing**: Services are accessed directly through Cloudflare tunnels without intermediate proxy layers
- **Comprehensive Monitoring**: Prometheus, Grafana, and Loki stack for observability
- **Automated Backups**: Duplicati for encrypted, deduplicated backups
- **Container Management**: Portainer for Docker container management
- **Productivity Apps**: Linkding for bookmarks, Actual Budget for finance management
- **File Management**: FileBrowser for web-based file access

## Services

| Service | Purpose | Local URL | External URL | Default Credentials |
|---------|---------|-----------|--------------|-------------------|
| Dashy | Centralized dashboard | http://localhost:80 | https://dashboard.yourdomain.com | No authentication |
| Grafana | Monitoring dashboards | http://localhost:3000 | https://grafana.yourdomain.com | admin / (see .env GRAFANA_ADMIN_PASSWORD) |
| Prometheus | Metrics collection | http://localhost:9090 | https://prometheus.yourdomain.com | No authentication |
| Portainer | Container management | http://localhost:9000 | https://portainer.yourdomain.com | Setup on first visit |
| FileBrowser | File management | http://localhost:8082 | https://files.yourdomain.com | admin / admin |
| Linkding | Bookmark manager | http://localhost:9090 | https://bookmarks.yourdomain.com | admin / (see .env LINKDING_SUPERUSER_PASSWORD) |
| Actual Budget | Personal finance | http://localhost:5006 | https://budget.yourdomain.com | Password: (see .env ACTUAL_PASSWORD) |
| Duplicati | Backup management | http://localhost:8200 | https://backup.yourdomain.com | Setup on first visit |

## 🔑 Quick Access (Current Deployment)

| Service | URL | Username | Password | Status |
|---------|-----|----------|----------|--------|
| FileBrowser | http://localhost:8082 | `admin` | `4EdsdIyxhDGxOaAA` | ✅ Ready |
| Portainer | http://localhost:9000 | *setup required* | *setup required* | ⚠️ Setup needed |
| Prometheus | http://localhost:9090 | *none* | *none* | ✅ Ready |
| Grafana | http://localhost:3000 | `admin` | *check .env* | ❌ Not running |

**💡 Tip**: Run `docker-compose logs filebrowser | Select-String "randomly generated password"` to get the current FileBrowser password.

## Quick Start

### Fresh Installation

1. **Clone and Setup**
   ```bash
   git clone https://github.com/jaromtia/homelab-gitops.git
   cd homelab-infrastructure
   cp .env.template .env
   ```

2. **Configure Environment**
   Edit `.env` file with your domain and credentials

3. **Setup Cloudflare Tunnel**
   - Create a tunnel in Cloudflare dashboard
   - Copy credentials to `config/cloudflared/credentials.json`
   - Update `config/cloudflared/config.yml` with your tunnel ID and domain

4. **Deploy with GitHub Integration**
   ```powershell
   # Fresh deployment with GitHub sync
   .\scripts\deploy-with-github.ps1 -Mode fresh -SyncToGitHub
   
   # Or traditional deployment
   docker-compose up -d
   ```

### Restore from GitHub

If you have an existing configuration in GitHub:

```powershell
# Restore complete configuration from GitHub
.\scripts\restore-from-github.ps1

# Deploy after restoration
.\scripts\deploy-with-github.ps1 -Mode restore
```

## Service Access & Authentication

### Local Testing (Without Cloudflare Tunnel)

For local testing, you can access services directly:

```powershell
# Start core services for testing
docker-compose up -d prometheus grafana portainer filebrowser

# Test service availability
Invoke-WebRequest -Uri "http://localhost:9090" -UseBasicParsing  # Prometheus
Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing  # Grafana
Invoke-WebRequest -Uri "http://localhost:9000" -UseBasicParsing  # Portainer
Invoke-WebRequest -Uri "http://localhost:8082" -UseBasicParsing  # FileBrowser

# Open services in browser
Start-Process "http://localhost:9090"   # Prometheus
Start-Process "http://localhost:3000"   # Grafana
Start-Process "http://localhost:9000"   # Portainer
Start-Process "http://localhost:8082"   # FileBrowser
```

### Default Credentials

**Important**: Update these default passwords in your `.env` file before deployment!

#### FileBrowser (http://localhost:8082)
- **Username**: `admin`
- **Password**: **Check container logs for generated password**
- **How to find password**: Run `docker-compose logs filebrowser | grep "randomly generated password"`
- **Example**: `User 'admin' initialized with randomly generated password: 4EdsdIyxhDGxOaAA`
- **Note**: Password is randomly generated on first startup

#### Grafana (http://localhost:3000)
- **Username**: `admin`
- **Password**: Set in `.env` as `GRAFANA_ADMIN_PASSWORD`
- **Default**: If not set, uses `admin`

#### Portainer (http://localhost:9000)
- **Setup**: Create admin user on first visit (within 5 minutes of startup)
- **Username**: Choose during setup
- **Password**: Choose during setup (minimum 12 characters)
- **Note**: If setup times out, restart the container to get a new 5-minute window

#### Linkding (http://localhost:9090)
- **Username**: Set in `.env` as `LINKDING_SUPERUSER_NAME` (default: `admin`)
- **Password**: Set in `.env` as `LINKDING_SUPERUSER_PASSWORD`

#### Actual Budget (http://localhost:5006)
- **Authentication**: Single password
- **Password**: Set in `.env` as `ACTUAL_PASSWORD`

#### Duplicati (http://localhost:8200)
- **Setup**: Configure password on first visit
- **Password**: Set in `.env` as `DUPLICATI_PASSWORD`

#### Prometheus (http://localhost:9090)
- **Authentication**: None (read-only metrics interface)

#### Dashy (http://localhost:80)
- **Authentication**: None by default
- **Configuration**: Edit `config/dashy/conf.yml` for custom settings

### Environment Variables for Authentication

Update these in your `.env` file:

```bash
# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=your-secure-password

# FileBrowser  
FILEBROWSER_ADMIN_USER=admin
FILEBROWSER_ADMIN_PASSWORD=your-secure-password

# Linkding
LINKDING_SUPERUSER_NAME=admin
LINKDING_SUPERUSER_PASSWORD=your-secure-password

# Actual Budget
ACTUAL_PASSWORD=your-secure-password

# Duplicati
DUPLICATI_PASSWORD=your-secure-password

# Portainer (set during first-time setup)
PORTAINER_ADMIN_PASSWORD=your-secure-password
```

## Key Features

### Secure External Access
- **No Port Forwarding**: All external access through Cloudflare tunnels
- **Automatic SSL**: Cloudflare handles SSL termination and certificate management
- **DDoS Protection**: Built-in protection through Cloudflare's global network
- **Local Control**: Full control over tunnel configuration and routing

### Monitoring & Observability
- **Metrics**: Prometheus collects metrics from all services
- **Visualization**: Grafana provides comprehensive dashboards
- **Logging**: Loki aggregates logs from all containers
- **Alerting**: Configurable alerts for system health

### Data Protection
- **Automated Backups**: Scheduled backups with Duplicati
- **Version Control**: All configurations stored in Git
- **Data Persistence**: Docker volumes for all critical data
- **Disaster Recovery**: Complete infrastructure recreation from code

## Configuration

### Environment Variables
Key variables in `.env`:
- `DOMAIN`: Your domain name for external access
- `GRAFANA_ADMIN_PASSWORD`: Grafana admin password
- `LINKDING_SUPERUSER_PASSWORD`: Linkding admin password
- `ACTUAL_PASSWORD`: Actual Budget password

### Cloudflare Tunnel Setup
See `config/cloudflared/README.md` for detailed setup instructions.

## Security

- All services run in isolated Docker networks
- Sensitive credentials excluded from version control
- Cloudflare provides DDoS protection and access policies
- Regular security updates through container image updates

## GitHub Integration

This homelab includes comprehensive GitHub integration for configuration management and deployment automation.

### Configuration Management

```powershell
# Save current configuration to GitHub
.\scripts\git-ops.ps1 save "Updated monitoring configuration"

# Load latest configuration from GitHub
.\scripts\git-ops.ps1 load

# Check repository status
.\scripts\git-ops.ps1 status

# Initialize Git repository
.\scripts\git-ops.ps1 setup
```

### Automated Deployment

```powershell
# Fresh deployment with GitHub sync
.\scripts\deploy-with-github.ps1 -Mode fresh -SyncToGitHub

# Update existing deployment
.\scripts\deploy-with-github.ps1 -Mode update

# Restore from GitHub repository
.\scripts\deploy-with-github.ps1 -Mode restore
```

### Configuration Backup Strategy

- **Configuration Files**: Automatically synced to GitHub repository
- **Service Data**: Backed up via Duplicati to configured storage
- **Secrets**: Excluded from Git, stored in `.env` file (not synced)
- **Restoration**: Complete infrastructure recreation from GitHub + data restore

## Maintenance

### Updates
```powershell
# Update with GitHub integration
.\scripts\deploy-with-github.ps1 -Mode update -SyncToGitHub

# Traditional update
docker-compose pull
docker-compose up -d
```

### Configuration Backups
```powershell
# Manual configuration backup to GitHub
.\scripts\git-ops.ps1 save "Manual backup before changes"

# Automated data backups via Duplicati
docker-compose exec duplicati duplicati-cli backup
```

### Monitoring
Access Grafana dashboards to monitor system health and performance.

## Troubleshooting

### Authentication Issues

#### FileBrowser Login Problems
FileBrowser generates a random password on first startup:

1. **Find the generated password**:
   ```bash
   docker-compose logs filebrowser | grep "randomly generated password"
   ```
   Look for: `User 'admin' initialized with randomly generated password: XXXXXXXXX`

2. **If you can't find the password, reset FileBrowser**:
   ```bash
   docker-compose down
   docker volume rm homelab_filebrowser_data
   docker-compose up -d filebrowser
   # Then check logs again for the new password
   docker-compose logs filebrowser | grep "randomly generated password"
   ```

3. **Change the password after login**:
   - Login with admin and the generated password
   - Go to Settings → User Management
   - Change the admin password to something memorable

#### Grafana Login Issues
1. Check environment variables are loaded:
   ```bash
   docker-compose exec grafana env | grep GRAFANA
   ```
2. Reset admin password:
   ```bash
   docker-compose exec grafana grafana-cli admin reset-admin-password newpassword
   ```

#### Portainer Setup Issues
1. If setup screen doesn't appear, reset Portainer:
   ```bash
   docker-compose down
   docker volume rm homelab_portainer_data
   docker-compose up -d portainer
   ```
2. Access http://localhost:9000 within 5 minutes of first start

### Service Access Issues

#### Service Not Responding
1. Check service status:
   ```bash
   docker-compose ps
   ```
2. Check service logs:
   ```bash
   docker-compose logs <service-name>
   ```
3. Restart specific service:
   ```bash
   docker-compose restart <service-name>
   ```

#### Port Conflicts
If ports are already in use:
1. Check what's using the port:
   ```bash
   netstat -ano | findstr :9090
   ```
2. Stop conflicting services or change ports in `docker-compose.yml`

### Current Working Credentials

**⚠️ IMPORTANT: These are the actual working credentials for your current deployment**

#### FileBrowser (http://localhost:8082)
- **Username**: `admin`
- **Password**: `4EdsdIyxhDGxOaAA` (randomly generated)

#### Portainer (http://localhost:9000)
- **Status**: Ready for initial setup
- **Action**: Visit http://localhost:9000 to create your admin account
- **Note**: Must complete setup within 5 minutes of container start

#### Prometheus (http://localhost:9090)
- **Authentication**: None required
- **Status**: ✅ Ready to use

### Quick Commands for Service Access

#### Get All Service Credentials
```powershell
# Get FileBrowser password
docker-compose logs filebrowser | Select-String "randomly generated password"

# Check service status
docker-compose ps

# Open services in browser
Start-Process "http://localhost:8082"  # FileBrowser (use admin + password above)
Start-Process "http://localhost:9000"  # Portainer (setup required)
Start-Process "http://localhost:9090"  # Prometheus (no auth needed)
```

#### Reset Portainer Setup
```powershell
# If Portainer setup timed out, reset it
docker-compose restart portainer
# Then access http://localhost:9000 within 5 minutes
```

#### Check Service Status
```powershell
# Check all services
docker-compose ps

# Check specific service logs
docker-compose logs filebrowser
docker-compose logs portainer
docker-compose logs grafana
```

### Testing Services

Use the provided testing script:
```powershell
.\test-services.ps1
```

Or test manually:
```powershell
# Check all services
docker-compose ps

# Test HTTP endpoints
Invoke-WebRequest -Uri "http://localhost:9090" -UseBasicParsing
Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing
Invoke-WebRequest -Uri "http://localhost:9000" -UseBasicParsing
Invoke-WebRequest -Uri "http://localhost:8082" -UseBasicParsing
```

## Support

For issues and questions:
1. Check service logs: `docker-compose logs <service-name>`
2. Verify tunnel status: `docker logs cloudflared`
3. Review configuration files in `config/` directory
4. Check the troubleshooting section above
5. Verify environment variables in `.env` file
