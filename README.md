# knvm — Node Version Manager

Windows'ta **admin şifresi gerektirmeden** birden fazla Node.js sürümü arasında
geçiş yapmayı sağlayan basit bir araç.

---

## Nasıl Çalışır?

```
%USERPROFILE%\knvm\
  ├── knvm.ps1          ← Çekirdek mantık
  ├── config.json       ← Aktif sürüm ve kayıtlı yollar
  └── shims\
        ├── knvm.cmd    ← knvm komutunu knvm.ps1'e yönlendirir
        ├── node.cmd    ← Her çağrıda config.json'ı okur, aktif node.exe'yi çalıştırır
        ├── npm.cmd     ← npm-cli.js'i aktif sürüm üzerinden çalıştırır
        └── npx.cmd     ← npx-cli.js'i aktif sürüm üzerinden çalıştırır
```

**config.json** örneği:
```json
{
  "current": "24.16.0",
  "versions": {
    "24.16.0": "Q:\\workSpace\\app\\node\\v24.16.0",
    "22.22.3": "Q:\\workSpace\\app\\node\\v22.22.3",
    "16.9.1":  "Q:\\workSpace\\app\\node\\v16.9.1"
  }
}
```

`knvm use <sürüm>` sadece `config.json`'ı günceller.  
PATH değişmez, terminal yeniden başlatılmaz, değişiklik **anında** geçerli olur.

---

## Gereksinimler

- Windows 10 / 11
- PowerShell 5.1 veya üstü
- Admin yetkisi **gerekmez**

---

## Kurulum

1. Bu repoyu klonla veya ZIP olarak indir.

2. Bir PowerShell terminali aç ve çalıştır:

```powershell
cd <indirilen-klasör>
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Kurulum şunları yapar:

| Adım | İşlem |
|------|-------|
| 1 | `%USERPROFILE%\knvm\` ve `shims\` klasörlerini oluşturur |
| 2 | `knvm.ps1`'i kopyalar |
| 3 | Shim'leri kopyalar (`node.cmd`, `npm.cmd`, `npx.cmd`, `knvm.cmd`) |
| 4 | `config.json` yoksa boş olarak oluşturur (varsa korunur) |
| 5 | `%USERPROFILE%\knvm\shims` yolunu **User PATH**'e ekler |
| 6 | PowerShell `$PROFILE`'ına shims'i PATH'in başına taşıyan satırı ekler |

> Adım 6, sistemde Machine PATH'te kayıtlı başka bir Node kurulumu (eski nvm,
> IntelliJ otomatik kurulumu vb.) varsa knvm'nin öncelikli olmasını sağlar.

3. Kurulum bittikten sonra **yeni bir terminal** aç  
   (veya mevcut terminalde: `. $PROFILE`)

4. Sürüm ekle ve kullanmaya başla:

```powershell
knvm add 22.22.3 "Q:\workSpace\app\node\v22.22.3"
knvm use 22.22.3
node -v   # v22.22.3
```

---

## Komutlar

### `knvm add <versiyon> <yol>` — Sürüm ekle

```powershell
knvm add 22.22.3 "Q:\workSpace\app\node\v22.22.3"
knvm add 24.16.0 "Q:\workSpace\app\node\v24.16.0"
```

- `<versiyon>`: Sürüm tanımlayıcı (`22.22.3`, `24.16.0`, `lts` vb. — istediğin herhangi bir isim)
- `<yol>`: İçinde `node.exe` bulunan klasör yolu
- `node_modules\npm\bin\npm-cli.js` eksikse uyarı verir

---

### `knvm use <versiyon>` — Aktif sürümü değiştir

```powershell
knvm use 22.22.3
```

Değişiklik anında geçerlidir. Yeni terminal açmak **gerekmez**.

---

### `knvm list` — Kayıtlı sürümleri listele

```powershell
knvm list
```

```
  * 24.16.0  =>  Q:\workSpace\app\node\v24.16.0
    22.22.3  =>  Q:\workSpace\app\node\v22.22.3
    16.9.1   =>  Q:\workSpace\app\node\v16.9.1
```

`*` aktif sürümü gösterir.

---

### `knvm current` — Aktif sürümü göster

```powershell
knvm current
# 24.16.0  =>  Q:\workSpace\app\node\v24.16.0
```

---

### `knvm remove <versiyon>` — Sürümü kayıttan sil

```powershell
knvm remove 16.9.1
```

Sadece kayıt silinir; diskteki Node klasörü dokunulmaz.

---

### `knvm resolve node` / `knvm resolve nodedir`

Shim'lerin (`node.cmd`, `npm.cmd`, `npx.cmd`) dahili olarak kullandığı komutlardır;
aktif sürümün `node.exe` veya klasör yolunu döndürür.

```powershell
knvm resolve node     # Q:\workSpace\app\node\v24.16.0\node.exe
knvm resolve nodedir  # Q:\workSpace\app\node\v24.16.0
```

---


## Güncelleme

Kaynak kodda değişiklik yaptıktan sonra aynı kurulum komutu yeterlidir:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`config.json` korunur, yalnızca `knvm.ps1` ve shim'ler güncellenir.

---

## Sorun Giderme

### `node -v` hâlâ eski sürümü gösteriyor

Sistemde Machine PATH'te kayıtlı başka bir Node var. Çözüm:

```powershell
# Mevcut terminalde profili yeniden yükle
. $PROFILE

# veya yeni bir terminal aç — profil otomatik yüklenir
```

### `knvm` komutu bulunamıyor

Kurulum yeni terminalden önce yapıldı; PATH henüz güncel değil.  
Yeni bir terminal aç veya:

```powershell
$env:PATH = "$env:USERPROFILE\knvm\shims;" + $env:PATH
```

### `npm` veya `npx` çalışmıyor

Eklenen Node klasöründe `node_modules\npm\bin\npm-cli.js` yok demektir.  
`knvm add` sırasında bu eksiklik uyarı olarak gösterilir.

### `where node` shim'i göstermiyor (cmd.exe'de)

`cmd.exe` terminali PowerShell profilini yüklemez; PATH önceliği devreye girmez.
Windows Terminal + PowerShell kullanılması önerilir.

---

## Bilinen Sınırlar

- Her `node` / `npm` / `npx` çağrısında ~200 ms PowerShell başlangıç gecikmesi oluşur (shim mimarisinin kaçınılmaz maliyeti).
- Global npm paketleri (`npm i -g`) sürüme özgüdür; `knvm use` sonrası global paketler değişir.
- `cmd.exe` terminalleri PATH önceliğinden otomatik yararlanamaz.
- Faz 5 (otomatik indirme) ve Faz 6 (`.knvmrc` otomatik seçim) henüz uygulanmadı.
