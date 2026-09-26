# Nginx & HAProxy High Availability (Active / Standby Failover) Qo'llanmasi

Ushbu qo'llanma taqdim etilgan arxitektura asosida **Virtual IP (VIP)**, **Keepalived (VRRP)**, **HAProxy** va **Nginx** serverlarini Master-Backup rejimida sozlash bo'yicha to'liq bosqichma-bosqich yo'riqnomadir.

---

## 📌 1. Arxitektura tushunchasi

```
                 [ Firewall / Router ]
                           │
             (NAT -> Virtual IP: 192.168.1.100)
                           │
            ┌──────────────┴──────────────┐
            ▼                             ▼
  ┌───────────────────┐         ┌───────────────────┐
  │ HAProxy 1 (Node1) │         │ HAProxy 2 (Node2) │
  │   192.168.1.10    │  VRRP   │   192.168.1.11    │
  │  [Active/Master]  │ ◄─────► │ [Standby/Backup]  │
  │ (Egasi: VIP .100) │         │                   │
  └─────────┬─────────┘         └─────────┬─────────┘
            │                             │
            └──────────────┬──────────────┘
                           ▼
            ┌─────────────────────────────┐
            │     Backend Nginx Klaster   │
            │  Nginx 1: 192.168.1.20      │
            │  Nginx 2: 192.168.1.21      │
            └─────────────────────────────┘
```

### Serverlar rejasi (IP manzillar misoli):
| Server nomi | Real IP | Vazifasi / Xizmatlar |
|---|---|---|
| **Virtual IP (VIP)** | `192.168.1.100` | Tashqi/Firewall yo'naltiriladigan yagona suzuvchi IP |
| **LB-01 (Master)** | `192.168.1.10` | Keepalived (Master) + HAProxy 1 |
| **LB-02 (Backup)** | `192.168.1.11` | Keepalived (Backup) + HAProxy 2 |
| **Web-01 (Backend)**| `192.168.1.20` | Nginx Web Server 1 |
| **Web-02 (Backend)**| `192.168.1.21` | Nginx Web Server 2 |

---

## 🚀 2. LB-01 va LB-02 da dastlabki sozlashlar (Ikkala serverda)

### 2.1. Paketlarni o'rnatish
Ubuntu/Debian tizimlarida:
```bash
sudo apt update
sudo apt install -y keepalived haproxy psmisc
```

RHEL / Rocky / AlmaLinux tizimlarida:
```bash
sudo dnf install -y keepalived haproxy psmisc
```

### 2.2. Tizimda Non-Local IP Binding yoqish
Keepalived ishga tushganda VIP hali interfeysga ulanmagan bo'lsa ham HAProxy xizmati erkin ko'tarila olishi uchun ushbu parametr shart:

```bash
# Vaqtinchalik yoqish:
sudo sysctl net.ipv4.ip_nonlocal_bind=1

# Doimiy saqlash:
echo "net.ipv4.ip_nonlocal_bind=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## ⚙️ 3. HAProxy ni sozlash (LB-01 va LB-02 da bir xil)

`/etc/haproxy/haproxy.cfg` faylini tahrirlang:
```bash
sudo nano /etc/haproxy/haproxy.cfg
```

Fayl oxiriga yoki asosiy qismiga quyidagilarni kiriting:

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Monitoring / Statistikalar paneli (Opsional)
listen stats
    bind 0.0.0.0:8404
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats admin if TRUE

# Asosiy kiruvchi oqim (Frontend)
frontend http_front
    # VIP yoki barcha interfeyslarni tinglaydi
    bind 192.168.1.100:80
    # Agar SSL bo'lsa: bind 192.168.1.100:443 ssl crt /etc/ssl/cert.pem
    mode http
    option forwardfor
    default_backend nginx_backends

# Nginx serverlariga yuk taqsimlash (Backend)
backend nginx_backends
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    server nginx1 192.168.1.20:80 check fall 3 rise 2
    server nginx2 192.168.1.21:80 check fall 3 rise 2
```

HAProxy ni qayta ishga tushiring:
```bash
sudo systemctl enable haproxy
sudo systemctl restart haproxy
```

---

## 🛡️ 4. Keepalived ni sozlash

Keepalived HAProxy xizmatini har 2 soniyada tekshiradi. Agar HAProxy to'xtab qolsa yoki server o'chsa, VIP darhol zaxiradagi (Backup) serverga o'tadi.

