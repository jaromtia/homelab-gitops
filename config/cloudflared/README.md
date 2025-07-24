# Cloudflare Tunnel Configuration

This directory contains the configuration for locally managed Cloudflare tunnels, providing secure external access to all homelab services without port forwarding or reverse proxy requirements.

## Files

- `config.yml` - Main tunnel configuration with ingress rules
- `credentials.json` - Tunnel credentials (not included in repository for security)

## Setup Instructions

### 1. Create a Cloudflare Tunnel

First, create a tunnel using the Cloudflare dashboard or CLI:

```bash
# Using cloudflared CLI
cloudflared tunnel create homelab
```

This will generate:
- A tunnel ID
- A credentials file (`credentials.json`)

### 2. Configure Tunnel Credentials

Copy the generated `credentials.json` file to this directory:

```bash
cp ~/.cloudflared/YOUR_TUNNEL_ID.json ./config/cloudflared/credentials.json
```

### 3. Update Configuration

Edit `config.yml` and replace:
- `YOUR_TUNNEL_ID` with your actual tunnel ID
- `${DOMAIN}` with your domain name

### 4. DNS Configuration

In your Cloudflare DNS settings, create CNAME records pointing to your tunnel:

```
dashboard.yourdomain.com -> YOUR_TUNNEL_ID.cfargotunnel.com
grafana.yourdomain.com   -> YOUR_TUNNEL_ID.cfargotunnel.com
prometheus.yourdomain.com -> YOUR_TUNNEL_ID.cfargotunnel.com
portainer.yourdomain.com -> YOUR_TUNNEL_ID.cfargotunnel.com
files.yourdomain.com     -> YOUR_TUNNEL_ID.cfargotunnel.com
bookmarks.yourdomain.com -> YOUR_TUNNEL_ID.cfargotunnel.com
budget.yourdomain.com    -> YOUR_TUNNEL_ID.cfargotunnel.com
backup.yourdomain.com    -> YOUR_TUNNEL_ID.cfargotunnel.com
```

## Security Notes

- The `credentials.json` file contains sensitive authentication data
- This file is excluded from version control via `.gitignore`
- Keep this file secure and backed up separately
- Rotate tunnel credentials periodically

## Service Access

Once configured, all services will be accessible via HTTPS through Cloudflare's global network:

- **Dashboard**: https://dashboard.yourdomain.com or https://yourdomain.com
- **Grafana**: https://grafana.yourdomain.com
- **Prometheus**: https://prometheus.yourdomain.com
- **Portainer**: https://portainer.yourdomain.com
- **File Browser**: https://files.yourdomain.com
- **Linkding**: https://bookmarks.yourdomain.com
- **Actual Budget**: https://budget.yourdomain.com
- **Duplicati**: https://backup.yourdomain.com

## Benefits of Local Management

- **Full Control**: Complete control over tunnel configuration and routing
- **No Reverse Proxy**: Direct service access without intermediate proxy layers
- **Automatic SSL**: Cloudflare handles SSL termination and certificate management
- **DDoS Protection**: Built-in protection through Cloudflare's global network
- **Access Policies**: Optional integration with Cloudflare Access for additional security
- **High Availability**: Automatic failover and load balancing through Cloudflare's edge network

## Troubleshooting

### Check Tunnel Status
```bash
docker logs cloudflared
```

### Test Tunnel Connectivity
```bash
cloudflared tunnel info YOUR_TUNNEL_ID
```

### Validate Configuration
```bash
cloudflared tunnel ingress validate /etc/cloudflared/config.yml
```

### Monitor Tunnel Health
The tunnel exposes metrics on port 8080 for monitoring:
```bash
curl http://localhost:8080/metrics
```