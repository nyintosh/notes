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
	echo -e "\n🎉 Choose the application type to set up:"
	echo -e "1) PostgreSQL installation"
	echo -e "2) Apache2, PHP, Composer installation"
	echo -e "3) Serve Yii2 application"
	echo -e "4) Serve Vue.js application\n"
	read -p "Enter your choice (1 to 4): " APP_CHOICE

	# Validate user input
	if [[ "$APP_CHOICE" =~ ^[1-4]$ ]]; then
		break
	else
		echo -e "\n\033[31mInvalid choice! Please select either 1, 2, 3, or 4.\033[0m"
	fi
done

# Prompt for virtual host configuration if needed
if [[ "$APP_CHOICE" == "3" || "$APP_CHOICE" == "4" ]]; then
	read -p "Enter the site name: " SITE_NAME
	read -p "Enter admin email: " SITE_ADMIN
	read -p "Configure hostname? (Y/n): " CONFIG_HOSTNAME
fi

# Get the current user
CURRENT_USER=$(whoami)

# Update package index
echo -e "\n🚀 Updating package index..."
sudo apt update
check_success "apt update"

# Install dependencies based on application type
case $APP_CHOICE in
1) # PostgreSQL installation
	echo -e "\n🔧 Installing PostgreSQL..."
	sudo apt install -y postgresql
	check_success "PostgreSQL installation"

	echo -e "\n✅ PostgreSQL installation complete. Proceed with further configurations as needed.\n"

	echo -e "📌 PostgreSQL Post-Installation Steps:\n"
	echo -e "1. Edit \033[33m/etc/postgresql/*/main/postgresql.conf\033[0m and set \033[33mlisten_addresses\033[0m (e.g., 'localhost' or '*')."
	echo -e "2. Access PostgreSQL: \033[36msudo -u postgres psql\033[0m."
	echo -e "3. Update the \033[33mpostgres\033[0m user password:"
	echo -e "   - Run: \033[36mALTER USER postgres WITH ENCRYPTED PASSWORD 'your_password';\033[0m"
	echo -e "4. Configure \033[33m/etc/postgresql/*/main/pg_hba.conf\033[0m for authentication:"
	echo -e "   - Use \033[33mscram-sha-256\033[0m for enhanced security:"
	echo -e "                  \t\033[36mTYPE \tDATABASE \tUSER \t\tADDRESS \tMETHOD\033[0m"
	echo -e "   [Local access] \t\033[36mlocal \tall \t\tpostgres \t\t\tscram-sha-256\033[0m"
	echo -e "   [Specific subnet] \t\033[36mhost \tall \t\tall \t\t192.168.1.0/24 \tscram-sha-256\033[0m"
	echo -e "   [All IPs] \t\t\033[36mhost \tall \t\tall \t\t0.0.0.0/0 \tscram-sha-256\033[0m"
	echo -e "5. Restart PostgreSQL: \033[36msudo systemctl restart postgresql\033[0m\n"
	exit 0
	;;

2) # Apache2, PHP, Composer installation
	echo -e "\n🔧 Installing apache2, php..."
	sudo apt install -y apache2 php libapache2-mod-php php-pgsql php-xml php-mbstring php-curl php-gd php-zip unzip
	sudo systemctl restart apache2
	check_success "Apache2 and PHP installation"

	echo -e "\n📦 Downloading and installing Composer..."
	cd ~ || exit
	curl -sS https://getcomposer.org/installer | php
	sudo mv ~/composer.phar /usr/local/bin/composer
	check_success "Composer installation"

	echo -e "\n🔄 Enabling mod_rewrite..."
	sudo a2enmod rewrite
	sudo systemctl restart apache2
	check_success "mod_rewrite enablement"

	echo -e "\n✅ Apache2, PHP, Composer installation complete. Proceed with further configurations as needed.\n"

	exit 0
	;;
esac

# Check if the web directory already exists
if [ -d "/var/www/$SITE_NAME" ]; then
	echo -e "\033[31mError: The directory /var/www/$SITE_NAME already exists. Choose a different site name.\033[0m\n"
	exit 1
fi

# Setup web directory
echo -e "\n📂 Setting up web directory under /var/www/$SITE_NAME..."
sudo mkdir -p /var/www/$SITE_NAME
sudo chown "$CURRENT_USER":www-data /var/www/$SITE_NAME
sudo chmod -R 755 /var/www/$SITE_NAME
check_success "web directory setup"

# Yii2 specific setup
if [ "$APP_CHOICE" == "3" ]; then
	# Setup git directory
	echo -e "\n📁 Setting up git directory under /var/repo/$SITE_NAME.git..."
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
	bash -c "cat > /var/repo/${SITE_NAME}.git/hooks/post-receive << 'EOL'
