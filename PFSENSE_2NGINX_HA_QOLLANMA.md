# pfSense + 2 ta Ubuntu Nginx (Master / Backup HA) Qo'llanmasi

Ushbu qo'llanmada **pfSense** xavfsizlik devori va sizning **2 ta Ubuntu serveringiz (Master: 192.168.1.121 va Backup: 192.168.1.122)** yordamida **Nginx + Keepalived (VRRP)** yuqori bardoshli (**High Availability**) tizimini sozlash ko'rsatilgan.

---

## 📌 1. Aniq Tarmoq Ma'lumotlari

Siz yuborgan `ip a` natijalariga asosan:
* **Interfeys nomi:** `ens33`
* **Master Server (Ubuntu):** `192.168.1.121`
* **Backup Server (Ubuntu):** `192.168.1.122`
* **Virtual IP (VIP):** `192.168.1.100` *(pfSense aynan shu IP ga yo'naltiradi)*

```
                 [ Internet / Tashqi Tarmoq ]
                              │
                              ▼
                     ┌──────────────────┐
                     │     pfSense      │
                     │  (WAN: Public IP)│
                     └────────┬─────────┘
                              │ Port Forward: 80, 443
                              ▼
                  [ Virtual IP (VIP): 192.168.1.100 ]
                              │
               ┌──────────────┴──────────────┐
               ▼ ens33 VRRP Heartbeat        ▼ ens33
    ┌──────────────────────┐      ┌──────────────────────┐
    │  Ubuntu Master       │      │  Ubuntu Backup       │
    │  IP: 192.168.1.121   │      │  IP: 192.168.1.122   │
    │  [Keepalived MASTER] │◄────►│  [Keepalived BACKUP] │
    │  (Hozirgi VIP egasi) │      │  (Kutish rejimida)   │
    └──────────────────────┘      └──────────────────────┘
```

---

## ⚙️ 2. Ikkala Serverda Bajariladigan Buyruqlar (Master va Backup da)

Ikkala terminal oynangizda navbatma-navbat bajaring:

### 2.1. Paketlarni o'rnatish
```bash
sudo apt update
sudo apt install -y nginx keepalived psmisc
```

### 2.2. Non-Local IP Binding yoqish
VIP hali interfeysda yo'q bo'lsa ham Nginx bemalol ko'tarilishi uchun:
```bash
echo "net.ipv4.ip_nonlocal_bind=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2.3. Nginx tekshiruv skriptini yaratish
```bash
sudo nano /usr/local/bin/check_nginx.sh
```
Ichiga quyidagilarni yozing:
```bash
#!/bin/bash
if /usr/bin/killall -0 nginx; then
    exit 0
else
    exit 1
fi
```
Saqlang (`Ctrl+O`, `Enter`, `Ctrl+X`) va ijro huquqini bering:
```bash
sudo chmod +x /usr/local/bin/check_nginx.sh
```

---

## 🛡️ 3. Keepalived ni sozlash

### 3.1. Master Serverda (`sarvar@Master` - 192.168.1.121):
Faylni oching:
```bash
sudo nano /etc/keepalived/keepalived.conf
```
Ichiga quyidagilarni to'liq joylashtiring:
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
Saqlab chiqing (`Ctrl+O`, `Enter`, `Ctrl+X`).

---

### 3.2. Backup Serverda (`sarvar@Backup` - 192.168.1.122):
Faylni oching:
```bash
sudo nano /etc/keepalived/keepalived.conf
```
Ichiga quyidagilarni to'liq joylashtiring:
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
Saqlab chiqing (`Ctrl+O`, `Enter`, `Ctrl+X`).

---

### 3.3. Xizmatlarni ishga tushirish (Ikkala serverda):
```bash
sudo systemctl enable nginx keepalived
sudo systemctl restart nginx
sudo systemctl restart keepalived
```

---

## 🧪 4. Tekshiruv (VIP paydo bo'ldimi?)

Master serverda buyruq bering:
```bash
ip a show ens33
```
Natijada `192.168.1.121` tagida qo'shimcha tarzda:
```
inet 192.168.1.100/24 scope global secondary ens33
```
qatori chiqishi kerak!

Backup serverda esa tekshirsangiz, faqat `192.168.1.122` bo'lishi kerak (`100` ko'rinmasligi kerak).

---

## 🔥 5. pfSense dagi Sozlama (Port Forward)

pfSense Web paneliga o'ting:
1. **Firewall** ➡️ **NAT** ➡️ **Port Forward**
2. Qoida yarating yoki mavjudini tahrirlang:
   * **Interface:** `WAN`
   * **Protocol:** `TCP`
   * **Destination Port:** `HTTP` (80) va `HTTPS` (443)
   * **Redirect target IP:** `192.168.1.100` *(Virtual IP ni ko'rsatasiz!)*
   * **Redirect target port:** `80` (yoki `443`)
   * **Filter rule association:** `Add associated filter rule`
3. **Save** va **Apply Changes**.

---

## ⚡ 6. Avariya (Failover) Testi

1. Master serverda Nginx ni to'xtating:
   ```bash
   sudo systemctl stop nginx
   ```
2. Darhol Backup serverda tekshiring:
   ```bash
   ip a show ens33
   ```
   `192.168.1.100` VIP darhol Backup serverga o'tgan bo'ladi!
3. Master serverda Nginx ni qayta yoqsangiz:
   ```bash
   sudo systemctl start nginx
   ```
   VIP yana avtomatik Master serverga qaytadi.
