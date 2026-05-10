# New-SPEYKInventarisatieAccount

> Script van [SPEYK](https://www.speyk.nl) om snel en veilig een tijdelijk beheeraccount aan te maken voor een ICT-inventarisatie bij een onderwijsinstelling.

---

## Wat doet dit script?

Wanneer SPEYK een inventarisatie uitvoert bij jouw school, heeft onze adviseur tijdelijk toegang nodig tot jullie Microsoft 365-omgeving. Dit script maakt daarvoor automatisch een apart account aan — zodat je adviseur nooit hoeft in te loggen met jouw eigen beheerdersaccount.

Het script regelt in één keer:

- ✅ Aanmaken van het account `speyk-inventarisatie@jouwschool.nl`
- ✅ Toewijzen van de rol **Global Administrator** (nodig voor de inventarisatie)
- ✅ Verplichte **MFA** (multi-factor authenticatie) zodat het account beveiligd is
- ✅ Een **tijdelijk wachtwoord** dat bij de eerste aanmelding meteen gewijzigd moet worden
- ✅ Een **Temporary Access Pass** (TAP) als jouw licentie dat ondersteunt — dit is een eenmalige inlogcode waarmee de adviseur direct MFA kan instellen

---

## Wat heb je nodig?

### 1. PowerShell 7

Dit script werkt **niet** in de oudere Windows PowerShell (de blauwe versie die standaard op Windows staat). Je hebt PowerShell 7 nodig — de nieuwere versie met een zwart venster.

**Heb je PowerShell 7 al?**
Open PowerShell en typ:
```powershell
$PSVersionTable.PSVersion
```
Staat er `Major: 7` of hoger? Dan ben je klaar.

**Nog niet? Download het hier:**
👉 [https://aka.ms/powershell](https://aka.ms/powershell)
Kies de Windows installer (`.msi`) en installeer met de standaardinstellingen.

---

### 2. Beheerdersaccount

Je hebt een account nodig met de rol **Global Administrator** in jullie Microsoft 365-omgeving. Dat is normaal gesproken het account waarmee jij als ICT-beheerder beheertaken uitvoert.

---

### 3. Internetverbinding

Het script verbindt automatisch met Microsoft via de browser. Je hoeft verder niets apart te installeren of configureren.

---

## Stap voor stap

### Stap 1 – Download het script

Klik rechtsboven op deze pagina op **Code → Download ZIP**, of download alleen het bestand `New-SPEYKInventarisatieAccount.ps1`.

Sla het bestand op ergens makkelijk terug te vinden, bijvoorbeeld op je bureaublad of in `C:\Scripts\`.

---

### Stap 2 – Open PowerShell 7

Zoek in het startmenu naar **PowerShell 7** (of **pwsh**). Klik er met de rechtermuisknop op en kies **Als administrator uitvoeren**.

> ⚠️ Let op: open dus **niet** de blauwe "Windows PowerShell", maar de zwarte "PowerShell 7".

---

### Stap 3 – Navigeer naar het script

Typ in het PowerShell-venster:
```powershell
cd C:\Scripts
```
(of de map waar jij het bestand hebt opgeslagen)

---

### Stap 4 – Voer het script uit

Typ het volgende commando en vervang `jouwschool.nl` door het e-maildomein van jouw school:

```powershell
.\New-SPEYKInventarisatieAccount.ps1 -TenantDomein "jouwschool.nl"
```

---

### Stap 5 – Inloggen bij Microsoft

Na het starten opent er automatisch een browservenster. Log in met jouw eigen beheerdersaccount. Microsoft vraagt mogelijk toestemming voor de benodigde rechten — klik op **Accepteren**.

> Het script vraagt soms twee keer om in te loggen. Dit is normaal: de tweede keer is voor een extra beveiligingsmachtiging (voor de TAP-aanmaak).

---

### Stap 6 – Wacht tot het script klaar is

Je ziet in het PowerShell-venster stap voor stap wat er gebeurt:

```
► Controleren PowerShell-versie...
  ✓ PowerShell 7.4.x gedetecteerd.

► Controleren benodigde modules...
  ✓ Microsoft.Graph.Authentication aanwezig
  ...

► Account aanmaken: speyk-inventarisatie@jouwschool.nl
  ✓ Account aangemaakt.

► Global Administrator rol toewijzen...
  ✓ Global Administrator rol toegewezen.

► MFA configureren...
  ✓ Conditional Access policy aangemaakt.

► Temporary Access Pass aanmaken...
  ✓ TAP aangemaakt (geldig 8 uur, eenmalig gebruik).
```

---

### Stap 7 – Geef de gegevens door aan SPEYK

Aan het einde verschijnt een samenvatting met het wachtwoord of de TAP-code:

```
══════════════════════════════════════════════════════
  ACCOUNT AANGEMAAKT – GEEF ONDERSTAANDE GEGEVENS
  VEILIG DOOR AAN SPEYK (bijv. via beveiligde chat)
══════════════════════════════════════════════════════

  UPN            : speyk-inventarisatie@jouwschool.nl
  Rol            : Global Administrator
  MFA            : Verplicht (Conditional Access)

  ─── Eerste aanmelding ───────────────────────────────
  Temporary Access Pass : AbCdEf123456
  (TAP is eenmalig geldig, vervalt na 8 uur)

  Aanmeldportal  : https://portal.microsoft.com
  MFA registratie: https://aka.ms/mfasetup
══════════════════════════════════════════════════════
```

Stuur deze gegevens **veilig** door naar jouw SPEYK-contactpersoon — bij voorkeur via de beveiligde chat of e-mail die jullie voor dit project gebruiken. **Stuur het wachtwoord nooit via een gewone e-mail.**

---

## Veelgestelde vragen

### Het script zegt dat er een module geïnstalleerd wordt — is dat veilig?
Ja. Het script installeert officiële Microsoft-modules van de PowerShell Gallery. Dit zijn dezelfde modules die IT-professionals wereldwijd gebruiken om Microsoft 365 te beheren.

### Ik zie een foutmelding over "uitvoeringsbeleid"
Typ dit commando en probeer daarna opnieuw:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Het script vraagt twee keer om in te loggen
Dat is normaal. De tweede aanmelding is voor een extra beveiligingsmachtiging om de Temporary Access Pass aan te maken.

### Ik heb geen Business Premium of E3 licentie (bijv. alleen Office 365 A1)
Voeg dan `-MaakConditionalAccessPolicy:$false` toe aan het commando:
```powershell
.\New-SPEYKInventarisatieAccount.ps1 -TenantDomein "jouwschool.nl" -MaakConditionalAccessPolicy:$false
```
Het script valt dan terug op per-user MFA.

### Wat moet ik doen nadat de inventarisatie klaar is?
Verwijder het account zodra SPEYK aangeeft klaar te zijn. Ga daarvoor naar:
👉 [https://entra.microsoft.com](https://entra.microsoft.com) → **Gebruikers** → zoek op `speyk-inventarisatie` → **Verwijderen**

---

## Licentievereisten

| Functie | Vereiste licentie |
|---|---|
| Account aanmaken + Global Admin | Elke Microsoft 365 licentie |
| MFA via Conditional Access | Entra ID P1 (inbegrepen bij Business Premium, E3, A3) |
| MFA via per-user (fallback) | Elke Microsoft 365 licentie |
| Temporary Access Pass (TAP) | Entra ID P1 (inbegrepen bij Business Premium, E3, A3) |

---

## Vragen of problemen?

Neem contact op met jouw SPEYK-contactpersoon, of mail naar [a.zoutenbier@speyk.nl](mailto:a.zoutenbier@speyk.nl).

---

*Gemaakt door SPEYK – ICT-dienstverlener voor onderwijs en bedrijfsleven*
*Veenendaal · [www.speyk.nl](https://www.speyk.nl)*