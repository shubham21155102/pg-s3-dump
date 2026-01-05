#!/bin/bash
# =============================================================================
# Configuration Management Library
# =============================================================================

# Source common library
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Configuration file paths
PG_CONFIG_FILE="$CONFIG_DIR/postgres.conf"
PG_DEST_CONFIG_FILE="$CONFIG_DIR/postgres-dest.conf"
AWS_CONFIG_FILE="$CONFIG_DIR/aws.conf"
S3_CONFIG_FILE="$CONFIG_DIR/s3.conf"

# =============================================================================
# PostgreSQL Configuration Functions
# =============================================================================

prompt_postgres_config() {
    print_section "PostgreSQL Connection Configuration"

    # Check if config exists and ask to reuse
    if [[ -f "$PG_CONFIG_FILE" ]]; then
        if confirm_action "Existing PostgreSQL configuration found. Load it?" "Y"; then
            source "$PG_CONFIG_FILE"
            log_success "Configuration loaded from $PG_CONFIG_FILE"
            echo ""
            echo "  Host:     $PG_HOST"
            echo "  Port:     $PG_PORT"
            echo "  Database: $PG_DATABASE"
            echo "  User:     $PG_USER"
            echo ""
            if ! confirm_action "Use this configuration?" "Y"; then
                _prompt_postgres_new_config
            fi
        else
            _prompt_postgres_new_config
        fi
    else
        _prompt_postgres_new_config
    fi
}

_prompt_postgres_new_config() {
    echo "Enter PostgreSQL connection details:"
    echo ""

    # Host
    read -p "  Host [default: localhost]: " PG_HOST
    PG_HOST="${PG_HOST:-localhost}"

    # Port
    read -p "  Port [default: 5432]: " PG_PORT
    PG_PORT="${PG_PORT:-5432}"

    # Database name
    read -p "  Database name: " PG_DATABASE
    while [[ -z "$PG_DATABASE" ]]; do
        echo -e "${RED}Database name is required${NC}"
        read -p "  Database name: " PG_DATABASE
    done

    # Username
    read -p "  Username [default: postgres]: " PG_USER
    PG_USER="${PG_USER:-postgres}"

    # Password
    echo ""
    read -s -p "  Password: " PG_PASSWORD
    echo ""
    while [[ -z "$PG_PASSWORD" ]]; do
        echo -e "${RED}Password is required${NC}"
        read -s -p "  Password: " PG_PASSWORD
        echo ""
    done

    echo ""

    # Save configuration
    cat > "$PG_CONFIG_FILE" <<EOF
# PostgreSQL Configuration
# Generated: $(get_timestamp)
PG_HOST="$PG_HOST"
PG_PORT="$PG_PORT"
PG_DATABASE="$PG_DATABASE"
PG_USER="$PG_USER"
PG_PASSWORD="$PG_PASSWORD"
EOF

    chmod 600 "$PG_CONFIG_FILE"
    log_success "Configuration saved to $PG_CONFIG_FILE"
}

load_postgres_config() {
    if [[ -f "$PG_CONFIG_FILE" ]]; then
        source "$PG_CONFIG_FILE"
        log_debug "PostgreSQL config loaded"
        return 0
    else
        log_error "PostgreSQL configuration not found"
        log_info "Run the script with --config to set up configuration"
        return 1
    fi
}

# =============================================================================
# PostgreSQL Destination Configuration (for Restore)
# =============================================================================

prompt_postgres_dest_config() {
    print_section "Destination Database Configuration (for Restore)"

    # Check if config exists and ask to reuse
    if [[ -f "$PG_DEST_CONFIG_FILE" ]]; then
        if confirm_action "Existing destination database configuration found. Load it?" "Y"; then
            source "$PG_DEST_CONFIG_FILE"
            log_success "Destination configuration loaded"
            echo ""
            echo "  Host:     $DEST_PG_HOST"
            echo "  Port:     $DEST_PG_PORT"
            echo "  Database: $DEST_PG_DATABASE"
            echo "  User:     $DEST_PG_USER"
            echo ""
            if ! confirm_action "Use this configuration?" "Y"; then
                _prompt_postgres_dest_new_config
            fi
        else
            _prompt_postgres_dest_new_config
        fi
    else
        _prompt_postgres_dest_new_config
    fi
}

