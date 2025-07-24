# Cloudflare Tunnel Configuration

This directory contains the configuration for locally managed Cloudflare tunnels, providing secure external access to all homelab services without port forwarding, reverse proxy requirements, or SSL certificate management.

## ✅ Implementation Status

This Cloudflare tunnel implementation is **COMPLETE** and includes:

- ✅ **Service Configuration**: Fully configured cloudflared service in Docker Compose
- ✅ **Ingress Rules**: Direct service routing for all homelab services
- ✅ **Health Monitoring**: Comprehensive health checks and automatic reconnection
- ✅ **Management Scripts**: Tunnel creation, DNS setup, and monitoring utilities
- ✅ **Metrics Integration**: Prometheus scraping for tunnel observability
- ✅ **Security Features**: Post-quantum cryptography and connection optimization

## Files

- `config.yml` - Main tunnel configuration with ingress rules and connection settings
- `credentials.json` - Tunnel credentials (not included in repository for security)
- `credentials.json.template` - Template for credentials file structure
- `healthcheck.sh` - Comprehensive health check script for tunnel monitoring
- `tunnel-manager.sh` - Management script for tunnel operations
- `tunnel-status.sh` - Simple status monitoring script
- `README.md` - This documentation file

## Quick Setup Guide

### Prerequisites

1. **Install cloudflared CLI**:
   ```bash
   # On macOS
   brew install cloudflared
   
   # On Linux
   wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
   sudo dpkg -i cloudflared-linux-amd64.deb
   
   # On Windows
   # Download from: https://github.com/cloudflare/cloudflared/releases
   ```

2. **Authenticate with Cloudflare**:
   ```bash
   cloudflared tunnel login
   ```

### Method 1: Automated Setup (Recommended)

Use the provided tunnel management script:

```bash
# Make script executable (Linux/macOS)
chmod +x config/cloudflared/tunnel-manager.sh

# Create a new tunnel
./config/cloudflared/tunnel-manager.sh create homelab

# Follow the displayed instructions for DNS setup
./config/cloudflared/tunnel-manager.sh setup-dns YOUR_TUNNEL_ID

# Update your .env file with your domain
echo "DOMAIN=your-domain.com" >> .env

# Start the tunnel
docker-compose up -d cloudflared
```

### Method 2: Manual Setup

1. **Create a Cloudflare Tunnel**:
   ```bash
   cloudflared tunnel create homelab
   ```

2. **Copy Credentials**:
   ```bash
   cp ~/.cloudflared/YOUR_TUNNEL_ID.json ./config/cloudflared/credentials.json
   chmod 600 ./config/cloudflared/credentials.json
   ```

3. **Update Configuration**:
   Edit `config.yml` and replace `YOUR_TUNNEL_ID` with your actual tunnel ID.

4. **Configure Environment**:
   ```bash
   cp .env.template .env
   # Edit .env and set DOMAIN=your-domain.com
   ```

5. **Setup DNS Records**:
   Create CNAME records in Cloudflare DNS:
   ```
   Name                    | Target                           | Type
   ----------------------- | -------------------------------- | -----
   your-domain.com         | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   dashboard.your-domain   | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   grafana.your-domain     | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   prometheus.your-domain  | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   portainer.your-domain   | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   files.your-domain       | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   bookmarks.your-domain   | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   budget.your-domain      | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   backup.your-domain      | YOUR_TUNNEL_ID.cfargotunnel.com | CNAME
   ```

## Configuration Features

### Enhanced Connection Settings

The tunnel configuration includes:

- **Automatic Reconnection**: Configurable retry logic with exponential backoff
- **Health Monitoring**: Metrics endpoint on port 8080 for Prometheus integration
- **Connection Pooling**: Optimized connection management for better performance
- **Protocol Optimization**: QUIC protocol for improved performance and reliability
- **Post-Quantum Cryptography**: Future-proofing with quantum-resistant encryption

### Service-Specific Optimizations

Each service has tailored connection settings:

- **File Management**: Extended timeouts for large file operations
- **Monitoring Services**: Optimized keep-alive settings for real-time data
- **Backup Services**: Increased timeouts for backup operations
- **Dashboard Services**: Fast connection settings for responsive UI

### Security Features

- **Direct Service Routing**: No intermediate proxy layers
- **Automatic SSL/TLS**: Cloudflare handles certificate management
- **DDoS Protection**: Built-in protection through Cloudflare's global network
- **Access Control**: Optional integration with Cloudflare Access policies
- **Credential Security**: Encrypted credential storage with proper file permissions

## Service Access URLs

Once configured, all services are accessible via HTTPS:

| Service | URL | Description |
|---------|-----|-------------|
| **Main Dashboard** | `https://your-domain.com` | Primary entry point |
| **Dashboard** | `https://dashboard.your-domain.com` | Dashy service dashboard |
| **Grafana** | `https://grafana.your-domain.com` | Monitoring and visualization |
| **Prometheus** | `https://prometheus.your-domain.com` | Metrics collection |
| **Portainer** | `https://portainer.your-domain.com` | Container management |
| **File Browser** | `https://files.your-domain.com` | File management interface |
| **Linkding** | `https://bookmarks.your-domain.com` | Bookmark manager |
| **Actual Budget** | `https://budget.your-domain.com` | Personal finance |
| **Duplicati** | `https://backup.your-domain.com` | Backup management |

## Management Commands

### Using the Tunnel Manager Script

