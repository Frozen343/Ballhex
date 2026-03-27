# Ballhex UI / UX Spec

## 1. Amac

Ballhex'in mevcut arayuzu calisiyor ama futbol oyunu hissi vermiyor; daha cok editor paneli ya da debug araci gibi gorunuyor. Bu dokumanin amaci, mevcut akisin ustune mobil odakli, cizgi film tadinda, modern ve okunabilir bir UI/UX sistemi tanimlamak.

Bu spec su alanlari kapsar:

- Ilk giris / profil olusturma
- Ana menu ve oyun modu secimi
- Ranked akislarinin gorunumu
- Ozel lobi listesi ve oda kurma deneyimi
- Lobi ici ESC paneli
- Mac ici chat / toast davranisi
- Ortak tema sistemi ve komponent dili

## 2. Mevcut Durum Analizi

Kod incelemesine gore su temel akıs var:

- `NicknameScreen -> MainMenu -> Match`
- `Match` icinde `PauseMenu`, `MatchHUD`, `EndMatchPanel`
- Profil bilgisi su an sadece `player_name` olarak tutuluyor

Sorunlar:

- `MainMenu` su an tablo benzeri bir oda listesi ve sag kolon butonlariyla calisiyor. Oyun modu secim hissi yok.
- `NicknameScreen` sadece isim girilen tek karttan olusuyor. Profil, avatar, hos geldin anı ve marka hissi yok.
- `PauseMenu` fonksiyonel ama bir futbol lobi salonu gibi degil; admin paneli gibi duruyor.
- `MatchHUD` ust skor paneli ve alttaki chat paneli sade ama cok sert bloklar halinde. Mobil tarafa uygun katman hissi vermiyor.
- Chat paneli teknik olarak auto-scroll yapiyor, ama gorunumu mesaj akisi yerine kalin bir kutu gibi.
- Projede su anda neredeyse hic gorsel varlik, font sistemi veya ortak `Theme` altyapisi yok. Bu yuzden ekranlar kendi basina stil veriyor.

## 3. Tasarim Yonu

### Ana stil

Ballhex icin onerilen yon:

- Futbol + arcade + sosyal lobby hibriti
- Mobil oyun ana menusu gibi katmanli kartlar
- Cam efekti, yumusak golgeler, buyuk radius, kalin vurgu renkleri
- Cartoon hissi, ama cocuksu degil; enerjik ve premium

### Gorsel kimlik

- Zemin: koyu lacivertten gece yesiline kayan gradient
- Vurgu renkleri:
  - Cimen yesili
  - Enerjik mercan / kirmizi
  - Elektrik mavi
  - Sicak sari vurgu
- Yuzeyler:
  - yari seffaf koyu kart
  - ince parlak outline
  - yumusak ic golge
- Form dili:
  - buyuk yuvarlatilmis kose
  - capsule butonlar
  - takim rozetleri icin renkli chip yapisi

### Duygu

- Oyuna girdiginde "ranked oynayayim / arkadaslarla lobi kurayim" hissi vermeli
- UI oyunu bogmamalı; sahayi gostermeye devam etmeli
- Lobi ekranlari sosyal bir topluluk / mac odasi gibi hissettirmeli

## 4. Bilgi Mimarisi

Yeni hedef akis:

1. `Welcome / Sign In`
2. `Profile Setup`
3. `Main Menu`
4. `Mode Select`
5. `Ranked Queue` veya `Custom Lobby Browser`
6. `Room / Lobby`
7. `Match`

Not:

- Simdilik backend login zorunlu degil.
- Ilk fazda "guest profile" mantigi kurulabilir.
- Sonraki fazda Google / Apple / platform login buna eklenebilir.

## 5. Ekranlar

### 5.1 Welcome / Sign In

Amac:

- Oyuna ilk giriste bos bir isim formu gostermek yerine markali bir karsilama sunmak
- Oyuncuyu profil mantigina sokmak

Icerik:

- Ustte buyuk Ballhex logosu
- Ortada futbol topu / altigen motifli hafif animasyonlu hero alan
- Altta iki ana aksiyon:
  - `Continue as Guest`
  - `Sign In` (simdilik disabled / yakinda)

Davranis:

- Eger kayitli profil yoksa bu ekran acilir
- Guest secilirse Profile Setup ekranina gecilir
- Kayitli profil varsa direkt Main Menu'ye gidilebilir

### 5.2 Profile Setup

Mevcut nickname ekraninin yerine gececek.

Icerik:

- Profil karti
- Nickname input
- Hazir avatar secici
- Takma ad uzunluk / uygunluk yardim metni
- `Continue` butonu

Ek profil alanlari:

- `display_name`
- `avatar_id`
- `profile_tag` veya kısa numeric id

Not:

- Ilk fazda sadece local kayit yeterli
- Bu alanlar sonradan ranked ve lobi kartlarinda kullanilacak

### 5.3 Main Menu

Mevcut oda listesi acilisi yerine yeni ana merkez.

