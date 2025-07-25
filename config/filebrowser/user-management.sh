#!/bin/bash

# FileBrowser User Management Script
# This script provides utilities for managing users, permissions, and sharing in FileBrowser

set -e

FB_DATABASE="/database/filebrowser.db"
FB_ROOT="/srv"

# Function to display usage
usage() {
    echo "FileBrowser User Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  add-user <username> <password> [scope] [permissions]"
    echo "  remove-user <username>"
    echo "  list-users"
    echo "  update-permissions <username> <permissions>"
    echo "  create-share <username> <path> [expires]"
    echo "  list-shares [username]"
    echo "  remove-share <share-id>"
    echo "  reset-password <username> <new-password>"
    echo ""
    echo "Permission options (use --perm.NAME=true/false):"
    echo "  --perm.admin      - Administrative privileges"
    echo "  --perm.create     - Create files and folders"
    echo "  --perm.delete     - Delete files and folders"
    echo "  --perm.modify     - Modify files"
    echo "  --perm.rename     - Rename files and folders"
    echo "  --perm.share      - Create file shares"
    echo "  --perm.download   - Download files"
    echo ""
    echo "Examples:"
    echo "  $0 add-user john password123 /srv/users/john --perm.admin=false --perm.share=true"
    echo "  $0 create-share john /srv/shared/document.pdf 24h"
    echo "  $0 list-users"
}

# Function to add a new user
add_user() {
    local username="$1"
    local password="$2"
    local scope="${3:-/srv/users/$username}"
    shift 3
    local permissions="$@"
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        echo "Error: Username and password are required"
        usage
        exit 1
    fi
    
    # Create user directory if it doesn't exist
    mkdir -p "$scope"
    chmod 755 "$scope"
    
    # Add user to FileBrowser
    echo "Adding user: $username"
    filebrowser -d "$FB_DATABASE" users add "$username" "$password" --scope "$scope" $permissions
    
    echo "User $username added successfully with scope: $scope"
}

# Function to remove a user
remove_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required"
        usage
        exit 1
    fi
    
    echo "Removing user: $username"
    filebrowser -d "$FB_DATABASE" users rm "$username"
    echo "User $username removed successfully"
}

# Function to list all users
list_users() {
    echo "Current FileBrowser users:"
    filebrowser -d "$FB_DATABASE" users ls
}

# Function to update user permissions
update_permissions() {
    local username="$1"
    shift
    local permissions="$@"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required"
        usage
        exit 1
    fi
    
    echo "Updating permissions for user: $username"
    filebrowser -d "$FB_DATABASE" users update "$username" $permissions
    echo "Permissions updated successfully"
}

# Function to create a file share
create_share() {
    local username="$1"
    local filepath="$2"
    local expires="${3:-}"
    
    if [ -z "$username" ] || [ -z "$filepath" ]; then
        echo "Error: Username and file path are required"
        usage
        exit 1
    fi
    
    local share_cmd="filebrowser -d $FB_DATABASE shares add $filepath"
    
    if [ -n "$expires" ]; then
        share_cmd="$share_cmd --expires $expires"
    fi
    
    echo "Creating share for: $filepath"
    eval $share_cmd
    echo "Share created successfully"
}

# Function to list shares
list_shares() {
    local username="${1:-}"
    
    echo "Current file shares:"
    if [ -n "$username" ]; then
        filebrowser -d "$FB_DATABASE" shares ls --username "$username"
    else
        filebrowser -d "$FB_DATABASE" shares ls
    fi
}

# Function to remove a share
remove_share() {
    local share_id="$1"
    
    if [ -z "$share_id" ]; then
        echo "Error: Share ID is required"
        usage
        exit 1
    fi
    
    echo "Removing share: $share_id"
    filebrowser -d "$FB_DATABASE" shares rm "$share_id"
    echo "Share removed successfully"
}

# Function to reset user password
reset_password() {
    local username="$1"
    local new_password="$2"
    
    if [ -z "$username" ] || [ -z "$new_password" ]; then
        echo "Error: Username and new password are required"
        usage
        exit 1
    fi
    
    echo "Resetting password for user: $username"
    filebrowser -d "$FB_DATABASE" users update "$username" --password "$new_password"
    echo "Password reset successfully"
}

# Main script logic
case "${1:-}" in
    "add-user")
        shift
        add_user "$@"
        ;;
    "remove-user")
        remove_user "$2"
        ;;
    "list-users")
        list_users
        ;;
    "update-permissions")
        shift
        update_permissions "$@"
        ;;
    "create-share")
        create_share "$2" "$3" "$4"
        ;;
    "list-shares")
        list_shares "$2"
        ;;
    "remove-share")
        remove_share "$2"
        ;;
    "reset-password")
        reset_password "$2" "$3"
        ;;
    *)
        usage
        exit 1
        ;;
esac