#!/bin/bash

# ============================================
# Devil Panels - Server Initial Setup Script
# ============================================
# Este script configura un servidor Ubuntu 22.04 desde cero
# Ejecutar como root o con sudo
#
# Uso: sudo bash server-setup.sh
# ============================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones de logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root (sudo bash server-setup.sh)"
fi

# ============================================
# Variables de Configuracion
# ============================================
read -sp "Ingresa password para Redis: " REDIS_PASSWORD
echo ""

log_info "Iniciando configuracion del servidor..."

# ============================================
# 1. Actualizar Sistema
# ============================================
log_info "Actualizando sistema operativo..."
apt update && apt upgrade -y
log_success "Sistema actualizado"
    
# ============================================
# 2. Instalar Dependencias Basicas
# ============================================
log_info "Instalando dependencias basicas..."
apt install -y \
    software-properties-common \
    curl \
    wget \
    git \
    unzip \
    zip \
    htop \
    ufw \
    fail2ban \
    certbot
log_success "Dependencias basicas instaladas"

# ============================================
# 3. Instalar Nginx
# ============================================
log_info "Instalando Nginx..."
apt install -y nginx
systemctl enable nginx
systemctl start nginx
log_success "Nginx instalado"

# ============================================
# 4. Instalar PHP 8.3
# ============================================
log_info "Instalando PHP 8.3..."
add-apt-repository -y ppa:ondrej/php
apt update
apt install -y \
    php8.3-fpm \
    php8.3-cli \
    php8.3-mysql \
    php8.3-pgsql \
    php8.3-sqlite3 \
    php8.3-mbstring \
    php8.3-xml \
    php8.3-curl \
    php8.3-zip \
    php8.3-redis \
    php8.3-bcmath \
    php8.3-gd \
    php8.3-intl \
    php8.3-readline

# Configurar PHP para produccion
sed -i 's/display_errors = On/display_errors = Off/' /etc/php/8.3/fpm/php.ini
sed -i 's/expose_php = On/expose_php = Off/' /etc/php/8.3/fpm/php.ini
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 50M/' /etc/php/8.3/fpm/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 50M/' /etc/php/8.3/fpm/php.ini
sed -i 's/memory_limit = 128M/memory_limit = 256M/' /etc/php/8.3/fpm/php.ini

systemctl restart php8.3-fpm
log_success "PHP 8.3 instalado y configurado"

# ============================================
# 5. Instalar Composer
# ============================================
log_info "Instalando Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer
log_success "Composer instalado"

# ============================================
# 6b. Configurar SQLite para Laravel Panel
# ============================================
log_info "Configurando SQLite para el panel..."
apt install -y sqlite3
# El archivo SQLite se creara cuando se ejecute php artisan migrate
log_success "SQLite configurado"

# ============================================
# 7. Instalar Redis
# ============================================
log_info "Instalando Redis..."
apt install -y redis-server

# Configurar Redis con password
sed -i "s/# requirepass foobared/requirepass ${REDIS_PASSWORD}/" /etc/redis/redis.conf
sed -i 's/supervised no/supervised systemd/' /etc/redis/redis.conf

systemctl restart redis-server
systemctl enable redis-server
log_success "Redis instalado y configurado"

# ============================================
# 8. Instalar Node.js 20 LTS
# ============================================
log_info "Instalando Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
log_success "Node.js $(node -v) instalado"

# ============================================
# 10. Crear Directorios de Aplicacion
# ============================================
log_info "Creando directorios de aplicacion..."
mkdir -p /var/www/dinamic_ltm
mkdir -p /etc/ssl/cloudflare
chown -R dev1lb0y:dev1lb0y /var/www/dinamic_ltm
log_success "Directorios creados"

# ============================================
# 11. Configurar Firewall (UFW)
# ============================================
log_info "Configurando firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'

# Permitir solo IPs de Cloudflare (opcional - se puede hacer via Security Groups de AWS)
# Las IPs de Cloudflare cambian, mejor manejar en Security Groups

ufw --force enable
log_success "Firewall configurado"

# ============================================
# 12. Configurar Fail2Ban
# ============================================
log_info "Configurando Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
EOF

systemctl restart fail2ban
systemctl enable fail2ban
log_success "Fail2Ban configurado"

# ============================================
# 13. Crear Usuario para Deployments (opcional)
# ============================================
log_info "Configurando usuario dev1lb0y para deployments..."
usermod -aG www-data dev1lb0y

# Configurar SSH key para deployments automaticos
mkdir -p /home/dev1lb0y/.ssh
chmod 700 /home/dev1lb0y/.ssh
touch /home/dev1lb0y/.ssh/authorized_keys
chmod 600 /home/dev1lb0y/.ssh/authorized_keys
chown -R dev1lb0y:dev1lb0y /home/dev1lb0y/.ssh

log_success "Usuario configurado"

# ============================================
# 14. Optimizar Sistema
# ============================================
log_info "Optimizando sistema..."

# Aumentar limites de archivos abiertos
cat >> /etc/security/limits.conf <<EOF

# Devil Panels Optimizations
* soft nofile 65535
* hard nofile 65535
dev1lb0y soft nofile 65535
dev1lb0y hard nofile 65535
www-data soft nofile 65535
www-data hard nofile 65535
EOF

# Optimizar sysctl
cat >> /etc/sysctl.conf <<EOF

# Devil Panels Network Optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.netdev_max_backlog = 65535
EOF

sysctl -p

log_success "Sistema optimizado"

# ============================================
# Resumen Final
# ============================================
echo ""
echo "============================================"
echo -e "${GREEN}CONFIGURACION COMPLETADA${NC}"
echo "============================================"
echo ""
echo "Servicios instalados:"
echo "  - Nginx: $(nginx -v 2>&1 | cut -d'/' -f2)"
echo "  - PHP: $(php -v | head -n1 | cut -d' ' -f2)"
echo "  - PostgreSQL: $(psql --version | cut -d' ' -f3)"
echo "  - SQLite: $(sqlite3 --version | cut -d' ' -f1)"
echo "  - Redis: $(redis-server --version | cut -d' ' -f3 | cut -d'=' -f2)"
echo "  - Node.js: $(node -v)"
echo "  - Composer: $(composer --version | cut -d' ' -f3)"
echo ""
echo "Bases de datos:"
echo "  - PostgreSQL: dpns (para Node backend)"
echo "  - SQLite: database.sqlite (para Laravel panel)"
echo ""
echo "Directorios:"
echo "  - /var/www/dinamic_ltm (Laravel)"
echo "  - /etc/ssl/cloudflare (Certificados)"
echo ""
echo "============================================"
echo "SIGUIENTES PASOS:"
echo "============================================"
echo ""
echo "1. Subir certificados Cloudflare Origin a /etc/ssl/cloudflare/"
echo "   - origin.pem"
echo "   - origin.key"
echo ""
echo "2. Copiar configuracion Nginx:"
echo "   - sudo cp nginx/front.conf /etc/nginx/sites-available/front"
echo "   - sudo ln -s /etc/nginx/sites-available/front /etc/nginx/sites-enabled/"
echo "   - sudo rm /etc/nginx/sites-enabled/default"
echo "   - sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo "3. Ejecutar deploy.sh para desplegar la aplicacion"
echo ""
echo "============================================"
echo ""
