#Requires -Version 7.0
<#
.SYNOPSIS
    Maakt het SPEYK inventarisatie-account aan in Microsoft 365 met Global Admin en verplichte MFA.

.DESCRIPTION
    Dit script:
    - Controleert of PowerShell 7+ wordt gebruikt
    - Controleert en installeert benodigde modules (Microsoft.Graph)
    - Maakt het account speyk-inventarisatie@<domein> aan
    - Wijst de Global Administrator rol toe
    - Forceert MFA via een Conditional Access policy (per-user MFA als fallback)
    - Genereert een tijdelijk wachtwoord en TAP (Temporary Access Pass)

.NOTES
    Vereisten:
    - PowerShell 7.0 of hoger
    - Uitvoeren als Global Administrator
    - Entra ID P1 of hoger voor Conditional Access (aanbevolen)

    Auteur : SPEYK – Alexander Zoutenbier
    Versie : 1.1
    Datum  : 2026

    Changelog:
    1.1 - Per-user MFA endpoint gecorrigeerd naar beta/users/{id}/authentication/requirements
        - TAP scope (UserAuthenticationMethod.ReadWrite.All) expliciet geconsent via aparte Graph-call
        - CA policy standaard aan (Business Premium / E3 heeft Entra P1)
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    # Het UPN-domein van de tenant, bijv. "ggca.nl" of "rscollege.nl"
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
    [string]$TenantDomein,

    # Weergavenaam voor het account
    [string]$DisplayName = 'SPEYK Inventarisatie',

    # Conditional Access policy aanmaken voor MFA.
    # Standaard AAN – Business Premium en E3 bevatten Entra ID P1.
    # Zet op -MaakConditionalAccessPolicy:$false voor tenants zonder P1 (bijv. alleen A1).
    [switch]$MaakConditionalAccessPolicy = $true
)

#region ── Helpers ────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Bericht)
    Write-Host "`n► $Bericht" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Bericht)
    Write-Host "  ✓ $Bericht" -ForegroundColor Green
}

function Write-Waarschuwing {
    param([string]$Bericht)
    Write-Host "  ⚠ $Bericht" -ForegroundColor Yellow
}

function Write-Fout {
    param([string]$Bericht)
    Write-Host "  ✗ $Bericht" -ForegroundColor Red
}

