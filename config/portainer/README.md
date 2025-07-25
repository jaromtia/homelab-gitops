# Portainer Configuration

This directory contains configuration files for Portainer, the container management interface.

## Overview

Portainer provides a web-based interface for managing Docker containers, images, networks, and volumes. It offers:

- Container monitoring and control capabilities
- Real-time log viewing and resource monitoring
- Container restart and management features
- Docker socket access for full container management

## Configuration Files

- `setup-portainer.ps1` - Initial setup script for Portainer
- `portainer-config.json` - Portainer configuration settings
- `manage-containers.ps1` - Container management utilities
- `monitoring-dashboard.json` - Custom monitoring dashboard configuration

## Access Information

- **URL**: http://localhost:9000 (local) or https://portainer.yourdomain.com (via Cloudflare tunnel)
- **Default Admin**: Set during first login
- **Docker Socket**: Read-only access to /var/run/docker.sock

## Features

### Container Management (Requirement 9.1, 9.2)
- View all running containers and their status
- Start, stop, restart, and remove containers
- Container resource monitoring and control

### Log Viewing (Requirement 9.3)
- Real-time container log streaming
- Log search and filtering capabilities
- Historical log access

### Resource Monitoring (Requirement 9.4)
- CPU, memory, and network usage monitoring
- Container performance metrics
- Resource allocation and limits management

## Security Considerations

- Docker socket is mounted as read-only for security
- Access control through Portainer's built-in authentication
- Network isolation through Docker networks
- Secure external access via Cloudflare tunnel

## Backup Integration

Portainer data is automatically backed up by Duplicati:
- Configuration data: `/data` volume
- User settings and preferences
- Custom templates and configurations