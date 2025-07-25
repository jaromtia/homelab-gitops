#!/bin/bash

# FileBrowser Docker Entrypoint Script
# This script handles container initialization, user setup, and service startup

set -e

# Configuration variables
FB_CONFIG_FILE="/.filebrowser.json"
FB_DATABASE="/database/filebrowser.db"
FB_ROOT="/srv"
FB_ADMIN_USER="${FILEBROWSER_ADMIN_USER:-admin}"
FB_ADMIN_PASSWORD="${FILEBROWSER_ADMIN_PASSWORD:-changeme}"

echo "=== FileBrowser Container Initialization ==="

# Create necessary directories
echo "Creating directory structure..."
mkdir -p /database
mkdir -p /srv/shared
mkdir -p /srv/users
mkdir -p /srv/uploads
mkdir -p /srv/public
mkdir -p /srv/.quarantine
mkdir -p /var/log
mkdir -p /backups/filebrowser

# Set proper permissions
chmod 755 /srv/shared /srv/users /srv/uploads /srv/public
chmod 700 /srv/.quarantine
chmod 755 /database /var/log

# Initialize database if it doesn't exist
if [ ! -f "$FB_DATABASE" ]; then
    echo "Initializing FileBrowser database..."
    
    # Initialize configuration
    filebrowser -d "$FB_DATABASE" config init
    filebrowser -d "$FB_DATABASE" config set --address 0.0.0.0
    filebrowser -d "$FB_DATABASE" config set --port 80
    filebrowser -d "$FB_DATABASE" config set --log stdout
    filebrowser -d "$FB_DATABASE" config set --root "$FB_ROOT"
    filebrowser -d "$FB_DATABASE" config set --baseurl ""
    
    # Create admin user
    echo "Creating admin user: $FB_ADMIN_USER"
    filebrowser -d "$FB_DATABASE" users add "$FB_ADMIN_USER" "$FB_ADMIN_PASSWORD" --perm.admin
    
    # Create default users with different permission levels
    echo "Creating default users..."
    
    # Guest user - read-only access to public folder
    filebrowser -d "$FB_DATABASE" users add guest guest \
        --scope "/srv/public" \
        --perm.admin=false \
        --perm.create=false \
        --perm.delete=false \
        --perm.modify=false \
        --perm.rename=false \
        --perm.share=false \
        --perm.download=true
    
    # Standard user - full access to personal directory
    filebrowser -d "$FB_DATABASE" users add user user \
        --scope "/srv/users/user" \
        --perm.admin=false \
        --perm.create=true \
        --perm.delete=true \
        --perm.modify=true \
        --perm.rename=true \
        --perm.share=true \
        --perm.download=true
    
    # Create user directories
    mkdir -p /srv/users/user
    chmod 755 /srv/users/user
    
    echo "Database initialization completed"
else
    echo "Database already exists, skipping initialization"
fi

# Create sample files and directories for demonstration
if [ ! -f "/srv/public/README.md" ]; then
    echo "Creating sample files..."
    
    cat > /srv/public/README.md << 'EOF'
# Homelab File Manager

Welcome to your homelab file management system!

## Features

- **Web-based Interface**: Access your files from anywhere through your browser
- **Secure Sharing**: Create secure links to share files with others
- **User Management**: Multiple users with different permission levels
- **File Upload/Download**: Easy drag-and-drop file operations
- **Search**: Find files quickly with built-in search functionality

## Directory Structure

- `/public/` - Files accessible to all users
- `/shared/` - Shared files between users
- `/users/` - Personal user directories
- `/uploads/` - Temporary upload area

## Getting Started

1. Log in with your credentials
2. Navigate through the directory structure
3. Upload files by dragging them into the browser
4. Create shares by right-clicking on files
5. Manage users through the admin interface (admin users only)

## Security

- All file transfers are encrypted via HTTPS
- Shares can be password protected and have expiration dates
- User access is controlled through granular permissions
- File uploads are scanned for security

For support, contact your system administrator.
EOF

    cat > /srv/shared/welcome.txt << 'EOF'
Welcome to the shared directory!

This directory is accessible to all authenticated users.
Use this space to share files between different users.

Guidelines:
- Keep files organized in subdirectories
- Use descriptive filenames
- Clean up old files regularly
- Respect storage quotas
EOF

    # Create some sample directories
    mkdir -p /srv/shared/documents
    mkdir -p /srv/shared/images
    mkdir -p /srv/shared/archives
    mkdir -p /srv/uploads/temp
    
    echo "Sample files created"
fi

# Set up health check endpoint
echo "Setting up health monitoring..."
cat > /srv/health.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>FileBrowser Health Check</title>
</head>
<body>
    <h1>FileBrowser Health Check</h1>
    <p>Status: OK</p>
    <p>Timestamp: $(date)</p>
</body>
</html>
EOF

# Create a simple health check script
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# Simple health check for FileBrowser
if curl -f -s http://localhost:80/ > /dev/null; then
    echo "OK"
    exit 0
else
    echo "FAIL"
    exit 1
fi
EOF
chmod +x /usr/local/bin/health-check.sh

# Display configuration summary
echo "=== Configuration Summary ==="
echo "Database: $FB_DATABASE"
echo "Root directory: $FB_ROOT"
echo "Admin user: $FB_ADMIN_USER"
echo "Config file: $FB_CONFIG_FILE"
echo "================================"

# Start FileBrowser with proper signal handling
echo "Starting FileBrowser server..."

# Function to handle shutdown signals
shutdown() {
    echo "Received shutdown signal, stopping FileBrowser..."
    kill -TERM "$child" 2>/dev/null
    wait "$child"
    echo "FileBrowser stopped"
    exit 0
}

# Set up signal handlers
trap shutdown SIGTERM SIGINT

# Start FileBrowser in background
filebrowser -d "$FB_DATABASE" &
child=$!

# Wait for the process
wait "$child"