_prompt_postgres_dest_new_config() {
    echo "Enter destination PostgreSQL connection details:"
    echo ""
    echo -e "${YELLOW}This is the database where backups will be restored${NC}"
    echo ""

    # Host
    read -p "  Host [default: localhost]: " DEST_PG_HOST
    DEST_PG_HOST="${DEST_PG_HOST:-localhost}"

    # Port
    read -p "  Port [default: 5432]: " DEST_PG_PORT
    DEST_PG_PORT="${DEST_PG_PORT:-5432}"

    # Database name
    read -p "  Database name: " DEST_PG_DATABASE
    while [[ -z "$DEST_PG_DATABASE" ]]; do
        echo -e "${RED}Database name is required${NC}"
        read -p "  Database name: " DEST_PG_DATABASE
    done

    # Username
    read -p "  Username [default: postgres]: " DEST_PG_USER
    DEST_PG_USER="${DEST_PG_USER:-postgres}"

    # Password
    echo ""
    read -s -p "  Password: " DEST_PG_PASSWORD
    echo ""
    while [[ -z "$DEST_PG_PASSWORD" ]]; do
        echo -e "${RED}Password is required${NC}"
        read -s -p "  Password: " DEST_PG_PASSWORD
        echo ""
    done

    echo ""

    # Save configuration
    cat > "$PG_DEST_CONFIG_FILE" <<EOF
# PostgreSQL Destination Configuration (for Restore)
# Generated: $(get_timestamp)
DEST_PG_HOST="$DEST_PG_HOST"
DEST_PG_PORT="$DEST_PG_PORT"
DEST_PG_DATABASE="$DEST_PG_DATABASE"
DEST_PG_USER="$DEST_PG_USER"
DEST_PG_PASSWORD="$DEST_PG_PASSWORD"
EOF

    chmod 600 "$PG_DEST_CONFIG_FILE"
    log_success "Destination configuration saved to $PG_DEST_CONFIG_FILE"
}

load_postgres_dest_config() {
    if [[ -f "$PG_DEST_CONFIG_FILE" ]]; then
        source "$PG_DEST_CONFIG_FILE"
        # Use destination config for restore operations
        PG_HOST="$DEST_PG_HOST"
        PG_PORT="$DEST_PG_PORT"
        PG_DATABASE="$DEST_PG_DATABASE"
        PG_USER="$DEST_PG_USER"
        PG_PASSWORD="$DEST_PG_PASSWORD"
        log_debug "PostgreSQL destination config loaded"
        return 0
    else
        log_debug "No destination config found, using source config"
        return 1
    fi
}

use_destination_db() {
    # Set database variables from destination config
    PG_HOST="${DEST_PG_HOST:-$PG_HOST}"
    PG_PORT="${DEST_PG_PORT:-$PG_PORT}"
    PG_DATABASE="${DEST_PG_DATABASE:-$PG_DATABASE}"
    PG_USER="${DEST_PG_USER:-$PG_USER}"
    PG_PASSWORD="${DEST_PG_PASSWORD:-$PG_PASSWORD}"
}

# =============================================================================
# AWS Configuration Functions
# =============================================================================

prompt_aws_config() {
    print_section "AWS Configuration"

    # Check if config exists
    if [[ -f "$AWS_CONFIG_FILE" ]]; then
        if confirm_action "Existing AWS configuration found. Load it?" "Y"; then
            source "$AWS_CONFIG_FILE"
            log_success "Configuration loaded"
            echo ""
            echo "  Access Key: ${AWS_ACCESS_KEY_ID:0:8}..."
            echo "  Region:     $AWS_DEFAULT_REGION"
            echo ""
            if ! confirm_action "Use this configuration?" "Y"; then
                _prompt_aws_new_config
            fi
        else
            _prompt_aws_new_config
        fi
    else
        _prompt_aws_new_config
    fi
}

_prompt_aws_new_config() {
    echo "Enter AWS credentials:"
    echo ""

    # Access Key
    read -p "  AWS Access Key ID: " AWS_ACCESS_KEY_ID
    while [[ -z "$AWS_ACCESS_KEY_ID" ]]; do
        echo -e "${RED}Access Key ID is required${NC}"
        read -p "  AWS Access Key ID: " AWS_ACCESS_KEY_ID
    done

    # Secret Key
    read -s -p "  AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    while [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; do
        echo -e "${RED}Secret Access Key is required${NC}"
        read -s -p "  AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo ""
    done

    # Region
    echo ""
    read -p "  AWS Region [default: us-east-1]: " AWS_DEFAULT_REGION
    AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

    echo ""

    # Save configuration
    cat > "$AWS_CONFIG_FILE" <<EOF
# AWS Configuration
# Generated: $(get_timestamp)
AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION"
EOF

    chmod 600 "$AWS_CONFIG_FILE"
    log_success "AWS credentials saved to $AWS_CONFIG_FILE"
    log_warning "File permissions set to 600 (read/write for owner only)"
}

load_aws_config() {
    if [[ -f "$AWS_CONFIG_FILE" ]]; then
        source "$AWS_CONFIG_FILE"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
        export AWS_DEFAULT_REGION
        log_debug "AWS config loaded and exported"
        return 0
    else
        log_error "AWS configuration not found"
        return 1
    fi
}

# =============================================================================
# S3 Configuration Functions
# =============================================================================

prompt_s3_config() {
    print_section "S3 Configuration"

    # Check if config exists
    if [[ -f "$S3_CONFIG_FILE" ]]; then
        if confirm_action "Existing S3 configuration found. Load it?" "Y"; then
            source "$S3_CONFIG_FILE"
            log_success "Configuration loaded"
            echo ""
            echo "  Bucket:     $S3_BUCKET"
            echo "  Backup Path: $S3_BACKUP_PATH"
            echo ""
            if ! confirm_action "Use this configuration?" "Y"; then
                _prompt_s3_new_config
            fi
        else
            _prompt_s3_new_config
        fi
    else
        _prompt_s3_new_config
    fi
}

