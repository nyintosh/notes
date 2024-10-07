#!/bin/bash

# Apache Server & Git Hooks Configuration Script

# Function to check for successful command execution
check_success() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31mError occurred during the execution of: $1\033[0m"
        exit 1
    fi
}

# Get the site name from user input
read -p "🎉 Enter the site name: " SITE_NAME

# Get the current user
CURRENT_USER=$(whoami)

# Check if the web directory already exists
if [ -d "/var/www/$SITE_NAME" ]; then
    echo -e "\033[31mError: The directory /var/www/$SITE_NAME already exists. Please choose a different site name.\033[0m"
    exit 1
fi

# Update and upgrade Ubuntu packages
echo -e "\n🚀 Updating and upgrading Ubuntu packages..."
sudo apt update && sudo apt upgrade -y
check_success "apt update && apt upgrade"

# Install Apache2 and required PHP libraries
echo -e "\n🔧 Installing Apache2 and PHP libraries..."
sudo apt install -y apache2
sudo apt install -y php libapache2-mod-php php-pgsql php-xml php-mbstring php-curl php-gd php-zip unzip
sudo systemctl restart apache2
check_success "apache2 and PHP installation"

# Setup web directory
echo -e "\n📂 Setting up web directory for '$SITE_NAME'..."
sudo mkdir /var/www/$SITE_NAME
sudo chown "$CURRENT_USER":root /var/www/$SITE_NAME
check_success "web directory setup"

# Setup git directory
echo -e "\n📁 Setting up Git directory for '${SITE_NAME}.git'..."
sudo mkdir -p /var/repo/${SITE_NAME}.git
sudo chown "$CURRENT_USER":root /var/repo/${SITE_NAME}.git
check_success "git directory setup"

# Initialize Git repository
echo -e "\n📥 Initializing Git repository..."
cd /var/repo/${SITE_NAME}.git || exit
git init --bare
check_success "git repository initialization"

# Setup post-receive script
echo -e "\n🎲 Setting up post-receive script..."
echo '#!/bin/sh

WORK_TREE=/var/www/'$SITE_NAME'
GIT_DIR=/var/repo/'$SITE_NAME'.git

git --work-tree=$WORK_TREE --git-dir=$GIT_DIR checkout -f' > /var/repo/${SITE_NAME}.git/hooks/post-receive
chmod +x /var/repo/${SITE_NAME}.git/hooks/post-receive
check_success "post-receive script setup"

# Download and install Composer
echo -e "\n📦 Downloading and installing Composer..."
cd ~ || exit
curl -sS https://getcomposer.org/installer | php
sudo mv ~/composer.phar /usr/local/bin/composer
check_success "Composer installation"

# Enable mod rewrite
echo -e "\n🔄 Enabling mod rewrite..."
sudo a2enmod rewrite
sudo systemctl restart apache2
check_success "mod rewrite enablement"

# Add site to Apache availability
echo -e "\n📄 Adding site to Apache availability for '$SITE_NAME'..."
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/$SITE_NAME.conf
sudo a2dissite 000-default.conf
sudo a2ensite $SITE_NAME.conf
sudo systemctl reload apache2
check_success "Add site availability"

echo -e "\n🎊 Server setup for '$SITE_NAME' completed successfully! 🎊"
echo -e "🌟 Your Apache server is now ready to serve your site at /var/www/$SITE_NAME 🌟"
echo -e "\n📝 **Important:** Update **/etc/apache2/sites-available/$SITE_NAME.conf** to configure your site properly.\n"
