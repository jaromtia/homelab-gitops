# Traefik Configuration

This directory contains the Traefik reverse proxy configuration with automatic SSL certificate management using Let's Encrypt.

## Files Structure

```
config/traefik/
├── traefik.yml              # Static configuration
├── dynamic/
│   ├── tls.yml             # TLS options and certificate settings
│   └── middleware.yml      # HTTP middleware definitions
├── ssl-monitor.service     # Systemd service for SSL monitoring
└── README.md              # This file
```

## Configuration Overview

### Static Configuration (traefik.yml)

The static configuration defines:
- **Entry Points**: HTTP (80), HTTPS (443), and Dashboard (8080)
- **Providers**: Docker provider for service discovery and file provider for dynamic config
- **Certificate Resolvers**: Let's Encrypt ACME configuration
- **Logging**: Structured JSON logging with access logs
- **Metrics**: Prometheus metrics endpoint
- **API**: Dashboard and API access

### Dynamic Configuration

#### TLS Configuration (dynamic/tls.yml)
- **TLS Options**: Modern TLS 1.2/1.3 configuration with secure cipher suites
- **Certificate Stores**: Default certificate storage configuration
- **Security**: SNI strict mode and secure curve preferences

#### Middleware Configuration (dynamic/middleware.yml)
- **Security Headers**: HSTS, CSP, and other security headers
- **Rate Limiting**: Request rate limiting to prevent abuse
- **Authentication**: Basic auth for Traefik dashboard
- **CORS**: Cross-origin resource sharing configuration
- **Compression**: Response compression middleware
- **Error Pages**: Custom error page handling

## Environment Variables

Required environment variables (set in `.env` file):

```bash
# Domain configuration
DOMAIN=your-domain.com
ACME_EMAIL=your-email@example.com

# Traefik dashboard authentication
TRAEFIK_DASHBOARD_USER=admin
TRAEFIK_DASHBOARD_PASSWORD_HASH=your-hashed-password

# Network configuration
DOCKER_SUBNET=172.20.0.0/16
```

### Generating Password Hash

To generate a password hash for the Traefik dashboard:

```bash
# Using htpasswd
htpasswd -nb admin your-password

# Using openssl
echo $(htpasswd -nb admin your-password) | sed -e s/\\$/\\$\\$/g

# Using Python
python3 -c "import bcrypt; print(bcrypt.hashpw(b'your-password', bcrypt.gensalt()).decode())"
```

## SSL Certificate Management

### Automatic Certificate Generation

Traefik automatically generates SSL certificates using Let's Encrypt ACME protocol:

1. **HTTP Challenge**: Default method using HTTP-01 challenge
2. **Certificate Storage**: Certificates stored in `/letsencrypt/acme.json`
3. **Auto-Renewal**: Certificates automatically renewed before expiration
4. **Multiple Domains**: Supports multiple domains and subdomains

### Certificate Storage

Certificates are stored in the `traefik_letsencrypt` Docker volume:
- **Location**: `/letsencrypt/acme.json` inside container
- **Format**: JSON format with encrypted private keys
- **Permissions**: File must have 600 permissions
- **Backup**: Automatically backed up by Duplicati

### Manual Certificate Operations

```bash
# Check certificate expiration
./scripts/ssl-health-check.sh check

# Force certificate renewal
./scripts/ssl-health-check.sh renew your-domain.com

# Monitor certificate status
./scripts/ssl-health-check.sh monitor
```

## Service Discovery

Traefik automatically discovers services using Docker labels:

### Basic Service Configuration

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

### Advanced Service Configuration

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      # Basic routing
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      
      # Service configuration
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
      - "traefik.http.services.myapp.loadbalancer.healthcheck.path=/health"
      - "traefik.http.services.myapp.loadbalancer.healthcheck.interval=30s"
      
      # Middleware
      - "traefik.http.routers.myapp.middlewares=security-headers,rate-limit"
      
      # Priority (higher number = higher priority)
      - "traefik.http.routers.myapp.priority=100"
```

## Health Monitoring

### Built-in Health Checks

Traefik provides several health endpoints:

- **Ping**: `http://localhost:8080/ping` - Basic health check
- **Dashboard**: `http://localhost:8080/dashboard/` - Web interface
- **API**: `http://localhost:8080/api/` - REST API
- **Metrics**: `http://localhost:8080/metrics` - Prometheus metrics

### SSL Certificate Monitoring

The included SSL health check script monitors certificate expiration:

```bash
# Run health check
./scripts/ssl-health-check.sh

# Continuous monitoring
./scripts/ssl-health-check.sh monitor

# Check specific domain
./scripts/ssl-health-check.sh -d example.com check
```

### Systemd Service (Linux)

For automated monitoring on Linux systems:

```bash
# Copy service file
sudo cp config/traefik/ssl-monitor.service /etc/systemd/system/

# Edit environment variables
sudo systemctl edit ssl-monitor.service

# Enable and start service
sudo systemctl enable ssl-monitor.service
sudo systemctl start ssl-monitor.service

# Check status
sudo systemctl status ssl-monitor.service
```

## Troubleshooting

### Common Issues

1. **Certificate Generation Fails**
   - Check domain DNS resolution
   - Verify ports 80/443 are accessible
   - Check ACME email configuration
   - Review Traefik logs: `docker logs traefik`

2. **Service Not Accessible**
   - Verify service labels are correct
   - Check if service is in the correct network
   - Confirm service port configuration
   - Check Traefik dashboard for service status

3. **Dashboard Not Accessible**
   - Verify password hash is correct
   - Check if port 8080 is exposed
   - Confirm middleware configuration

### Log Analysis

```bash
# View Traefik logs
docker logs traefik -f

# View access logs
docker exec traefik tail -f /var/log/traefik/access.log

# View error logs
docker exec traefik tail -f /var/log/traefik/traefik.log

# Check certificate renewal logs
grep -i "acme\|certificate" /var/log/traefik/traefik.log
```

### Testing Configuration

Run the comprehensive test suite:

```bash
# Test all components
./scripts/test-traefik.sh

# Test specific domain
DOMAIN=your-domain.com ./scripts/test-traefik.sh
```

## Security Considerations

### Network Security

- **Internal Networks**: Backend services isolated from external access
- **Firewall**: Only ports 80, 443, and 8080 (internal) exposed
- **TLS**: Modern TLS configuration with secure cipher suites
- **Headers**: Security headers automatically added to responses

### Access Control

- **Dashboard**: Protected with basic authentication
- **API**: Restricted to authenticated users
- **Metrics**: Limited to internal network access
- **Certificates**: Stored with restricted permissions

### Monitoring

- **Access Logs**: All requests logged with client information
- **Error Tracking**: Failed requests and errors logged
- **Certificate Monitoring**: Automated certificate expiration alerts
- **Health Checks**: Continuous service health monitoring

## Performance Optimization

### Resource Limits

The Traefik container is configured with resource limits:
- **Memory**: 256MB limit, 128MB reservation
- **CPU**: 0.5 CPU limit, 0.25 CPU reservation

### Caching

- **Static Files**: Automatic compression for static content
- **Headers**: Appropriate caching headers set
- **Connection Pooling**: HTTP/2 and connection reuse enabled

### Load Balancing

- **Health Checks**: Automatic unhealthy backend removal
- **Sticky Sessions**: Available for stateful applications
- **Circuit Breaker**: Automatic failure detection and recovery