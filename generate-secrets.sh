#!/bin/bash

# ============================================
# Devil Panels - Secret Generator
# ============================================
# Genera todos los secretos necesarios para produccion
#
# Uso: bash generate-secrets.sh
# ============================================

echo "============================================"
echo "Devil scams - Generador de Secretos"
echo "============================================"
echo ""
echo "Copia estos valores a tus archivos .env"
echo ""
echo "============================================"
echo ""

# APP_KEY para Laravel (base64)
echo "# Laravel APP_KEY"
echo "APP_KEY=base64:$(openssl rand -base64 32)"
echo ""

# Shared Secret (64 caracteres hex)
echo "# Shared Secret (Laravel + Node)"
echo "SHARED_SECRET=$(openssl rand -hex 32)"
echo ""

# Session Secret
echo "# Session Secret (Node)"
echo "SESSION_SECRET=$(openssl rand -hex 16)"
echo ""

# Redis Password
echo "# Redis Password"
echo "REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')"
echo ""

echo "============================================"
echo "IMPORTANTE: Guarda estos valores de forma segura"
echo "============================================"
