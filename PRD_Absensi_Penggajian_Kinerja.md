# PRD — Aplikasi Web Absensi GPS, Penggajian & Target Kinerja Individual

> Dokumen ini adalah Product Requirements Document (PRD) sekaligus prompt siap pakai.
> Salin seluruh isi di bawah garis ini dan berikan ke AI coding assistant / developer.

| Item | Keterangan |
|---|---|
| Pemilik produk | Nanang (Admin / Owner) |
| Versi dokumen | 1.0 |
| Tanggal | 29 September 2026 |
| Status | Draft untuk pengembangan |

---

## 0. Peran & Instruksi untuk AI / Developer

Kamu adalah **senior full-stack engineer Laravel** yang berpengalaman dengan **PHP 8.2+, Laravel 11, MySQL 8 / MariaDB 10.6+, Blade + Tailwind CSS**, dan deployment di **VPS aaPanel (Nginx + PHP-FPM)**.
Buatkan aplikasi lengkap sesuai PRD berikut. Tulis kode yang **production-ready, aman, dan terdokumentasi**, dan kerjakan **bertahap per milestone** (lihat Bagian 13).
Semua teks antarmuka dalam **Bahasa Indonesia**, format uang **Rupiah (Rp 1.234.567)**, zona waktu **Asia/Jakarta (WIB)**.

---

## 1. Ringkasan Produk

**Nama kerja:** AbsenKu — Absensi, Gaji & Kinerja
**Tujuan:** Satu aplikasi web ringan untuk usaha kecil (±10 karyawan) yang:
1. Mencatat kehadiran karyawan secara **akurat berbasis lokasi GPS** (harus berada di kantor).
2. Menghitung **gaji bulanan otomatis** dari gaji pokok + tunjangan, dipotong ketidakhadiran, ditambah lembur dan bonus target.
3. Memantau **target kinerja individual** tiap karyawan (mis. jumlah pelanggan baru, nilai penjualan).
4. Menghasilkan **slip gaji PDF** dan **rekap Excel/CSV** dengan sekali klik.

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
| **Karyawan** | ±10 | Clock-in/out dari HP, lihat riwayat absensi, update progres target, lihat & unduh slip gaji |

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
| Gaji pokok | decimal | ✔ | mis. 3.000.000 |
| Tunjangan tetap | decimal | ✔ | mis. 500.000 |
| Nilai potongan per hari | decimal | ✔ | Default otomatis = gaji pokok ÷ hari kerja standar (22), bisa diubah manual |
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
- **Jam kerja standar:** jam masuk (mis. 08:00), jam pulang (mis. 17:00), toleransi terlambat (mis. 15 menit).
- **Jendela absensi:** clock-in diizinkan mulai 07:00, clock-out paling lambat 23:59 (bisa diatur).
- **Hari kerja:** pilih hari (default Senin–Sabtu atau Senin–Jumat).
- **Hari libur:** kalender libur nasional/perusahaan (CRUD tanggal + keterangan).

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
4. Lembur baru masuk perhitungan gaji jika **disetujui admin** (status lembur: `menunggu` → `disetujui`/`ditolak`). Admin bisa mengaktifkan opsi "lembur otomatis disetujui".

### 5.4 Aturan Absensi
- Clock-in **hanya 1x per hari**; clock-out hanya 1x setelah clock-in.
- Clock-in di luar jendela absensi → **ditolak**, karyawan bisa mengajukan **permintaan absensi manual** yang harus disetujui admin.
- **Hari libur & hari non-kerja:** tombol absensi disembunyikan; tidak dihitung alfa. Jika tetap masuk kerja di hari libur, karyawan mengajukan absensi manual dan admin dapat menandainya sebagai lembur.
- **Lupa clock-out:** scheduler pukul 23:59 menandai `lupa_clock_out`; jam pulang dianggap = jam pulang standar, **tanpa lembur**, admin bisa koreksi.
- **Alfa otomatis:** scheduler pukul 23:59 memberi status `alfa` pada karyawan aktif yang tidak clock-in di hari kerja dan tidak memiliki izin/cuti.

