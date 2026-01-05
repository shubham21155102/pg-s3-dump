#!/bin/bash
# =============================================================================
# PostgreSQL S3 Backup Manager - Main Menu
# =============================================================================
# Interactive menu for managing PostgreSQL database backups to/from S3
# =============================================================================

set -e

# Source library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Version
VERSION="1.0.0"

# =============================================================================
# Menu Functions
# =============================================================================

show_main_menu() {
    clear
    print_banner "PostgreSQL S3 Backup Manager v${VERSION}"

    cat <<EOF
${GREEN}Main Menu${NC}

  ${CYAN}1.${NC} Backup Database to S3
  ${CYAN}2.${NC} Restore Database from S3
  ${CYAN}3.${NC} List Available Backups
  ${CYAN}4.${NC} Configure Settings
  ${CYAN}5.${NC} Show Current Configuration
  ${CYAN}6.${NC} View Backup Logs
  ${CYAN}7.${NC} Maintenance Tools
  ${CYAN}0.${NC} Exit

EOF
}

show_config_menu() {
    print_section "Configuration Menu"

    cat <<EOF
  ${CYAN}1.${NC} Configure Source Database (for Backup)
  ${CYAN}2.${NC} Configure Destination Database (for Restore)
  ${CYAN}3.${NC} Configure AWS Credentials
  ${CYAN}4.${NC} Configure S3 Bucket
  ${CYAN}5.${NC} Configure All Settings
  ${CYAN}6.${NC} Reset Configuration
  ${CYAN}0.${NC} Back to Main Menu

EOF
}

show_maintenance_menu() {
    print_section "Maintenance Tools"

    cat <<EOF
  ${CYAN}1.${NC} Test Database Connection
  ${CYAN}2.${NC} Test AWS/S3 Connection
  ${CYAN}3.${NC} Clean Old Local Backups
  ${CYAN}4.${NC} View Backup History
  ${CYAN}5.${NC} Backup Health Check
  ${CYAN}0.${NC} Back to Main Menu

EOF
}

# =============================================================================
# Menu Actions
# =============================================================================

action_backup() {
    print_section "Backup Database to S3"
    bash "$SCRIPT_DIR/bin/backup-to-s3.sh" "$@"
    echo ""
    read -p "Press Enter to continue..."
}

action_restore() {
    print_section "Restore Database from S3"
    bash "$SCRIPT_DIR/bin/restore-from-s3.sh" "$@"
    echo ""
    read -p "Press Enter to continue..."
}

action_list() {
    bash "$SCRIPT_DIR/bin/restore-from-s3.sh" --list
    echo ""
    read -p "Press Enter to continue..."
}

action_configure() {
    local choice

    while true; do
        clear
        show_config_menu
        read -p "Select option [0-6]: " choice

        case $choice in
            1)
                clear
                prompt_postgres_config
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                clear
                prompt_postgres_dest_config
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                clear
                prompt_aws_config
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                clear
                prompt_s3_config
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                clear
                setup_all_configs
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                clear
                echo "Reset Configuration:"
                echo "  1) Source database only"
                echo "  2) Destination database only"
                echo "  3) AWS only"
                echo "  4) S3 only"
                echo "  5) All configurations"
                echo ""
                read -p "Select [1-5]: " reset_choice
                case $reset_choice in
                    1) reset_config "postgres" ;;
                    2) reset_config "dest" ;;
                    3) reset_config "aws" ;;
                    4) reset_config "s3" ;;
                    5) reset_config "all" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                echo "Invalid option"
                sleep 1
                ;;
        esac
    done
}

action_show_config() {
    clear
    show_configs
    read -p "Press Enter to continue..."
}

