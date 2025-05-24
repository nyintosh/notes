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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/server_setup_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/tmp/server_setup_backup_$(date +%Y%m%d_%H%M%S)"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Enhanced output functions
print_header() {
    echo -e "\n${BOLD}${BLUE}================================${NC}"
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BOLD}${BLUE}================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    log "ERROR: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
    log "WARNING: $1"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_step() {
    echo -e "${PURPLE}🔄 $1${NC}"
    log "STEP: $1"
}

# Enhanced error handling with cleanup
cleanup() {
    if [[ -d "$BACKUP_DIR" ]]; then
        print_info "Backup files available at: $BACKUP_DIR"
    fi
    print_info "Full log available at: $LOG_FILE"
}

trap cleanup EXIT

# Rollback function for critical failures
rollback_changes() {
    local operation="$1"
    print_warning "Rolling back changes for: $operation"

    case "$operation" in
    "apache_config")
        if [[ -n "${SITE_NAME:-}" && -f "/etc/apache2/sites-available/$SITE_NAME.conf" ]]; then
            sudo a2dissite "$SITE_NAME.conf" 2>/dev/null || true
            sudo rm -f "/etc/apache2/sites-available/$SITE_NAME.conf"
            sudo systemctl reload apache2 2>/dev/null || true
        fi
        ;;
    "web_directory")
        if [[ -n "${SITE_NAME:-}" && -d "/var/www/$SITE_NAME" ]]; then
            sudo rm -rf "/var/www/$SITE_NAME"
        fi
        ;;
    "git_directory")
        if [[ -n "${SITE_NAME:-}" && -d "/var/repo/$SITE_NAME.git" ]]; then
            sudo rm -rf "/var/repo/$SITE_NAME.git"
        fi
        ;;
    esac
}

# Enhanced command execution with better error handling
execute_command() {
    local cmd="$1"
    local description="$2"
    local allow_failure="${3:-false}"

    print_step "$description"

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

    print_success "$description completed"
    return 0
}

# System requirements check
check_system_requirements() {
    print_header "System Requirements Check"

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons"
        print_info "Please run as a regular user with sudo privileges"
        exit 1
    fi

    # Check sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_info "Checking sudo privileges..."
        sudo -v || {
            print_error "This script requires sudo privileges"
            exit 1
        }
    fi

    # Check available disk space (minimum 1GB)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then
        print_warning "Less than 1GB of disk space available"
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Check internet connectivity
    if ! ping -c 1 google.com &>/dev/null; then
        print_error "No internet connection detected"
        print_info "Internet connection is required for package installation"
        exit 1
    fi

    print_success "System requirements check passed"
}