Yerlesim:

- Ust bar:
  - profil avatari
  - oyuncu adi
  - online durum / baglanti
  - ayarlar butonu
- Orta alan:
  - buyuk animasyonlu mod kartlari
- Alt alan:
  - son mesaj / etkinlik ticker'i
  - kucuk arkadas / party durumu yeri

Ana kartlar:

- `Ranked`
- `Custom Lobby`
- `Training / Offline`

Davranis:

- Kart hover / focus / select ile hafif buyur
- Secilen kart arka planda renk dalgasi veya saha isigi uretsin
- Mobil mantiginda swipe benzeri gecis desteklenebilir

### 5.4 Ranked Menu

Ranked simdilik tam calismasa da gorunus su an oturmali.

Moduller:

- `1v1 Solo Queue`
- `3v3 Party Queue`
- `5v5 Party Queue`

Kart icerigi:

- mod adi
- kisa aciklama
- tahmini oyuncu sayisi
- queue durumu
- CTA butonu

Party akis mantigi:

- 1v1 icin tek butonla queue
- 3v3 / 5v5 icin "create ranked party" karti
- Party odasi tasarimi custom lobby ile ayni dili kullanacak

Bu fazda:

- Ranked kartlari ve placeholder queue ekranlari hazirlanir
- Gercek matchmaking entegrasyonu daha sonra tamamlanir

### 5.5 Custom Lobby Browser

Su anki `Room list` ekraninin yerini alacak.

Yeni duzen:

- Ustte segment:
  - `Ranked`
  - `Custom`
  - `Training`
- Custom seciliyken:
  - arama satiri
  - filtre chipleri
  - `Create Lobby` ana butonu

Lobi listesi tablo yerine kart olacak.

Her lobi kartinda:

- oda adi
- host oyuncu
- oyuncu doluluk durumu
- kurallar ozeti
- ping / bolge bilgisi icin alan
- mini takim ikonlari veya slot noktaciklari
- `Join` butonu

Kart dili:

- daha az yazi, daha cok hiyerarsi
- ustte oda adi
- altta meta satiri
- sagda ana aksiyon

Bos durum:

- "No active lobbies" yazisinin yerine illustre bir bos state
- altinda `Create Your First Lobby`

### 5.6 Create Lobby Sheet

Sag kolon formu yerine modal / bottom sheet.

Icerik:

- lobby adi
- oyuncu limiti
- mac suresi
- gol limiti
- gizli / public secimi icin yer
- `Create Lobby`

Tasarim:

- mobil dialog mantigi
- buyuk inputlar
- secenekler pill veya segmented control gibi

### 5.7 In-Lobby / ESC Panel

Bu ekran su an fonksiyonel ama gorsel olarak zayif.

Yeni davranis:

- ESC acinca tam sert panel yerine seffaf / blur destekli overlay
- Ortada `Room Command Center`
- Sol ve sag takim panelleri kart halinde
- Ortada `Bench / Spectators`
- En ustte oda adi, mod etiketi, mac kurali ozeti

Yerlesim:

- Header:
  - oda adi
  - room code
  - `Resume`, `Start Match`, `Leave`
- Body:
  - `Red Team`
  - `Bench`
  - `Blue Team`
- Footer:
  - yonetim aksiyonlari
  - helper text

Takim kolonlari:

- her oyuncu satiri avatar + isim + host/admin rozetleri
- secildiginde kart glow alsin
- drag & drop gorunur olsun

Host icin ekstra:

- `Randomize`
- `Auto Balance`
- `Match Rules`

Oyuncu icin:

- sadece gorulebilir ve temiz
- gereksiz admin kontrolu gizlenir

### 5.8 Match HUD

Skor paneli daha sportif hale getirilecek.

Yeni yapi:

- orta ustte capsule scoreboard
- solda red skor
- ortada sure
- sagda blue skor
- altta kucuk durum etiketi: `Ranked`, `Friendly`, `Overtime`

Announcement:

- gol oldugunda center text yerine daha enerjik banner
- scale + fade + color pulse

Pause overlay:

- gri katman yerine stadion isigi dusmus gibi yumusak blur / dim

### 5.9 Chat / Event Feed

Istegin dogrultusunda chat daha seffaf ve sosyal akacak.

Hedef davranis:

- chat kutusu ekranin alt-solunda yari seffaf
- normalde dar halde event feed gibi gorunur
- mesaj gelince genisleyip bir sure daha belirgin kalir
- oyuncu yazi yazarken tam aktif moda gecer
- yeni mesaj geldiginde otomatik en alta scroll olur

Mesaj turleri:

- normal chat
- sistem mesajlari
- oyuncu giris / cikis eventleri

Gorunum:

- mesaj baloncuklari yerine hafif satir bazli kartlar
- oyuncu adi renkli
- sistem mesajlari italik / daha soluk
- join / left eventleri farkli renk

Davranis detaylari:

