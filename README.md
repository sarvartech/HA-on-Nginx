# 🚀 pfSense & Nginx High Availability (HA) Failover Cluster

<p align="center">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white" />
  <img src="https://img.shields.io/badge/Nginx-Reverse%20Proxy-009639?style=for-the-badge&logo=nginx&logoColor=white" />
  <img src="https://img.shields.io/badge/Keepalived-VRRP%20HA-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/pfSense-Firewall%20%2F%20NAT-black?style=for-the-badge&logo=pfsense&logoColor=white" />
</p>

Ushbu repozitoriy **pfSense** xavfsizlik devori va **2 ta Ubuntu serverida Nginx + Keepalived (VRRP)** protokoli yordamida uzluksiz ishlovchi (**High Availability - Master/Backup**) klaster tizimini sozlash bo'yicha to'liq va amaliy qo'llanmadir.

---

## 📑 Mundarija
- [Arxitektura](#-arxitektura)
- [Serverlar va Tarmoq Rejasi](#-serverlar-va-tarmoq-rejasi)
- [Repozitoriya Tuzilishi](#-repozitoriya-tuzilishi)
- [1-Qadam: Dastlabki Sozlashlar (Master & Backup)](#-1-qadam-dastlabki-sozlashlar-ikkala-serverda)
- [2-Qadam: Nginx Monitoring Skripti](#-2-qadam-nginx-monitoring-skripti)
- [3-Qadam: Keepalived ni Sozlash](#-3-qadam-keepalived-ni-sozlash)
- [4-Qadam: pfSense NAT Port Forward](#-4-qadam-pfsense-nat-port-forward-sozlamalari)
- [5-Qadam: Nginx Reverse Proxy & SSL](#-5-qadam-nginx-reverse-proxy--ssl-sozlamalari)
- [6-Qadam: Master va Backup Avto-Sinxronizatsiya](#-6-qadam-avtomatik-sinxronizatsiya-autosync)
- [7-Qadam: Failover Testi](#-7-qadam-klasterni-sinab-korish-failover-test)
- [Monitoring va Loglar](#-monitoring-va-jonli-loglar)

---

## 🏛️ Arxitektura

```
                     [ Internet / Foydalanuvchilar ]
                                    │
                                    ▼
                           ┌──────────────────┐
                           │     pfSense      │
                           │  (Firewall/NAT)  │
                           └────────┬─────────┘
                                    │ Port Forward: 80, 443
                                    ▼
                        [ Virtual IP: 192.168.1.100 ]
                                    │
                     ┌──────────────┴──────────────┐
                     ▼ VRRP Heartbeat (Multicast)  ▼
          ┌──────────────────────┐      ┌──────────────────────┐
          │     Nginx-Master     │      │     Nginx-Backup     │
          │    192.168.1.121     │      │    192.168.1.122     │
          │ [Keepalived: MASTER] │◄────►│ [Keepalived: BACKUP] │
          │ (Hozirgi VIP egasi)  │      │  (Kutish rejimida)   │
          └──────────┬───────────┘      └──────────┬───────────┘
                     │                             │
                     └──────────────┬──────────────┘
                                    ▼
                         ┌────────────────────┐
                         │   Backend App      │
                         │ (192.168.1.50:443) │
                         └────────────────────┘
```

---

## 🌐 Serverlar va Tarmoq Rejasi

| Hostname | Rol | Real IP | Virtual IP (VIP) | Interfeys |
|---|---|---|---|---|
| **pfSense** | Router / Firewall | `192.168.1.1` | - | LAN / WAN |
| **Master** | Nginx Primary Node | `192.168.1.121` | `192.168.1.100` | `ens33` |
| **Backup** | Nginx Standby Node | `192.168.1.122` | `192.168.1.100` | `ens33` |
| **Backend** | Ilova / Web Server | `192.168.1.50` | - | - |

---

## 📂 Repozitoriya Tuzilishi

```
nginx-HA/
├── README.md                       # Asosiy to'liq qo'llanma
├── configs/
│   ├── keepalived/
│   │   ├── master.conf             # Master server uchun Keepalived sozlamasi
│   │   └── backup.conf             # Backup server uchun Keepalived sozlamasi
│   └── nginx/
│       ├── app.conf                # SSL bilan to'liq Reverse Proxy konfiguratsiyasi
│       └── backend-health.conf     # Health-check endpoint misoli
└── scripts/
    ├── check_nginx.sh              # Nginx jarayonini tekshiruvchi pulsometr skript
    └── nginx-autosync.sh           # Konfiguratsiyalarni avto-sinxronizatsiya qilish
```

---

## ⚙️ 1-Qadam: Dastlabki Sozlashlar (Ikkala Serverda)

Ikkala Ubuntu serveringizda (`Master` va `Backup`) quyidagi amallarni bajaring:

```bash
# 1. Paketlarni o'rnatish
sudo apt update
sudo apt install -y nginx keepalived psmisc inotify-tools rsync curl

# 2. Non-local bindingni yoqish (VIP interfeysda yo'q bo'lsa ham Nginx ko'tarilishi uchun)
echo "net.ipv4.ip_nonlocal_bind=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## 🩺 2-Qadam: Nginx Monitoring Skripti

Keepalived nafaqat server o'chishini, balki Nginx jarayoni to'xtab qolishini ham sezishi uchun ikkala serverda tekshiruv skripti bo'lishi shart.

**Ikkala serverda bajaring:**
```bash
sudo nano /usr/local/bin/check_nginx.sh
```

Quyidagi kodni yozing:
```bash
#!/bin/bash
# Xotirada Nginx jarayoni mavjudligini tekshiradi (0 = OK, 1 = Error)
if /usr/bin/killall -0 nginx; then
    exit 0
else
    exit 1
fi
```

Ijro huquqini bering:
```bash
sudo chmod +x /usr/local/bin/check_nginx.sh
```

---

## 🛡️ 3-Qadam: Keepalived ni Sozlash

### A) Master Serverda (`sarvar@Master` - 192.168.1.121)
`/etc/keepalived/keepalived.conf` fayliga quyidagini yozing:

```keepalived
global_defs {
    router_id nginx_master
    script_user root
    enable_script_security
}

vrrp_script chk_nginx {
    script "/usr/local/bin/check_nginx.sh"
    interval 2
    weight 2
}

vrrp_instance VI_NGINX {
    state MASTER
    interface ens33
    virtual_router_id 51
    priority 101
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass NginxSecretPass123
    }

    virtual_ipaddress {
        192.168.1.100/24 dev ens33
    }

    track_script {
        chk_nginx
    }
}
```

### B) Backup Serverda (`sarvar@Backup` - 192.168.1.122)
`/etc/keepalived/keepalived.conf` fayliga quyidagini yozing:

```keepalived
global_defs {
    router_id nginx_backup
    script_user root
    enable_script_security
}

vrrp_script chk_nginx {
    script "/usr/local/bin/check_nginx.sh"
    interval 2
    weight 2
}

vrrp_instance VI_NGINX {
    state BACKUP
    interface ens33
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass NginxSecretPass123
    }

    virtual_ipaddress {
        192.168.1.100/24 dev ens33
    }

    track_script {
        chk_nginx
    }
}
```

### C) Xizmatlarni ishga tushirish:
```bash
sudo systemctl enable --now nginx keepalived
```

Tekshirish:
```bash
ip a show ens33
# Master serverda "192.168.1.100/24" paydo bo'lishi kerak!
```

---

## 🔥 4-Qadam: pfSense NAT Port Forward Sozlamalari

pfSense veb-paneliga kiring:
1. **Firewall** ➡️ **NAT** ➡️ **Port Forward**
2. 80 (HTTP) va 443 (HTTPS) portlar uchun qoida qo'shing:
   * **Interface:** `WAN`
   * **Protocol:** `TCP`
   * **Destination Port:** `HTTP (80)` va `HTTPS (443)`
   * **Redirect target IP:** `192.168.1.100` *(Faqat VIP manzili!)*
   * **Redirect target port:** `80` va `443`
   * **Filter rule association:** `Add associated filter rule`
3. **Save** va **Apply Changes**.

---

## 🔒 5-Qadam: Nginx Reverse Proxy & SSL Sozlamalari

Ikkala serverda (`/etc/nginx/sites-available/app.conf`):

```nginx
upstream backend_cluster {
    server 192.168.1.50:443;
}

# HTTP dan HTTPS ga yo'naltirish
server {
    listen 80;
    server_name vault-srv.trustbank.uz;
    return 301 https://$host$request_uri;
}

# Asosiy HTTPS Reverse Proxy
server {
    listen 443 ssl;
    server_name vault-srv.trustbank.uz;

    ssl_certificate     /etc/ssl/certs/vault.crt;
    ssl_certificate_key /etc/ssl/private/vault.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://backend_cluster;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_verify off;
    }
}
```

Faollashtirish:
```bash
sudo ln -sf /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## 🔄 6-Qadam: Avtomatik Sinxronizatsiya (Auto-Sync)

Master serverda yaratilgan yangi saytlar va konfiguratsiyalar Backup serverga avtomatik o'tishi uchun:

1. **Masterda SSH kalit ulanadi:**
   ```bash
   ssh-keygen -t ed25519
   ssh-copy-id sarvar@192.168.1.122
   ```

2. **Backup serverda huquq beriladi:**
   ```bash
   sudo chown -R sarvar:sarvar /etc/nginx/sites-available /etc/nginx/sites-enabled
   ```

3. **Master serverda avto-sinxronizator yoqiladi:**
   `scripts/nginx-autosync.sh` skripti orqali Masterdagi barcha o'zgarishlar Backupga real vaqtda nusxalanadi va Backupda `nginx reload` qilinadi.

---

## 🧪 7-Qadam: Klasterni Sinab Ko'rish (Failover Test)

1. Brauzerda saytga kiring: `https://vault-srv.trustbank.uz`
2. Master serverda Nginx'ni to'xtating yoki butun serverni o'chiring:
   ```bash
   sudo systemctl stop nginx
   # yoki
   sudo poweroff
   ```
3. Backup serverda tekshiring:
   ```bash
   ip a show ens33
   ```
   **`192.168.1.100`** VIP darhol Backup serverga o'tadi va sayt bir soniyaga ham uzilmasdan ishlashda davom etadi!

---

## 📊 Monitoring va Jonli Loglar

```bash
# Jonli so'rovlar oqimi (Access log):
sudo tail -f /var/log/nginx/access.log

# Jonli xatoliklar (Error log):
sudo tail -f /var/log/nginx/error.log

# Keepalived holati va VIP o'tishlari:
sudo journalctl -u keepalived -f
```

---

## 👨‍💻 Muallif
* **Sarvar** ([Sysadmin Sarvar](https://youtube.com))
* Litsenziya: MIT License