### 4.1. HAProxy monitoring skripti (LB-01 va LB-02 da)
Skript yaratamiz:
```bash
sudo nano /usr/local/bin/check_haproxy.sh
```

Mazmuni:
```bash
#!/bin/bash
/usr/bin/killall -0 haproxy
```

Ijro huquqini bering:
```bash
sudo chmod +x /usr/local/bin/check_haproxy.sh
```

---

### 4.2. LB-01 (Master) uchun Keepalived sozlamasi
Tarmoq kartangiz nomini aniqlang (masalan: `eth0` yoki `ens192`):
```bash
ip -br a
```

`/etc/keepalived/keepalived.conf` faylini tahrirlang:
```bash
sudo nano /etc/keepalived/keepalived.conf
```

Quyidagi konfiguratsiyani kiriting:
```keepalived
global_defs {
    router_id haproxy_lb01
    script_user root
    enable_script_security
}

# HAProxy holatini tekshiruvchi skript
vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0               # <--- Tarmoq kartangiz nomini yozing
    virtual_router_id 51         # Har ikkala serverda bir xil bo'lishi shart!
    priority 101                 # Masterda ustunlik yuqoriroq (101)
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass SecretVRRPPass123
    }

    virtual_ipaddress {
        192.168.1.100/24 dev eth0
    }

    track_script {
        chk_haproxy
    }
}
```

---

### 4.3. LB-02 (Backup / Standby) uchun Keepalived sozlamasi
`/etc/keepalived/keepalived.conf`:
```bash
sudo nano /etc/keepalived/keepalived.conf
```

Quyidagi konfiguratsiyani kiriting:
```keepalived
global_defs {
    router_id haproxy_lb02
    script_user root
    enable_script_security
}

vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0               # <--- Tarmoq kartangiz nomi
    virtual_router_id 51         # Master bilan bir xil bo'lishi shart!
    priority 100                 # Zaxirada priority pastroq (100)
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass SecretVRRPPass123
    }

    virtual_ipaddress {
        192.168.1.100/24 dev eth0
    }

    track_script {
        chk_haproxy
    }
}
```

Keepalived ni ishga tushiring:
```bash
sudo systemctl enable keepalived
sudo systemctl restart keepalived
```

---

## 🌐 5. Backend Nginx serverlarini sozlash (Nginx 1 va Nginx 2)

HAProxy `httpchk GET /health` orqali server sog'lomligini tekshirishi uchun Nginx serverlarida `/health` yo'nalishini qo'shing:

`/etc/nginx/sites-available/default` yoki `/etc/nginx/conf.d/default.conf`:
```nginx
server {
    listen 80;
    server_name _;

    # HAProxy Health-Check uchun endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
```

Qayta ishga tushirish:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 🧪 6. Test qilish va Ishlashini tekshirish

### 1-Tekshiruv: VIP qaysi serverda turganini ko'rish
LB-01 (Master) da buyruq bering:
```bash
ip addr show eth0
```
Natijada `inet 192.168.1.100/24` ko'rinishi kerak. LB-02 da esa bu IP ko'rinmasligi kerak.

### 2-Tekshiruv: Failover (Avtomatik o'tish) testi
LB-01 da HAProxy xizmatini to'xtating:
```bash
sudo systemctl stop haproxy
```
Yoki LB-01 ni o'chirib qo'ying (reboot):
```bash
sudo reboot
```

Darhol LB-02 (Backup) da tekshiring:
```bash
ip addr show eth0
```
Endi `192.168.1.100` VIP IP avtomatik ravishda **LB-02** ga ko'chgan bo'ladi! Xizmatda uzilish bo'lmaydi.

LB-01 qayta tiklanganda, uning `priority`si 101 bo'lgani sababli VIP avtomatik unga qaytadi.

---

## 🔒 7. Firewall (UFW / Firewalld) sozlamalari
VRRP protokoli ishlashi uchun tarmoqlararo multicast trafigiga ruxsat berish zarur:

**Ubuntu (UFW):**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8404/tcp # HAProxy stats
# VRRP protokoli uchun:
sudo ufw allow proto vrrp
```

**RHEL/CentOS (Firewalld):**
```bash
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --add-protocol=vrrp --permanent
sudo firewall-cmd --reload
```