function New-WillekeurigWachtwoord {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%&*'
    -join ((1..20) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

#endregion

#region ── 0. PowerShell versiecheck ─────────────────────────────────────────

Write-Step "Controleren PowerShell-versie..."
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Fout "Dit script vereist PowerShell 7 of hoger. Huidige versie: $($PSVersionTable.PSVersion)"
    Write-Host "  Download: https://aka.ms/powershell" -ForegroundColor DarkGray
    exit 1
}
Write-OK "PowerShell $($PSVersionTable.PSVersion) gedetecteerd."

#endregion

#region ── 1. Module-controle en installatie ──────────────────────────────────

Write-Step "Controleren benodigde modules..."

$vereisteScopeGroepen = @{
    'Microsoft.Graph.Authentication'      = 'Authenticatie en verbinding'
    'Microsoft.Graph.Users'               = 'Gebruikersbeheer'
    'Microsoft.Graph.Identity.DirectoryManagement' = 'Rol-toewijzingen'
    'Microsoft.Graph.Identity.SignIns'    = 'Conditional Access / MFA'
}

$teInstalleren = [System.Collections.Generic.List[string]]::new()

foreach ($module in $vereisteScopeGroepen.GetEnumerator()) {
    if (Get-Module -ListAvailable -Name $module.Key) {
        Write-OK "$($module.Key) aanwezig  ($($module.Value))"
    } else {
        Write-Waarschuwing "$($module.Key) ontbreekt  ($($module.Value))"
        $teInstalleren.Add($module.Key)
    }
}

if ($teInstalleren.Count -gt 0) {
    Write-Step "Installeren ontbrekende modules (CurrentUser scope)..."
    foreach ($mod in $teInstalleren) {
        try {
            Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
            Write-OK "$mod geïnstalleerd."
        } catch {
            Write-Fout "Kon $mod niet installeren: $_"
            exit 1
        }
    }
}

Import-Module Microsoft.Graph.Authentication,
              Microsoft.Graph.Users,
              Microsoft.Graph.Identity.DirectoryManagement,
              Microsoft.Graph.Identity.SignIns -ErrorAction Stop

Write-OK "Alle modules geladen."

#endregion

#region ── 2. Verbinden met Microsoft Graph ───────────────────────────────────

Write-Step "Verbinden met Microsoft Graph..."

$scopes = @(
    'User.ReadWrite.All'
    'RoleManagement.ReadWrite.Directory'
    'Policy.ReadWrite.ConditionalAccess'
    'Policy.Read.All'
    'Directory.ReadWrite.All'
    'UserAuthenticationMethod.ReadWrite.All'
)

try {
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
    $context = Get-MgContext
    Write-OK "Verbonden als: $($context.Account) | Tenant: $($context.TenantId)"
} catch {
    Write-Fout "Verbinding mislukt: $_"
    exit 1
}

#endregion

#region ── 3. Account aanmaken ───────────────────────────────────────────────

$upn       = "speyk-inventarisatie@$TenantDomein"
$wachtwoord = New-WillekeurigWachtwoord

Write-Step "Account aanmaken: $upn"

# Controleer of account al bestaat
$bestaandAccount = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue

if ($bestaandAccount) {
    Write-Waarschuwing "Account $upn bestaat al (ObjectId: $($bestaandAccount.Id)). Bestaand account wordt gebruikt."
    $nieuwAccount = $bestaandAccount
} else {
    $accountParams = @{
        DisplayName         = $DisplayName
        UserPrincipalName   = $upn
        MailNickname        = 'speyk-inventarisatie'
        AccountEnabled      = $true
        PasswordProfile     = @{
            Password                      = $wachtwoord
            ForceChangePasswordNextSignIn = $true   # Eenmalig wachtwoord
        }
        UsageLocation       = 'NL'
    }

    try {
        $nieuwAccount = New-MgUser @accountParams -ErrorAction Stop
        Write-OK "Account aangemaakt. ObjectId: $($nieuwAccount.Id)"
    } catch {
        Write-Fout "Account aanmaken mislukt: $_"
        Disconnect-MgGraph | Out-Null
        exit 1
    }
}

#endregion

#region ── 4. Global Administrator rol toewijzen ─────────────────────────────

Write-Step "Global Administrator rol toewijzen..."

$globalAdminRolNaam = 'Global Administrator'
$rol = Get-MgDirectoryRole -Filter "displayName eq '$globalAdminRolNaam'" -ErrorAction SilentlyContinue

# Rol activeren als nog niet actief in de tenant
if (-not $rol) {
    Write-Waarschuwing "Global Administrator rol nog niet geactiveerd – wordt nu geactiveerd..."
    $rolTemplate = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -eq $globalAdminRolNaam }
    if (-not $rolTemplate) {
        Write-Fout "Kon de Global Administrator rolsjabloon niet vinden."
        Disconnect-MgGraph | Out-Null
        exit 1
    }
    $rol = New-MgDirectoryRole -RoleTemplateId $rolTemplate.Id -ErrorAction Stop
}

# Controleer of al lid van de rol
$bestaandLidmaatschap = Get-MgDirectoryRoleMember -DirectoryRoleId $rol.Id |
    Where-Object { $_.Id -eq $nieuwAccount.Id }

if ($bestaandLidmaatschap) {
    Write-Waarschuwing "Account is al Global Administrator."
} else {
    $refBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($nieuwAccount.Id)" }
    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $rol.Id -BodyParameter $refBody -ErrorAction Stop
    Write-OK "Global Administrator rol toegewezen."
}

#endregion

#region ── 5. MFA forceren ───────────────────────────────────────────────────

Write-Step "MFA configureren..."

if ($MaakConditionalAccessPolicy) {
    # ── 5a. Conditional Access policy (aanbevolen, vereist Entra ID P1+) ──
    Write-Host "  Methode: Conditional Access policy" -ForegroundColor DarkGray

    $caNaam = 'SPEYK – Verplichte MFA voor inventarisatieaccount'

    $bestaandeCA = Get-MgIdentityConditionalAccessPolicy |
        Where-Object { $_.DisplayName -eq $caNaam }

    if ($bestaandeCA) {
        Write-Waarschuwing "Conditional Access policy '$caNaam' bestaat al – wordt overgeslagen."
    } else {
        $caBody = @{
            displayName = $caNaam
            state       = 'enabled'
            conditions  = @{
                users        = @{
                    includeUsers = @($nieuwAccount.Id)
                }
                applications = @{
                    includeApplications = @('All')
                }
            }
            grantControls = @{
                operator        = 'OR'
                builtInControls = @('mfa')
            }
        }

        try {
            $caPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $caBody -ErrorAction Stop
            Write-OK "Conditional Access policy aangemaakt: $($caPolicy.Id)"
        } catch {
            Write-Waarschuwing "CA policy mislukt (mogelijk geen Entra P1 licentie): $_"
            Write-Waarschuwing "Valt terug op per-user MFA..."
            $MaakConditionalAccessPolicy = $false
        }
    }
}