action_view_logs() {
    print_section "Backup Logs"

    if [[ ! -d "$LOG_DIR" ]] || [[ -z "$(ls -A "$LOG_DIR" 2>/dev/null)" ]]; then
        log_warning "No log files found"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi

    echo "Recent log files:"
    echo ""

    ls -lt "$LOG_DIR" | head -10 | while read -r line; do
        echo "  $line"
    done

    echo ""
    read -p "Enter log filename to view (or press Enter to skip): " log_file

    if [[ -n "$log_file" && -f "$LOG_DIR/$log_file" ]]; then
        echo ""
        echo "--- Contents of $log_file ---"
        cat "$LOG_DIR/$log_file"
        echo ""
        echo "--- End of file ---"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

action_maintenance() {
    local choice

    while true; do
        clear
        show_maintenance_menu
        read -p "Select option [0-5]: " choice

        case $choice in
            1)
                clear
                _test_db_connection
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                clear
                _test_aws_connection
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                clear
                _clean_old_backups
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                clear
                _view_backup_history
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                clear
                _backup_health_check
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                echo "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Maintenance Functions
# =============================================================================

_test_db_connection() {
    print_section "Test Database Connection"

    if ! load_postgres_config; then
        log_error "PostgreSQL configuration not found"
        return 1
    fi

    echo "Testing connection to:"
    echo "  Host: $PG_HOST"
    echo "  Port: $PG_PORT"
    echo "  Database: $PG_DATABASE"
    echo "  User: $PG_USER"
    echo ""

    if validate_db_connection "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASSWORD" "$PG_DATABASE"; then
        log_success "Database connection successful"

        # Get database info
        export PGPASSWORD="$PG_PASSWORD"
        echo ""
        echo "Database Information:"
        psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
            -c "SELECT version();" -t | head -1
        unset PGPASSWORD
    else
        log_error "Database connection failed"
        echo "  Please check your configuration"
    fi
}

_test_aws_connection() {
    print_section "Test AWS/S3 Connection"

    if ! load_aws_config || ! load_s3_config; then
        log_error "AWS/S3 configuration not found"
        return 1
    fi

    setup_aws_credentials "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_DEFAULT_REGION"

    echo "Testing AWS credentials..."
    echo "  Region: $AWS_DEFAULT_REGION"
    echo ""

    # Test AWS credentials
    if aws sts get-caller-identity > /dev/null 2>&1; then
        log_success "AWS credentials valid"

        echo ""
        echo "AWS Account Info:"
        aws sts get-caller-identity --query 'Account' --output text | \
            awk '{print "  Account ID: " $1}'
    else
        log_error "AWS credentials invalid"
        return 1
    fi

    echo ""
    echo "Testing S3 bucket access..."
    echo "  Bucket: $S3_BUCKET"
    echo ""

    if aws s3 ls "s3://${S3_BUCKET}/" > /dev/null 2>&1; then
        log_success "S3 bucket accessible"

        echo ""
        echo "Backup path contents:"
        aws s3 ls "s3://${S3_BUCKET}/${S3_BACKUP_PATH}/" --recursive 2>/dev/null | \
            head -5 | while read -r line; do
            echo "  $line"
            done
    else
        log_error "Cannot access S3 bucket"
        echo "  Please check bucket name and permissions"
        return 1
    fi
}

_clean_old_backups() {
    print_section "Clean Old Local Backups"

    echo "Local backup directory: $BACKUP_DIR"
    echo ""

    # Show current backups
    echo "Current local backups:"
    find "$BACKUP_DIR" -type f \( -name "*.dump" -o -name "*.sql" \) 2>/dev/null | \
        sort -r | while read -r file; do
        echo "  $(basename "$file") - $(get_file_size "$file")"
    done

    echo ""
    read -p "Keep how many recent backups? [default: 5]: " keep_count
    keep_count=${keep_count:-5}

    echo ""
    log_info "Deleting backups older than last $keep_count..."

    local deleted=0
    find "$BACKUP_DIR" -type f \( -name "*.dump" -o -name "*.sql" \) 2>/dev/null | \
        sort -r | tail -n +$((keep_count + 1)) | while read -r file; do
        echo "  Deleting: $(basename "$file")"
        rm -f "$file"
        ((deleted++))
    done

    echo ""
    log_success "Cleanup completed"
}

_view_backup_history() {
    print_section "Backup History"

    echo "Recent local backups:"
    echo ""

    find "$BACKUP_DIR" -type f \( -name "*.dump" -o -name "*.sql" \) 2>/dev/null | \
        sort -r | head -10 | while read -r file; do
        local name=$(basename "$file")
        local size=$(get_file_size "$file")
        local date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || \
                    stat -c "%y" "$file" 2>/dev/null | cut -d'.' -f1)
        echo "  $name"
        echo "    Size: $size | Date: $date"
        echo ""
    done

    if [[ -f "$LOG_DIR/backup_history.log" ]]; then
        echo "Backup history log:"
        tail -20 "$LOG_DIR/backup_history.log" | while read -r line; do
            echo "  $line"
        done
    fi
}

