# Devil Panels - Deployment Guide

## Arquitectura de Dominios

Este proyecto usa **dominios separados** para el panel y el backend:

| Componente | Dominio Ejemplo | Base de Datos | Descripcion |
|------------|-----------------|---------------|-------------|
| Panel Laravel | `panel.tudominio.com` | SQLite | Frontend/Dashboard |
| Backend Node | `api.otrodominio.com` | PostgreSQL | API REST + WebSocket |

Esto permite mayor flexibilidad y seguridad al tener los servicios en dominios independientes.

## Estructura de Archivos

```
deploy/
├── .env.production.example    # Template de variables Laravel
├── .env.backend.example       # Template de variables Node
├── server-setup.sh            # Script de configuracion inicial del servidor
├── deploy.sh                  # Script de despliegue automatizado
├── generate-secrets.sh        # Generador de secretos
├── ecosystem.config.js        # Configuracion PM2 para Node
├── nginx/
│   ├── panel.conf             # Config Nginx para Laravel
│   └── api.conf               # Config Nginx para Node API
└── github-workflows/
    └── deploy-backend.yml     # CI/CD para el backend Node
```

## Pasos de Despliegue

### 1. Configurar Cloudflare

**Para el dominio del PANEL:**
1. Crear cuenta en [Cloudflare](https://cloudflare.com)
2. Agregar dominio del panel (ej: tudominio.com)
3. Cambiar nameservers en Namecheap
4. Configurar SSL > Full (Strict)
5. Crear Origin Certificate para `*.tudominio.com` y descargar `origin-panel.pem` y `origin-panel.key`

**Para el dominio del BACKEND:**
1. Agregar dominio del backend (ej: otrodominio.com)
2. Cambiar nameservers en Namecheap
3. Configurar SSL > Full (Strict)
4. Crear Origin Certificate para `*.otrodominio.com` y descargar `origin-backend.pem` y `origin-backend.key`
5. Habilitar WebSockets en Network (importante para Socket.io)

### 2. Configurar AWS EC2

1. Crear instancia Ubuntu 22.04 (t3.small minimo)
2. Asignar Elastic IP
3. Configurar Security Group:
   - SSH (22) → Tu IP
   - HTTP (80) → IPs de Cloudflare
   - HTTPS (443) → IPs de Cloudflare
   - TCP 3000 → IPs de Cloudflare (WebSocket)

### 3. Configurar Servidor

```bash
# Conectar al servidor
ssh -i tu-key.pem ubuntu@TU_IP

# Clonar repositorio (o subir archivos)
git clone TU_REPO /tmp/deploy
cd /tmp/deploy/deploy

# Ejecutar setup inicial
sudo bash server-setup.sh
```

### 4. Subir Certificados Cloudflare

```bash
# Desde tu maquina local
scp -i tu-key.pem origin.pem ubuntu@TU_IP:/tmp/
scp -i tu-key.pem origin.key ubuntu@TU_IP:/tmp/

# En el servidor
sudo mv /tmp/origin.pem /etc/ssl/cloudflare/
sudo mv /tmp/origin.key /etc/ssl/cloudflare/
sudo chmod 600 /etc/ssl/cloudflare/origin.key
```

### 5. Configurar Nginx

```bash
# Editar panel.conf - reemplazar {{DOMAIN}} con dominio del panel
# Ejemplo: panel.tudominio.com
sudo nano /tmp/deploy/deploy/nginx/panel.conf

# Editar api.conf - reemplazar {{BACKEND_DOMAIN}} con dominio del backend
# Ejemplo: api.otrodominio.com
sudo nano /tmp/deploy/deploy/nginx/api.conf

# Copiar configuraciones
sudo cp /tmp/deploy/deploy/nginx/panel.conf /etc/nginx/sites-available/panel
sudo cp /tmp/deploy/deploy/nginx/api.conf /etc/nginx/sites-available/api

# Actualizar rutas de certificados en api.conf si usas certificados separados:
# ssl_certificate /etc/ssl/cloudflare/origin-backend.pem;
# ssl_certificate_key /etc/ssl/cloudflare/origin-backend.key;

# Activar sitios
sudo ln -s /etc/nginx/sites-available/panel /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/api /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default

# Verificar y reiniciar
sudo nginx -t
sudo systemctl reload nginx
```

### 6. Generar Secretos

```bash
bash generate-secrets.sh
# Copiar los valores generados a los archivos .env
```

### 7. Configurar Aplicaciones

```bash
# Panel Laravel (usa SQLite)
cd /var/www/devil-panel
git clone TU_REPO_LARAVEL .
cp deploy/.env.production.example .env
nano .env  # Configurar valores
composer install --no-dev
php artisan key:generate
touch database/database.sqlite  # Crear archivo SQLite
php artisan migrate --force
npm install && npm run build
sudo chown -R www-data:www-data storage bootstrap/cache database

# Backend Node (usa PostgreSQL)
cd /var/www/devil-backend
git clone TU_REPO_NODE .
cp /tmp/deploy/deploy/.env.backend.example .env
nano .env  # Configurar valores (DATABASE_URL con PostgreSQL)
npm install --production
npx prisma migrate deploy  # Si usas Prisma
pm2 start ecosystem.config.js
pm2 save
```

### 8. Configurar GitHub Actions (CI/CD)

**En el repositorio del PANEL:**

1. Ir a Settings > Secrets and variables > Actions
2. Agregar estos secrets:
   - `SSH_PRIVATE_KEY`: Tu clave SSH privada
   - `SSH_HOST`: IP del servidor
   - `SSH_USER`: ubuntu
   - `DOMAIN`: tudominio.com (dominio del panel)

El archivo `.github/workflows/deploy-panel.yml` ya esta incluido.

**En el repositorio del BACKEND:**

1. Copiar `github-workflows/deploy-backend.yml` a `.github/workflows/`
2. Agregar secrets:
   - `SSH_PRIVATE_KEY`: Tu clave SSH privada
   - `SSH_HOST`: IP del servidor
   - `SSH_USER`: ubuntu
   - `DOMAIN`: otrodominio.com (dominio del backend)

## Comandos Utiles

```bash
# Desplegar manualmente
./deploy.sh panel      # Solo panel
./deploy.sh backend    # Solo backend
./deploy.sh all        # Ambos
./deploy.sh health     # Verificar servicios

# Rollback
./deploy.sh rollback panel
./deploy.sh rollback backend

# Logs
pm2 logs devil-backend
tail -f /var/www/devil-panel/storage/logs/laravel.log
tail -f /var/log/nginx/panel_error.log

# Estado de servicios
sudo systemctl status nginx php8.3-fpm postgresql redis
pm2 status
```

## Verificacion

1. `https://panel.tudominio.com` - Debe cargar el login
2. `https://api.otrodominio.com/health` - Debe responder OK
3. WebSocket debe conectar a `wss://api.otrodominio.com` (verificar en DevTools > Network > WS)

## Agregar Nuevos Proyectos

1. En Cloudflare DNS: Agregar registro A para `proyecto.tudominio.com`
2. En `.env` del backend: Agregar a `PROJECT_SECRETS`
3. Reiniciar: `pm2 reload devil-backend`
4. En el proyecto externo: Configurar headers `X-Project-Slug` y `X-Project-Secret`
