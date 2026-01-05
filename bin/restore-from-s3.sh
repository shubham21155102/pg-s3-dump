#!/bin/bash
# =============================================================================
# PostgreSQL Restore from S3 Script
# =============================================================================
# This script downloads a PostgreSQL dump from S3 and restores it to a database
# =============================================================================

set -e

# Source library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/config.sh"

# =============================================================================
# Script Variables
# ==============================================================================

TIMESTAMP=$(get_timestamp)
DOWNLOAD_DIR="$BACKUP_DIR"
DOWNLOADED_FILE=""
LOG_FILE="$LOG_DIR/restore_${TIMESTAMP}.log"

# =============================================================================
# Usage Function
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [S3_URI]

Restore a PostgreSQL database from an S3 backup

OPTIONS:
    -h, --help              Show this help message
    -c, --config            Reconfigure settings
    --list                  List available backups in S3
    --file S3_URI           Specify S3 URI to restore (s3://bucket/path/file.dump)
    --clean                 Drop existing database before restore
    --create-db             Create database if it doesn't exist
    --db-only               Skip S3 download, restore from local file

ARGUMENTS:
    S3_URI                  S3 URI of the backup file to restore
                            (s3://bucket/path/file.dump or s3://bucket/path/file.sql)

EXAMPLES:
    # List available backups
    $(basename "$0") --list

    # Restore from S3 URI
    $(basename "$0") s3://my-bucket/postgres-backups/2024-01-04/db_backup.dump

    # Interactive restore (select from list)
    $(basename "$0")

    # Clean restore (drop existing tables)
    $(basename "$0") --clean

    # Restore from local file
    $(basename "$0") --db-only /path/to/backup.dump

EOF
    exit 0
}

# =============================================================================
# S3 Functions
# =============================================================================

list_s3_backups() {
    print_section "Available S3 Backups"

    if ! load_s3_config; then
        log_error "S3 configuration not found"
        log_info "Run with --config to set up"
        return 1
    fi

    if ! load_aws_config; then
        log_error "AWS configuration not found"
        return 1
    fi

    setup_aws_credentials "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_DEFAULT_REGION"

    log_info "Listing backups from: s3://${S3_BUCKET}/${S3_BACKUP_PATH}/"
    echo ""

    # List all backups
    aws s3 ls "s3://${S3_BUCKET}/${S3_BACKUP_PATH}/" --recursive | while read -r line; do
        echo "  $line"
    done

    echo ""
    log_success "List completed"
    echo ""
}

select_s3_backup() {
    local backups=()
    local index=1

    print_section "Select Backup to Restore"

    log_info "Fetching available backups..."

    # Get list of backups
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Extract fields from s3 ls output: date time size key_path
        local datetime=$(echo "$line" | awk '{print $1" "$2}')
        local size=$(echo "$line" | awk '{print $3}')
        # The key path starts from field 4 (may contain spaces)
        local key_path=$(echo "$line" | cut -d' ' -f4-)
        # Get just the filename for display
        local filename=$(basename "$key_path")

        backups+=("$key_path")

        echo "  [$index] $filename"
        echo "       Size: $size | Date: $datetime"
        ((index++))
    done < <(aws s3 ls "s3://${S3_BUCKET}/${S3_BACKUP_PATH}/" --recursive 2>/dev/null | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "No backups found in S3"
        return 1
    fi

    echo ""
    read -p "Select backup number [1-${#backups[@]}]: " selection

    if [[ "$selection" -ge 1 && "$selection" -le ${#backups[@]} ]]; then
        SELECTED_BACKUP="${backups[$((selection-1))]}"
        log_success "Selected: $SELECTED_BACKUP"
        return 0
    else
        log_error "Invalid selection"
        return 1
    fi
}

download_from_s3() {
    local s3_uri="$1"
    local filename

    # Extract filename from S3 URI
    filename=$(basename "$s3_uri")
    DOWNLOADED_FILE="$DOWNLOAD_DIR/$filename"

    print_section "Downloading from S3"

    log_info "Source: $s3_uri"
    log_info "Destination: $DOWNLOADED_FILE"

    # Check if file already exists
    if [[ -f "$DOWNLOADED_FILE" ]]; then
        if confirm_action "File already exists locally. Use existing file?" "Y"; then
            log_info "Using existing local file"
            return 0
        else
            rm -f "$DOWNLOADED_FILE"
        fi
    fi

    # Download
    if aws s3 cp "$s3_uri" "$DOWNLOADED_FILE" > "$LOG_FILE.download" 2>&1; then
        log_success "Download completed"
        log_info "File size: $(get_file_size "$DOWNLOADED_FILE")"
        return 0
    else
        log_error "Download failed"
        echo "  Check log file: $LOG_FILE.download"
        return 1
    fi
}

# =============================================================================
# Restore Functions
# =============================================================================

restore_database() {
    local backup_file="$1"
    local clean_restore="${2:-false}"

    print_section "Restoring Database"

    # Check file format
    local file_ext="${backup_file##*.}"
    local is_compressed=false

    # Handle compressed files
    if [[ "$file_ext" == "gz" ]]; then
        is_compressed=true
        local base_name="${backup_file%.gz}"
        file_ext="${base_name##*.}"

        # Decompress
        log_info "Decompressing file..."
        gunzip -c "$backup_file" > "$base_name"
        backup_file="$base_name"
    fi

    # Set PGPASSWORD
    export PGPASSWORD="$PG_PASSWORD"

    if [[ "$clean_restore" == true ]]; then
        log_warning "Clean restore requested - dropping existing schema"
        echo ""
        if ! confirm_action "This will DELETE all existing data. Continue?" "N"; then
            log_info "Restore cancelled"
            return 1
        fi

        log_info "Dropping existing schema..."
        psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
            -c "DROP SCHEMA public CASCADE;" \
            -c "CREATE SCHEMA public;" \
            -c "GRANT ALL ON SCHEMA public TO $PG_USER;" \
            -c "GRANT ALL ON SCHEMA public TO public;" \
            > /dev/null 2>&1

        log_success "Schema cleaned"
    fi

    # Restore based on format
    if [[ "$file_ext" == "dump" || "$file_ext" == "backup" ]]; then
        # Custom format
        log_info "Restoring from custom format dump..."
        if pg_restore -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
            -d "$PG_DATABASE" \
            --no-owner --no-acl -v "$backup_file" > "$LOG_FILE.restore" 2>&1; then
            log_success "Restore completed"
        else
            log_error "Restore failed"
            echo "  Check log file: $LOG_FILE.restore"
            return 1
        fi
    else
        # Plain SQL format
        log_info "Restoring from SQL file..."
        if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" \
            -d "$PG_DATABASE" \
            -f "$backup_file" > "$LOG_FILE.restore" 2>&1; then
            log_success "Restore completed"
        else
            log_error "Restore failed"
            echo "  Check log file: $LOG_FILE.restore"
            return 1
        fi
    fi

    # Clean up decompressed file if needed
    if [[ "$is_compressed" == true && -f "$backup_file" ]]; then
        rm -f "$backup_file"
    fi

    return 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

LIST_ONLY=false
SPECIFIED_S3_URI=""
CLEAN_RESTORE=false
CREATE_DB=false
LOCAL_FILE_ONLY=false
LOCAL_FILE_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--config)
            setup_all_configs
            exit 0
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --file)
            SPECIFIED_S3_URI="$2"
            shift 2
            ;;
        --clean)
            CLEAN_RESTORE=true
            shift
            ;;
        --create-db)
            CREATE_DB=true
            shift
            ;;
        --db-only)
            LOCAL_FILE_ONLY=true
            LOCAL_FILE_PATH="$2"
            shift 2
            ;;
        s3://*)
            SPECIFIED_S3_URI="$1"
            shift
            ;;
        *)
            if [[ "$LOCAL_FILE_ONLY" == true && -z "$LOCAL_FILE_PATH" ]]; then
                LOCAL_FILE_PATH="$1"
            fi
            shift
            ;;
    esac
