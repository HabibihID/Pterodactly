# 🐦 Habibih Pterodactyl Installer

Installer Pterodactyl Panel & Wings serba-bisa dalam satu script — lengkap dengan framework tema **Blueprint**, update, dan uninstall. Menu berbahasa Indonesia, tinggal pilih nomor.

> Script ini **tidak berafiliasi** dengan Pterodactyl Project. Panel & Wings diunduh dari rilis resmi Pterodactyl di GitHub, tema dari rilis resmi Blueprint.

## ✨ Fitur

| Menu | Fungsi |
|---|---|
| 1 | Instal Panel (PHP 8.3, MariaDB, Redis, Nginx, SSL opsional, firewall opsional) |
| 2 | Instal Wings (Docker + Wings + systemd, tinggal paste `config.yml`) |
| 3 | Instal Panel + Wings di satu server |
| 4 | Pasang Blueprint (framework tema/extension) |
| 5 | Pasang Ekstensi/Tema Blueprint |
| 6 | Katalog Tema Gratis (unduh dari GitHub pembuatnya) |
| 7 | Update Panel ke versi terbaru |
| 8 | Uninstall Panel |
| 9 | Uninstall Wings |

Password admin panel & database dibuat otomatis dan ditampilkan di akhir instalasi.

## 💻 Sistem yang didukung

- Ubuntu 22.04 / 24.04
- Debian 11 / 12
- Login sebagai **root** di VPS (disarankan VPS fresh)

## 🚀 Cara pakai

```bash
bash <(curl -s https://raw.githubusercontent.com/HabibihID/Pterodactly/main/install.sh)
```

Atau unduh dulu baru jalankan:

```bash
curl -O https://raw.githubusercontent.com/HabibihID/Pterodactly/main/install.sh
bash install.sh
```

## 📝 Catatan

- Untuk SSL langsung jadi saat instal panel, arahkan dulu domain/subdomain ke IP VPS.
- Wings: ambil `config.yml` dari Panel → Admin → Nodes → pilih node → tab **Configuration**, lalu paste saat diminta script.
- Uninstall meminta konfirmasi ketik `HAPUS` agar tidak salah pencet.
