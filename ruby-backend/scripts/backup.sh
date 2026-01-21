#!/bin/bash

# Database backup script for Spotik Ruby Backend
# This script creates daily backups and maintains a 7-day retention policy

set -e

# Configuration
BACKUP_DIR="/backups"
DB_HOST="${DB_HOST:-postgres}"
DB_NAME="${DB_NAME:-spotik}"
DB_USER="${DB_USER:-spotik_user}"
RETENTION_DAYS=7

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/spotik_backup_$TIMESTAMP.sql"

echo "Starting database backup at $(date)"
echo "Backup file: $BACKUP_FILE"

# Create database backup
if pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" --verbose --no-password > "$BACKUP_FILE"; then
    echo "Database backup completed successfully"
    
    # Compress the backup
    gzip "$BACKUP_FILE"
    BACKUP_FILE="$BACKUP_FILE.gz"
    
    # Get file size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "Compressed backup size: $BACKUP_SIZE"
    
    # Clean up old backups (keep only last 7 days)
    echo "Cleaning up old backups (keeping last $RETENTION_DAYS days)"
    find "$BACKUP_DIR" -name "spotik_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
    
    # List remaining backups
    echo "Current backups:"
    ls -lh "$BACKUP_DIR"/spotik_backup_*.sql.gz 2>/dev/null || echo "No backups found"
    
    echo "Backup process completed at $(date)"
else
    echo "ERROR: Database backup failed" >&2
    exit 1
fi