```bash
# List all available tunnels
./config/cloudflared/tunnel-manager.sh list

# Get tunnel information
./config/cloudflared/tunnel-manager.sh info

# Validate configuration
./config/cloudflared/tunnel-manager.sh validate

# Test connectivity
./config/cloudflared/tunnel-manager.sh test

# Monitor tunnel status
./config/cloudflared/tunnel-manager.sh monitor

# Cleanup tunnel (careful!)
./config/cloudflared/tunnel-manager.sh cleanup TUNNEL_ID
```

### Docker Commands

```bash
# Start tunnel service
docker-compose up -d cloudflared

# View tunnel logs
docker logs -f cloudflared

# Check tunnel health
docker exec cloudflared /etc/cloudflared/healthcheck.sh

# Restart tunnel service
docker-compose restart cloudflared

# Stop tunnel service
docker-compose stop cloudflared
```

## Monitoring and Health Checks

### Built-in Health Checks

The tunnel service includes comprehensive health monitoring:

1. **Process Health**: Verifies cloudflared daemon is running
2. **Metrics Endpoint**: Checks metrics availability on port 8080
3. **Configuration Validation**: Validates tunnel configuration syntax
4. **Connectivity Tests**: Verifies tunnel connection to Cloudflare edge
5. **Log Analysis**: Monitors for recent errors and connection issues

### Prometheus Integration

Tunnel metrics are automatically scraped by Prometheus:

- **Endpoint**: `http://cloudflared:8080/metrics`
- **Scrape Interval**: 30 seconds
- **Key Metrics**: Active streams, total requests, connection status

### Manual Health Checks

```bash
# Quick health check
docker exec cloudflared /etc/cloudflared/tunnel-status.sh health

# Get metrics in JSON format
docker exec cloudflared /etc/cloudflared/tunnel-status.sh metrics

# Comprehensive health check
docker exec cloudflared /etc/cloudflared/healthcheck.sh
```

## Troubleshooting

### Common Issues

1. **Tunnel Not Connecting**:
   ```bash
   # Check credentials
   docker exec cloudflared cat /etc/cloudflared/credentials.json
   
   # Validate configuration
   docker exec cloudflared cloudflared tunnel ingress validate /etc/cloudflared/config.yml
   
   # Check logs
   docker logs cloudflared
   ```

2. **DNS Resolution Issues**:
   ```bash
   # Test DNS resolution
   nslookup dashboard.your-domain.com
   
   # Check CNAME records
   dig dashboard.your-domain.com CNAME
   ```

3. **Service Not Accessible**:
   ```bash
   # Test internal connectivity
   docker exec cloudflared wget -qO- http://dashy:80
   
   # Check service health
   docker-compose ps
   ```

### Log Analysis

```bash
# View recent logs
docker logs --tail 50 cloudflared

# Follow logs in real-time
docker logs -f cloudflared

# Search for errors
docker logs cloudflared 2>&1 | grep -i error

# Check tunnel metrics
curl http://localhost:8080/metrics
```

### Performance Optimization

1. **Connection Tuning**: Adjust `max-upstream-conns` in config.yml
2. **Protocol Selection**: Switch between QUIC, HTTP/2, or HTTP/1.1
3. **Timeout Adjustment**: Modify service-specific timeout values
4. **Keep-Alive Settings**: Optimize connection persistence

## Security Best Practices

### Credential Management

- Store `credentials.json` with restricted permissions (600)
- Exclude credentials from version control
- Rotate tunnel credentials periodically
- Use separate tunnels for different environments

### Access Control

- Configure Cloudflare Access policies for sensitive services
- Use strong authentication for service interfaces
- Monitor access logs regularly
- Implement IP allowlisting if needed

### Network Security

- Keep cloudflared updated to latest version
- Monitor tunnel metrics for anomalies
- Use Cloudflare's security features (WAF, DDoS protection)
- Regular security audits of exposed services

## Advanced Configuration

### Custom Ingress Rules

Add custom services to `config.yml`:

```yaml
ingress:
  - hostname: custom.your-domain.com
    service: http://custom-service:8080
    originRequest:
      connectTimeout: 30s
      tlsTimeout: 10s
```

### Access Policies

Integrate with Cloudflare Access:

```yaml
ingress:
  - hostname: admin.your-domain.com
    service: http://admin-service:8080
    originRequest:
      access:
        required: true
        teamName: your-team
```

### Load Balancing

Configure multiple origins:

```yaml
ingress:
  - hostname: api.your-domain.com
    service: http://api-service:8080
    originRequest:
      loadBalancer:
        - http://api-1:8080
        - http://api-2:8080
```

## Support and Resources

- **Cloudflare Tunnel Documentation**: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
- **cloudflared CLI Reference**: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/
- **Tunnel Management API**: https://developers.cloudflare.com/api/operations/cloudflare-tunnel-list-cloudflare-tunnels
- **Community Support**: https://community.cloudflare.com/

## Benefits of This Implementation

### Operational Benefits

- **Zero Port Forwarding**: No firewall configuration required
- **Automatic SSL**: No certificate management overhead
- **Global CDN**: Improved performance through Cloudflare's edge network
- **Built-in Security**: DDoS protection and WAF capabilities
- **High Availability**: Automatic failover and redundancy

### Management Benefits

- **Infrastructure as Code**: All configuration version controlled
- **Easy Deployment**: Single command deployment across environments
- **Comprehensive Monitoring**: Built-in health checks and metrics
- **Automated Recovery**: Self-healing tunnel connections
- **Centralized Logging**: Unified log aggregation and analysis