_backup_health_check() {
    print_section "Backup Health Check"

    local issues=0

    # Check directories
    echo "Checking directories..."
    for dir in "$BACKUP_DIR" "$LOG_DIR" "$CONFIG_DIR"; do
        if [[ -d "$dir" ]]; then
            echo "  ${GREEN}OK${NC} - $dir"
        else
            echo "  ${RED}MISSING${NC} - $dir"
            ((issues++))
        fi
    done

    echo ""

    # Check configs
    echo "Checking configurations..."
    for config in "$PG_CONFIG_FILE" "$AWS_CONFIG_FILE" "$S3_CONFIG_FILE"; do
        if [[ -f "$config" ]]; then
            echo "  ${GREEN}OK${NC} - $(basename "$config")"
        else
            echo "  ${YELLOW}MISSING${NC} - $(basename "$config")"
            ((issues++))
        fi
    done

    echo ""

    # Check required commands
    echo "Checking required commands..."
    for cmd in pg_dump pg_restore psql aws; do
        if command -v "$cmd" &> /dev/null; then
            echo "  ${GREEN}OK${NC} - $cmd"
        else
            echo "  ${RED}MISSING${NC} - $cmd"
            ((issues++))
        fi
    done

    echo ""

    # Check S3 connectivity
    if load_aws_config && load_s3_config; then
        echo "Checking S3 connectivity..."
        setup_aws_credentials "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_DEFAULT_REGION"
        if aws s3 ls "s3://${S3_BUCKET}/" > /dev/null 2>&1; then
            echo "  ${GREEN}OK${NC} - S3 bucket accessible"
        else
            echo "  ${RED}FAILED${NC} - Cannot access S3 bucket"
            ((issues++))
        fi
    fi

    echo ""
    if [[ $issues -eq 0 ]]; then
        log_success "Health check passed - no issues found"
    else
        log_warning "Health check found $issues issue(s)"
    fi
}

# =============================================================================
# Quick Actions (command line arguments)
# =============================================================================

show_quick_help() {
    cat <<EOF
PostgreSQL S3 Backup Manager v${VERSION}

Usage: $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
  backup              Backup database to S3
  restore             Restore database from S3
  list                List available backups in S3
  config              Configure settings
  status              Show current configuration
  logs                View backup logs
  health              Run health check
  menu                Show interactive menu (default)

OPTIONS for backup:
  --plain             Use plain SQL format
  --schema-only       Backup schema only
  --data-only         Backup data only
  --compress          Compress backup file

OPTIONS for restore:
  --clean             Drop existing data before restore
  --create-db         Create database if needed
  --file URI          Specify S3 URI

EXAMPLES:
  $(basename "$0") backup --compress
  $(basename "$0") restore --clean
  $(basename "$0") restore s3://bucket/path/backup.dump
  $(basename "$0") list

For interactive mode, run: $(basename "$0")
EOF
}

# =============================================================================
# Main Program
# =============================================================================

main() {
    # Parse command line arguments
    if [[ $# -gt 0 ]]; then
        case "$1" in
            backup)
                shift
                action_backup "$@"
                exit 0
                ;;
            restore)
                shift
                action_restore "$@"
                exit 0
                ;;
            list)
                action_list
                exit 0
                ;;
            config)
                setup_directories
                if [[ -n "$2" ]]; then
                    case "$2" in
                        postgres|pg) prompt_postgres_config ;;
                        dest|destination) prompt_postgres_dest_config ;;
                        aws) prompt_aws_config ;;
                        s3) prompt_s3_config ;;
                        all) setup_all_configs ;;
                    esac
                else
                    action_configure
                fi
                exit 0
                ;;
            status)
                setup_directories
                show_configs
                exit 0
                ;;
            logs)
                action_view_logs
                exit 0
                ;;
            health)
                setup_directories
                _backup_health_check
                exit 0
                ;;
            -h|--help)
                show_quick_help
                exit 0
                ;;
            menu)
                # Continue to interactive menu
                ;;
            *)
                echo "Unknown command: $1"
                echo ""
                show_quick_help
                exit 1
                ;;
        esac
    fi

    # Setup directories
    setup_directories

    # Interactive menu
    local choice

    while true; do
        show_main_menu
        read -p "Select option [0-7]: " choice

        case $choice in
            1)
                action_backup
                ;;
            2)
                action_restore
                ;;
            3)
                action_list
                ;;
            4)
                action_configure
                ;;
            5)
                action_show_config
                ;;
            6)
                action_view_logs
                ;;
            7)
                action_maintenance
                ;;
            0|q|Q)
                clear
                echo "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Run main
main "$@"
