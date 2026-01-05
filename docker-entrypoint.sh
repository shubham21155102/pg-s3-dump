#!/bin/bash
# =============================================================================
# Docker Entrypoint for PostgreSQL S3 Backup
# =============================================================================
# This script handles environment variable configuration and command routing
# =============================================================================

set -e

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Directory paths
export APP_DIR="/app"
export BACKUP_DIR="/app/backups"
export LOG_DIR="/app/logs"
export CONFIG_DIR="/app/config"
export LIB_DIR="/app/lib"

# Source library functions
source "$LIB_DIR/common.sh"

# =============================================================================
# Configuration from Environment Variables
# =============================================================================

setup_config_from_env() {
    print_section "Loading Configuration from Environment"

    local has_config=0

    # PostgreSQL Configuration
    if [[ -n "$PGHOST" ]]; then
        export PG_HOST="$PGHOST"
        export PG_PORT="${PGPORT:-5432}"
        export PG_DATABASE="$PGDATABASE"
        export PG_USER="$PGUSER"
        export PG_PASSWORD="$PGPASSWORD"

        log_success "PostgreSQL configuration loaded"
        echo "  Host:     $PG_HOST"
        echo "  Port:     $PG_PORT"
        echo "  Database: $PG_DATABASE"
        echo "  User:     $PG_USER"
        has_config=1
    else
        log_warning "PostgreSQL configuration not set (PGHOST, PGDATABASE, PGUSER, PGPASSWORD required)"
    fi

    # AWS Configuration
    if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
        export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

        log_success "AWS configuration loaded"
        echo "  Region:   $AWS_DEFAULT_REGION"
        has_config=1
    else
        log_warning "AWS configuration not set (AWS_ACCESS_KEY_ID required)"
    fi

    # S3 Configuration
    if [[ -n "$S3_BUCKET" ]]; then
        export S3_BUCKET="$S3_BUCKET"
        export S3_BACKUP_PATH="${S3_BACKUP_PATH:-postgres-backups}"

        log_success "S3 configuration loaded"
        echo "  Bucket:   $S3_BUCKET"
        echo "  Path:     $S3_BACKUP_PATH"
        has_config=1
    else
        log_warning "S3 configuration not set (S3_BUCKET required)"
    fi

    echo ""

    if [[ $has_config -eq 0 ]]; then
        log_error "No configuration found. Please set environment variables."
        return 1
    fi

    return 0
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_backup_config() {
    local missing=0

    if [[ -z "$PGHOST" ]]; then
        log_error "PGHOST is required for backup"
        missing=1
    fi
    if [[ -z "$PGDATABASE" ]]; then
        log_error "PGDATABASE is required for backup"
        missing=1
    fi
    if [[ -z "$PGUSER" ]]; then
        log_error "PGUSER is required for backup"
        missing=1
    fi
    if [[ -z "$PGPASSWORD" ]]; then
        log_error "PGPASSWORD is required for backup"
        missing=1
    fi
    if [[ -z "$S3_BUCKET" ]]; then
        log_error "S3_BUCKET is required for backup"
        missing=1
    fi
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        log_error "AWS_ACCESS_KEY_ID is required for backup"
        missing=1
    fi

    return $missing
}

validate_restore_config() {
    local missing=0

    if [[ -z "$PGHOST" ]]; then
        log_error "PGHOST is required for restore"
        missing=1
    fi
    if [[ -z "$PGDATABASE" ]]; then
        log_error "PGDATABASE is required for restore"
        missing=1
    fi
    if [[ -z "$PGUSER" ]]; then
        log_error "PGUSER is required for restore"
        missing=1
    fi
    if [[ -z "$PGPASSWORD" ]]; then
        log_error "PGPASSWORD is required for restore"
        missing=1
    fi
    if [[ -z "$S3_BUCKET" ]]; then
        log_error "S3_BUCKET is required for restore"
        missing=1
    fi
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        log_error "AWS_ACCESS_KEY_ID is required for restore"
        missing=1
    fi

    return $missing
}

# =============================================================================
# Command Execution Functions
# =============================================================================

run_backup() {
    print_banner "PostgreSQL Backup to S3"

    if ! validate_backup_config; then
        exit 1
    fi

    setup_config_from_env

    # Load modified config.sh functions with env vars
    source "$LIB_DIR/config.sh"

    # Set internal variables from environment
    PG_HOST="$PGHOST"
    PG_PORT="${PGPORT:-5432}"
    PG_DATABASE="$PGDATABASE"
    PG_USER="$PGUSER"
    PG_PASSWORD="$PGPASSWORD"
    S3_BUCKET="$S3_BUCKET"
    S3_BACKUP_PATH="${S3_BACKUP_PATH:-postgres-backups}"

    # Execute backup script
    exec "$APP_DIR/bin/backup-to-s3.sh" "$@"
}

run_restore() {
    print_banner "PostgreSQL Restore from S3"

    if ! validate_restore_config; then
        exit 1
    fi

    setup_config_from_env

    # Load modified config.sh functions with env vars
    source "$LIB_DIR/config.sh"

    # Set internal variables from environment
    PG_HOST="$PGHOST"
    PG_PORT="${PGPORT:-5432}"
    PG_DATABASE="$PGDATABASE"
    PG_USER="$PGUSER"
    PG_PASSWORD="$PGPASSWORD"
    S3_BUCKET="$S3_BUCKET"
    S3_BACKUP_PATH="${S3_BACKUP_PATH:-postgres-backups}"

    # Execute restore script
    exec "$APP_DIR/bin/restore-from-s3.sh" "$@"
}

run_list() {
    print_banner "Listing S3 Backups"

    if [[ -z "$S3_BUCKET" ]]; then
        log_error "S3_BUCKET is required"
        exit 1
    fi

    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        log_error "AWS_ACCESS_KEY_ID is required"
        exit 1
    fi

    setup_config_from_env

    # List backups
    local s3_path="s3://${S3_BUCKET}/${S3_BACKUP_PATH:-postgres-backups}/"
    log_info "Listing backups from: $s3_path"
    echo ""

    aws s3 ls "$s3_path" --recursive || true
}

run_cron() {
    print_banner "Running Cron Mode"

    if ! validate_backup_config; then
        exit 1
    fi

    if [[ -z "$CRON_SCHEDULE" ]]; then
        log_error "CRON_SCHEDULE environment variable is required for cron mode"
        exit 1
    fi

    setup_config_from_env

    log_info "Cron Schedule: $CRON_SCHEDULE"
    log_info "Timezone: ${TZ:-UTC}"

    # Create crontab file
    cat > /tmp/crontab <<EOF
$(echo "$CRON_SCHEDULE" | tr -d '\r') cd /app && bash docker-entrypoint.sh backup >> /var/log/backup.log 2>&1
EOF

    # Start cron
    log_info "Starting cron daemon..."
    exec crond -f -l 2
}

show_version() {
    cat /app/VERSION 2>/dev/null || echo "dev"
}

show_help() {
    cat <<EOF
PostgreSQL S3 Backup - Docker Image

This containerized application provides PostgreSQL database backup and restore
functionality with AWS S3 storage.

ENVIRONMENT VARIABLES:
  PostgreSQL:
    PGHOST              PostgreSQL host (required)
    PGPORT              PostgreSQL port (default: 5432)
    PGDATABASE          Database name (required)
    PGUSER              Database user (required)
    PGPASSWORD          Database password (required)

  AWS:
    AWS_ACCESS_KEY_ID   AWS access key (required)
    AWS_SECRET_ACCESS_KEY   AWS secret key (required)
    AWS_DEFAULT_REGION  AWS region (default: us-east-1)

  S3:
    S3_BUCKET           S3 bucket name (required)
    S3_BACKUP_PATH      S3 path prefix (default: postgres-backups)

  Cron:
    CRON_SCHEDULE       Cron schedule for automated backups
    TZ                  Timezone (default: UTC)

COMMANDS:
  backup               Run backup to S3
                      Additional options:
                        --plain         Use plain SQL format
                        --schema-only   Backup schema only
                        --data-only     Backup data only
                        --compress      Compress backup file

  restore [OPTIONS]    Restore from S3
                      Additional options:
                        --list          List available backups
                        --file URI      Specific S3 URI to restore
                        --clean         Drop existing data before restore
                        --create-db     Create database if not exists

  list                 List available backups in S3

  cron                 Run in cron mode (requires CRON_SCHEDULE)

  version              Show version information

  help                 Show this help message

EXAMPLES:
  # Run backup
  docker run --rm \\
    -e PGHOST=db.example.com \\
    -e PGDATABASE=mydb \\
    -e PGUSER=admin \\
    -e PGPASSWORD=secret \\
    -e AWS_ACCESS_KEY_ID=AKIA... \\
    -e AWS_SECRET_ACCESS_KEY=secret \\
    -e S3_BUCKET=my-backups \\
    pg-s3-backup backup

  # Run with docker-compose
  docker-compose run --rm pg-s3-backup backup

  # List backups
  docker run --rm \\
    -e AWS_ACCESS_KEY_ID=AKIA... \\
    -e AWS_SECRET_ACCESS_KEY=secret \\
    -e S3_BUCKET=my-backups \\
    pg-s3-backup list

  # Automated backups with cron
  docker run -d \\
    -e CRON_SCHEDULE="0 2 * * *" \\
    -e PGHOST=db.example.com \\
    ... \\
    pg-s3-backup cron

EOF
}

# =============================================================================
# Main Entrypoint
# =============================================================================

main() {
    # Setup directories
    setup_directories

    # Show banner if running interactively
    if [[ -t 0 ]]; then
        print_banner "PostgreSQL S3 Backup" "" "40"
    fi

    # Parse command
    local command="${1:-help}"
    shift || true

    case "$command" in
        backup)
            run_backup "$@"
            ;;
        restore)
            run_restore "$@"
            ;;
        list)
            run_list
            ;;
        cron)
            run_cron
            ;;
        version|--version|-v)
            show_version
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
