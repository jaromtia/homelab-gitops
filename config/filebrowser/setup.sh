#!/bin/bash

# FileBrowser Setup Script
# This script initializes FileBrowser with proper user management, permissions, and sharing capabilities

set -e

# Configuration variables
FB_CONFIG_FILE="/etc/filebrowser/.filebrowser.json"
FB_DATABASE="/database/filebrowser.db"
FB_ROOT="/srv"
FB_ADMIN_USER="${FILEBROWSER_ADMIN_USER:-admin}"
FB_ADMIN_PASSWORD="${FILEBROWSER_ADMIN_PASSWORD:-admin}"

echo "Starting FileBrowser setup..."

# Wait for database directory to be available
while [ ! -d "/database" ]; do
    echo "Waiting for database directory..."
    sleep 2
done

# Create necessary directories
mkdir -p /srv/shared
mkdir -p /srv/users
mkdir -p /srv/uploads
mkdir -p /srv/public

# Set proper permissions
chmod 755 /srv/shared
chmod 755 /srv/users
chmod 755 /srv/uploads
chmod 755 /srv/public

# Initialize database if it doesn't exist
if [ ! -f "$FB_DATABASE" ]; then
    echo "Initializing FileBrowser database..."
    
    # Create initial admin user
    filebrowser -d "$FB_DATABASE" config init
    filebrowser -d "$FB_DATABASE" config set --address 0.0.0.0
    filebrowser -d "$FB_DATABASE" config set --port 80
    filebrowser -d "$FB_DATABASE" config set --log stdout
    filebrowser -d "$FB_DATABASE" config set --root "$FB_ROOT"
    
    # Create admin user
    filebrowser -d "$FB_DATABASE" users add "$FB_ADMIN_USER" "$FB_ADMIN_PASSWORD" --perm.admin
    
    echo "Admin user created: $FB_ADMIN_USER"
fi

# Create default user directories and set permissions
echo "Setting up user directories and permissions..."

# Create a guest user with limited permissions for sharing
if ! filebrowser -d "$FB_DATABASE" users ls | grep -q "guest"; then
    filebrowser -d "$FB_DATABASE" users add guest guest \
        --scope "/srv/public" \
        --perm.create=false \
        --perm.delete=false \
        --perm.modify=false \
        --perm.rename=false \
        --perm.share=false \
        --perm.download=true
    echo "Guest user created for public access"
fi

# Create a standard user with normal permissions
if ! filebrowser -d "$FB_DATABASE" users ls | grep -q "user"; then
    filebrowser -d "$FB_DATABASE" users add user user \
        --scope "/srv/users/user" \
        --perm.admin=false \
        --perm.create=true \
        --perm.delete=true \
        --perm.modify=true \
        --perm.rename=true \
        --perm.share=true \
        --perm.download=true
    
    # Create user directory
    mkdir -p /srv/users/user
    chmod 755 /srv/users/user
    echo "Standard user created with personal directory"
fi

# Set up sharing configuration
echo "Configuring file sharing capabilities..."

# Enable sharing globally
filebrowser -d "$FB_DATABASE" config set --signup=false
filebrowser -d "$FB_DATABASE" config set --createUserDir=true

echo "FileBrowser setup completed successfully!"

# Start FileBrowser
echo "Starting FileBrowser server..."
exec filebrowser -d "$FB_DATABASE"