#!/bin/sh

WORK_TREE=/var/www/$SITE_NAME
GIT_DIR=/var/repo/$SITE_NAME.git

read oldrev newrev refname
BRANCH=\$(echo \$refname | sed 's|refs/heads/||')

git --work-tree=\$WORK_TREE --git-dir=\$GIT_DIR checkout -f \$BRANCH
EOL"
	chmod +x /var/repo/${SITE_NAME}.git/hooks/post-receive
	check_success "post-receive script setup"
fi

# Create and configure Apache VirtualHost
echo -e "\n📝 Creating Apache virtual host configuration for '$SITE_NAME'..."
sudo bash -c "cat > /etc/apache2/sites-available/$SITE_NAME.conf << EOL
<VirtualHost *:80>
    ServerName www.$SITE_NAME
    ServerAdmin $SITE_ADMIN
    DocumentRoot \"/var/www/$SITE_NAME$([ \"$APP_CHOICE\" == \"3\" ] && echo '/web')\"

    <Directory \"/var/www/$SITE_NAME$([ \"$APP_CHOICE\" == \"3\" ] && echo '/web')\">
        RewriteEngine on
        $([ \"$APP_CHOICE\" == \"3\" ] && echo -e '\n        RewriteRule ^index.php/ - [L,R=404]\n')
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d

        RewriteRule . \$([ \"$APP_CHOICE\" == \"3\" ] && echo 'index.php' || echo 'index.html') [L]

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

if [ "$CONFIG_HOSTNAME" = "Y" ] || [ "$CONFIG_HOSTNAME" = "y" ]; then
	# Append hostname to /etc/hosts
	echo -e "\n🌐 Appending hostname to /etc/hosts..."
	sudo bash -c "echo '127.0.0.1 $SITE_NAME' >> /etc/hosts"
	check_success "hostname appending"
fi

# Check for Apache configuration and guide user
echo -e "\n\033[32m🎊 Server setup for '$SITE_NAME' completed successfully! 🎊\033[0m"
echo -e "🌟 Your Apache server is now ready to serve your site at \033[33m/var/www/$SITE_NAME\033[0m 🌟"
echo -e "\n\033[36m📝 **Important Tasks After Setup**:\033[0m\n"
echo -e "  - Review the Apache configuration: \033[33m/etc/apache2/sites-available/$SITE_NAME.conf\033[0m"
echo -e "  - Consider disabling the default site if needed:"
echo -e "      \033[35msudo a2dissite 000-default.conf && sudo systemctl reload apache2\033[0m"
echo -e "  - Make sure your DNS settings point to the server's IP address."
echo -e "  - Set up SSL for HTTPS if needed, e.g., using Let's Encrypt. Follow this guide:"
echo -e "      \033[34mhttps://www.digitalocean.com/community/tutorials/how-to-secure-apache-with-let-s-encrypt-on-ubuntu\033[0m"

# Yii2 specific post-installation instructions
if [ "$APP_CHOICE" == "3" ]; then
	echo -e "\n📌 Yii2 Post-Installation Steps:\n"
	echo -e "1. Add a new remote origin to your local Git repository:"
	echo -e "   - Run: \033[36mgit remote add origin ssh://your_server_user@your_server:/var/repo/$SITE_NAME\033[0m"
	echo -e "   - Push the code: \033[36mgit push origin main\033[0m (or your branch name)."
	echo -e "2. On the server, navigate to the project directory:"
	echo -e "   - \033[36mcd /var/www/$SITE_NAME\033[0m"
	echo -e "   - Run: \033[36mcomposer install\033[0m"
	echo -e "3. Create the database configuration file (db.php) in the config directory:"
	echo -e "   - Path: \033[33m/var/www/$SITE_NAME/config/db.php\033[0m"
	echo -e "   - Define your database connection settings in db.php."
	echo -e "4. Run migrations only if needed:"
	echo -e "   - Execute: \033[36m./yii migrate\033[0m.\n\n"
	exit 0
fi

# Vue.js specific post-installation instructions
if [ "$APP_CHOICE" == "4" ]; then
	echo -e "\n📌 Vue.js Post-Installation Steps:\n"
	echo -e "Create a deployment script (\033[33m<your_deploy_script_name>.sh\033[0m) in your project directory with the following content:\n"
	echo -e "\033[33m<your_deploy_script_name>.sh\033[0m:"
	echo -e "#!/bin/bash\nnpm run build\nrsync -av --progress dist/ your_user@your_ip:/var/www/$SITE_NAME/\n"
	exit 0
fi

exit 0