### 5.5 Izin, Sakit & Cuti
- Karyawan mengajukan **izin / sakit / cuti** (tanggal mulai–selesai, alasan, lampiran foto opsional untuk sakit).
- Admin **menyetujui/menolak**. Hari yang disetujui berstatus `izin`/`sakit`/`cuti`.
- Pengaturan admin per jenis: **dipotong gaji atau tidak** (default: sakit & cuti tidak dipotong, izin dipotong).
- Kuota cuti tahunan per karyawan (default 12 hari).

### 5.6 Koreksi & Log
- Admin dapat **mengoreksi** absensi (ubah jam/status) dengan **alasan wajib**; semua perubahan masuk **audit log** (siapa, kapan, nilai lama → baru).
- Admin dapat melihat **peta titik GPS** tiap absensi untuk verifikasi.

### 5.7 Anti-Kecurangan (dasar)
- Validasi jarak & akurasi dilakukan di server.
- Tandai (flag) absensi mencurigakan: akurasi 0/sangat sempurna berulang, koordinat identik persis dengan hari sebelumnya, atau perangkat/user-agent berbeda dari biasanya. Flag hanya **peringatan untuk admin**, tidak memblokir.
- Catatan: fake GPS tidak bisa dicegah 100% dari browser; opsi lanjutan (fase 2): **foto selfie saat clock-in**.

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
- Satu karyawan boleh punya **lebih dari satu target** per bulan. Aturan bonus: bonus dihitung **per target yang tercapai**.
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
- Periode gaji = **1 bulan kalender** (tanggal 1 s.d. akhir bulan). Opsi fase 2: periode kustom (mis. 26–25).
- **Hari kerja efektif** = jumlah hari kerja di bulan tersebut − hari libur.

### 7.2 Rumus Perhitungan

