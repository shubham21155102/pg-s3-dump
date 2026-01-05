#!/bin/bash
# =============================================================================
# PostgreSQL Backup to S3 Script
# =============================================================================
# This script backs up a PostgreSQL database and uploads the dump to S3
# =============================================================================

set -e

# Source library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/config.sh"

# =============================================================================
# Script Variables
# =============================================================================

TIMESTAMP=$(get_timestamp)
BACKUP_FILENAME="${PG_DATABASE:-db}_backup_${TIMESTAMP}.dump"
LOCAL_BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILENAME"
LOG_FILE="$LOG_DIR/backup_${TIMESTAMP}.log"

# =============================================================================
# Usage Function
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Backup a PostgreSQL database to S3

OPTIONS:
    -h, --help              Show this help message
    -c, --config            Reconfigure settings
    --plain                 Use plain SQL format instead of custom format
    --schema-only           Backup schema only (no data)
    --data-only             Backup data only (no schema)
    --no-upload             Create local backup only, skip S3 upload
    --compress              Compress the backup file

EXAMPLES:
    # Standard backup to S3
    $(basename "$0")

    # Backup with plain SQL format
    $(basename "$0") --plain

    # Schema only backup
    $(basename "$0") --schema-only

    # Local backup only (no S3 upload)
    $(basename "$0") --no-upload

EOF
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

BACKUP_FORMAT="custom"  # custom or plain
SCHEMA_ONLY=""
DATA_ONLY=""
NO_UPLOAD=false
COMPRESS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -c|--config)
            setup_all_configs
            exit 0
            ;;
        --plain)
            BACKUP_FORMAT="plain"
            ;;
        --schema-only)
            SCHEMA_ONLY="--schema-only"
            ;;
        --data-only)
            DATA_ONLY="--data-only"
            ;;
        --no-upload)
            NO_UPLOAD=true
            ;;
        --compress)
            COMPRESS=true
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

# =============================================================================
# Main Execution
# =============================================================================

