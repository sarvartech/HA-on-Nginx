#!/bin/bash
# ==============================================================================
# Nginx Configuration Real-time Auto-Sync Daemon
# Muallif: Sysadmin Sarvar
# ==============================================================================

BACKUP_IP="192.168.1.122"
BACKUP_USER="sarvar"
WATCH_DIRS="/etc/nginx/sites-available/ /etc/nginx/sites-enabled/ /etc/nginx/conf.d/"

echo "==> Nginx Auto-Sync xizmati monitoringni boshladi..."

while inotifywait -r -e modify,create,delete,move $WATCH_DIRS; do
    echo "==> O'zgarish aniqlandi! Sinxronizatsiya boshlanmoqda..."

    # 1. sites-available ni sinxronlash
    rsync -avz --delete /etc/nginx/sites-available/ ${BACKUP_USER}@${BACKUP_IP}:/etc/nginx/sites-available/

    # 2. sites-enabled ni sinxronlash
    rsync -avz --delete /etc/nginx/sites-enabled/ ${BACKUP_USER}@${BACKUP_IP}:/etc/nginx/sites-enabled/

    # 3. conf.d mavjud bo'lsa sinxronlash
    if [ -d "/etc/nginx/conf.d" ]; then
        rsync -avz --delete /etc/nginx/conf.d/ ${BACKUP_USER}@${BACKUP_IP}:/etc/nginx/conf.d/
    fi

    # 4. Backup serverda Nginx sintaksisini tekshirish va reload qilish
    ssh ${BACKUP_USER}@${BACKUP_IP} "sudo nginx -t && sudo systemctl reload nginx"

    echo "==> Sinxronizatsiya va Nginx Reload muvaffaqiyatli bajarildi!"
done
