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

# Get the site admin email from user input
read -p "🔫 Enter site admin email: " ADMIN_EMAIL

# Get the current user
CURRENT_USER=$(whoami)

# Check if the web directory already exists
if [ -d "/var/www/$SITE_NAME" ]; then
	echo -e "\033[31mError: The directory /var/www/$SITE_NAME already exists. Choose a different site name.\033[0m"
	exit 1
fi

# Update and upgrade Ubuntu packages
echo -e "\n🚀 Updating and upgrading Ubuntu packages..."
sudo apt update && sudo apt upgrade -y
check_success "apt update && upgrade"

# Install Apache2 and required PHP libraries
echo -e "\n🔧 Installing Apache2 and PHP libraries..."
sudo apt install -y apache2
sudo apt install -y php libapache2-mod-php php-pgsql php-xml php-mbstring php-curl php-gd php-zip unzip
sudo systemctl restart apache2
check_success "apache2 and PHP installation"

# Setup web directory
echo -e "\n📂 Setting up web directory for '$SITE_NAME'..."
sudo mkdir /var/www/$SITE_NAME
sudo chown "$CURRENT_USER":www-data /var/www/$SITE_NAME
sudo chmod -R 755 /var/www/$SITE_NAME
check_success "web directory setup"

# Setup git directory
echo -e "\n📁 Setting up Git directory for '${SITE_NAME}.git'..."
sudo mkdir -p /var/repo/${SITE_NAME}.git
sudo chown "$CURRENT_USER":www-data /var/repo/${SITE_NAME}.git
sudo chmod -R 750 /var/repo/${SITE_NAME}.git
check_success "git directory setup"

# Initialize Git repository
echo -e "\n📥 Initializing Git repository..."
cd /var/repo/${SITE_NAME}.git || exit
git init --bare
check_success "git repository initialization"

# Setup post-receive script
echo -e "\n🎲 Setting up post-receive script..."
sudo bash -c "cat > /var/repo/${SITE_NAME}.git/hooks/post-receive << 'EOL'
#!/bin/sh

WORK_TREE=/var/www/$SITE_NAME
GIT_DIR=/var/repo/$SITE_NAME.git

read oldrev newrev refname
BRANCH=\$(echo \$refname | sed 's|refs/heads/||')

git --work-tree=\$WORK_TREE --git-dir=\$GIT_DIR checkout -f \$BRANCH
EOL"
sudo chmod +x /var/repo/${SITE_NAME}.git/hooks/post-receive
check_success "post-receive script setup"

# Download and install Composer
echo -e "\n📦 Downloading and installing Composer..."
cd ~ || exit
curl -sS https://getcomposer.org/installer | php
sudo mv ~/composer.phar /usr/local/bin/composer
check_success "Composer installation"

# Enable mod_rewrite for pretty URLs
echo -e "\n🔄 Enabling mod_rewrite..."
sudo a2enmod rewrite
sudo systemctl restart apache2
check_success "mod_rewrite enablement"

# Create and configure Apache VirtualHost for Yii2
echo -e "\n📝 Creating Apache virtual host configuration for '$SITE_NAME'..."
sudo bash -c "cat > /etc/apache2/sites-available/$SITE_NAME.conf << EOL
<VirtualHost *:80>
    ServerName www.$SITE_NAME
    ServerAdmin $ADMIN_EMAIL
    DocumentRoot \"/var/www/$SITE_NAME/web\"

    <Directory \"/var/www/$SITE_NAME/web\">
        # Enable mod_rewrite for pretty URLs
        RewriteEngine on

        # Redirect index.php in URLs to a 404 error
        RewriteRule ^index.php/ - [L,R=404]

        # If a file or directory exists, serve it directly
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d

        # Otherwise forward the request to index.php
        RewriteRule . index.php

        # Allow .htaccess overrides and other Apache options
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Logging (adjust paths if needed)
    ErrorLog \${APACHE_LOG_DIR}/$SITE_NAME-error.log
    CustomLog \${APACHE_LOG_DIR}/$SITE_NAME-access.log combined
</VirtualHost>
EOL"
check_success "apache virtual host configuration"

# Enable the new site and reload Apache
echo -e "\n🌐 Enabling site '$SITE_NAME' and reloading Apache..."
sudo a2ensite $SITE_NAME.conf
sudo systemctl reload apache2
check_success "site enablement"

# Check for Apache configuration and guide user
echo -e "\n\033[32m🎊 Server setup for '$SITE_NAME' completed successfully! 🎊\033[0m"
echo -e "🌟 Your Apache server is now ready to serve your site at \033[33m/var/www/$SITE_NAME\033[0m 🌟"
echo -e "\n\033[36m📝 **Important Tasks After Setup**:\033[0m"
echo -e "  - Review the Apache configuration: \033[33m/etc/apache2/sites-available/$SITE_NAME.conf\033[0m"
echo -e "  - Consider disabling the default site if needed:"
echo -e "      \033[35msudo a2dissite 000-default.conf && sudo systemctl reload apache2\033[0m"
echo -e "  - Make sure your DNS settings point to the server's IP address."
echo -e "  - Set up SSL for HTTPS if needed, e.g., using Let's Encrypt. Follow this guide:"
echo -e "      \033[34mhttps://www.digitalocean.com/community/tutorials/how-to-secure-apache-with-let-s-encrypt-on-ubuntu\033[0m"
echo -e "\n\033[32m✨ Enjoy your new setup! ✨\033[0m\n\n"