_prompt_s3_new_config() {
    echo "Enter S3 bucket details:"
    echo ""

    # Bucket name
    read -p "  S3 Bucket Name: " S3_BUCKET
    while [[ -z "$S3_BUCKET" ]]; do
        echo -e "${RED}Bucket name is required${NC}"
        read -p "  S3 Bucket Name: " S3_BUCKET
    done

    # Backup path prefix
    read -p "  Backup Path Prefix [default: postgres-backups]: " S3_BACKUP_PATH
    S3_BACKUP_PATH="${S3_BACKUP_PATH:-postgres-backups}"

    echo ""

    # Save configuration
    cat > "$S3_CONFIG_FILE" <<EOF
# S3 Configuration
# Generated: $(get_timestamp)
S3_BUCKET="$S3_BUCKET"
S3_BACKUP_PATH="$S3_BACKUP_PATH"
EOF

    chmod 600 "$S3_CONFIG_FILE"
    log_success "S3 configuration saved"
}

load_s3_config() {
    if [[ -f "$S3_CONFIG_FILE" ]]; then
        source "$S3_CONFIG_FILE"
        log_debug "S3 config loaded"
        return 0
    else
        log_error "S3 configuration not found"
        return 1
    fi
}

# =============================================================================
# Full Configuration Setup
# =============================================================================

setup_all_configs() {
    prompt_postgres_config
    prompt_aws_config
    prompt_s3_config

    echo ""
    log_success "All configurations completed!"
    echo ""
}

# =============================================================================
# Configuration Display
# =============================================================================

show_configs() {
    print_section "Current Configuration"

    echo -e "${CYAN}PostgreSQL (Source - for Backup):${NC}"
    if [[ -f "$PG_CONFIG_FILE" ]]; then
        source "$PG_CONFIG_FILE"
        echo "  Config File: $PG_CONFIG_FILE"
        echo "  Host:        $PG_HOST"
        echo "  Port:        $PG_PORT"
        echo "  Database:    $PG_DATABASE"
        echo "  User:        $PG_USER"
    else
        echo "  ${YELLOW}Not configured${NC}"
    fi

    echo ""
    echo -e "${CYAN}PostgreSQL (Destination - for Restore):${NC}"
    if [[ -f "$PG_DEST_CONFIG_FILE" ]]; then
        source "$PG_DEST_CONFIG_FILE"
        echo "  Config File: $PG_DEST_CONFIG_FILE"
        echo "  Host:        $DEST_PG_HOST"
        echo "  Port:        $DEST_PG_PORT"
        echo "  Database:    $DEST_PG_DATABASE"
        echo "  User:        $DEST_PG_USER"
    else
        echo "  ${YELLOW}Not configured (will use source)${NC}"
    fi

    echo ""
    echo -e "${CYAN}AWS:${NC}"
    if [[ -f "$AWS_CONFIG_FILE" ]]; then
        source "$AWS_CONFIG_FILE"
        echo "  Config File:   $AWS_CONFIG_FILE"
        echo "  Access Key:    ${AWS_ACCESS_KEY_ID:0:8}..."
        echo "  Region:        $AWS_DEFAULT_REGION"
    else
        echo "  ${YELLOW}Not configured${NC}"
    fi

    echo ""
    echo -e "${CYAN}S3:${NC}"
    if [[ -f "$S3_CONFIG_FILE" ]]; then
        source "$S3_CONFIG_FILE"
        echo "  Config File:     $S3_CONFIG_FILE"
        echo "  Bucket:          $S3_BUCKET"
        echo "  Backup Path:     $S3_BACKUP_PATH"
    else
        echo "  ${YELLOW}Not configured${NC}"
    fi

    echo ""
}

# =============================================================================
# Configuration Reset
# =============================================================================

reset_config() {
    local config_type="$1"

    case "$config_type" in
        postgres|pg)
            if [[ -f "$PG_CONFIG_FILE" ]]; then
                rm -f "$PG_CONFIG_FILE"
                log_success "PostgreSQL configuration deleted"
            fi
            ;;
        dest|destination)
            if [[ -f "$PG_DEST_CONFIG_FILE" ]]; then
                rm -f "$PG_DEST_CONFIG_FILE"
                log_success "Destination PostgreSQL configuration deleted"
            fi
            ;;
        aws)
            if [[ -f "$AWS_CONFIG_FILE" ]]; then
                rm -f "$AWS_CONFIG_FILE"
                log_success "AWS configuration deleted"
            fi
            ;;
        s3)
            if [[ -f "$S3_CONFIG_FILE" ]]; then
                rm -f "$S3_CONFIG_FILE"
                log_success "S3 configuration deleted"
            fi
            ;;
        all)
            rm -f "$PG_CONFIG_FILE" "$PG_DEST_CONFIG_FILE" "$AWS_CONFIG_FILE" "$S3_CONFIG_FILE"
            log_success "All configurations deleted"
            ;;
        *)
            log_error "Unknown config type: $config_type"
            echo "  Valid options: postgres, dest, aws, s3, all"
            return 1
            ;;
    esac

    return 0
}
