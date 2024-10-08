# Apache Server & Git Hooks Configuration

## 1. Server Setup

### 1.1 Install Ubuntu Updates

```bash
sudo apt update && sudo apt upgrade
```

### 1.2 Install Apache2 and Required Libraries

```bash
sudo apt install apache2
sudo apt install php libapache2-mod-php php-pgsql php-xml php-mbstring php-curl php-gd php-zip unzip
```

### 1.3 Restart Apache Server

```bash
sudo systemctl restart apache2
```

## 2. Directory Structure

### 2.1 Setup Web Directory

```bash
sudo mkdir /var/www/{site_name}
sudo chown {user}:root /var/www/{site_name}
```

### 2.2 Setup Git Directory

```bash
sudo mkdir -p /var/repo/{site_name}.git
sudo chown {user}:root /var/repo/{site_name}.git
```

### 2.3 Initialize Git Repository

```bash
cd /var/repo/{site_name}.git
git init --bare
```

## 3. Git Hooks Configuration

### 3.1 Setup `post-receive` script

```bash
cd /var/repo/{site_name}.git/hooks
echo '#!/bin/sh

WORK_TREE=/var/www/{site_name}
GIT_DIR=/var/repo/{site_name}.git

git --work-tree=$WORK_TREE --git-dir=$GIT_DIR checkout -f' > post-receive
chmod +x post-receive
```

## 4. Composer Installation

### 4.1 Download & Install Composer

```bash
cd ~
curl -sS https://getcomposer.org/installer | php
sudo mv ~/composer.phar /usr/local/bin/composer
```

## 5. Apache Configuration

### 5.1 Enable Mod Rewrite

```bash
sudo a2enmod rewrite
sudo systemctl restart apache2
```

## 6. Local Development Setup

### 6.1 Create SSH Config File

- Edit `~/.ssh/config`

```txt
Host {site_name}
  HostName {HOST_NAME}
  Port {PORT}
  User {USER}
  IdentityFile {IDENTITY_FILE_PATH}
```

### 6.2 Add Git Remote URL

```bash
git remote add {remote_name} ssh://{site_name}/var/repo/{site_name}.git
```

### 6.3 Deploy Your Application

```bash
git push {remote_name} {branch_name}
```

## 7. Additional Steps to Get Up and Running

### 7.1 Create `/etc/apache2/sites-available/{site_name}.conf`

```bash
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/{site_name}.conf
sudo vim /etc/apache2/sites-available/{site_name}.conf
```

> *Update the configuration file according to your site’s requirements*

### 7.2 Enable the Site

```bash
sudo a2ensite {site_name}.conf
```

### 7.3 Disable the Default Site (Optional)

```bash
sudo a2dissite 000-default.conf
```

### 7.3 Reload Apache Server

```bash
sudo systemctl reload apache2
```