if (-not $MaakConditionalAccessPolicy) {
    # ── 5b. Per-user MFA fallback (geen Entra P1 beschikbaar) ─────────────
    # Correct endpoint: beta, property 'perUserMfaState' op het user-object zelf.
    # v1.0 /authentication/requirements bestaat niet – dat geeft een 400.
    Write-Host "  Methode: per-user MFA via beta endpoint" -ForegroundColor DarkGray

    $mfaUri  = "https://graph.microsoft.com/beta/users/$($nieuwAccount.Id)/authentication/requirements"
    $mfaBody = @{ perUserMfaState = 'enforced' } | ConvertTo-Json -Compress

    try {
        Invoke-MgGraphRequest -Method PATCH -Uri $mfaUri -Body $mfaBody `
            -ContentType 'application/json' -ErrorAction Stop
        Write-OK "Per-user MFA ingesteld op 'enforced' (beta endpoint)."
    } catch {
        Write-Waarschuwing "Per-user MFA via Graph mislukt: $_"
        Write-Waarschuwing "Stel handmatig in via Entra portal:"
        Write-Waarschuwing "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/UserDetailsMenuBlade/~/UserAuthMethods/userId/$($nieuwAccount.Id)"
    }
}

#endregion

#region ── 6. Temporary Access Pass (TAP) aanmaken ───────────────────────────

Write-Step "Temporary Access Pass aanmaken voor eerste aanmelding..."

# TAP vereist de scope UserAuthenticationMethod.ReadWrite.All.
# Deze scope kan een aparte admin-consent trigger geven – daarom een tweede
# Connect-MgGraph met alleen deze scope als die nog niet geconsent is.
$tapScope = 'UserAuthenticationMethod.ReadWrite.All'
$huidigScopes = (Get-MgContext).Scopes

if ($tapScope -notin $huidigScopes) {
    Write-Waarschuwing "Scope $tapScope nog niet geconsent – extra aanmelding vereist..."
    try {
        Connect-MgGraph -Scopes $tapScope -NoWelcome -ErrorAction Stop
        Write-OK "Aanvullende scope geconsent."
    } catch {
        Write-Waarschuwing "Kon aanvullende scope niet ophalen: $_"
    }
}

$tapUri  = "https://graph.microsoft.com/v1.0/users/$($nieuwAccount.Id)/authentication/temporaryAccessPassMethods"
$tapBody = @{
    isUsableOnce      = $true
    lifetimeInMinutes = 480   # 8 uur geldig
} | ConvertTo-Json -Compress

try {
    $tapResponse = Invoke-MgGraphRequest -Method POST -Uri $tapUri `
        -Body $tapBody -ContentType 'application/json' -ErrorAction Stop
    $tapCode = $tapResponse.temporaryAccessPass
    Write-OK "TAP aangemaakt (geldig 8 uur, eenmalig gebruik)."
} catch {
    Write-Waarschuwing "TAP aanmaken mislukt: $_"
    Write-Waarschuwing "Controleer of de TAP authentication method ingeschakeld is in Entra:"
    Write-Waarschuwing "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods"
    $tapCode = $null
}

#endregion

#region ── 7. Samenvatting ────────────────────────────────────────────────────

Write-Host ""
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  ACCOUNT AANGEMAAKT – GEEF ONDERSTAANDE GEGEVENS"     -ForegroundColor Magenta
Write-Host "  VEILIG DOOR AAN SPEYK (bijv. via beveiligde chat)"   -ForegroundColor Magenta
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""
Write-Host "  UPN            : $upn"
Write-Host "  ObjectId       : $($nieuwAccount.Id)"
Write-Host "  Rol            : Global Administrator"
Write-Host "  MFA            : Verplicht ($(if ($MaakConditionalAccessPolicy) {'Conditional Access'} else {'per-user enforced'}))"
Write-Host ""
Write-Host "  ─── Eerste aanmelding ───────────────────────────────"
if ($tapCode) {
    Write-Host "  Temporary Access Pass : $tapCode" -ForegroundColor Yellow
    Write-Host "  (TAP is eenmalig geldig, vervalt na 8 uur)"
    Write-Host "  Gebruik de TAP om MFA-methode te registreren."
} else {
    Write-Host "  Tijdelijk wachtwoord  : $wachtwoord" -ForegroundColor Yellow
    Write-Host "  (Wachtwoord moet worden gewijzigd bij eerste login)"
}
Write-Host ""
Write-Host "  Aanmeldportal  : https://portal.microsoft.com"
Write-Host "  MFA registratie: https://aka.ms/mfasetup"
Write-Host "══════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null
Write-OK "Graph-verbinding afgesloten."

#endregion