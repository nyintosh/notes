#!/bin/bash

# Enhanced Server Setup Script
# Supports PostgreSQL, Apache2/PHP/Composer, Yii2, and Vue.js applications

set -euo pipefail # Exit on error, undefined variables, pipe failures

# Color definitions for better output
readonly RED='\033[31m'
readonly GREEN='\033[32m' 
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly PURPLE='\033[35m'
readonly CYAN='\033[36m'
readonly WHITE='\033[37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Global variables 
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/server_setup_$(date +%Y%m%d_%H%M%S).log"
readonly BACKUP_DIR="/tmp/server_setup_backup_$(date +%Y%m%d_%H%M%S)"

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"

# Set strict permissions
chmod 700 "$(dirname "$LOG_FILE")" "$BACKUP_DIR"

# Logging function with timestamps
log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

# Enhanced output functions with proper escaping
print_header() {
    printf "\n${BOLD}${BLUE}================================${NC}\n"
    printf "${BOLD}${BLUE}%s${NC}\n" "$1"
    printf "${BOLD}${BLUE}================================${NC}\n\n"
}

print_success() {
    printf "${GREEN}✅ %s${NC}\n" "$1"
    log "SUCCESS: $1"
}

print_error() {
    printf "${RED}❌ ERROR: %s${NC}\n" "$1" >&2
    log "ERROR: $1"
}

print_warning() {
    printf "${YELLOW}⚠️  WARNING: %s${NC}\n" "$1"
    log "WARNING: $1"
}

print_info() {
    printf "${CYAN}ℹ️  %s${NC}\n" "$1"
}

print_step() {
    printf "${PURPLE}🔄 %s${NC}\n" "$1"
    log "STEP: $1"
}

# Enhanced error handling with cleanup
cleanup() {
    local exit_code=$?
    
    # Only show backup info if directory exists and contains files
    if [[ -d "$BACKUP_DIR" ]] && [[ "$(ls -A "$BACKUP_DIR")" ]]; then
        print_info "Backup files available at: $BACKUP_DIR"
    fi

    if [[ -f "$LOG_FILE" ]]; then
        print_info "Full log available at: $LOG_FILE" 
    fi

    # Remove empty directories
    rmdir "$BACKUP_DIR" 2>/dev/null || true
    rmdir "$(dirname "$LOG_FILE")" 2>/dev/null || true

    exit $exit_code
}

trap cleanup EXIT
trap 'echo "Script interrupted" >&2; exit 1' INT TERM

# Enhanced rollback function
rollback_changes() {
    local operation="$1"
    print_warning "Rolling back changes for: $operation"

    case "$operation" in
        apache_config)
            if [[ -n "${SITE_NAME:-}" ]] && [[ -f "/etc/apache2/sites-available/$SITE_NAME.conf" ]]; then
                sudo a2dissite "$SITE_NAME.conf" &>/dev/null || true
                sudo rm -f "/etc/apache2/sites-available/$SITE_NAME.conf"
                sudo systemctl reload apache2 &>/dev/null || true
            fi
            ;;
            
        web_directory)
            if [[ -n "${SITE_NAME:-}" ]] && [[ -d "/var/www/$SITE_NAME" ]]; then
                sudo rm -rf "/var/www/$SITE_NAME"
            fi
            ;;
            
        git_directory) 
            if [[ -n "${SITE_NAME:-}" ]] && [[ -d "/var/repo/$SITE_NAME.git" ]]; then
                sudo rm -rf "/var/repo/$SITE_NAME.git"
            fi
            ;;
    esac
}

# Enhanced command execution with timeouts
execute_command() {
    local cmd="$1"
    local description="$2"
    local allow_failure="${3:-false}"
    local timeout="${4:-300}" # 5 minute default timeout

    print_step "$description"

    # Use timeout command if available
    if command -v timeout >/dev/null 2>&1; then
        if ! timeout "$timeout" bash -c "$cmd" >>"$LOG_FILE" 2>&1; then
            if [[ "$allow_failure" == "true" ]]; then
                print_warning "Command failed but continuing: $description"
                return 1
            else
                print_error "Failed to execute: $description"
                print_error "Command: $cmd"
                exit 1
            fi
        fi
    else
        # Fallback if timeout not available
        if ! eval "$cmd" >>"$LOG_FILE" 2>&1; then
            if [[ "$allow_failure" == "true" ]]; then
                print_warning "Command failed but continuing: $description"
                return 1
            else  
                print_error "Failed to execute: $description"
                print_error "Command: $cmd"
                exit 1
            fi
        fi
    fi

    print_success "$description completed"
    return 0
}

# Rest of functions remain the same...

# Main execution with enhanced error handling
main() {
    # Check if script is sourced
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        print_error "This script should not be sourced"
        return 1
    fi

    # Verify bash version >= 4
    if ((BASH_VERSINFO[0] < 4)); then
        print_error "Bash version 4 or higher required"
        exit 1
    fi

    print_header "Server Setup Script v2.0"
    print_info "Log file: $LOG_FILE"

    # System checks with timeout
    execute_command "check_system_requirements" "System requirement checks" false 60

    # Get user choices
    get_application_choice

    # Handle different installation types
    case $APP_CHOICE in
        1) install_postgresql ;; 
        2) install_apache_php ;;
        3|4)
            get_site_configuration

            # Install base components if needed
            if ! systemctl is-active --quiet apache2 2>/dev/null; then
                install_apache_php
            fi

            # Setup with proper error handling
            setup_web_directory || {
                rollback_changes "web_directory"
                exit 1
            }

            if [[ $APP_CHOICE == "3" ]]; then
                setup_git_repository || {
                    rollback_changes "git_directory" 
                    exit 1
                }
            fi

            setup_apache_virtualhost || {
                rollback_changes "apache_config"
                exit 1  
            }

            configure_hostname

            display_completion_message
            ;;
        *)
            print_error "Invalid application choice"
            exit 1
            ;;
    esac

    print_success "Script execution completed successfully"
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
