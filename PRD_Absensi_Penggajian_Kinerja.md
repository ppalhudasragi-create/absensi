# PRD — Aplikasi Web Absensi GPS, Penggajian & Target Kinerja Individual

> Dokumen ini adalah Product Requirements Document (PRD) sekaligus prompt siap pakai.
> Salin seluruh isi di bawah garis ini dan berikan ke AI coding assistant / developer.

| Item | Keterangan |
|---|---|
| Pemilik produk | Nanang (Admin / Owner) |
| Versi dokumen | 1.2 (semua keputusan owner final; jam kerja, periode gaji & batas libur per hari dapat diatur) |
| Tanggal | 29 September 2026 |
| Status | Draft untuk pengembangan |

---

## 0. Peran & Instruksi untuk AI / Developer

Kamu adalah **senior full-stack engineer Laravel** yang berpengalaman dengan **PHP 8.2+, Laravel 11, MySQL 8 / MariaDB 10.6+, Blade + Tailwind CSS**, dan deployment di **VPS aaPanel (Nginx + PHP-FPM)**.
Buatkan aplikasi lengkap sesuai PRD berikut. Tulis kode yang **production-ready, aman, dan terdokumentasi**, dan kerjakan **bertahap per milestone** (lihat Bagian 14).
Semua teks antarmuka dalam **Bahasa Indonesia**, format uang **Rupiah (Rp 1.234.567)**, zona waktu **Asia/Jakarta (WIB)**.

---

## 1. Ringkasan Produk

**Nama kerja:** AbsenKu — Absensi, Gaji & Kinerja
**Tujuan:** Satu aplikasi web ringan untuk usaha kecil (±10 karyawan) yang:
1. Mencatat kehadiran karyawan secara **akurat berbasis lokasi GPS** (harus berada di kantor).
2. Menghitung **gaji bulanan otomatis** dari gaji pokok + tunjangan, dipotong ketidakhadiran, ditambah lembur dan bonus target.
3. Memantau **target kinerja individual** tiap karyawan (mis. jumlah pelanggan baru, nilai penjualan).
4. Mengatur **jadwal libur mandiri**: kantor buka setiap hari, tiap karyawan memilih sendiri **4 hari libur per bulan**.
5. Membagikan **tugas kerja** (mis. pemasangan/servis ke pelanggan) ke **grup WhatsApp** dengan format pesan yang rapi, dan mencatat penyelesaiannya.
6. Menghasilkan **slip gaji PDF** dan **rekap Excel/CSV** dengan sekali klik.

**Masalah yang diselesaikan:**
- Absensi manual (buku/WA) mudah dimanipulasi dan sulit direkap.
- Perhitungan gaji manual memakan waktu dan rawan salah hitung.
- Target kerja karyawan tidak terdokumentasi dan tidak terhubung ke insentif.

**Di luar lingkup (versi 1):** BPJS, PPh 21, kasbon/pinjaman, multi-cabang, aplikasi mobile native, integrasi bank/transfer otomatis.

---

## 2. Pengguna & Peran

| Peran | Jumlah | Kebutuhan utama |
|---|---|---|
| **Admin** (Nanang) | 1 (bisa lebih) | Kelola karyawan, lokasi kantor, jam kerja, hari libur, target, hitung & bayar gaji, lihat laporan |
| **Karyawan / Teknisi** | ±10 | Clock-in/out dari HP, pilih 4 hari libur/bulan, kerjakan & laporkan tugas, update progres target, lihat & unduh slip gaji |

**Asumsi perangkat:** karyawan memakai **smartphone** (Chrome/Safari) dengan GPS aktif. Tampilan harus **mobile-first**. Admin memakai laptop maupun HP.

---

## 3. Tech Stack & Arsitektur