done

# =============================================================================
# Main Execution
# =============================================================================

main() {
    print_banner "PostgreSQL Restore from S3"

    # Setup directories
    setup_directories

    # Validate required commands
    log_info "Checking required commands..."
    if ! validate_required_commands "psql" "pg_isready"; then
        exit 1
    fi

    if [[ "$LOCAL_FILE_ONLY" == false ]]; then
        if ! check_aws_cli; then
            exit 1
        fi
    fi

    # List only mode
    if [[ "$LIST_ONLY" == true ]]; then
        list_s3_backups
        exit 0
    fi

    # Load AWS/S3 config if not local file only
    if [[ "$LOCAL_FILE_ONLY" == false ]]; then
        if ! load_aws_config; then
            prompt_aws_config
        fi
        if ! load_s3_config; then
            prompt_s3_config
        fi
        setup_aws_credentials "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_DEFAULT_REGION"
    fi

    # Load destination PostgreSQL config (where we will restore TO)
    print_section "Destination Database Configuration"
    log_info "This is the database where the backup will be restored"
    echo ""

    if ! load_postgres_dest_config; then
        if confirm_action "Configure a different destination database?" "N"; then
            prompt_postgres_dest_config
            load_postgres_dest_config
        else
            log_info "Using source database as destination"
            # Load source config if no destination configured
            if ! load_postgres_config; then
                prompt_postgres_config
            fi
        fi
    fi

    # Get S3 URI
    if [[ "$LOCAL_FILE_ONLY" == false ]]; then
        if [[ -z "$SPECIFIED_S3_URI" ]]; then
            if ! select_s3_backup; then
                exit 1
            fi
            # SELECTED_BACKUP already contains the full key path from --recursive listing
            SPECIFIED_S3_URI="s3://${S3_BUCKET}/${SELECTED_BACKUP}"
        fi

        # Download from S3
        if ! download_from_s3 "$SPECIFIED_S3_URI"; then
            exit 1
        fi
    else
        DOWNLOADED_FILE="$LOCAL_FILE_PATH"

        if [[ ! -f "$DOWNLOADED_FILE" ]]; then
            log_error "Local file not found: $DOWNLOADED_FILE"
            exit 1
        fi
    fi

    # Show restore configuration
    print_section "Restore Configuration"

    echo "  PostgreSQL:"
    echo "    Host:     $PG_HOST"
    echo "    Port:     $PG_PORT"
    echo "    Database: $PG_DATABASE"
    echo "    User:     $PG_USER"
    echo ""
    echo "  Source:"
    echo "    File:     $DOWNLOADED_FILE"
    echo "    Size:     $(get_file_size "$DOWNLOADED_FILE")"
    echo ""
    echo "  Options:"
    [[ "$CLEAN_RESTORE" == true ]] && echo "    Clean:    Yes (will drop existing data)"
    [[ "$CREATE_DB" == true ]] && echo "    Create DB: Yes"
    echo ""

    # Test database connection
    log_info "Testing database connection..."

    if ! validate_db_connection "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASSWORD" "$PG_DATABASE"; then
        if [[ "$CREATE_DB" == true ]]; then
            log_warning "Database doesn't exist, creating it..."
            export PGPASSWORD="$PG_PASSWORD"
            psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d postgres \
                -c "CREATE DATABASE $PG_DATABASE;" > /dev/null 2>&1
            log_success "Database created"
        else
            log_error "Cannot connect to database"
            echo "  The database '$PG_DATABASE' may not exist"
            echo "  Use --create-db to create it automatically"
            exit 1
        fi
    else
        log_success "Database connection verified"
    fi

    # Confirm restore
    if ! confirm_action "Start restore?" "Y"; then
        log_info "Restore cancelled"
        exit 0
    fi

    # Perform restore
    echo ""
    log_info "Starting restore at $(date)"

    if restore_database "$DOWNLOADED_FILE" "$CLEAN_RESTORE"; then
        print_section "Restore Summary"

        echo "  Status:      ${GREEN}Success${NC}"
        echo "  Database:    $PG_DATABASE"
        echo "  Restored:    $(date)"
        echo ""
        log_success "Restore completed successfully!"
    else
        log_error "Restore failed"
        exit 1
    fi

    echo ""
}

# Run main function
main "$@"
