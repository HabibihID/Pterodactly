#!/usr/bin/env bash
# ============================================================
#   HABIBI PTERODACTYL INSTALLER
#   Panel + Wings + Tema (Blueprint) dalam satu script
#   Jalankan sebagai root di VPS:
#     Ubuntu 22.04 / 24.04  |  Debian 11 / 12
#   Script ini TIDAK berafiliasi dengan Pterodactyl Project.
# ============================================================

# ------------------------- Helper ---------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

ask() { # ask "pertanyaan" -> jawaban di $REPLY_JAWAB
  local q="$1" def="${2:-}"
  if [ -n "$def" ]; then read -r -p "$q [$def]: " REPLY_JAWAB; REPLY_JAWAB="${REPLY_JAWAB:-$def}"
  else read -r -p "$q: " REPLY_JAWAB; fi
}

confirm() { # confirm "pertanyaan?" -> return 0 jika ya
  local ans
  read -r -p "$1 (y/n): " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

gen_pass() { head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "${1:-24}"; }

pause() { read -r -p "Tekan ENTER untuk lanjut..."; }

# ------------------------- Cek awal -------------------------
PANEL_DIR="/var/www/pterodactyl"
WINGS_DIR="/etc/pterodactyl"
PHP_VER="8.3"
NODE_VER="20"

require_root() {
  [ "$EUID" -eq 0 ] || die "Script ini harus dijalankan sebagai root. Login sebagai root lalu jalankan lagi."
}

detect_os() {
  [ -f /etc/os-release ] || die "Tidak bisa mendeteksi OS."
  . /etc/os-release
  OS_ID="$ID"; OS_VER="$VERSION_ID"
  case "$OS_ID" in
    ubuntu|debian) ;;
    *) die "OS tidak didukung: $PRETTY_NAME. Gunakan Ubuntu 22.04/24.04 atau Debian 11/12." ;;
  esac
  info "OS terdeteksi: $PRETTY_NAME"
}

apt_update() { info "Memperbarui daftar paket..."; apt-get update -y >/dev/null 2>&1 || die "apt-get update gagal. Cek koneksi internet VPS."; }

# ------------------------- PHP ------------------------------
install_php() {
  info "Menginstal PHP $PHP_VER..."
  if [ "$OS_ID" = "ubuntu" ]; then
    apt-get install -y software-properties-common ca-certificates lsb-release apt-transport-https >/dev/null 2>&1
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || die "Gagal menambah PPA PHP."
  else
    apt-get install -y ca-certificates apt-transport-https lsb-release curl gnupg >/dev/null 2>&1
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/sury-php.gpg || die "Gagal mengambil kunci repo PHP (sury)."
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury-php.list
  fi
  apt_update
  apt-get install -y php${PHP_VER} php${PHP_VER}-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} || die "Instalasi PHP gagal."
  ok "PHP $(php -v | head -n1 | cut -d' ' -f2) terinstal."
}

install_composer() {
  if command -v composer >/dev/null 2>&1; then ok "Composer sudah ada."; return; fi
  info "Menginstal Composer..."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || die "Instalasi Composer gagal."
  ok "Composer terinstal."
}

# ------------------------- Database -----------------------
install_mariadb_redis() {
  info "Menginstal MariaDB & Redis..."
  apt-get install -y mariadb-server redis-server || die "Instalasi MariaDB/Redis gagal."
  systemctl enable --now mariadb redis-server >/dev/null 2>&1 || die "Gagal menjalankan MariaDB/Redis."
  ok "MariaDB & Redis aktif."
}