# Enhanced input validation
validate_site_name() {
    local name="$1"

    # Check for valid characters (alphanumeric, hyphens, dots)
    if [[ ! $name =~ ^[a-zA-Z0-9.-]+$ ]]; then
        return 1
    fi

    # Check length
    if [[ ${#name} -lt 3 || ${#name} -gt 63 ]]; then
        return 1
    fi

    # Check for reserved names
    local reserved_names=("localhost" "www" "mail" "ftp" "admin" "root" "test")
    for reserved in "${reserved_names[@]}"; do
        if [[ "$name" == "$reserved" ]]; then
            return 1
        fi
    done

    return 0
}

validate_email() {
    local email="$1"
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Enhanced user input functions
get_application_choice() {
    print_header "Application Setup Selection"

    while true; do
        echo -e "${BOLD}🎯 Choose the application type to set up:${NC}"
        echo -e "  ${CYAN}1)${NC} PostgreSQL installation only"
        echo -e "  ${CYAN}2)${NC} Apache2 + PHP + Composer installation only"
        echo -e "  ${CYAN}3)${NC} Complete Yii2 application setup"
        echo -e "  ${CYAN}4)${NC} Complete Vue.js application setup"
        echo -e "  ${CYAN}5)${NC} Exit"
        echo

        read -p "Enter your choice (1-5): " -r APP_CHOICE

        case $APP_CHOICE in
        [1-5])
            if [[ $APP_CHOICE == "5" ]]; then
                print_info "Setup cancelled by user"
                exit 0
            fi
            break
            ;;
        *)
            print_error "Invalid choice! Please select 1-5"
            ;;
        esac
    done

    log "User selected application type: $APP_CHOICE"
}

get_site_configuration() {
    print_header "Site Configuration"

    # Get site name
    while true; do
        read -p "Enter the site name (e.g., myapp.local): " -r SITE_NAME

        if validate_site_name "$SITE_NAME"; then
            # Check if directory already exists
            if [[ -d "/var/www/$SITE_NAME" ]]; then
                print_warning "Directory /var/www/$SITE_NAME already exists"
                read -p "Do you want to remove it and continue? (y/N): " -r
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    execute_command "sudo rm -rf /var/www/$SITE_NAME" "Removing existing directory"
                    break
                else
                    continue
                fi
            else
                break
            fi
        else
            print_error "Invalid site name! Use only letters, numbers, hyphens, and dots (3-63 characters)"
        fi
    done

    # Get admin email
    while true; do
        read -p "Enter admin email: " -r SITE_ADMIN
        if validate_email "$SITE_ADMIN"; then
            break
        else
            print_error "Invalid email format!"
        fi
    done

    # Configure hostname
    read -p "Configure hostname in /etc/hosts? (Y/n): " -r CONFIG_HOSTNAME
    CONFIG_HOSTNAME=${CONFIG_HOSTNAME:-Y}

    print_info "Site configuration:"
    print_info "  - Site name: $SITE_NAME"
    print_info "  - Admin email: $SITE_ADMIN"
    print_info "  - Configure hostname: $CONFIG_HOSTNAME"
}

# Backup existing configurations
create_backup() {
    local file_path="$1"
    local backup_name="$2"

    if [[ -f "$file_path" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file_path" "$BACKUP_DIR/$backup_name.backup"
        print_info "Backed up $file_path to $BACKUP_DIR/$backup_name.backup"
    fi
}

# Enhanced PostgreSQL installation
install_postgresql() {
    print_header "PostgreSQL Installation"

    # Check if already installed
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        print_warning "PostgreSQL is already installed and running"
        local version
        version=$(sudo -u postgres psql -c "SELECT version();" 2>/dev/null | head -1 || echo "Unknown")
        print_info "Current version: $version"

        read -p "Continue with configuration? (Y/n): " -r
        if [[ ! ${REPLY:-Y} =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    execute_command "sudo apt update" "Updating package index"
    execute_command "sudo apt install -y postgresql postgresql-contrib" "Installing PostgreSQL"
    execute_command "sudo systemctl enable postgresql" "Enabling PostgreSQL service"
    execute_command "sudo systemctl start postgresql" "Starting PostgreSQL service"

    print_success "PostgreSQL installation completed"

    # Post-installation guidance
    echo -e "${YELLOW}3. Configure authentication:${NC}"
    echo -e "   Edit: ${CYAN}/etc/postgresql/*/main/pg_hba.conf${NC}"
    echo -e "   Example secure configuration:"
    echo -e "   ${CYAN}local   all             postgres                               scram-sha-256${NC}"
    echo -e "   ${CYAN}host    all             all             192.168.1.0/24         scram-sha-256${NC}\n"

    echo -e "${YELLOW}4. Restart PostgreSQL after configuration:${NC}"
    echo -e "   ${CYAN}sudo systemctl restart postgresql${NC}\n"

    echo -e "${YELLOW}5. Test connection:${NC}"
    echo -e "   ${CYAN}sudo -u postgres psql -c 'SELECT version();'${NC}\n"

    echo -e "${YELLOW}6. Login and access PostgreSQL:${NC}"
    echo -e "   ${CYAN}psql -U postgres -W${NC}"
    echo -e "   ${CYAN}# Enter your postgres user password when prompted${NC}"
    echo -e "   ${CYAN}# Use \\l to list databases, \\q to quit${NC}\n"

    # Post-installation guidance
    print_header "PostgreSQL Configuration Guide"
    echo -e "${YELLOW}📋 Essential PostgreSQL Configuration Steps:${NC}\n"

    echo -e "${YELLOW}1. Set PostgreSQL superuser password:${NC}"
    echo -e "   ${CYAN}sudo -u postgres psql${NC}"
    echo -e "   ${CYAN}ALTER USER postgres WITH ENCRYPTED PASSWORD 'your_secure_password';${NC}"
    echo -e "   ${CYAN}\\q${NC}\n"

    echo -e "${YELLOW}2. Configure authentication (Required):${NC}"
    echo -e "   Edit: ${CYAN}sudo nano /etc/postgresql/*/main/pg_hba.conf${NC}"
    echo -e "   ${YELLOW}Change this line:${NC}"
    echo -e "   ${RED}local   all             postgres                                peer${NC}"
    echo -e "   ${YELLOW}To this:${NC}"
    echo -e "   ${GREEN}local   all             postgres                                scram-sha-256${NC}"
    echo -e "   ${YELLOW}Ensure other entries use scram-sha-256:${NC}"
    echo -e "   ${CYAN}local   all             all                                     scram-sha-256${NC}"
    echo -e "   ${CYAN}host    all             all             127.0.0.1/32            scram-sha-256${NC}\n"

    echo -e "${YELLOW}3. Configure network access (Optional - for remote connections):${NC}"
    echo -e "   Edit: ${CYAN}sudo nano /etc/postgresql/*/main/postgresql.conf${NC}"
    echo -e "   Find and modify: ${CYAN}listen_addresses = 'localhost'${NC}"
    echo -e "   ${GRAY}# Use 'localhost' for local only, or '*' for all interfaces${NC}\n"

    echo -e "${YELLOW}4. Restart PostgreSQL service:${NC}"
    echo -e "   ${CYAN}sudo systemctl restart postgresql${NC}"
    echo -e "   ${CYAN}sudo systemctl status postgresql${NC} ${GRAY}# Verify it's running${NC}\n"

    echo -e "${YELLOW}5. Test connection methods:${NC}"
    echo -e "   ${YELLOW}Initial test (should work immediately):${NC}"
    echo -e "   ${CYAN}sudo -u postgres psql -c 'SELECT version();'${NC}"
    echo -e "   ${YELLOW}Password authentication test:${NC}"
    echo -e "   ${CYAN}psql -U postgres -W${NC}"
    echo -e "   ${CYAN}psql -h localhost -U postgres -W${NC} ${GRAY}# If socket connection fails${NC}\n"

    echo -e "${YELLOW}6. Essential PostgreSQL commands:${NC}"
    echo -e "   ${YELLOW}Connection commands:${NC}"
    echo -e "   ${CYAN}psql -U postgres -W${NC}                    ${GRAY}# Connect with password${NC}"
    echo -e "   ${CYAN}psql -U postgres -d database_name -W${NC}   ${GRAY}# Connect to specific DB${NC}"
    echo -e "   ${CYAN}psql -h localhost -U postgres -W${NC}       ${GRAY}# Force TCP connection${NC}"
    echo -e "   ${YELLOW}Inside PostgreSQL:${NC}"
    echo -e "   ${CYAN}\\l${NC}                                      ${GRAY}# List all databases${NC}"
    echo -e "   ${CYAN}\\du${NC}                                     ${GRAY}# List all users/roles${NC}"
    echo -e "   ${CYAN}\\c database_name${NC}                       ${GRAY}# Switch to database${NC}"
    echo -e "   ${CYAN}\\dt${NC}                                     ${GRAY}# List tables in current DB${NC}"
    echo -e "   ${CYAN}\\q${NC}                                      ${GRAY}# Quit PostgreSQL${NC}\n"

    echo -e "${YELLOW}7. Create your first database and user:${NC}"
    echo -e "   ${CYAN}CREATE DATABASE myapp;${NC}"
    echo -e "   ${CYAN}CREATE USER myuser WITH ENCRYPTED PASSWORD 'mypassword';${NC}"
    echo -e "   ${CYAN}GRANT ALL PRIVILEGES ON DATABASE myapp TO myuser;${NC}"
    echo -e "   ${CYAN}\\q${NC}\n"

    echo -e "${YELLOW}🔧 Troubleshooting:${NC}"
    echo -e "${RED}• Peer authentication failed:${NC} Check pg_hba.conf configuration (Step 2)"
    echo -e "${RED}• Connection refused:${NC} Ensure PostgreSQL service is running (Step 4)"
    echo -e "${RED}• Password authentication failed:${NC} Verify password was set correctly (Step 1)\n"

    print_info "PostgreSQL service status:"
    sudo systemctl status postgresql --no-pager -l
}

# Enhanced Apache/PHP installation
install_apache_php() {
    print_header "Apache2, PHP & Composer Installation"

    # Check existing installations
    if systemctl is-active --quiet apache2 2>/dev/null; then
        print_warning "Apache2 is already running"
        apache2 -v 2>/dev/null || true
    fi

    if command -v php &>/dev/null; then
        print_warning "PHP is already installed"
        php --version | head -1
    fi

    if command -v composer &>/dev/null; then
        print_warning "Composer is already installed"
        composer --version 2>/dev/null || true
    fi

    execute_command "sudo apt update" "Updating package index"

    # Install Apache2 and PHP with comprehensive modules
    local php_packages=(
        "apache2"
        "php"
        "libapache2-mod-php"
        "php-pgsql"
        "php-mysql"
        "php-xml"
        "php-mbstring"
        "php-curl"
        "php-gd"
        "php-zip"
        "php-intl"
        "php-bcmath"
        "php-json"
        "unzip"
        "curl"
        "git"
    )

    execute_command "sudo apt install -y ${php_packages[*]}" "Installing Apache2 and PHP packages"
    execute_command "sudo systemctl enable apache2" "Enabling Apache2 service"
    execute_command "sudo systemctl start apache2" "Starting Apache2 service"

    # Install Composer
    if ! command -v composer &>/dev/null; then
        print_step "Installing Composer"
        cd /tmp || exit 1

        # Download and verify Composer installer
        execute_command "curl -sS https://getcomposer.org/installer -o composer-setup.php" "Downloading Composer installer"

        # Install Composer globally
        execute_command "sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer" "Installing Composer globally"
        execute_command "rm composer-setup.php" "Cleaning up Composer installer"
    fi

    # Configure Apache modules
    execute_command "sudo a2enmod rewrite" "Enabling mod_rewrite"
    execute_command "sudo a2enmod headers" "Enabling mod_headers"
    execute_command "sudo a2enmod ssl" "Enabling mod_ssl" "true"

    execute_command "sudo systemctl restart apache2" "Restarting Apache2"

    print_success "Apache2, PHP, and Composer installation completed"

    # Display versions
    print_info "Installed versions:"
    apache2 -v | head -1
    php --version | head -1
    composer --version 2>/dev/null || echo "Composer: Failed to get version"

    # Security recommendations
    print_header "Security Recommendations"
    echo -e "${YELLOW}🔒 Consider implementing these security measures:${NC}\n"
    echo -e "1. Hide PHP version: Add ${CYAN}expose_php = Off${NC} to php.ini"
    echo -e "2. Configure firewall: ${CYAN}sudo ufw enable && sudo ufw allow 22,80,443/tcp${NC}"
    echo -e "3. Set proper file permissions for web directories"
    echo -e "4. Configure SSL/TLS certificates for HTTPS"
    echo -e "5. Regular security updates: ${CYAN}sudo apt update && sudo apt upgrade${NC}"
}

# Enhanced directory setup with proper permissions
setup_web_directory() {
    local dir_path="/var/www/$SITE_NAME"
    local current_user
    current_user=$(whoami)

    print_step "Setting up web directory: $dir_path"

    # Create directory structure
    execute_command "sudo mkdir -p '$dir_path'" "Creating web directory"

    # Set ownership and permissions
    execute_command "sudo chown '$current_user':www-data '$dir_path'" "Setting directory ownership"
    execute_command "sudo chmod 755 '$dir_path'" "Setting directory permissions"

    # Create index file for testing
    if [[ $APP_CHOICE == "4" ]]; then
        # Vue.js placeholder
        execute_command "echo '<!DOCTYPE html><html><head><title>$SITE_NAME</title></head><body><h1>Vue.js App: $SITE_NAME</h1><p>Deploy your built Vue.js application here.</p></body></html>' > '$dir_path/index.html'" "Creating placeholder index.html"
    elif [[ $APP_CHOICE == "3" ]]; then
        # Yii2 will have its own structure
        print_info "Yii2 application structure will be created after Git deployment"
    fi

    print_success "Web directory setup completed"
}

# Enhanced Git repository setup for Yii2
setup_git_repository() {
    local repo_path="/var/repo/$SITE_NAME.git"
    local current_user
    current_user=$(whoami)

    print_step "Setting up Git repository: $repo_path"

    execute_command "sudo mkdir -p '$repo_path'" "Creating Git repository directory"
    execute_command "sudo chown '$current_user':www-data '$repo_path'" "Setting Git directory ownership"
    execute_command "sudo chmod 750 '$repo_path'" "Setting Git directory permissions"

    # Initialize bare repository
    cd "$repo_path" || exit 1
    execute_command "git init --bare" "Initializing bare Git repository"

    # Create enhanced post-receive hook
    local hook_file="$repo_path/hooks/post-receive"
    print_step "Creating post-receive hook"

    sudo tee "$hook_file" >/dev/null <<EOL
#!/bin/bash

# Post-receive hook for $SITE_NAME
WORK_TREE="/var/www/$SITE_NAME"
GIT_DIR="/var/repo/$SITE_NAME.git"
DEPLOY_LOG="/var/log/$SITE_NAME-deploy.log"

# Logging function
log_deploy() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$DEPLOY_LOG"
}

log_deploy "Starting deployment..."

while read oldrev newrev refname; do
    BRANCH=\$(echo \$refname | sed 's|refs/heads/||')
    log_deploy "Deploying branch: \$BRANCH"
    
    # Checkout files
    git --work-tree="\$WORK_TREE" --git-dir="\$GIT_DIR" checkout -f "\$BRANCH"
    
    # Set proper permissions
    find "\$WORK_TREE" -type d -exec chmod 755 {} \\;
    find "\$WORK_TREE" -type f -exec chmod 644 {} \\;
    
    # Make Yii console executable if it exists
    if [[ -f "\$WORK_TREE/yii" ]]; then
        chmod +x "\$WORK_TREE/yii"
    fi
    
    log_deploy "Deployment completed for branch: \$BRANCH"
done

log_deploy "Post-receive hook completed"
EOL

    execute_command "sudo chmod +x '$hook_file'" "Making post-receive hook executable"
    execute_command "sudo chown '$current_user':www-data '$hook_file'" "Setting hook ownership"

    print_success "Git repository setup completed"
}

# Enhanced Apache virtual host configuration
setup_apache_virtualhost() {
    local config_file="/etc/apache2/sites-available/$SITE_NAME.conf"
    local document_root="/var/www/$SITE_NAME"

    # Add /web for Yii2 applications
    if [[ $APP_CHOICE == "3" ]]; then
        document_root="$document_root/web"
    fi

    print_step "Creating Apache virtual host configuration"

    # Backup existing configuration if it exists
    create_backup "$config_file" "$SITE_NAME-apache"

    # Create comprehensive virtual host configuration
    sudo tee "$config_file" >/dev/null <<EOL
<VirtualHost *:80>
    ServerName $SITE_NAME
    ServerAlias www.$SITE_NAME
    ServerAdmin $SITE_ADMIN
    DocumentRoot "$document_root"

    <Directory "$document_root">
        Options -Indexes +FollowSymLinks -MultiViews
        AllowOverride All
        Require all granted
        
        # Enable rewrite engine
        RewriteEngine On
        
$(if [[ $APP_CHOICE == "3" ]]; then
        cat <<'YII2_RULES'
        # Yii2 specific rules
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . index.php [L]
        
        # Security headers
        Header always set X-Content-Type-Options nosniff
        Header always set X-Frame-Options DENY
        Header always set X-XSS-Protection "1; mode=block"
        
        # Prevent access to sensitive files
        <FilesMatch "\.(htaccess|htpasswd|ini|log|sh|inc|bak)$">
            Require all denied
        </FilesMatch>
YII2_RULES
    elif [[ $APP_CHOICE == "4" ]]; then
        cat <<'VUE_RULES'
        # Vue.js SPA rules
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . index.html [L]
        
        # Enable compression for Vue.js assets
        <IfModule mod_deflate.c>
            AddOutputFilterByType DEFLATE text/css text/javascript application/javascript application/json
        </IfModule>
        
        # Cache static assets
        <IfModule mod_expires.c>
            ExpiresActive On
            ExpiresByType text/css "access plus 1 year"
            ExpiresByType application/javascript "access plus 1 year"
            ExpiresByType image/png "access plus 1 year"
            ExpiresByType image/jpg "access plus 1 year"
            ExpiresByType image/jpeg "access plus 1 year"
        </IfModule>
VUE_RULES
    fi)
    </Directory>

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/$SITE_NAME-error.log
    CustomLog \${APACHE_LOG_DIR}/$SITE_NAME-access.log combined
    LogLevel warn

    # Security settings
    ServerTokens Prod
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</VirtualHost>

# SSL Virtual Host (placeholder - configure with actual certificates)
# <VirtualHost *:443>
#     ServerName $SITE_NAME
#     ServerAlias www.$SITE_NAME
#     ServerAdmin $SITE_ADMIN
#     DocumentRoot "$document_root"
#     
#     SSLEngine on
#     SSLCertificateFile /path/to/certificate.crt
#     SSLCertificateKeyFile /path/to/private.key
#     
#     # Include the same directory configuration as above
# </VirtualHost>
EOL

    # Test Apache configuration
    if ! sudo apache2ctl configtest 2>/dev/null; then
        print_error "Apache configuration test failed"
        rollback_changes "apache_config"
        exit 1
    fi

    # Enable site and reload Apache
    execute_command "sudo a2ensite '$SITE_NAME.conf'" "Enabling site configuration"
    execute_command "sudo systemctl reload apache2" "Reloading Apache configuration"

    print_success "Apache virtual host configuration completed"
}

# Configure hostname in /etc/hosts
configure_hostname() {
    if [[ ${CONFIG_HOSTNAME,,} =~ ^y ]]; then
        print_step "Configuring hostname in /etc/hosts"

        # Check if entry already exists
        if grep -q "127.0.0.1.*$SITE_NAME" /etc/hosts; then
            print_warning "Hostname entry already exists in /etc/hosts"
        else
            # Backup hosts file
            create_backup "/etc/hosts" "hosts"

            # Add hostname entry
            execute_command "echo '127.0.0.1 $SITE_NAME www.$SITE_NAME' | sudo tee -a /etc/hosts" "Adding hostname to /etc/hosts"
        fi

        print_success "Hostname configuration completed"
    fi
}

# Comprehensive post-installation instructions
display_completion_message() {
    print_header "🎉 Setup Completed Successfully! 🎉"

    echo -e "${GREEN}✅ Your $([[ $APP_CHOICE == "3" ]] && echo "Yii2" || echo "Vue.js") application server is ready!${NC}\n"

    echo -e "${BOLD}📋 Server Information:${NC}"
    echo -e "  🌐 Site URL: ${CYAN}http://$SITE_NAME${NC}"
    echo -e "  📁 Document Root: ${CYAN}/var/www/$SITE_NAME$([[ $APP_CHOICE == "3" ]] && echo "/web")${NC}"
    echo -e "  📧 Admin Email: ${CYAN}$SITE_ADMIN${NC}"
    echo -e "  📝 Log File: ${CYAN}$LOG_FILE${NC}"

    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "  💾 Backups: ${CYAN}$BACKUP_DIR${NC}"
    fi

    echo -e "\n${BOLD}🔧 Next Steps:${NC}\n"

    if [[ $APP_CHOICE == "3" ]]; then
        # Yii2 specific instructions
        echo -e "${YELLOW}📌 Yii2 Application Deployment:${NC}"
        echo -e "1. ${CYAN}Add remote to your local repository:${NC}"
        echo -e "   git remote add production $(whoami)@$(hostname):/var/repo/$SITE_NAME.git"
        echo -e "\n2. ${CYAN}Deploy your application:${NC}"
        echo -e "   git push production main"
        echo -e "\n3. ${CYAN}Install dependencies on server:${NC}"
        echo -e "   cd /var/www/$SITE_NAME"
        echo -e "   composer install --no-dev --optimize-autoloader"
        echo -e "\n4. ${CYAN}Configure database connection:${NC}"
        echo -e "   Edit: /var/www/$SITE_NAME/config/db.php"
        echo -e "\n5. ${CYAN}Run migrations (if applicable):${NC}"
        echo -e "   ./yii migrate"
        echo -e "\n6. ${CYAN}Set proper permissions:${NC}"
        echo -e "   sudo chown -R $(whoami):www-data /var/www/$SITE_NAME"
        echo -e "   sudo chmod -R 755 /var/www/$SITE_NAME"
        echo -e "   sudo chmod -R 777 /var/www/$SITE_NAME/runtime /var/www/$SITE_NAME/web/assets"

    elif [[ $APP_CHOICE == "4" ]]; then
        # Vue.js specific instructions
        echo -e "${YELLOW}📌 Vue.js Application Deployment:${NC}"
        echo -e "1. ${CYAN}Build your Vue.js application locally:${NC}"
        echo -e "   npm run build"
        echo -e "\n2. ${CYAN}Deploy using rsync:${NC}"
        echo -e "   rsync -avz --delete dist/ $(whoami)@$(hostname):/var/www/$SITE_NAME/"
        echo -e "\n3. ${CYAN}Or create a deployment script:${NC}"
        cat <<'DEPLOY_SCRIPT'
   # deploy.sh
   #!/bin/bash
   npm run build
   rsync -avz --delete dist/ user@server:/var/www/SITE_NAME/
   ssh user@server "sudo systemctl reload apache2"
DEPLOY_SCRIPT
    fi

    echo -e "\n${BOLD}🔒 Security Recommendations:${NC}"
    echo -e "• Configure SSL/TLS certificates (Let's Encrypt recommended)"
    echo -e "• Set up firewall rules: ${CYAN}sudo ufw allow 22,80,443/tcp && sudo ufw enable${NC}"
    echo -e "• Regular updates: ${CYAN}sudo apt update && sudo apt upgrade${NC}"
    echo -e "• Monitor logs: ${CYAN}sudo tail -f /var/log/apache2/$SITE_NAME-*.log${NC}"
    echo -e "• Consider fail2ban for intrusion prevention"

    echo -e "\n${BOLD}🛠️  Useful Commands:${NC}"
    echo -e "• Test site: ${CYAN}curl -I http://$SITE_NAME${NC}"
    echo -e "• Apache config test: ${CYAN}sudo apache2ctl configtest${NC}"
    echo -e "• Restart Apache: ${CYAN}sudo systemctl restart apache2${NC}"
    echo -e "• View Apache status: ${CYAN}sudo systemctl status apache2${NC}"

    if [[ $APP_CHOICE == "3" ]]; then
        echo -e "• Check deployment log: ${CYAN}sudo tail -f /var/log/$SITE_NAME-deploy.log${NC}"
    fi

    echo -e "\n${GREEN}🎊 Happy coding! Your server is ready to serve your application! 🎊${NC}"
}

# Main execution flow
main() {
    print_header "Server Setup Script v2.0"
    print_info "Log file: $LOG_FILE"

    # System checks
    check_system_requirements

    # Get user choices
    get_application_choice

    # Handle different installation types
    case $APP_CHOICE in
    1) # PostgreSQL only
        install_postgresql
        ;;
    2) # Apache/PHP/Composer only
        install_apache_php
        ;;
    3 | 4) # Full application setup
        get_site_configuration

        # Install base components if needed
        if ! systemctl is-active --quiet apache2 2>/dev/null; then
            install_apache_php
        fi

        # Setup directories and configurations
        setup_web_directory || {
            rollback_changes "web_directory"
            exit 1
        }

        # Git repository setup for Yii2
        if [[ $APP_CHOICE == "3" ]]; then
            setup_git_repository || {
                rollback_changes "git_directory"
                exit 1
            }
        fi

        # Apache virtual host configuration
        setup_apache_virtualhost || {
            rollback_changes "apache_config"
            exit 1
        }

        # Configure hostname
        configure_hostname

        # Display completion message
        display_completion_message
        ;;
    esac

    print_success "Script execution completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