| Lapisan | Pilihan | Alasan |
|---|---|---|
| Backend | **Laravel 11 (PHP 8.2+)** | Auth, migration, scheduler, validation siap pakai; mudah dirawat satu orang |
| Database | **MySQL 8 / MariaDB 10.6+** | Didukung aaPanel |
| Frontend | **Blade + Tailwind CSS + Alpine.js** | Tanpa build SPA yang rumit; cukup Vite |
| Auth | Laravel Breeze (email + password, bcrypt) | Sederhana & aman |
| PDF | `barryvdh/laravel-dompdf` | Slip gaji |
| Excel | `maatwebsite/excel` | Export rekap gaji & absensi |
| Scheduler | Laravel Scheduler via cron aaPanel (`* * * * * php artisan schedule:run`) | Tandai alfa otomatis, auto clock-out |
| Server | VPS + aaPanel, Nginx, PHP-FPM, **HTTPS wajib** (Let's Encrypt) | Geolocation API browser **hanya berjalan di HTTPS** |

> Alternatif (opsional): Express.js + PostgreSQL. Namun PRD ini ditulis untuk Laravel.

---

## 4. Fitur 1 — Manajemen User & Role

### 4.1 Autentikasi
- Login dengan **email + password** (hash bcrypt). Tidak ada registrasi publik — **akun karyawan dibuat oleh admin**.
- Lupa password via email (opsional; fallback: admin reset password).
- Rate limit login: 5 percobaan / menit per IP.
- Session timeout 8 jam; opsi "ingat saya".

### 4.2 Data Karyawan (CRUD oleh Admin)
| Field | Tipe | Wajib | Catatan |
|---|---|---|---|
| Nama lengkap | string | ✔ | |
| Email | string unik | ✔ | Untuk login |
| No. HP | string | ✔ | |
| Posisi/Jabatan | string | ✔ | |
| Tanggal mulai kerja | date | ✔ | Gaji bulan pertama prorata dari tanggal ini |
| Jatah libur per bulan | integer | ✔ | Default **4 hari**, bisa diubah per karyawan |
| Gaji pokok | decimal | ✔ | mis. 3.000.000 |
| Tunjangan tetap | decimal | ✔ | mis. 500.000 |
| Nilai potongan per hari | decimal | ✔ | Default otomatis = gaji pokok ÷ 26 (hari kerja standar), bisa diubah manual |
| Tarif lembur per jam | decimal | – | Default otomatis (lihat 7.3), bisa diubah manual |
| Status | enum aktif/nonaktif | ✔ | Karyawan nonaktif tidak bisa login & tidak dihitung gajinya |

- Karyawan **tidak dihapus permanen** (soft delete) agar riwayat absensi & gaji tetap ada.
- Karyawan hanya bisa melihat **data dirinya sendiri** dan mengganti password.

---

## 5. Fitur 2 — Absensi Berbasis GPS

### 5.1 Pengaturan (Admin)
- **Lokasi kantor:** latitude, longitude, nama lokasi. Tombol **"Ambil Lokasi Saya"** mengisi koordinat dari browser admin saat berada di kantor; tampilkan pratinjau peta (Leaflet + OpenStreetMap).
- **Radius valid:** default **100 meter** (bisa diubah, min 20 m, maks 1000 m).
- **Batas akurasi GPS:** default 100 m — jika `accuracy` dari browser lebih besar dari ini, minta karyawan mencoba lagi di area terbuka.
- **Jam kerja standar (diatur di Pengaturan):** jam masuk (default 08:00), jam pulang (default 17:00), toleransi terlambat (default 15 menit). Perubahan berlaku mulai hari berikutnya; absensi yang sudah tercatat tidak dihitung ulang.
- **Jendela absensi:** clock-in diizinkan mulai 07:00, clock-out paling lambat 23:59 (bisa diatur).
- **Hari kerja:** **setiap hari (Senin–Minggu)**. Tidak ada hari libur tetap mingguan — libur diatur lewat **jatah libur pribadi** (Bagian 5.5).
- **Libur bersama (opsional):** kalender tanggal di mana semua karyawan libur (mis. Idul Fitri). Tidak mengurangi jatah libur pribadi.

### 5.2 Alur Clock-In
1. Karyawan membuka dashboard → tombol **"Clock-In"**.
2. Browser meminta izin & mengambil koordinat via **Geolocation API** (`enableHighAccuracy: true`, timeout 15 detik).
3. Koordinat dikirim ke server; **validasi dilakukan di server** (bukan hanya di browser):
   - Hitung jarak ke kantor dengan **rumus Haversine**.
   - Jarak ≤ radius **dan** akurasi ≤ batas akurasi → valid.
4. **Valid** → simpan absensi: tanggal, jam masuk, lat/lng, akurasi, jarak, IP, user-agent, status `hadir` atau `terlambat` (jika lewat jam masuk + toleransi).
5. **Tidak valid** → tampilkan pesan: *"Anda berada ±{jarak} m dari kantor. Absensi hanya bisa dilakukan dalam radius {radius} m."* Percobaan gagal tetap dicatat di log.
6. Jika izin lokasi ditolak / GPS mati → tampilkan panduan mengaktifkan lokasi.

### 5.3 Alur Clock-Out
1. Tombol **"Clock-Out"** muncul setelah clock-in. Clock-out **juga wajib di lokasi kantor** (validasi GPS sama).
2. Simpan jam pulang + koordinat.
3. Jika jam pulang > jam pulang standar → hitung **menit lembur** (dibulatkan ke bawah per 30 menit; lembur < 30 menit tidak dihitung).
4. Lembur **wajib disetujui admin** sebelum masuk perhitungan gaji (status lembur: `menunggu` → `disetujui`/`ditolak`). Admin bisa mengubah jumlah jam yang disetujui.

### 5.4 Aturan Absensi
- Clock-in **hanya 1x per hari**; clock-out hanya 1x setelah clock-in.
- Clock-in di luar jendela absensi → **ditolak**, karyawan bisa mengajukan **permintaan absensi manual** yang harus disetujui admin.
- **Hari libur pribadi & libur bersama:** tombol absensi disembunyikan; tidak dihitung alfa. Jika tetap masuk di hari liburnya, karyawan cukup membatalkan libur tersebut (jatah kembali) lalu clock-in seperti biasa.
- **Lupa clock-out:** scheduler pukul 23:59 menandai `lupa_clock_out`; jam pulang dianggap = jam pulang standar, **tanpa lembur**, admin bisa koreksi.
- **Alfa otomatis:** scheduler pukul 23:59 memberi status `alfa` pada karyawan aktif yang tidak clock-in, **bukan** hari libur pribadinya/libur bersama, dan tidak punya izin/sakit yang disetujui.

### 5.5 Jadwal Libur Pribadi (4x per Bulan)
Kantor beroperasi setiap hari; tiap karyawan/teknisi **memilih sendiri hari liburnya**.
- Halaman **"Jadwal Libur Saya"** berupa kalender bulan. Karyawan tap tanggal untuk menandai libur, maksimal sesuai **jatah libur** (default **4 hari/bulan**). Sisa jatah tampil jelas: *"Sisa libur bulan ini: 2 dari 4"*.
- Libur bisa dipilih untuk bulan berjalan dan bulan depan, paling lambat **H-1** (tidak bisa memilih/membatalkan hari ini atau tanggal yang sudah lewat).
- Tidak perlu persetujuan admin (supaya simpel), tetapi admin bisa **melihat, mengubah, atau membatalkan** libur siapa pun.
- **Maksimal karyawan libur di hari yang sama** diatur di Pengaturan (default 0 = tanpa batas, mis. isi 2 = maks 2 orang/hari). Jika penuh, tanggal tampil abu-abu "Kuota hari ini penuh". Libur yang sudah dipilih sebelum batas diubah tetap berlaku.
- Jatah libur dihitung **per periode gaji** (lihat 7.1). Jatah yang tidak dipakai **hangus** di akhir periode (tidak diakumulasi, tidak diuangkan).
- Tidak masuk di luar hari libur pribadi tanpa izin/sakit yang disetujui = **alfa (dipotong)**.
- Admin melihat **kalender tim**: siapa libur di tanggal berapa.

### 5.6 Izin & Sakit
- Karyawan mengajukan **izin / sakit** (tanggal mulai–selesai, alasan, lampiran foto opsional).
- Admin **menyetujui/menolak**. Hari yang disetujui berstatus `izin`/`sakit` dan **tidak dipotong gaji**. Pengajuan yang ditolak → hari itu dihitung alfa.
- Tidak ada cuti tahunan terpisah (sudah tercakup jatah libur 4x/bulan).

### 5.7 Koreksi & Log
- Admin dapat **mengoreksi** absensi (ubah jam/status) dengan **alasan wajib**; semua perubahan masuk **audit log** (siapa, kapan, nilai lama → baru).
- Admin dapat melihat **peta titik GPS** tiap absensi untuk verifikasi.

### 5.8 Anti-Kecurangan (dasar)
- Validasi jarak & akurasi dilakukan di server.
- Tandai (flag) absensi mencurigakan: akurasi 0/sangat sempurna berulang, koordinat identik persis dengan hari sebelumnya, atau perangkat/user-agent berbeda dari biasanya. Flag hanya **peringatan untuk admin**, tidak memblokir.
- Absensi **cukup GPS**, tanpa foto selfie (keputusan owner). Catatan: fake GPS tidak bisa dicegah 100% dari browser — flag di atas membantu admin memeriksa.

---

## 6. Fitur 3 — Target Kinerja Individual

### 6.1 Pengaturan Target (Admin)
- Admin membuat target **per karyawan per bulan**:
  | Field | Contoh |
  |---|---|
  | Nama target | "Temukan pelanggan baru" |
  | Tipe | `quantity` (jumlah) / `amount` (Rupiah) |
  | Nilai target | 10 (pelanggan) / 50.000.000 (Rp) |
  | Periode | Oktober 2026 |
  | Bonus jika tercapai | Nominal tetap (Rp 1.000.000) **atau** persentase dari gaji pokok (5%) |
- Satu karyawan boleh punya **lebih dari satu target** per bulan. Aturan bonus: **setiap target yang tercapai mendapat bonusnya masing-masing** (tidak harus semua tercapai).
- Fitur **salin target bulan lalu** ke bulan ini untuk semua/sebagian karyawan.
- Target bisa dikunci (`locked`) setelah periode gaji difinalisasi.

### 6.2 Update Progres (Karyawan)
- Karyawan menambah **entri progres**: tanggal, nilai (mis. +2 pelanggan), catatan singkat (mis. nama pelanggan/toko), lampiran opsional.
- Progres total = **jumlah semua entri** pada periode tersebut.
- Entri bisa diedit/dihapus oleh karyawan selama periode belum dikunci.
- Admin dapat **memverifikasi / menolak** entri progres; hanya entri yang tidak ditolak yang dihitung. (Opsi pengaturan: "progres wajib diverifikasi admin" ON/OFF.)

### 6.3 Tampilan
- **Dashboard karyawan:** progress bar `X / Y` + persentase, status **Tercapai** (hijau) / **Belum** (abu/kuning), sisa hari di bulan berjalan.
- **Dashboard admin:** tabel semua karyawan × target bulan ini (progres, %, status), sortir berdasarkan pencapaian; badge 🏆 untuk yang tercapai.
- Riwayat pencapaian target per karyawan (grafik sederhana 6 bulan terakhir).

---

## 7. Fitur 4 — Penggajian Bulanan

### 7.1 Periode
- **Tanggal mulai periode diatur di Pengaturan** (1–28, default **1**):
  - `1` → bulan kalender (1–31 Oktober).
  - `26` → 26 September s.d. 25 Oktober, diberi label **"Oktober 2026"** (label = bulan tanggal akhir periode).
- Periode ini dipakai konsisten untuk **gaji, jatah libur 4x, dan target**. Setiap kata "bulan" di dokumen ini berarti periode gaji.
- Perubahan tanggal mulai hanya berlaku untuk periode yang **belum dihitung**; periode yang sudah `final` tidak berubah. Admin mendapat peringatan jika ada periode yang akan tumpang tindih/terlewat.
- **Hari kerja efektif** = jumlah hari dalam periode − jatah libur pribadi (4) − libur bersama. Contoh: periode 31 hari → 27 hari kerja.

### 7.2 Rumus Perhitungan

```
Gaji Dasar          = Gaji Pokok + Tunjangan Tetap

Hari Tidak Hadir    = jumlah hari berstatus alfa
                      (izin/sakit disetujui, libur pribadi, libur bersama TIDAK dipotong)
Potongan Kehadiran  = Hari Tidak Hadir × Nilai Potongan per Hari

Gaji per Jam        = Gaji Pokok ÷ (Hari Kerja Standar × Jam Kerja per Hari)
                      (default: Gaji Pokok ÷ (26 × 8) = Gaji Pokok ÷ 208)
Tarif Lembur/Jam    = Gaji per Jam × Pengali Lembur   (default pengali 1,5; bisa diubah admin)
Total Jam Lembur    = Σ jam lembur yang DISETUJUI dalam periode
Gaji Lembur         = Total Jam Lembur × Tarif Lembur/Jam

Bonus Target        = Σ bonus dari setiap target yang tercapai
                      (nominal tetap, atau % × Gaji Pokok)

Penyesuaian Lain    = nilai manual admin (+/−) dengan keterangan (opsional)

TOTAL GAJI          = Gaji Dasar − Potongan Kehadiran + Gaji Lembur + Bonus Target ± Penyesuaian Lain
```

**Aturan tambahan:**
- Potongan kehadiran **tidak boleh melebihi Gaji Dasar** (total minimum Rp 0).
- **Karyawan baru/keluar di tengah bulan:** hari sebelum tanggal mulai / setelah tanggal keluar **tidak dihitung alfa**, dan gaji dasar diprorata: `Gaji Dasar × (hari kerja aktif ÷ hari kerja efektif)`.
- Keterlambatan **tidak dipotong** — hanya dicatat dan ditampilkan di rekap.
- Semua nilai dibulatkan ke **Rupiah terdekat** di hasil akhir.

### 7.3 Contoh Perhitungan
Gaji pokok Rp 3.000.000, tunjangan Rp 500.000, nilai per hari Rp 115.385 (3.000.000 ÷ 26), alfa 1 hari, izin 1 hari (tidak dipotong), 4 hari libur pribadi, lembur 4 jam disetujui, 1 target tercapai (bonus Rp 1.000.000):

| Komponen | Nilai |
|---|---|
| Gaji dasar | Rp 3.500.000 |
| Potongan alfa (1 × 115.385) | − Rp 115.385 |
| Lembur (4 jam × 14.423 × 1,5 = 4 × 21.635) | + Rp 86.538 |
| Bonus target | + Rp 1.000.000 |
| **Total** | **Rp 4.471.154** |

### 7.4 Alur Proses Gaji (Admin)
1. Pilih bulan → klik **"Hitung Gaji"** → sistem membuat **draft** untuk semua karyawan aktif.
2. Admin meninjau rincian per karyawan, menambah penyesuaian bila perlu, bisa **hitung ulang** selama masih draft.
3. Klik **"Finalisasi"** → nilai dikunci (snapshot semua komponen disimpan, tidak berubah walau data master diubah), absensi & target periode itu ikut terkunci.
4. Tandai **"Sudah Dibayar"** (tanggal bayar, metode: tunai/transfer, catatan).
5. Pembukaan kunci (unlock) hanya oleh admin dengan alasan, tercatat di audit log.

Status gaji: `draft` → `final` → `dibayar`.

### 7.5 Output
- **Rincian gaji** per karyawan di layar (semua komponen + jumlah hari hadir/terlambat/alfa/izin/sakit/libur + jam lembur + jumlah tugas selesai).
- **Slip gaji PDF** per karyawan per bulan: logo & nama usaha, periode, identitas karyawan, rincian pendapatan & potongan, total, status bayar. Karyawan bisa mengunduh slip miliknya (hanya yang sudah `final`).
- **Export Excel/CSV** rekap gaji satu bulan seluruh karyawan.
- **Export Excel/CSV** rekap absensi (filter karyawan & rentang tanggal).

---

## 8. Fitur 5 — Tugas Kerja & Share ke Grup WhatsApp

Tujuan: admin membuat tugas (mis. pasang/servis ke pelanggan), lalu **sekali klik membagikannya ke grup WhatsApp** dengan format rapi. Teknisi melaporkan selesai dan bisa membagikan laporannya ke grup juga. **Tanpa WhatsApp API berbayar** — cukup memakai link `wa.me`.

### 8.1 Membuat Tugas (Admin)
| Field | Wajib | Contoh |
|---|---|---|
| Judul pekerjaan | ✔ | Pasang WiFi baru |
| Teknisi ditugaskan | ✔ | Budi, Andi (boleh lebih dari 1) |
| Jadwal (tanggal & jam) | ✔ | Rab, 1 Okt 2026 — 09:00 |
| Prioritas | ✔ | Normal / **URGENT** |
| Nama pelanggan | – | Pak Slamet |
| No. HP pelanggan | – | 0812-3456-7890 |
| Alamat | – | Jl. Melati No. 5, Sidoarjo |
| Link lokasi (Google Maps) | – | tempel link, atau tombol "Ambil Lokasi Saya" |
| Detail / catatan | – | Pasang router + tarik kabel ±30 m |

- Nomor tugas otomatis: `TGS-YYMMDD-NNN` (mis. `TGS-261001-001`).
- Status: `baru` → `dikerjakan` → `selesai` (atau `batal` oleh admin).

### 8.2 Tombol Share
Di halaman detail tugas ada 2 tombol:
1. **"Bagikan ke WhatsApp"** → membuka `https://wa.me/?text=<pesan ter-encode>`; di WhatsApp user tinggal memilih **grup tujuan** lalu kirim.
2. **"Salin Teks"** → menyalin pesan ke clipboard (untuk Telegram / grup lain).

Pesan memakai format WhatsApp (`*tebal*`, `_miring_`) dan emoji agar mudah dibaca di HP.

**Format pesan TUGAS BARU:**
```
📋 *TUGAS BARU* — TGS-261001-001
━━━━━━━━━━━━━━━━━━
🔧 *Pekerjaan:* Pasang WiFi baru
🔴 *Prioritas:* URGENT
👷 *Teknisi:* Budi, Andi
📅 *Jadwal:* Rab, 1 Okt 2026 — 09:00 WIB

👤 *Pelanggan:* Pak Slamet
📞 *HP:* 0812-3456-7890
📍 *Alamat:* Jl. Melati No. 5, Sidoarjo
🗺️ *Maps:* https://maps.google.com/?q=-7.4478,112.7183

📝 *Detail:*
Pasang router + tarik kabel ±30 m.
━━━━━━━━━━━━━━━━━━
Mohon balas *SIAP* jika sudah diterima 🙏
```
(Baris yang datanya kosong otomatis tidak ditampilkan. Prioritas Normal memakai ikon 🟢.)

**Format pesan LAPORAN SELESAI:**
```
✅ *TUGAS SELESAI* — TGS-261001-001
━━━━━━━━━━━━━━━━━━
🔧 *Pekerjaan:* Pasang WiFi baru
👤 *Pelanggan:* Pak Slamet
👷 *Dikerjakan:* Budi, Andi
🕐 *Selesai:* Rab, 1 Okt 2026 — 11:40 WIB

📝 *Hasil:*
Router terpasang, sinyal normal, pelanggan sudah dicoba.
━━━━━━━━━━━━━━━━━━
```

**Format REKAP TUGAS HARI INI** (tombol di daftar tugas admin):
```
📊 *REKAP TUGAS* — Rab, 1 Okt 2026
━━━━━━━━━━━━━━━━━━
1. ✅ Pasang WiFi — Pak Slamet (Budi)
2. 🔄 Servis router — Bu Ani (Andi)
3. ⏳ Survey lokasi — CV Maju (Budi)
━━━━━━━━━━━━━━━━━━
Selesai 1 · Dikerjakan 1 · Belum 1
```
Keterangan ikon status: ⏳ baru · 🔄 dikerjakan · ✅ selesai · ❌ batal.

### 8.3 Alur Teknisi
1. Teknisi melihat **"Tugas Saya"** (tugas hari ini di atas, urut jadwal) di dashboard.
2. Tap **"Mulai Kerjakan"** → status `dikerjakan` (jam mulai tercatat).
3. Tap **"Selesai"** → isi **catatan hasil** (wajib) + foto opsional (maks 3, dikompres) → status `selesai`.
4. Setelah selesai, muncul tombol **"Bagikan Laporan ke WhatsApp"** dengan format laporan di atas.
5. Tombol **"Buka Maps"** dan **"Telepon Pelanggan"** (`tel:`) di detail tugas.

### 8.4 Aturan Sederhana
- Tugas **tidak memengaruhi gaji** (hanya dicatat & dihitung jumlahnya di rekap).
- Admin bisa edit/batalkan tugas; teknisi hanya bisa mengubah status tugas miliknya.
- Filter daftar tugas: tanggal, teknisi, status.
- Nama usaha di header pesan bisa diatur di Pengaturan (opsional).

---

## 9. Fitur 6 — Dashboard

### 9.1 Dashboard Admin
- **Kartu ringkasan:** jumlah karyawan aktif; hadir hari ini / terlambat / belum absen / izin; total gaji bulan ini + status (draft/final/dibayar); jumlah permintaan menunggu persetujuan (izin/sakit, lembur, absensi manual); **siapa yang libur hari ini**; tugas hari ini (baru/dikerjakan/selesai).
- **Daftar "Belum Clock-In Hari Ini"** (real-time saat dibuka).
- **Tabel absensi bulan berjalan:** filter karyawan & tanggal, badge status, ikon flag mencurigakan, klik untuk lihat peta.
- **Tabel gaji bulan berjalan:** status per karyawan (belum dihitung / draft / final / dibayar).
- **Widget target:** progres target semua karyawan bulan ini.

### 9.2 Dashboard Karyawan
- **Info jam kantor** (jam masuk, jam pulang, toleransi) + **lokasi kantor di peta** (Leaflet/OpenStreetMap) dengan lingkaran radius dan titik posisi karyawan saat ini.
- Tombol besar **Clock-In / Clock-Out** + status hari ini + jarak ke kantor.
- **Riwayat absensi bulan ini:** tabel tanggal, status, jam masuk, jam keluar (plus tampilan kalender berwarna per status).
- Ringkasan bulan ini: hadir, terlambat, alfa, izin/sakit, libur terpakai, jam lembur.
- **Target kinerja bulan ini** + progress bar + **form update progres langsung di dashboard** (nilai + catatan).
- **Gaji per periode:** daftar slip per bulan, lihat rincian komponen, dan **unduh PDF** (hanya yang sudah `final`).
- **Tugas Saya** hari ini + tombol Mulai/Selesai/Bagikan.
- **Sisa jatah libur** bulan ini + tombol ke kalender Jadwal Libur.
- **Estimasi gaji berjalan** (default **ON**, bisa dimatikan di Pengaturan): dihitung langsung dengan rumus 7.2 dari data periode berjalan sampai hari ini, lembur hanya yang sudah disetujui. Diberi label jelas *"Perkiraan — belum final, bisa berubah"* dan tidak bisa diunduh sebagai slip.

---

## 10. Notifikasi (Fase 2, opsional)
- Pengingat clock-in via **WhatsApp gateway / email** pukul 07:45 bagi yang belum absen.
- Notifikasi admin saat ada pengajuan izin/lembur/absensi manual.
- Pengiriman otomatis ke grup via WhatsApp gateway (menggantikan tombol share manual).
- Notifikasi karyawan saat slip gaji sudah final.

---

## 11. Skema Database (Ringkas)

```
users               id, name, email, phone, password, role(admin|employee), position,
                    join_date, end_date, day_off_quota, status, remember_token, timestamps, deleted_at
salary_settings     id, user_id, base_salary, allowance, daily_deduction,
                    overtime_rate_per_hour (nullable = pakai default), effective_from, timestamps
settings            key, value           -- office_lat, office_lng, radius_m, max_accuracy_m,
                                         -- work_start, work_end, late_tolerance_min,
                                         -- overtime_multiplier, standard_work_days (26),
                                         -- standard_hours_per_day, default_day_off_quota (4),
                                         -- max_off_per_day (0 = tanpa batas),
                                         -- payroll_start_day (1–28), show_salary_estimate,
                                         -- company_name, ...
holidays            id, date (unique), description          -- libur bersama
day_offs            id, user_id, date, created_by, timestamps  -- libur pribadi
                    UNIQUE(user_id, date)
attendances         id, user_id, date, clock_in_at, clock_in_lat, clock_in_lng,
                    clock_in_accuracy, clock_in_distance, clock_out_at, clock_out_lat,
                    clock_out_lng, clock_out_accuracy, clock_out_distance,
                    status(hadir|terlambat|alfa|izin|sakit|libur|lupa_clock_out),
                    overtime_minutes, overtime_status(none|pending|approved|rejected),
                    is_flagged, flag_reason, ip, user_agent, note, timestamps
                    UNIQUE(user_id, date)
attendance_attempts id, user_id, type(in|out), lat, lng, accuracy, distance, success, reason, created_at
leave_requests      id, user_id, type(izin|sakit|manual_attendance), start_date, end_date,
                    reason, attachment, status(pending|approved|rejected), reviewed_by, reviewed_at
targets             id, user_id, period (YYYY-MM), name, type(quantity|amount), target_value,
                    bonus_type(fixed|percent), bonus_value, locked, timestamps
target_progress     id, target_id, date, value, note, attachment, status(pending|approved|rejected), timestamps
payrolls            id, user_id, period (YYYY-MM), work_days, present_days, late_days,
                    absent_days, leave_days, overtime_hours, base_salary, allowance,
                    attendance_deduction, overtime_pay, target_bonus, adjustment,
                    adjustment_note, total, status(draft|final|paid), paid_at,
                    payment_method, snapshot_json, timestamps
                    UNIQUE(user_id, period)
tasks               id, code (unique), title, priority(normal|urgent), scheduled_at,
                    customer_name, customer_phone, address, maps_url, description,
                    status(baru|dikerjakan|selesai|batal), started_at, finished_at,
                    result_note, created_by, timestamps
task_user           task_id, user_id                       -- teknisi yang ditugaskan
task_photos         id, task_id, path, timestamps
audit_logs          id, user_id, action, auditable_type, auditable_id, old_values, new_values,
                    reason, ip, created_at
```

---

## 12. Kebutuhan Non-Fungsional

| Aspek | Kebutuhan |
|---|---|
| Keamanan | HTTPS wajib; CSRF; validasi & otorisasi server-side (Policy/Gate); karyawan tidak bisa mengakses data karyawan lain (uji IDOR); password bcrypt; rate limit login & endpoint absensi |
| Performa | Halaman utama < 2 detik di jaringan 4G; clock-in end-to-end < 5 detik |
| Ketersediaan | Backup database otomatis harian (fitur backup aaPanel), simpan 30 hari |
| Kompatibilitas | Chrome Android & Safari iOS versi 2 tahun terakhir; responsif 360 px ke atas |
| Zona waktu | Semua waktu disimpan & ditampilkan dalam Asia/Jakarta |
| Akurasi uang | Gunakan `DECIMAL(15,2)` di DB; perhitungan tanpa float |
| Audit | Semua perubahan gaji, koreksi absensi, dan pengaturan tercatat di audit log |
| Maintainability | Logika perhitungan gaji di satu service class (`PayrollCalculator`) dengan unit test |

---

## 13. Struktur Halaman (Routes)

**Karyawan:** `/login`, `/dashboard`, `/absensi` (riwayat), `/libur` (jadwal libur saya), `/tugas`, `/pengajuan` (izin/sakit/absensi manual), `/target`, `/gaji` (slip), `/profil`
**Admin:** `/admin/dashboard`, `/admin/karyawan`, `/admin/absensi`, `/admin/pengajuan`, `/admin/lembur`, `/admin/target`, `/admin/tugas`, `/admin/gaji/{periode}`, `/admin/libur` (kalender tim + libur bersama), `/admin/pengaturan` (lokasi & radius, jam kerja & toleransi, periode gaji, batas libur per hari, estimasi gaji ON/OFF, gaji default), `/admin/audit-log`

---

## 14. Milestone Pengerjaan

| # | Milestone | Isi | Estimasi |
|---|---|---|---|
| M1 | Fondasi | Setup Laravel, auth, role, CRUD karyawan, pengaturan, layout mobile-first | 3–4 hari |
| M2 | Absensi GPS | Pengaturan lokasi + peta, clock-in/out, validasi Haversine, log percobaan, riwayat, hari libur | 4–5 hari |
| M3 | Libur, Izin & Koreksi | Jadwal libur pribadi 4x/bulan + kalender tim, pengajuan izin/sakit/manual, persetujuan lembur, koreksi admin, scheduler alfa & lupa clock-out, audit log | 3 hari |
| M4 | Target Kinerja | CRUD target, progres, verifikasi, dashboard progres, salin target | 3 hari |
| M4b | Tugas & Share WA | CRUD tugas, alur teknisi, format pesan + tombol wa.me / salin, rekap harian | 2–3 hari |
| M5 | Penggajian | `PayrollCalculator` + unit test, draft/final/dibayar, slip PDF, export Excel/CSV | 4–5 hari |
| M6 | Dashboard & Rilis | Dashboard admin & karyawan, hardening keamanan, deploy aaPanel + HTTPS + cron + backup, UAT | 3 hari |

---

## 15. Kriteria Penerimaan (Acceptance Criteria)

**Absensi**
- [ ] Clock-in di dalam radius dengan akurasi baik → tersimpan, status `hadir` / `terlambat` sesuai jam.
- [ ] Clock-in di luar radius → ditolak dengan pesan berisi jarak & radius; percobaan tercatat.
- [ ] Clock-in kedua di hari yang sama → ditolak.
- [ ] Mengirim koordinat palsu langsung ke API (tanpa UI) tetap divalidasi server.
- [ ] Hari libur pribadi / libur bersama → tidak ada tombol absensi & tidak dihitung alfa.
- [ ] Karyawan tidak bisa memilih hari libur ke-5 dalam satu periode (jatah 4), tidak bisa memilih hari ini/tanggal lewat.
- [ ] Batas libur per hari = 2 dan sudah 2 orang libur → orang ke-3 tidak bisa memilih tanggal itu.
- [ ] Mengubah jam masuk di Pengaturan mengubah penentuan `terlambat` mulai hari berikutnya.
- [ ] Izin/sakit yang disetujui dan keterlambatan **tidak** memotong gaji.
- [ ] Karyawan tanpa absensi, bukan hari liburnya, & tanpa izin → otomatis `alfa` setelah scheduler berjalan.
- [ ] Clock-out setelah jam pulang ≥ 30 menit → lembur `pending`, masuk gaji hanya setelah disetujui.

**Target**
- [ ] Admin membuat target; karyawan melihat progress bar dan menambah progres.
- [ ] Progres mencapai/lebih dari target → status **Tercapai** dan bonus masuk perhitungan gaji.
- [ ] Karyawan dengan 3 target dan 2 tercapai → mendapat 2 bonus.

**Tugas**
- [ ] Tombol "Bagikan ke WhatsApp" membuka WhatsApp dengan pesan sesuai format Bagian 8.2 (baris kosong disembunyikan).
- [ ] Teknisi hanya melihat & mengubah status tugas miliknya; laporan selesai wajib berisi catatan hasil.
- [ ] Rekap tugas hari ini bisa disalin/dibagikan dengan jumlah status yang benar.

**Gaji**
- [ ] Tanggal mulai periode = 26 → periode "Oktober 2026" mencakup 26 Sep–25 Okt untuk gaji, jatah libur & target.
- [ ] Karyawan melihat estimasi gaji berjalan berlabel "Perkiraan"; saat dimatikan admin, estimasi tidak tampil.
- [ ] Contoh pada Bagian 7.3 menghasilkan total **Rp 4.471.154**.
- [ ] Karyawan yang mulai tanggal 15 tidak dihitung alfa sebelum tanggal 15 dan gajinya diprorata.
- [ ] Setelah finalisasi, mengubah gaji pokok karyawan **tidak** mengubah slip bulan yang sudah final.
- [ ] Slip PDF bisa diunduh admin (semua) dan karyawan (miliknya saja, yang sudah final).
- [ ] Export Excel/CSV berisi seluruh karyawan dan semua komponen gaji.

**Keamanan**
- [ ] Karyawan tidak bisa membuka halaman admin maupun data/slip karyawan lain (403).
- [ ] Setiap koreksi absensi & perubahan gaji tercatat di audit log dengan alasan.

---

## 16. Keputusan Owner (sudah dikonfirmasi)
| # | Topik | Keputusan |
|---|---|---|
| 1 | Hari kerja | Kantor buka **setiap hari**; tiap karyawan/teknisi memilih sendiri **4 hari libur per bulan** |
| 2 | Potongan izin & terlambat | **Tidak dipotong** (yang dipotong hanya alfa) |
| 3 | Lembur | **Wajib persetujuan admin** |
| 4 | Bonus target | **Setiap target yang tercapai** mendapat bonus |
| 5 | Selfie | **Tidak perlu**, cukup GPS |
| 6 | Tugas | Ditambahkan fitur **Tugas + share ke grup WhatsApp** dengan format standar (Bagian 8) |
| 7 | Jam kerja & toleransi terlambat | **Diatur di Pengaturan** (default 08:00–17:00, toleransi 15 menit) |
| 8 | Estimasi gaji berjalan | **Boleh dilihat karyawan** (default ON, bisa dimatikan) |
| 9 | Periode gaji | **Diatur di Pengaturan** — tanggal mulai 1–28 (default 1 = bulan kalender) |
| 10 | Batas karyawan libur di hari yang sama | **Diatur di Pengaturan** (default tanpa batas) |

Tidak ada pertanyaan terbuka — PRD siap dikerjakan.