```
Gaji Dasar          = Gaji Pokok + Tunjangan Tetap

Hari Tidak Hadir    = jumlah hari berstatus alfa
                    + jumlah hari izin yang diatur "dipotong"
Potongan Kehadiran  = Hari Tidak Hadir × Nilai Potongan per Hari

Gaji per Jam        = Gaji Pokok ÷ (Hari Kerja Standar × Jam Kerja per Hari)
                      (default: Gaji Pokok ÷ (22 × 8) = Gaji Pokok ÷ 176)
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
- Keterlambatan: default **tidak dipotong** (hanya dicatat). Opsi admin: potongan per kejadian terlambat (Rp X).
- Semua nilai dibulatkan ke **Rupiah terdekat** di hasil akhir.

### 7.3 Contoh Perhitungan
Gaji pokok Rp 3.000.000, tunjangan Rp 500.000, nilai per hari Rp 136.364 (3.000.000 ÷ 22), alfa 1 hari, lembur 4 jam disetujui, 1 target tercapai (bonus Rp 1.000.000):

| Komponen | Nilai |
|---|---|
| Gaji dasar | Rp 3.500.000 |
| Potongan (1 × 136.364) | − Rp 136.364 |
| Lembur (4 × 17.045 × 1,5 = 4 × 25.568) | + Rp 102.273 |
| Bonus target | + Rp 1.000.000 |
| **Total** | **Rp 4.465.909** |

### 7.4 Alur Proses Gaji (Admin)
1. Pilih bulan → klik **"Hitung Gaji"** → sistem membuat **draft** untuk semua karyawan aktif.
2. Admin meninjau rincian per karyawan, menambah penyesuaian bila perlu, bisa **hitung ulang** selama masih draft.
3. Klik **"Finalisasi"** → nilai dikunci (snapshot semua komponen disimpan, tidak berubah walau data master diubah), absensi & target periode itu ikut terkunci.
4. Tandai **"Sudah Dibayar"** (tanggal bayar, metode: tunai/transfer, catatan).
5. Pembukaan kunci (unlock) hanya oleh admin dengan alasan, tercatat di audit log.

Status gaji: `draft` → `final` → `dibayar`.

### 7.5 Output
- **Rincian gaji** per karyawan di layar (semua komponen + jumlah hari hadir/terlambat/alfa/izin/sakit/cuti + jam lembur).
- **Slip gaji PDF** per karyawan per bulan: logo & nama usaha, periode, identitas karyawan, rincian pendapatan & potongan, total, status bayar. Karyawan bisa mengunduh slip miliknya (hanya yang sudah `final`).
- **Export Excel/CSV** rekap gaji satu bulan seluruh karyawan.
- **Export Excel/CSV** rekap absensi (filter karyawan & rentang tanggal).

---

## 8. Fitur 5 — Dashboard

### 8.1 Dashboard Admin
- **Kartu ringkasan:** jumlah karyawan aktif; hadir hari ini / terlambat / belum absen / izin; total gaji bulan ini + status (draft/final/dibayar); jumlah permintaan menunggu persetujuan (izin, lembur, absensi manual).
- **Daftar "Belum Clock-In Hari Ini"** (real-time saat dibuka).
- **Tabel absensi bulan berjalan:** filter karyawan & tanggal, badge status, ikon flag mencurigakan, klik untuk lihat peta.
- **Tabel gaji bulan berjalan:** status per karyawan (belum dihitung / draft / final / dibayar).
- **Widget target:** progres target semua karyawan bulan ini.

### 8.2 Dashboard Karyawan
- **Info jam kantor** (jam masuk, jam pulang, toleransi) + **lokasi kantor di peta** (Leaflet/OpenStreetMap) dengan lingkaran radius dan titik posisi karyawan saat ini.
- Tombol besar **Clock-In / Clock-Out** + status hari ini + jarak ke kantor.
- **Riwayat absensi bulan ini:** tabel tanggal, status, jam masuk, jam keluar (plus tampilan kalender berwarna per status).
- Ringkasan bulan ini: hadir, terlambat, alfa, izin, jam lembur.
- **Target kinerja bulan ini** + progress bar + **form update progres langsung di dashboard** (nilai + catatan).
- **Gaji per periode:** daftar slip per bulan, lihat rincian komponen, dan **unduh PDF** (hanya yang sudah `final`).
- Estimasi gaji berjalan (opsional, bisa dimatikan admin).

---

## 9. Notifikasi (Fase 2, opsional)
- Pengingat clock-in via **WhatsApp gateway / email** pukul 07:45 bagi yang belum absen.
- Notifikasi admin saat ada pengajuan izin/lembur/absensi manual.
- Notifikasi karyawan saat slip gaji sudah final.

---

## 10. Skema Database (Ringkas)

```
users               id, name, email, phone, password, role(admin|employee), position,
                    join_date, end_date, status, remember_token, timestamps, deleted_at
salary_settings     id, user_id, base_salary, allowance, daily_deduction,
                    overtime_rate_per_hour (nullable = pakai default), effective_from, timestamps
settings            key, value           -- office_lat, office_lng, radius_m, max_accuracy_m,
                                         -- work_start, work_end, late_tolerance_min,
                                         -- work_days, overtime_multiplier, standard_work_days,
                                         -- standard_hours_per_day, auto_approve_overtime, ...
holidays            id, date (unique), description
attendances         id, user_id, date, clock_in_at, clock_in_lat, clock_in_lng,
                    clock_in_accuracy, clock_in_distance, clock_out_at, clock_out_lat,
                    clock_out_lng, clock_out_accuracy, clock_out_distance,
                    status(hadir|terlambat|alfa|izin|sakit|cuti|libur|lupa_clock_out),
                    overtime_minutes, overtime_status(none|pending|approved|rejected),
                    is_flagged, flag_reason, ip, user_agent, note, timestamps
                    UNIQUE(user_id, date)
attendance_attempts id, user_id, type(in|out), lat, lng, accuracy, distance, success, reason, created_at
leave_requests      id, user_id, type(izin|sakit|cuti|manual_attendance), start_date, end_date,
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
audit_logs          id, user_id, action, auditable_type, auditable_id, old_values, new_values,
                    reason, ip, created_at
