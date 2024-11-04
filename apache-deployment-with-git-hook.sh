#!/bin/bash

# Function to check for successful command execution
check_success() {
	if [ $? -ne 0 ]; then
		echo -e "\033[31mError occurred during the execution of: $1\033[0m"
		exit 1
	fi
}

# Prompt user for application type
while true; do
	echo "🎉 Choose the application type to set up:"
	echo "1) PostgreSQL"
	echo "2) Yii2"
	echo "3) Vue.js"
	read -p "Enter your choice (1, 2, or 3): " APP_CHOICE

	# Validate user input
	if [[ "$APP_CHOICE" =~ ^[1-3]$ ]]; then
		break
	else
		echo -e "\033[31mInvalid choice! Please select either 1, 2, or 3.\033[0m"
	fi
done

# Prompt for virtual host configuration if needed
if [[ "$APP_CHOICE" == "2" || "$APP_CHOICE" == "3" ]]; then
	read -p " Enter the site name: " SITE_NAME
	read -p " Enter site admin email: " SITE_ADMIN
	read -p " Configure virtual hosts (Y/N)? " CONFIGURE_VHOST
fi

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

# Install selected application type
case $APP_CHOICE in
1) # PostgreSQL setup
	echo -e "\n🔧 Installing PostgreSQL..."
	sudo apt install -y postgresql
	check_success "PostgreSQL installation"
	;;

2) # Yii2 setup
	echo -e "\n🔧 Installing Apache2 and PHP libraries..."
	sudo apt install -y apache2 php libapache2-mod-php php-pgsql php-xml php-mbstring php-curl php-gd php-zip unzip
	sudo systemctl restart apache2
	check_success "Apache2 and PHP installation"
	;;

3) # Vue.js setup
	echo -e "\n🔧 Installing Apache2..."
	sudo apt install -y apache2
	check_success "Apache2 installation"
	;;
esac

# End with post-installation instructions if PostgreSQL
if [ "$APP_CHOICE" == "1" ]; then
	echo -e "\n📌 PostgreSQL post-installation steps:"
	echo -e "1. Edit \033[33m/etc/postgresql/*/main/postgresql.conf\033[0m and locate \033[33mlisten_addresses\033[0m."
	echo -e "   - Set \033[33mlisten_addresses\033[0m as per your requirement (e.g., 'localhost' or '*')."
	echo -e "2. Login to the database: \033[36msudo -u postgres psql\033[0m."
	echo -e "3. Update the password for the \033[33mpostgres\033[0m user:"
	echo -e "   - Run: \033[36mALTER USER postgres WITH ENCRYPTED PASSWORD 'your_password';\033[0m"
	echo -e "4. Edit \033[33m/etc/postgresql/*/main/pg_hba.conf\033[0m to set \033[33mscram-sha-256\033[0m authentication for the \033[33mpostgres\033[0m user."
	echo -e "5. Restart the PostgreSQL service: \033[36msudo systemctl restart postgresql\033[0m."
fi

# Setup web directory
echo -e "\n📂 Setting up web directory for '$SITE_NAME'..."
sudo mkdir /var/www/$SITE_NAME
sudo chown "$CURRENT_USER":www-data /var/www/$SITE_NAME
sudo chmod -R 755 /var/www/$SITE_NAME
check_success "web directory setup"

# Yii2 specific setup
if [ "$APP_CHOICE" == "2" ]; then
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
fi

# Create and configure Apache VirtualHost
echo -e "\n📝 Creating Apache virtual host configuration for '$SITE_NAME'..."
sudo bash -c "cat > /etc/apache2/sites-available/$SITE_NAME.conf << EOL
<VirtualHost *:80>
    ServerName www.$SITE_NAME
    ServerAdmin $SITE_ADMIN
    DocumentRoot \"/var/www/$SITE_NAME$([ \"$APP_CHOICE\" == \"2\" ] && echo \"/web\")\"

    <Directory \"/var/www/$SITE_NAME$([ \"$APP_CHOICE\" == \"2\" ] && echo \"/web\")\">
        RewriteEngine on

        $([ \"$APP_CHOICE\" == \"2\" ] && echo 'RewriteRule ^index.php/ - [L,R=404]')

        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d

        RewriteRule . $([ \"$APP_CHOICE\" == \"2\" ] && echo 'index.php' || echo '/index.html [L]')

        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

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
