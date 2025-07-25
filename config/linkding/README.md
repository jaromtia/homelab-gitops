# Linkding Bookmark Manager Configuration

This directory contains configuration files for the Linkding bookmark manager service.

## Overview

Linkding is a self-hosted bookmark manager that provides:
- Web-based bookmark management interface
- Tagging and search functionality
- Import/export capabilities
- REST API for automation
- Browser extension support

## Configuration

### Environment Variables

The following environment variables are configured in the main `.env` file:

- `LINKDING_SUPERUSER_NAME`: Admin username (default: admin)
- `LINKDING_SUPERUSER_PASSWORD`: Admin password (set in .env)

### Service Configuration

- **Container**: `sissbruecker/linkding:latest`
- **Internal Port**: 9090
- **External Port**: 9091
- **Data Volume**: `linkding_data:/etc/linkding/data`
- **Networks**: frontend, backend
- **External Access**: https://bookmarks.${DOMAIN}

### Features Enabled

- Background tasks for bookmark processing
- URL validation for bookmark integrity
- Persistent SQLite database storage
- Health check monitoring
- Automatic backup integration via Duplicati

## Access

- **Web Interface**: https://bookmarks.${DOMAIN}
- **Local Access**: http://localhost:9091
- **Default Credentials**: admin / (password from .env)

## Data Persistence

- Database: SQLite stored in Docker volume `linkding_data`
- Backup: Included in Duplicati backup jobs
- Location: `/etc/linkding/data` inside container

## Health Monitoring

- Health check endpoint: `/health`
- Prometheus metrics: Available for monitoring integration
- Grafana dashboard: Included in monitoring stack

## Browser Extension

Linkding supports browser extensions for easy bookmark saving:
- Chrome/Edge: Available in Chrome Web Store
- Firefox: Available in Firefox Add-ons
- Configuration: Use https://bookmarks.${DOMAIN} as server URL

## API Access

REST API available at: https://bookmarks.${DOMAIN}/api/
- Authentication: Token-based
- Documentation: Available in web interface under Settings