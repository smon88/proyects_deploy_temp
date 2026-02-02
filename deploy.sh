#!/bin/bash

# ============================================
# Devil Panels - Automated Deployment Script
# ============================================
# Este script despliega/actualiza la aplicacion en produccion
#
# Uso:
#   ./deploy.sh     - Desplegar el Proyecto Laravel
#   ./deploy.sh rollback  - Revertir ultimo deploy
# ============================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funciones de logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# ============================================
# Configuracion
# ============================================
PROJECT_DIR="/var/www/dinamic_ltm"
PROJECT_REPO="git@github.com:smon88/dinamic_ltm.git"
DEPLOY_USER="dev1lb0y"
PHP_FPM_SERVICE="php8.3-fpm"
BACKUP_DIR="/var/backups/devil-projects"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ============================================
# Funciones de utilidad
# ============================================

check_requirements() {
    log_step "Verificando requisitos..."

    # Verificar git
    if ! command -v git &> /dev/null; then
        log_error "Git no esta instalado"
    fi

    # Verificar composer
    if ! command -v composer &> /dev/null; then
        log_error "Composer no esta instalado"
    fi

    # Verificar npm
    if ! command -v npm &> /dev/null; then
        log_error "npm no esta instalado"
    fi
    
    log_success "Requisitos verificados"
}

create_backup() {
    local app=$1
    local dir=$2

    log_step "Creando backup de $app..."
    mkdir -p "$BACKUP_DIR/$app"

    if [ -d "$dir" ] && [ "$(ls -A $dir 2>/dev/null)" ]; then
        tar -czf "$BACKUP_DIR/$app/${app}_${TIMESTAMP}.tar.gz" -C "$(dirname $dir)" "$(basename $dir)" 2>/dev/null || true

        # Mantener solo los ultimos 5 backups
        ls -t "$BACKUP_DIR/$app"/*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm --

        log_success "Backup creado: ${app}_${TIMESTAMP}.tar.gz"
    else
        log_warning "No hay archivos para respaldar en $dir"
    fi
}

# ============================================
# Deploy Proyecto Laravel
# ============================================
deploy_project() {
    log_info "=========================================="
    log_info "Desplegando Proyecto Laravel..."
    log_info "=========================================="

    create_backup "proyecto" "$PROJECT_DIR"

    cd "$PROJECT_DIR"

    # Activar modo mantenimiento
    log_step "Activando modo mantenimiento..."
    php artisan down --refresh=15 --secret="devil-bypass-$(date +%s)" || true

    # Pull ultimos cambios
    log_step "Descargando ultimos cambios..."
    git fetch origin
    git reset --hard origin/main

    # Instalar dependencias
    log_step "Instalando dependencias de Composer..."
    composer install --optimize-autoloader --no-dev --no-interaction

    # Crear archivo SQLite si no existe
    log_step "Verificando base de datos SQLite..."
    if [ ! -f "database/database.sqlite" ]; then
        touch database/database.sqlite
        log_success "Archivo SQLite creado"
    fi

    # Migraciones
    log_step "Ejecutando migraciones..."
    php artisan migrate --force

    # Limpiar y cachear
    log_step "Optimizando aplicacion..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache

    # Assets frontend
    log_step "Compilando assets..."
    npm ci --production=false
    npm run build

    # Permisos
    log_step "Configurando permisos..."
    sudo chown -R www-data:www-data storage bootstrap/cache
    sudo chmod -R 775 storage bootstrap/cache

    # Reiniciar PHP-FPM
    log_step "Reiniciando PHP-FPM..."
    sudo systemctl reload $PHP_FPM_SERVICE

    # Desactivar modo mantenimiento
    log_step "Desactivando modo mantenimiento..."
    php artisan up

    log_success "Proyecto desplegado exitosamente"
}


# ============================================
# Rollback
# ============================================
rollback() {
    local app=$1

    if [ -z "$app" ]; then
        echo "Uso: ./deploy.sh rollback [proyecto]"
        exit 1
    fi

    local backup_path=""
    local restore_dir=""

    case $app in
        proyect)
            backup_path="$BACKUP_DIR/proyect"
            restore_dir="$PROJECT_DIR"
            ;;
        *)
            log_error "App desconocida: $app"
            ;;
    esac

    # Encontrar ultimo backup
    local latest_backup=$(ls -t "$backup_path"/*.tar.gz 2>/dev/null | head -n 1)

    if [ -z "$latest_backup" ]; then
        log_error "No hay backups disponibles para $app"
    fi

    log_warning "Restaurando desde: $latest_backup"
    read -p "Continuar? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        log_info "Rollback cancelado"
        exit 0
    fi

    # Activar mantenimiento si es panel
    if [ "$app" = "panel" ]; then
        cd "$PROJECT_DIR" && php artisan down || true
    fi

    # Restaurar
    log_step "Restaurando backup..."
    rm -rf "${restore_dir}.old" 2>/dev/null || true
    mv "$restore_dir" "${restore_dir}.old"
    mkdir -p "$(dirname $restore_dir)"
    tar -xzf "$latest_backup" -C "$(dirname $restore_dir)"

    # Post-restore
    if [ "$app" = "panel" ]; then
        cd "$PROJECT_DIR"
        sudo chown -R www-data:www-data storage bootstrap/cache
        php artisan up
        sudo systemctl reload $PHP_FPM_SERVICE
    else
        cd "$BACKEND_DIR"
        pm2 reload devil-backend
    fi

    # Limpiar backup temporal
    rm -rf "${restore_dir}.old"

    log_success "Rollback completado exitosamente"
}

# ============================================
# Health Check
# ============================================
health_check() {
    log_info "=========================================="
    log_info "Verificando estado de servicios..."
    log_info "=========================================="

    echo ""

    # Nginx
    if systemctl is-active --quiet nginx; then
        log_success "Nginx: Activo"
    else
        log_error "Nginx: Inactivo"
    fi

    # PHP-FPM
    if systemctl is-active --quiet $PHP_FPM_SERVICE; then
        log_success "PHP-FPM: Activo"
    else
        log_error "PHP-FPM: Inactivo"
    fi


    # Redis
    if systemctl is-active --quiet redis; then
        log_success "Redis: Activo"
    else
        log_error "Redis: Inactivo"
    fi


    echo ""

    # Verificar endpoints
    log_info "Verificando endpoints..."

    # Panel
    if curl -sf -o /dev/null "http://localhost/"; then
        log_success "Proyecto responde correctamente"
    else
        log_warning "Proyecto no responde en localhost"
    fi

    log_info "Para ver logs de Laravel: tail -f $PROJECT_DIR/storage/logs/laravel.log"
}

# ============================================
# Main
# ============================================

# Verificar argumentos
if [ $# -eq 0 ]; then
    echo "Uso: ./deploy.sh [panel|backend|all|rollback|health]"
    echo ""
    echo "Comandos:"
    echo "  panel     - Desplegar panel Laravel"
    echo "  backend   - Desplegar backend Node"
    echo "  all       - Desplegar ambos"
    echo "  rollback  - Revertir ultimo deploy (requiere especificar app)"
    echo "  health    - Verificar estado de servicios"
    exit 1
fi

# Verificar requisitos
check_requirements

# Ejecutar comando
case $1 in
    proyect)
        deploy_project
        ;;
    all)
        deploy_project
        echo ""
        ##deploy_backend
        ;;
    rollback)
        rollback $2
        ;;
    health)
        health_check
        ;;
    *)
        log_error "Comando desconocido: $1"
        ;;
esac

echo ""
log_info "=========================================="
log_success "Proceso completado"
log_info "=========================================="