# ------------------------- Panel ----------------------------
install_panel() {
  detect_os
  warn "Panel akan diinstal di server ini. Pastikan ini VPS fresh (belum ada web lain)."
  ask "Domain/subdomain untuk panel (contoh: panel.domainkamu.com)" ""; local FQDN="$REPLY_JAWAB"
  [ -n "$FQDN" ] || die "Domain tidak boleh kosong."
  ask "Email admin panel" ""; local ADMIN_EMAIL="$REPLY_JAWAB"
  [ -n "$ADMIN_EMAIL" ] || die "Email tidak boleh kosong."
  ask "Username admin panel" "admin"; local ADMIN_USER="$REPLY_JAWAB"
  ask "Nama depan admin" "Admin"; local ADMIN_FIRST="$REPLY_JAWAB"
  ask "Nama belakang admin" "Habibi"; local ADMIN_LAST="$REPLY_JAWAB"
  ask "Timezone" "Asia/Jakarta"; local TZ="$REPLY_JAWAB"

  local MODE
  confirm "Pasang SSL HTTPS (Let's Encrypt) sekarang? (domain harus sudah mengarah ke IP server ini)" && MODE="ssl" || MODE="http"

  apt_update
  install_php
  install_composer
  install_mariadb_redis
  apt-get install -y nginx git curl tar unzip zip software-properties-common || die "Instalasi paket dasar gagal."

  # --- Database panel ---
  local DB_PASS; DB_PASS="$(gen_pass 24)"
  info "Membuat database panel..."
  mysql -e "CREATE DATABASE IF NOT EXISTS panel;" || die "Gagal membuat database."
  mysql -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';" || die "Gagal membuat user database."
  mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;" || die "Gagal memberi hak akses database."

  # --- Unduh panel ---
  info "Mengunduh Pterodactyl Panel terbaru..."
  mkdir -p "$PANEL_DIR" && cd "$PANEL_DIR" || die "Tidak bisa masuk ke $PANEL_DIR."
  curl -sL -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz" || die "Gagal mengunduh panel."
  tar -xzf panel.tar.gz && rm -f panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction || die "composer install gagal."

  # --- Konfigurasi .env ---
  cp .env.example .env
  php artisan key:generate --force >/dev/null || die "Gagal membuat APP_KEY."
  local PROTO="https"; [ "$MODE" = "http" ] && PROTO="http"
  sed -i "s|^APP_URL=.*|APP_URL=${PROTO}://${FQDN}|" .env
  sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=${TZ}|" .env
  sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
  sed -i "s|^DB_PORT=.*|DB_PORT=3306|" .env
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=panel|" .env
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=pterodactyl|" .env
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env
  sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=redis|" .env
  sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|" .env
  sed -i "s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|" .env
  grep -q "^REDIS_HOST=" .env && sed -i "s|^REDIS_HOST=.*|REDIS_HOST=127.0.0.1|" .env

  info "Menjalankan migrasi database..."
  php artisan migrate --seed --force || die "Migrasi database gagal."
  chown -R www-data:www-data "$PANEL_DIR"/*

  # --- User admin ---
  local ADMIN_PASS; ADMIN_PASS="$(gen_pass 16)"
  info "Membuat user admin..."
  php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" \
    --name-first="$ADMIN_FIRST" --name-last="$ADMIN_LAST" --password="$ADMIN_PASS" --admin=1 || die "Gagal membuat user admin."

  # --- Cron & queue worker ---
  (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run"; echo "* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1") | crontab -
  cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable --now pteroq.service

  # --- Nginx ---
  info "Mengatur Nginx..."
  cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};
    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;
    client_max_body_size 100m;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t || die "Konfigurasi Nginx tidak valid."
  systemctl restart nginx php${PHP_VER}-fpm

  # --- SSL ---
  if [ "$MODE" = "ssl" ]; then
    info "Memasang sertifikat SSL..."
    apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1
    certbot --nginx -d "$FQDN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || warn "SSL gagal dipasang. Cek apakah domain sudah mengarah ke IP server ini, lalu jalankan: certbot --nginx -d $FQDN"
  fi

  # --- Firewall (opsional) ---
  if confirm "Aktifkan firewall UFW? (port 22, 80, 443 dibuka)"; then
    apt-get install -y ufw >/dev/null 2>&1
    ufw allow 22/tcp >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
    ufw --force enable >/dev/null
    ok "Firewall UFW aktif."
  fi

  echo ""
  ok "==================================================="
  ok "  PANEL BERHASIL DIINSTAL!"
  ok "  URL       : ${PROTO}://${FQDN}"
  ok "  Email     : ${ADMIN_EMAIL}"
  ok "  Username  : ${ADMIN_USER}"
  ok "  Password  : ${ADMIN_PASS}   <-- SIMPAN BAIK-BAIK!"
  ok "  DB PASS   : ${DB_PASS}"
  ok "==================================================="
  warn "Catat password di atas sekarang. Password tidak ditampilkan lagi."
  pause
}

# ------------------------- Wings ----------------------------
install_wings() {
  detect_os
  warn "Wings akan diinstal di server ini (bisa satu server dengan panel)."
  apt_update
  apt-get install -y curl tar unzip zip || die "Instalasi paket dasar gagal."

  # --- Docker ---
  if ! command -v docker >/dev/null 2>&1; then
    info "Menginstal Docker..."
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash || die "Instalasi Docker gagal."
  fi
  systemctl enable --now docker

  # --- Wings binary ---
  info "Mengunduh Wings terbaru..."
  mkdir -p "$WINGS_DIR" /var/log/pterodactyl /var/lib/pterodactyl/volumes
  local ARCH="amd64"; [ "$(uname -m)" = "aarch64" ] && ARCH="arm64"
  curl -sL -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}" || die "Gagal mengunduh Wings."
  chmod u+x /usr/local/bin/wings
  ok "Wings terinstal: $(/usr/local/bin/wings --version 2>/dev/null | head -n1)"

  # --- Konfigurasi node ---
  echo ""
  info "Sekarang ambil config.yml dari Panel kamu:"
  info "  Panel > Admin (ikon roda gigi) > Nodes > pilih node > tab Configuration"
  info "Salin seluruh isi config.yml, lalu tempel di bawah ini."
  info "Setelah selesai menempel, tekan ENTER lalu Ctrl+D."
  echo ""
  read -r -p "Tekan ENTER untuk mulai menempel config.yml..." _
  cat > "${WINGS_DIR}/config.yml" || die "Gagal menyimpan config.yml."
  grep -q "uuid:" "${WINGS_DIR}/config.yml" || warn "Isi config sepertinya tidak lengkap (tidak ada 'uuid:'). Cek lagi di Panel."

  # --- Systemd service ---
  cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wings || die "Wings gagal start. Cek: journalctl -u wings -e"

  if confirm "Buka port Wings di firewall UFW? (8080 = daemon, 2022 = SFTP)"; then
    apt-get install -y ufw >/dev/null 2>&1
    ufw allow 8080/tcp >/dev/null; ufw allow 2022/tcp >/dev/null
  fi

  echo ""
  ok "==================================================="
  ok "  WINGS BERHASIL DIINSTAL & BERJALAN!"
  ok "  Cek status : systemctl status wings"
  ok "  Lihat log  : journalctl -u wings -f"
  ok "==================================================="
  warn "Di Panel, pastikan FQDN/SNI node sudah sesuai dan daemon port 8080."
  pause
}

# ------------------------- Update panel ---------------------
update_panel() {
  [ -d "$PANEL_DIR" ] || die "Panel tidak ditemukan di $PANEL_DIR."
  warn "Panel akan di-update ke versi terbaru. Website panel akan mati sebentar."
  confirm "Lanjut update?" || return
  cd "$PANEL_DIR" || die "Tidak bisa masuk $PANEL_DIR."
  php artisan down
  curl -sL -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz" || die "Gagal mengunduh update."
  tar -xzf panel.tar.gz && rm -f panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction || die "composer install gagal."
  php artisan migrate --seed --force || die "Migrasi gagal."
  php artisan view:clear; php artisan config:clear; php artisan route:clear
  chown -R www-data:www-data "$PANEL_DIR"/*
  php artisan up
  ok "Panel berhasil di-update."
  pause
}

# ------------------------- Tema (Blueprint) -----------------
install_blueprint() {
  [ -d "$PANEL_DIR" ] || die "Panel tidak ditemukan di $PANEL_DIR. Instal panel dulu ya."
  warn "Blueprint akan dipasang di atas panel. Pastikan tidak ada mod panel lain yang bentrok."
  confirm "Lanjut pasang Blueprint (framework tema)?" || return
  cd "$PANEL_DIR" || die "Tidak bisa masuk $PANEL_DIR."

  apt_update
  apt-get install -y ca-certificates curl git gnupg unzip wget zip || die "Instalasi deps gagal."

  # --- Node.js + yarn (dibutuhkan Blueprint) ---
  if ! command -v node >/dev/null 2>&1; then
    info "Menginstal Node.js ${NODE_VER}.x..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg || die "Gagal mengambil kunci NodeSource."
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VER}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    apt_update
    apt-get install -y nodejs || die "Instalasi Node.js gagal."
  fi
  command -v yarn >/dev/null 2>&1 || npm i -g yarn || die "Instalasi yarn gagal."
  info "Menyiapkan dependensi Node panel (yarn install)..."
  yarn install >/dev/null 2>&1 || warn "yarn install ada peringatan, lanjut saja."

  # --- Unduh rilis Blueprint terbaru dari GitHub ---
  info "Mengunduh Blueprint terbaru..."
  local BP_URL
  BP_URL="$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep browser_download_url | grep '\.zip"' | head -n1 | cut -d '"' -f 4)"
  [ -n "$BP_URL" ] || die "Tidak menemukan file rilis Blueprint di GitHub. Cek koneksi / coba lagi nanti."
  curl -sL -o /tmp/blueprint.zip "$BP_URL" || die "Gagal mengunduh Blueprint."
  unzip -oq /tmp/blueprint.zip -d "$PANEL_DIR" || die "Gagal mengekstrak Blueprint."
  rm -f /tmp/blueprint.zip

  # --- Konfigurasi .blueprintrc ---
  cat > "${PANEL_DIR}/.blueprintrc" <<'EOF'
WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";
EOF

  info "Menjalankan installer Blueprint..."
  chmod +x "${PANEL_DIR}/blueprint.sh"
  bash "${PANEL_DIR}/blueprint.sh" || die "Installer Blueprint gagal. Lihat pesan error di atas."
  ok "Blueprint terpasang. Ikon puzzle (ekstensi) sekarang ada di kanan atas panel."

  echo ""
  info "Terakhir: pasang ekstensi/tema lewat menu 'Pasang Ekstensi Blueprint' di script ini,"
  info "atau manual: cd ${PANEL_DIR} && blueprint -install <nama-ekstensi>"
  pause
}

install_extension() {
  [ -f "${PANEL_DIR}/blueprint.sh" ] || die "Blueprint belum terpasang. Pasang dulu lewat menu tema."
  ask "Nama/identifier ekstensi Blueprint (atau path file .blueprint)" ""; local EXT="$REPLY_JAWAB"
  [ -n "$EXT" ] || die "Nama ekstensi kosong."
  cd "$PANEL_DIR" || die "Tidak bisa masuk $PANEL_DIR."
  bash blueprint.sh -install "$EXT" || die "Instalasi ekstensi gagal. Pastikan nama/path ekstensinya benar."
  ok "Ekstensi '${EXT}' terpasang. Cek di panel (ikon puzzle kanan atas)."
  pause
}

# ------------------ Katalog tema gratis (GitHub) ------------------
# Tema open-source yang file .blueprint-nya diunduh langsung dari repo
# resmi pembuatnya saat runtime (installer ini tidak menyebarluaskan
# ulang file tema siapa pun).
bp_install_download() { # bp_install_download <url> <namafile.blueprint> <label>
  local URL="$1" FILE="$2" LABEL="$3"
  info "Mengunduh ${LABEL}..."
  curl -fsSL -o "${PANEL_DIR}/${FILE}" "$URL" || { warn "Gagal mengunduh ${LABEL}. Periksa koneksi internet."; return 1; }
  [ -s "${PANEL_DIR}/${FILE}" ] || { warn "File ${LABEL} kosong/tidak valid."; return 1; }
  info "Memasang ${LABEL}..."
  bash blueprint.sh -install "${FILE%.blueprint}" || { warn "Gagal memasang ${LABEL}. Lihat pesan Blueprint di atas."; return 1; }
  ok "${LABEL} terpasang. Aktifkan/atur lewat ikon puzzle di panel."
}

install_theme_catalog() {
  [ -f "${PANEL_DIR}/blueprint.sh" ] || die "Blueprint belum terpasang. Pasang dulu lewat menu 4 (Pasang Blueprint)."
  cd "$PANEL_DIR" || die "Tidak bisa masuk $PANEL_DIR."
  while true; do
    echo ""
    echo "  ===== KATALOG TEMA GRATIS (dari GitHub pembuatnya) ====="
    echo "  1) Darkenate      — tema gelap (blueprint-community)"
    echo "  2) Abyss Purple   — ungu (fernsehheft)"
    echo "  3) Emerald Abyss  — hijau zamrud (fernsehheft)"
    echo "  4) Crimson Abyss  — merah (fernsehheft)"
    echo "  5) Amber Abyss    — kuning amber (fernsehheft)"
    echo "  6) SKA Theme      — neon luar angkasa (sdgamer8263)"
    echo "  7) URL sendiri    — unduh file .blueprint dari URL kamu"
    echo "  0) Kembali"
    echo ""
    read -r -p "  Pilih tema: " TEMA
    case "$TEMA" in
      1) bp_install_download "https://github.com/blueprint-community/extension-darkenate/releases/latest/download/darkenate.blueprint" "darkenate.blueprint" "Darkenate" ;;
      2) bp_install_download "https://github.com/fernsehheft/Abyss-Purple/releases/latest/download/abysspurple.blueprint" "abysspurple.blueprint" "Abyss Purple" ;;
      3) bp_install_download "https://github.com/fernsehheft/Emerald-Abyss/releases/latest/download/emeraldabyss.blueprint" "emeraldabyss.blueprint" "Emerald Abyss" ;;
      4) bp_install_download "https://github.com/fernsehheft/Crimson-Abyss/releases/latest/download/crimsonabyss.blueprint" "crimsonabyss.blueprint" "Crimson Abyss" ;;
      5) bp_install_download "https://github.com/fernsehheft/Amber-Abyss/releases/latest/download/amberabyss.blueprint" "amberabyss.blueprint" "Amber Abyss" ;;
      6) bp_install_download "https://raw.githubusercontent.com/sdgamer8263-sketch/skathemes/main/skatheme.blueprint" "skatheme.blueprint" "SKA Theme" ;;
      7)
        ask "Tempel URL file .blueprint" ""; local CUSTOM_URL="$REPLY_JAWAB"
        if [ -z "$CUSTOM_URL" ]; then warn "URL kosong, batal."; continue; fi
        local CUSTOM_FILE; CUSTOM_FILE="$(basename "${CUSTOM_URL%%\?*}")"
        case "$CUSTOM_FILE" in *.blueprint) ;; *) CUSTOM_FILE="custom.blueprint" ;; esac
        bp_install_download "$CUSTOM_URL" "$CUSTOM_FILE" "Tema dari URL"
        ;;
      0) return ;;
      *) warn "Pilihan tidak dikenal." ;;
    esac
    pause
  done
}

# ------------------------- Uninstall ------------------------
uninstall_panel() {
  warn "Ini akan MENGHAPUS panel, database panel, dan file di $PANEL_DIR. Tidak bisa dibatalkan!"
  confirm "Yakin hapus panel?" || return
  ask "Ketik HAPUS untuk konfirmasi" ""; [ "$REPLY_JAWAB" = "HAPUS" ] || { warn "Dibatalkan."; return; }
  systemctl disable --now pteroq.service 2>/dev/null
  rm -f /etc/systemd/system/pteroq.service
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
  (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run") | crontab -
  mysql -e "DROP DATABASE IF EXISTS panel; DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null
  rm -rf "$PANEL_DIR"
  systemctl daemon-reload; systemctl restart nginx 2>/dev/null
  ok "Panel sudah dihapus."
  pause
}

uninstall_wings() {
  warn "Ini akan MENGHAPUS Wings dan config di $WINGS_DIR. Container game server TIDAK ikut dihapus."
  confirm "Yakin hapus Wings?" || return
  ask "Ketik HAPUS untuk konfirmasi" ""; [ "$REPLY_JAWAB" = "HAPUS" ] || { warn "Dibatalkan."; return; }
  systemctl disable --now wings 2>/dev/null
  rm -f /etc/systemd/system/wings.service
  rm -f /usr/local/bin/wings
  rm -rf "$WINGS_DIR"
  systemctl daemon-reload
  ok "Wings sudah dihapus."
  pause
}

# ------------------------- Menu utama -----------------------
banner() {
  clear
  echo -e "${GREEN}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        HABIBI PTERODACTYL INSTALLER          ║"
  echo "  ║   Panel • Wings • Tema — semua dalam 1 menu  ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

menu() {
  while true; do
    banner
    echo "  1) Instal Panel"
    echo "  2) Instal Wings"
    echo "  3) Instal Panel + Wings (satu server)"
    echo "  4) Pasang Blueprint (framework tema)"
    echo "  5) Pasang Ekstensi/Tema Blueprint"
    echo "  6) Katalog Tema Gratis (GitHub)"
    echo "  7) Update Panel"
    echo "  8) Uninstall Panel"
    echo "  9) Uninstall Wings"
    echo "  0) Keluar"
    echo ""
    read -r -p "  Pilih menu: " PIL
    case "$PIL" in
      1) install_panel ;;
      2) install_wings ;;
      3) install_panel; install_wings ;;
      4) install_blueprint ;;
      5) install_extension ;;
      6) install_theme_catalog ;;
      7) update_panel ;;
      8) uninstall_panel ;;
      9) uninstall_wings ;;
      0) echo "Sampai jumpa!"; exit 0 ;;
      *) warn "Pilihan tidak dikenal."; sleep 1 ;;
    esac
  done
}

# Jika stdin bukan terminal (mis. dijalankan via bash <(curl ...)),
# arahkan input ke terminal asli supaya prompt tetap interaktif.
[ -t 0 ] || exec </dev/tty

require_root
menu
