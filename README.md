# musicRa

Pemutar musik Android bergaya Spotify dengan tema hijau. Semua lagu diambil dari YouTube Music, dan aplikasinya bisa dipakai tanpa login.

## Fitur unggulan

- **Tetap diputar saat diminimize.** Pemutaran berjalan di foreground service (`audio_service` + `just_audio`), lengkap dengan kontrol di notifikasi, layar kunci, dan tombol headset. Musik tetap jalan saat aplikasi ditutup atau di-swipe dari recent apps.
- **Download ke lokal.** Unduh satu lagu atau satu playlist sekaligus. Lagu diambil per potongan Range 2 MB agar tidak diperlambat YouTube, dan unduhan otomatis lanjut kalau URL kedaluwarsa. File dan covernya disimpan di penyimpanan aplikasi, jadi tetap bisa diputar tanpa internet.
- **Tempel link playlist.** Link playlist, album, atau mix dari YouTube dan YouTube Music (`list=PL…`, `OLAK5uy_…`, `RDCLAK…`, `browse/VL…`) langsung jadi playlist di Koleksi. Link di clipboard terdeteksi otomatis. Playlist hasil impor bisa disinkronkan ulang untuk menambahkan lagu baru.
- Beranda dari YouTube Music, pencarian dengan saran dan filter (Lagu, Video, Album, Playlist), radio atau autoplay saat antrean habis, antrean yang bisa diatur, acak dan ulangi, Lagu yang Disukai, serta riwayat putar.

## Cara kerja data YouTube

Lapisan `lib/youtube/` adalah porting Dart dari modul `innertube` di Convx:

| Kebutuhan | Endpoint InnerTube | Klien |
|---|---|---|
| Beranda, playlist, album | `browse` (`FEmusic_home`, `VL…`, `MPREb_…`) | `WEB_REMIX` |
| Pencarian, saran | `search`, `music/get_search_suggestions` | `WEB_REMIX` |
| Radio, autoplay, mix `RD…` | `next` | `WEB_REMIX` |
| URL audio | `player` | `ANDROID_VR 1.43` → `VISIONOS` → `IOS` → `ANDROID_VR 1.61`, lalu `youtube_explode_dart` sebagai cadangan |

Aplikasi tidak memakai akun maupun cookie. Setiap request hanya membawa `visitorData` anonim dari `music.youtube.com/sw.js_data`. Klien stream yang terakhir berhasil akan dicoba duluan pada request berikutnya.

## Struktur

```
lib/
  youtube/   klien InnerTube, parser JSON, resolver stream, pengenal link playlist (Dart murni)
  data/      penyimpanan lokal sqflite: playlist, disukai, unduhan, riwayat
  download/  pengelola unduhan bertahap
  player/    audio handler (antrean, shuffle/repeat, autoplay, putar dari file unduhan)
  ui/        shell 3 tab, layar Beranda/Cari/Koleksi/Playlist/Player, widget bersama
tool/smoke_youtube.dart   uji langsung ke YouTube Music
```

## Menjalankan

Proyek ini memakai Flutter 3.24.5 (Dart 3.5) di `E:\Flutter\3.24.5` (lihat `.fvmrc`).

```bash
E:/Flutter/3.24.5/bin/flutter run
```

```bash
E:/Flutter/3.24.5/bin/flutter test
```

```bash
E:/Flutter/3.24.5/bin/dart run tool/smoke_youtube.dart
```

```bash
E:/Flutter/3.24.5/bin/flutter build apk --release
```

Build release masih ditandatangani dengan debug key. Siapkan keystore sendiri sebelum aplikasinya dibagikan.

### Catatan build

- Semua plugin dipaksa memakai AGP 8.5.2 milik aplikasi (lihat `android/build.gradle`), jadi hanya satu versi AGP yang perlu diunduh.
- `ndkVersion` di-set ke `27.0.12077973` karena itulah NDK yang terpasang dan memenuhi syarat plugin (26.1 ke atas).
- Kalau koneksi sering memutus unduhan Maven ("Tag mismatch"), unduh jar yang gagal secara manual ke `~/.m2/repository`. Repo `mavenLocal()` dibaca lebih dulu, tapi hanya untuk grup Kotlin, Android tools, Flutter, `com.google.*`, dan `androidx.*`.
