#!/bin/bash
# =============================================================================
# Common Library Functions
# =============================================================================

# Colors for output (only define if not already set)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' # No Color

# Directory paths
# Detect if we're being sourced from lib/ or from bin/
CURRENT_FILE="${BASH_SOURCE[0]}"
LIB_DIR="$(cd "$(dirname "$CURRENT_FILE")" && pwd)"
PROJECT_ROOT="$(dirname "$LIB_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
BACKUP_DIR="$PROJECT_ROOT/backups"
LOG_DIR="$PROJECT_ROOT/logs"

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# =============================================================================
# Banner Functions
# =============================================================================

print_banner() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title} - 2) / 2 ))

    echo ""
    echo -e "${GREEN}$(printf '=%.0s' $(seq 1 $width))${NC}"
    printf "${GREEN}%${padding}s%s%${padding}s${NC}\n" "" "$title" ""
    echo -e "${GREEN}$(printf '=%.0s' $(seq 1 $width))${NC}"
    echo ""
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# =============================================================================
# Directory Setup
# =============================================================================

setup_directories() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$CONFIG_DIR"
    log_debug "Directories created/verified"
}

# =============================================================================
# Timestamp Functions
# =============================================================================

get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

get_date() {
    date +"%Y-%m-%d"
}

# =============================================================================
# File Size Function
# =============================================================================

get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        du -h "$file" | cut -f1
    else
        echo "N/A"
    fi
}

# =============================================================================
# Confirmation Prompt
# =============================================================================

confirm_action() {
    local message="$1"
    local default="${2:-N}"

    if [[ "$default" == "Y" ]]; then
        local prompt="$message [Y/n]: "
    else
        local prompt="$message [y/N]: "
    fi

    read -p "$prompt" -r response
    response="${response:-$default}"

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_required_commands() {
    local missing_commands=()

    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        echo "  Please install the missing commands and try again."
        return 1
    fi

    return 0
}

validate_db_connection() {
    local pghost="$1"
    local pgport="$2"
    local pguser="$3"
    local pgpassword="$4"
    local pgdatabase="$5"

    export PGPASSWORD="$pgpassword"

    if pg_isready -h "$pghost" -p "$pgport" -U "$pguser" -t 5 &> /dev/null; then
        unset PGPASSWORD
        return 0
    else
        unset PGPASSWORD
        return 1
    fi
}

# =============================================================================
# AWS Configuration Functions
# =============================================================================

setup_aws_credentials() {
    local aws_access_key="$1"
    local aws_secret_key="$2"
    local aws_region="${3:-us-east-1}"

    export AWS_ACCESS_KEY_ID="$aws_access_key"
    export AWS_SECRET_ACCESS_KEY="$aws_secret_key"
    export AWS_DEFAULT_REGION="$aws_region"

    log_debug "AWS credentials configured for region: $aws_region"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        echo "  To install AWS CLI, visit: https://aws.amazon.com/cli/"
        echo "  macOS: brew install awscli"
        echo "  Linux: apt-get install awscli or yum install awscli"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed (optional, for better JSON parsing)"
        echo "  To install: brew install jq"
    fi

    return 0
}

# =============================================================================
# Cleanup Function
# =============================================================================

cleanup() {
    log_debug "Performing cleanup..."
    if [[ -n "${PGPASSWORD:-}" ]]; then
        unset PGPASSWORD
    fi
}

# Trap cleanup on exit
trap cleanup EXIT