```

---

## 11. Kebutuhan Non-Fungsional

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

## 12. Struktur Halaman (Routes)

**Karyawan:** `/login`, `/dashboard`, `/absensi` (riwayat), `/pengajuan` (izin/sakit/cuti/absensi manual), `/target`, `/gaji` (slip), `/profil`
**Admin:** `/admin/dashboard`, `/admin/karyawan`, `/admin/absensi`, `/admin/pengajuan`, `/admin/lembur`, `/admin/target`, `/admin/gaji/{periode}`, `/admin/libur`, `/admin/pengaturan` (lokasi, jam kerja, gaji default), `/admin/audit-log`

---

## 13. Milestone Pengerjaan

| # | Milestone | Isi | Estimasi |
|---|---|---|---|
| M1 | Fondasi | Setup Laravel, auth, role, CRUD karyawan, pengaturan, layout mobile-first | 3–4 hari |
| M2 | Absensi GPS | Pengaturan lokasi + peta, clock-in/out, validasi Haversine, log percobaan, riwayat, hari libur | 4–5 hari |
| M3 | Izin & Koreksi | Pengajuan izin/sakit/cuti/manual, persetujuan lembur, koreksi admin, scheduler alfa & lupa clock-out, audit log | 3 hari |
| M4 | Target Kinerja | CRUD target, progres, verifikasi, dashboard progres, salin target | 3 hari |
| M5 | Penggajian | `PayrollCalculator` + unit test, draft/final/dibayar, slip PDF, export Excel/CSV | 4–5 hari |
| M6 | Dashboard & Rilis | Dashboard admin & karyawan, hardening keamanan, deploy aaPanel + HTTPS + cron + backup, UAT | 3 hari |

---

## 14. Kriteria Penerimaan (Acceptance Criteria)

**Absensi**
- [ ] Clock-in di dalam radius dengan akurasi baik → tersimpan, status `hadir` / `terlambat` sesuai jam.
- [ ] Clock-in di luar radius → ditolak dengan pesan berisi jarak & radius; percobaan tercatat.
- [ ] Clock-in kedua di hari yang sama → ditolak.
- [ ] Mengirim koordinat palsu langsung ke API (tanpa UI) tetap divalidasi server.
- [ ] Hari libur/non-kerja → tidak ada tombol absensi & tidak dihitung alfa.
- [ ] Karyawan tanpa absensi & tanpa izin di hari kerja → otomatis `alfa` setelah scheduler berjalan.
- [ ] Clock-out setelah jam pulang ≥ 30 menit → lembur `pending`, masuk gaji hanya setelah disetujui.

**Target**
- [ ] Admin membuat target; karyawan melihat progress bar dan menambah progres.
- [ ] Progres mencapai/lebih dari target → status **Tercapai** dan bonus masuk perhitungan gaji.

**Gaji**
- [ ] Contoh pada Bagian 7.3 menghasilkan total **Rp 4.465.909**.
- [ ] Karyawan yang mulai tanggal 15 tidak dihitung alfa sebelum tanggal 15 dan gajinya diprorata.
- [ ] Setelah finalisasi, mengubah gaji pokok karyawan **tidak** mengubah slip bulan yang sudah final.
- [ ] Slip PDF bisa diunduh admin (semua) dan karyawan (miliknya saja, yang sudah final).
- [ ] Export Excel/CSV berisi seluruh karyawan dan semua komponen gaji.

**Keamanan**
- [ ] Karyawan tidak bisa membuka halaman admin maupun data/slip karyawan lain (403).
- [ ] Setiap koreksi absensi & perubahan gaji tercatat di audit log dengan alasan.

---

## 15. Pertanyaan Terbuka (perlu konfirmasi Nanang)
1. Hari kerja: Senin–Jumat atau Senin–Sabtu? Jam kerja standar tepatnya?
2. Apakah izin (bukan sakit/cuti) dipotong gaji? Apakah keterlambatan dipotong?
3. Lembur perlu persetujuan admin, atau otomatis dihitung?
4. Bonus target: nominal tetap atau persentase? Jika punya beberapa target, bonus per target atau hanya jika semua tercapai?
5. Apakah perlu foto selfie saat clock-in untuk mencegah titip absen / fake GPS?
6. Apakah karyawan boleh melihat estimasi gaji berjalan sebelum final?
7. Periode gaji: bulan kalender atau tanggal tertentu (mis. 26–25)?