main() {
    print_banner "PostgreSQL Backup to S3"

    # Setup directories
    setup_directories

    # Validate required commands
    log_info "Checking required commands..."
    if ! validate_required_commands "pg_dump" "pg_isready"; then
        exit 1
    fi

    if [[ "$NO_UPLOAD" == false ]]; then
        if ! check_aws_cli; then
            exit 1
        fi
    fi

    # Load configurations
    if ! load_postgres_config; then
        prompt_postgres_config
    fi

    if [[ "$NO_UPLOAD" == false ]]; then
        if ! load_aws_config; then
            prompt_aws_config
        fi
        if ! load_s3_config; then
            prompt_s3_config
        fi

        # Setup AWS credentials
        setup_aws_credentials "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_DEFAULT_REGION"
    fi

    print_section "Backup Configuration"

    echo "  PostgreSQL:"
    echo "    Host:     $PG_HOST"
    echo "    Port:     $PG_PORT"
    echo "    Database: $PG_DATABASE"
    echo "    User:     $PG_USER"
    echo ""

    if [[ "$NO_UPLOAD" == false ]]; then
        echo "  S3 Destination:"
        echo "    Bucket:    $S3_BUCKET"
        echo "    Path:      $S3_BACKUP_PATH/"
        echo "    Region:    $AWS_DEFAULT_REGION"
        echo ""
    fi

    echo "  Options:"
    echo "    Format:    $BACKUP_FORMAT"
    [[ -n "$SCHEMA_ONLY" ]] && echo "    Schema:    Only"
    [[ -n "$DATA_ONLY" ]] && echo "    Data:      Only"
    [[ "$COMPRESS" == true ]] && echo "    Compress:  Yes"
    [[ "$NO_UPLOAD" == true ]] && echo "    Upload:    No (local only)"
    echo ""

    # Test database connection
    print_section "Testing Database Connection"

    if validate_db_connection "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASSWORD" "$PG_DATABASE"; then
        log_success "Database connection successful"
    else
        log_error "Cannot connect to database"
        echo "  Please check your connection details and try again"
        exit 1
    fi

    # Create backup
    print_section "Creating Database Backup"

    log_info "Starting backup at $(date)"

    # Set PGPASSWORD for pg_dump
    export PGPASSWORD="$PG_PASSWORD"

    # Build pg_dump command
    PG_DUMP_OPTS=(
        -h "$PG_HOST"
        -p "$PG_PORT"
        -U "$PG_USER"
        -d "$PG_DATABASE"
        -v
    )

    if [[ "$BACKUP_FORMAT" == "custom" ]]; then
        PG_DUMP_OPTS+=(-F c -f "$LOCAL_BACKUP_FILE")
        BACKUP_FILENAME="${PG_DATABASE}_backup_${TIMESTAMP}.dump"
    else
        PG_DUMP_OPTS+=(-F p)
        LOCAL_BACKUP_FILE="$BACKUP_DIR/${PG_DATABASE}_backup_${TIMESTAMP}.sql"
        BACKUP_FILENAME="${PG_DATABASE}_backup_${TIMESTAMP}.sql"
    fi

    [[ -n "$SCHEMA_ONLY" ]] && PG_DUMP_OPTS+=($SCHEMA_ONLY)
    [[ -n "$DATA_ONLY" ]] && PG_DUMP_OPTS+=($DATA_ONLY)

    # Execute backup
    log_info "Running: pg_dump ${PG_DUMP_OPTS[*]}"

    if pg_dump "${PG_DUMP_OPTS[@]}" > "$LOG_FILE" 2>&1; then
        log_success "Backup created successfully"
        log_info "Local file: $LOCAL_BACKUP_FILE"
        log_info "File size: $(get_file_size "$LOCAL_BACKUP_FILE")"
    else
        log_error "Backup failed"
        echo "  Check log file: $LOG_FILE"
        exit 1
    fi

    # Compress if requested
    if [[ "$COMPRESS" == true ]]; then
        log_info "Compressing backup file..."
        gzip -f "$LOCAL_BACKUP_FILE"
        LOCAL_BACKUP_FILE="${LOCAL_BACKUP_FILE}.gz"
        BACKUP_FILENAME="${BACKUP_FILENAME}.gz"
        log_info "Compressed file: $LOCAL_BACKUP_FILE"
        log_info "Compressed size: $(get_file_size "$LOCAL_BACKUP_FILE")"
    fi

    # Upload to S3
    if [[ "$NO_UPLOAD" == false ]]; then
        print_section "Uploading to S3"

        S3_KEY="${S3_BACKUP_PATH}/$(get_date)/${BACKUP_FILENAME}"
        S3_URI="s3://${S3_BUCKET}/${S3_KEY}"

        log_info "Uploading to: $S3_URI"

        if aws s3 cp "$LOCAL_BACKUP_FILE" "$S3_URI" > "$LOG_FILE.s3" 2>&1; then
            log_success "Upload completed successfully"
            log_info "S3 Location: s3://${S3_BUCKET}/${S3_KEY}"
        else
            log_error "Upload failed"
            echo "  Check log file: $LOG_FILE.s3"
            exit 1
        fi

        # Verify upload
        log_info "Verifying upload..."
        if aws s3 ls "$S3_URI" > /dev/null 2>&1; then
            log_success "Upload verified"
        else
            log_warning "Could not verify upload"
        fi

        # List recent backups
        echo ""
        log_info "Recent backups in S3:"
        aws s3 ls "s3://${S3_BUCKET}/${S3_BACKUP_PATH}/$(get_date)/" 2>/dev/null || \
        aws s3 ls "s3://${S3_BUCKET}/${S3_BACKUP_PATH}/" | tail -5
    fi

    # Cleanup old local backups (keep last 10)
    print_section "Cleanup"

    log_info "Cleaning up old local backups (keeping last 10)..."
    find "$BACKUP_DIR" -name "${PG_DATABASE}_backup_*" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
    log_info "Cleanup completed"

    # Summary
    print_section "Backup Summary"

    echo "  Status:     ${GREEN}Success${NC}"
    echo "  Local File: $LOCAL_BACKUP_FILE"
    echo "  File Size:  $(get_file_size "$LOCAL_BACKUP_FILE")"

    if [[ "$NO_UPLOAD" == false ]]; then
        echo "  S3 URI:     $S3_URI"
    fi

    echo ""
    log_success "Backup completed at $(date)"

    # Restore hint
    if [[ "$NO_UPLOAD" == false ]]; then
        echo ""
        echo -e "${YELLOW}To restore this backup:${NC}"
        echo "  bash $(dirname "$0")/restore-from-s3.sh"
    fi

    echo ""
}

# Run main function
main "$@"
