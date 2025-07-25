# Actual Budget Personal Finance Manager Configuration

This directory contains configuration files for the Actual Budget personal finance management service.

## Overview

Actual Budget is a self-hosted personal finance manager that provides:
- Budget tracking and planning
- Transaction categorization
- Account synchronization
- Financial reporting and analytics
- Mobile app support
- Bank import capabilities

## Configuration

### Environment Variables

The following environment variables are configured in the main `.env` file:

- `ACTUAL_PASSWORD`: Server password for accessing the budget data

### Service Configuration

- **Container**: `actualbudget/actual-server:latest`
- **Internal Port**: 5006
- **External Port**: 5006
- **Data Volume**: `actual_data:/data`
- **Networks**: frontend
- **External Access**: https://budget.${DOMAIN}

### Features Enabled

- Secure data storage with encryption
- Multi-device synchronization
- Budget file management
- Transaction import/export
- Health check monitoring
- Automatic backup integration via Duplicati

## Access

- **Web Interface**: https://budget.${DOMAIN}
- **Local Access**: http://localhost:5006
- **Server Password**: (password from .env)

## Data Persistence

- Database: SQLite stored in Docker volume `actual_data`
- Budget Files: Stored in `/data` inside container
- Backup: Included in Duplicati backup jobs
- Encryption: Data encrypted at rest

## Health Monitoring

- Health check endpoint: `/`
- Container health monitoring
- Grafana dashboard: Included in monitoring stack

## Mobile App

Actual Budget supports mobile apps:
- iOS: Available in App Store
- Android: Available in Google Play Store
- Configuration: Use https://budget.${DOMAIN} as server URL

## Bank Integration

Actual Budget supports bank account synchronization:
- Manual CSV import
- OFX/QFX file import
- API integration (where supported)
- Transaction categorization rules

## Backup and Security

- Automatic backups via Duplicati
- Data encryption at rest
- Secure HTTPS access via Cloudflare tunnel
- No external dependencies for core functionality

## Usage Tips

1. **Initial Setup**: Create your first budget file after accessing the web interface
2. **Account Setup**: Add your bank accounts and credit cards
3. **Category Setup**: Create budget categories that match your spending patterns
4. **Transaction Import**: Import historical transactions via CSV or OFX files
5. **Budget Planning**: Set monthly budget amounts for each category
6. **Regular Monitoring**: Check progress regularly and adjust budgets as needed