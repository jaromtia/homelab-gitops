# FileBrowser Configuration

This directory contains the configuration files and management scripts for the FileBrowser service in the homelab infrastructure.

## Overview

FileBrowser provides a web-based file management interface with the following features:

- **Web Interface**: Access files through a modern web browser
- **User Management**: Multiple users with granular permissions
- **Secure Sharing**: Create password-protected, time-limited file shares
- **File Operations**: Upload, download, rename, delete, and organize files
- **Search**: Find files quickly with built-in search functionality
- **Mobile Support**: Responsive design works on all devices

## Files

### Configuration Files

- `filebrowser.json` - Main FileBrowser configuration with security settings and defaults
- `security-config.json` - Extended security configuration including file type restrictions and sharing policies
- `docker-entrypoint.sh` - Container initialization script (Linux)
- `setup.sh` - Service setup script (Linux)

### Management Scripts

- `setup-filebrowser.ps1` - Initial setup and deployment script (Windows)
- `manage-users.ps1` - User management operations (Windows)
- `user-management.sh` - User management operations (Linux)

### Documentation

- `README.md` - This documentation file

## Quick Start

### 1. Initial Setup

Run the setup script to initialize FileBrowser:

```powershell
# Windows
.\config\filebrowser\setup-filebrowser.ps1

# Linux/macOS
./config/filebrowser/setup.sh
```

### 2. Access the Interface

- **Local**: http://localhost:8082
- **External**: https://files.yourdomain.com (via Cloudflare tunnel)

### 3. Default Credentials

- **Admin User**: admin
- **Admin Password**: Set via `FILEBROWSER_ADMIN_PASSWORD` environment variable

## User Management

### Adding Users

```powershell
# Windows
.\config\filebrowser\manage-users.ps1 -Action add-user -Username "john" -Password "password123"

# With custom permissions
.\config\filebrowser\manage-users.ps1 -Action add-user -Username "jane" -Password "secret" -Permissions @{admin=$false; share=$true; create=$true}
```

```bash
# Linux/macOS
./config/filebrowser/user-management.sh add-user john password123
./config/filebrowser/user-management.sh add-user jane secret --perm.admin=false --perm.share=true
```

### Managing Permissions

Available permissions:
- `admin` - Administrative privileges
- `create` - Create files and folders
- `delete` - Delete files and folders
- `modify` - Edit files
- `rename` - Rename files and folders
- `share` - Create file shares
- `download` - Download files

### Default Users

The system creates three default users:

1. **admin** - Full administrative access
2. **user** - Standard user with personal directory
3. **guest** - Read-only access to public files

## File Sharing

### Creating Shares

1. Navigate to the file in the web interface
2. Right-click and select "Share"
3. Configure share settings:
   - Expiration date
   - Password protection
   - Download limits

### Share Types

- **Public**: Accessible to anyone with the link
- **Private**: Requires authentication
- **Collaboration**: Allows uploads from recipients

### Managing Shares

```powershell
# Windows
.\config\filebrowser\manage-users.ps1 -Action create-share -Username "john" -FilePath "/srv/shared/document.pdf" -Expires "7d"
.\config\filebrowser\manage-users.ps1 -Action list-shares
```

## Directory Structure

```
/srv/                    # Root directory
├── public/             # Public files (guest accessible)
├── shared/             # Shared files between users
├── users/              # Personal user directories
│   ├── user/          # Standard user directory
│   └── john/          # Custom user directory
├── uploads/           # Temporary upload area
└── .quarantine/       # Quarantined files (security)
```

## Security Features

### File Type Restrictions

- **Allowed**: Documents, images, videos, archives, code files
- **Blocked**: Executables, scripts, potentially dangerous files
- **Scanning**: Uploaded files are scanned for security

### Access Controls

- User-based permissions
- Directory-level access control
- Session management with timeouts
- Failed login protection

### Sharing Security

- Password protection available
- Expiration dates enforced
- Download tracking and limits
- Secure link generation

## Backup Integration

FileBrowser data is automatically backed up by Duplicati:

- **Database**: User accounts and settings
- **Configuration**: Service configuration files
- **User Files**: Optional (configure in Duplicati)

## Monitoring

### Health Checks

- Container health monitoring
- Service availability checks
- Resource usage tracking

### Metrics

- Prometheus metrics endpoint: `/metrics`
- User activity tracking
- File operation statistics

### Logs

- Application logs: Docker container logs
- Audit logs: `/var/log/filebrowser-audit.log`
- Access logs: Integrated with monitoring stack

## Troubleshooting

### Common Issues

1. **Container won't start**
   ```bash
   docker-compose logs filebrowser
   ```

2. **Can't access web interface**
   - Check port 8082 is not blocked
   - Verify container is running: `docker ps`

3. **Permission denied errors**
   - Check file permissions in data directory
   - Verify user has correct scope settings

4. **Shares not working**
   - Check Cloudflare tunnel configuration
   - Verify external domain is accessible

### Reset Configuration

To reset FileBrowser to default settings:

```bash
# Stop container
docker-compose stop filebrowser

# Remove database volume
docker volume rm homelab_filebrowser_data

# Restart container
docker-compose up -d filebrowser
```

## Environment Variables

Set these in your `.env` file:

```env
# FileBrowser Configuration
FILEBROWSER_ADMIN_USER=admin
FILEBROWSER_ADMIN_PASSWORD=your-secure-password

# Domain for external access
DOMAIN=yourdomain.com
```

## Advanced Configuration

### Custom Themes

Place custom CSS files in the configuration directory and reference them in `filebrowser.json`.

### Command Integration

Configure custom commands for file operations in the `commands` section of the configuration.

### External Authentication

FileBrowser supports external authentication providers. Configure in the `auth` section.

## Support

For issues and questions:

1. Check the container logs: `docker-compose logs filebrowser`
2. Review the FileBrowser documentation: https://filebrowser.org/
3. Check the homelab infrastructure documentation

## Version Information

- FileBrowser: Latest stable version
- Container: `filebrowser/filebrowser:latest`
- Configuration Version: 1.0