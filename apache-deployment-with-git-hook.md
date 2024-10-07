# Apache Server & Git Hooks Configuration

## 1. Server Setup

> Install Ubuntu Updates

```bash
sudo apt update && sudo apt upgrade
```

> Install Apache2 and Required Libraries

```bash
sudo apt install apache2
sudo apt install php libapache2-mod-php php-pgsql php-xml php-mbstring php-curl php-gd php-zip unzip
```

> Restart Apache Server

```bash
sudo systemctl restart apache2
```

## 2. Directory Structure

> Setup Web Directory

```bash
sudo mkdir /var/www/{site_name}
sudo chown {user}:root /var/www/{site_name}
```

> Setup Git Directory

```bash
sudo mkdir -p /var/repo/{site_name}.git
sudo chown {user}:root /var/repo/{site_name}.git
```

> Initialize Git Repository

```bash
cd /var/repo/{site_name}.git
git init --bare
```

## 3. Git Hooks Configuration

> Setup `post-receive` script

```bash
cd /var/repo/{site_name}.git/hooks
echo '#!/bin/sh

WORK_TREE=/var/www/{site_name}
GIT_DIR=/var/repo/{site_name}.git

git --work-tree=$WORK_TREE --git-dir=$GIT_DIR checkout -f develop' > post-receive
chmod +x post-receive
```

## 4. Composer Installation

> Download & Install Composer

```bash
cd ~
curl -sS https://getcomposer.org/installer | php
sudo mv ~/composer.phar /usr/local/bin/composer
```

## 5. Apache Configuration

> Enable Mod Rewrite

```bash
sudo a2enmod rewrite
sudo systemctl restart apache2
```

## 6. Local Development Setup

> Create SSH Config File

- Edit `~/.ssh/config`

```txt
Host {site_name}
  HostName {HOST_NAME}
  Port {PORT}
  User {USER}
  IdentityFile {IDENTITY_FILE_PATH}
```

> Add Git Remote URL

```bash
git remote add {remote_name} ssh://{site_name}/var/repo/{site_name}.git
```

> Deploy Your Application

```bash
git push {remote_name} {branch_name}
```

## 7. Additional Steps to Get Up and Running

> Create `/etc/apache2/sites-available/{site_name}.conf`

```bash
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/{site_name}.conf
sudo vim /etc/apache2/sites-available/{site_name}.conf
```

*Update the configuration file according to your site’s requirements*

> Enable the Site

```bash
sudo a2ensite {site_name}.conf
```

> Disable the Default Site (Optional)

```bash
sudo a2dissite 000-default.conf
```