- input focus degilken sadece son 3-5 satir hafif opak gorunsun
- focus olunca panel boyu buyusun
- belli sure mesaj yoksa tekrar compact moda donsun
- manuel yukari scroll yapilmadiysa yeni mesajda en alta insin

## 6. Ortak UI Sistemi

Bu yenileme tek tek node boyamak yerine ortak bir tema sistemiyle kurulacak.

Olusturulacak yapilar:

- `Theme / UI tokens`
- ortak buton stilleri
- ortak panel stilleri
- ortak input stilleri
- chip / badge / tag stilleri
- takim renk varyantlari

Temel tokenlar:

- spacing scale
- radius scale
- shadow / outline yogunlugu
- text renk hiyerarsisi
- accent renkleri
- success / warning / danger renkleri

Komponentler:

- `PrimaryButton`
- `SecondaryButton`
- `GhostButton`
- `GlassCard`
- `TagChip`
- `TeamBadge`
- `ProfilePill`
- `ToastLine`

## 7. Animasyon Prensipleri

UI'nin guzel gorunmesi kadar hareket dili de onemli.

Kurallar:

- ekran girislerinde 150-300ms arasi yumusak ease-out
- kart seciminde scale + glow
- modal acilisinda alttan kayma ya da yumusak pop
- toast/chat eventlerinde hafif slide + fade
- asiri hareket yok; hizli ve temiz

## 8. Mobil Odakli Kurallar

Ballhex web/desktop uzerinden de calissa, tasarim mobil mantigi ile kurulacak.

Kurallar:

- buyuk tap hedefleri
- tek elde okunabilir hiyerarsi
- az yazili, yuksek kontrastli kartlar
- ana aksiyonlar bas parmak erisimi gibi net
- yatay ve dar ekranlarda kolonlar alt alta dusebilmeli

Responsive yaklasim:

- desktop: 2 veya 3 kolon
- tablet: 2 kolon
- mobile / dar oran: stacked cards + bottom sheet

## 9. Teknik Uygulama Plani

### Faz 1 - Tema Temeli

- ortak renk/token yapisi kur
- ortak button/panel/input stillerini cikar
- mevcut ekranlari bu stil sistemine baglamaya basla

### Faz 2 - Profil Girisi

- `NicknameScreen` yerine `Welcome` + `Profile Setup` akislarini kur
- `GameSettings` icine avatar ve profil verileri ekle
- `App.gd` ilk acilis kararini bu yeni profile gore ver

### Faz 3 - Yeni Main Menu

- mevcut `MainMenu`yi oda listesi ekrani olmaktan cikar
- mod secim merkezine donustur
- `Ranked`, `Custom Lobby`, `Training` kartlarini ekle

### Faz 4 - Custom Lobby Browser

- oda listesi tablo yapisini kart tasarimina cevir
- `Create Lobby` modalini kur
- bos state ve filtre satirini ekle

### Faz 5 - Ranked Shell

- 1v1, 3v3, 5v5 ranked kartlarini ve queue ekranlarini hazirla
- party lobby gorunumunu ozel lobi diliyle ayni aileye sok

### Faz 6 - In-Lobby / PauseMenu

- ESC panelini yeni command center tasarimina cevir
- takim kolonlarini kartlastir
- admin ve normal oyuncu durumlarini net ayir

### Faz 7 - Chat / Feed / HUD

- chat panelini compact + expanded davranisli hale getir
- event feed animasyonlarini ekle
- skor panelini modernlestir

## 10. Ilk Uygulama Onceligi

Ilk gelistirme dalgasi icin onerdigim sira:

1. Global tema sistemi
2. Welcome + Profile Setup
3. Main Menu mode select
4. Custom Lobby Browser redesign
5. PauseMenu redesign
6. Match chat redesign
7. Ranked gorunusleri

Bu sira dogru cunku:

- once tum ekranlarda kullanacagimiz gorsel dili kurariz
- sonra kullanicinin ilk gordugu ekranlari duzeltiriz
- ardindan hali hazirda calisan custom lobby akislarini yeni gorunume tasiriz
- en son ranked shell'i oturturuz

## 11. Basari Kriterleri

Bu yenileme tamamlandiginda su sonuc beklenir:

- oyun ilk acilista prototip degil urun gibi hissettirir
- kullanici ne yapacagini ekranda rahat anlar
- custom lobby listesi sosyal ve temiz gorunur
- lobi ici yönetim ekranı korkutucu degil premium hisseder
- chat oyunu kapatan bir blok degil, oyuna karisan akici bir katman olur
- ranked sisteminin gelecegi daha ilk bakista hissedilir

## 12. Notlar

- Projede su an ozel font ve ikon seti bulunmuyor. Ilk implementasyonda sekil, renk, spacing ve panel diliyle kalite yukseltecegim.
- Daha sonra istersek futbol odakli ikonlar, avatar setleri ve ozel font ekleyebiliriz.
- Ranked backend hazir olmasa bile UI simdiden urun kalitesinde kurulabilir.
