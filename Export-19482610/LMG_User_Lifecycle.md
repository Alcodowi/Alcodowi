# Cycle de vie d'un utilisateur — LMG (MIM Identity Management)

> **Environnement :** Microsoft Identity Manager (MIM) | **Exporté :** Mars 2026
> 
> Ce document décrit le cycle de vie complet d'une ressource utilisateur dans MIM : de sa création jusqu'à sa suppression définitive, en passant par toutes les étapes intermédiaires (provisionnement AD, activation, blocage, désactivation, quarantaine).

---

## Table des matières

1. [Vue d'ensemble du cycle de vie](#1-vue-densemble-du-cycle-de-vie)
2. [Phase 1 — Création et initialisation](#2-phase-1--création-et-initialisation)
3. [Phase 2 — Calcul des attributs](#3-phase-2--calcul-des-attributs)
4. [Phase 3 — Provisionnement Active Directory](#4-phase-3--provisionnement-active-directory)
5. [Phase 4 — Activation du compte](#5-phase-4--activation-du-compte)
6. [Phase 5 — Vie active de l'utilisateur](#6-phase-5--vie-active-de-lutilisateur)
7. [Phase 6 — Blocage manuel](#7-phase-6--blocage-manuel)
8. [Phase 7 — Réinitialisation du mot de passe](#8-phase-7--réinitialisation-du-mot-de-passe)
9. [Phase 8 — Désactivation (fin de contrat)](#9-phase-8--désactivation-fin-de-contrat)
10. [Phase 9 — Quarantaine et suppression](#10-phase-9--quarantaine-et-suppression)
11. [Cas particuliers selon EmployeeType](#11-cas-particuliers-selon-employeetype)
12. [Attributs clés du cycle de vie](#12-attributs-clés-du-cycle-de-vie)
13. [Référence des MPRs et Sets impliqués](#13-référence-des-mprs-et-sets-impliqués)

---

## 1. Vue d'ensemble du cycle de vie

```mermaid
flowchart TD
    SRC["📥 Source HR (iHris)\nou création manuelle MIM"]

    subgraph CREATION["🟢 PHASE 1-3 : Création"]
        C1["Entrée dans MIM\n(objet Person créé)"]
        C2["Initialisation des flags\n& attributs calculés"]
        C3["AccountName unique\nInitialPassword\nDNAD"]
        C4["Provisionnement AD\n(SyncRule → AD)"]
        C5["Notification manager\n(mot de passe initial)"]
    end

    subgraph ACTIVATION["🔵 PHASE 4 : Activation"]
        A1["J-10 avant StartDate\nou ForceEnable=True"]
        A2["Compte ACTIF\n(Visible=True, AccountEnabled)"]
        A3["O365 Licence activée"]
    end

    subgraph VIE["⚡ PHASE 5 : Vie active"]
        V1["Mises à jour attributs\n(Company, Site, Unit, Manager...)"]
        V2["Synchronisation\niHris / référentiels"]
    end

    subgraph BLOCAGE["🟠 PHASE 6 : Blocage manuel"]
        BL1["LMG_BlockAccount = True"]
        BL2["Compte désactivé\n+ Reset mot de passe (Red Button)"]
    end

    subgraph DISABLE["🔴 PHASE 7-8 : Désactivation"]
        D1["EmployeeEndDate < Aujourd'hui\n(Visible=True)"]
        D2["Compte INACTIF\n(déplacé en Quarantine OU)"]
    end

    subgraph DELETE["⚫ PHASE 9 : Suppression"]
        DEL1["EmployeeEndDate + 180 jours\n+ en OU Quarantine"]
        DEL2["Ressource supprimée de MIM\n(et AD)"]
    end

    SRC --> C1
    C1 --> C2 --> C3 --> C4 --> C5
    C5 --> A1 --> A2 --> A3
    A3 --> VIE
    VIE --> BL1
    BL1 --> BL2
    BL2 -->|"LMG_BlockAccount = False\nou ForceEnable"| A2
    VIE --> D1 --> D2
    D2 -->|"EndDate repoussée\ndans le futur"| A2
    D2 --> DEL1 --> DEL2

    style CREATION fill:#e8f5e9,stroke:#2e7d32
    style ACTIVATION fill:#e3f2fd,stroke:#1565c0
    style VIE fill:#fff9c4,stroke:#f9a825
    style BLOCAGE fill:#fff3e0,stroke:#e65100
    style DISABLE fill:#fce4ec,stroke:#c62828
    style DELETE fill:#eceff1,stroke:#37474f
```

---

## 2. Phase 1 — Création et initialisation

### Source des utilisateurs

Les utilisateurs entrent dans MIM selon deux chemins :

| Source | Mécanisme | Description |
|--------|-----------|-------------|
| **iHris (SIRH)** | Synchronisation MIM Sync | Source autoritaire pour les permanents et temporaires. Les données RH (nom, prénom, matricule, site, société, contrat) arrivent via le connecteur iHris. |
| **Création manuelle** | Portail MIM | Un administrateur ou HR crée l'objet directement dans le portail MIM. |

### Déclenchement de la création

```mermaid
flowchart LR
    NEW["Nouvel objet Person\ncréé dans MIM"]
    
    NEW -->|"Requête Create"| MPR1["📋 MPR: Init Flags\n(Request · Create)"]
    NEW -->|"Entre dans le Set"| SET1["Set: All LMG Users not admin\n/Person[not(LMG_isAdmin='true')]"]
    
    SET1 -->|"Set Transition"| MPR2["📋 MPR: User Creation\n(SetTransition)"]
    
    MPR1 --> WF1["⚡ Initialization Flags\n→ UpdateResources\n(drapeaux internes initialisés)"]
    
    MPR2 --> WF2["⚡ Set default employee end date\n→ Calcul selon EmployeeType"]
    MPR2 --> WF3["⚡ Calcul DisplayName\n→ UpdateResources + FunctionActivity"]
    MPR2 --> WF4["⚡ Calcul AccountName\n→ GenerateUniqueValue + UpdateResources"]
    MPR2 --> WF5["⚡ Generate initial password\n→ UpdateResources"]
    MPR2 --> WF6["⚡ Set AD Account Status\n→ UpdateResources"]
    MPR2 --> WF7["⚡ Set Inactive\n→ FunctionActivity (compte désactivé au départ)"]
    MPR2 --> WF8["⚡ Set Visible to True\n→ UpdateResources (rendu visible dans MIM)"]
    MPR2 --> WF9["⚡ Calcul DatetimeUTC from Enddate"]
    MPR2 --> WF10["⚡ Update ManagerID from ManagerRef"]
    
    style MPR1 fill:#fadbd8,stroke:#e74c3c
    style MPR2 fill:#fadbd8,stroke:#e74c3c
    style SET1 fill:#d6eaf8,stroke:#2980b9
```

### Ce qui se passe à la création

| Étape | Workflow | Résultat |
|-------|----------|----------|
| Drapeaux initialisés | Initialization Flags | Attributs booléens LMG positionnés à leur valeur par défaut |
| Date de fin calculée | Set default employee end date | `EmployeeEndDate` calculée selon le type de contrat |
| Nom affiché | Calcul DisplayName | `DisplayName` = Prénom + NOM, avec règles de formatage |
| Nom de compte | Calcul AccountName | `AccountName` unique généré (`GenerateUniqueValue`), ex. `jdupont` |
| Mot de passe initial | Generate initial password | `InitialPassword` généré et stocké temporairement dans MIM |
| Statut AD | Set AD Account Status | `AccountEnabled` positionné dans MIM |
| Compte inactif | Set Inactive | Compte démarré **inactif** (FunctionActivity) |
| Visible | Set Visible to True | `Visible = True` dans MIM |
| ManagerID | Update ManagerID From ManagerRef | Lien bidirectionnel Manager/ManagerRef synchronisé |

> 💡 **Point important :** À la création, le compte est **inactif** (`Set Inactive`). Il ne sera activé qu'à J-10 avant la `EmployeeStartDate`.

---

## 3. Phase 2 — Calcul des attributs

Après la création, plusieurs MPRs de type **Request** se déclenchent automatiquement pour calculer les attributs dérivés dès que les données sources sont disponibles.

```mermaid
flowchart TD
    U["👤 Objet Person dans MIM"]
    
    U -->|"Company_ID renseigné"| R1["📋 !LMG - User : Update LMG_CompanyRef when company_ID is updated\n→ Set LMG_Company from Company_ID\n→ Set Company Attributes from LMG_CompanyRef"]
    U -->|"LMG_SiteID ou SiteCode renseigné"| R2["📋 !LMG - User : Update LMG_SiteRef when LMG_SiteID Change\n→ Set LMG_SiteRef from SiteID or SiteCode\n→ Set Site attributes from LMG_SiteRef"]
    U -->|"LMG_UnitCode renseigné"| R3["📋 !LMG - User : Update LMG_Unit when LMG_UnitCode Change\n→ Set LMG_Unit from LMG_UnitCode\n→ Set Unit attributes from LMG_UnitRef"]
    U -->|"Prénom ou Nom modifié"| R4["📋 !LMG - User : Update FirstName LastName\n→ Calcul DisplayName\n→ Calcul Email"]
    U -->|"LMG_CompanyRef modifié"| R5["📋 !LMG - User : Update Company Attributes when LMG_CompanyRef Change\n→ Calcul Email (domain @company)"]
    U -->|"ManagerRef modifié"| R6["📋 !LMG - User : Update ManagerID From ManagerRef\n→ ManagerID synchronisé"]
    U -->|"EmployeeEndDate modifié"| R7["📋 !LMG - User : Define Enddate UTC Windows from Enddate\n→ Calcul DatetimeUTC from Enddate"]
    U -->|"EmployeeType modifié"| R8["📋 !LMG - User : Modification EmployeeType\n→ Set default employee end date"]
    U -->|"LMG_PreferredLanguageRef modifié"| R9["📋 !LMG - User : Change PreferredLanguage when LMG_PreferredLanguageRef Change\n→ Update PreferredLanguage"]
    U -->|"Photo modifiée"| R10["📋 !LMG - User : Update Photo To Entra ID\n→ PowerShell → Upload vers Entra ID"]

    style U fill:#d6eaf8,stroke:#2980b9
```

### Chaîne de résolution des référentiels

```mermaid
flowchart LR
    iHris["iHris (RH)"] -->|"Company_ID\nSiteCode / SiteID\nUnitCode"| MIM["MIM Person"]
    MIM -->|"LMG_CompanyRef"| CMP["Objet Company\n(attributs copiés\nsur Person)"]
    MIM -->|"LMG_SiteRef"| SIT["Objet Site\n(Country, Cluster, City\ncopiés sur Person)"]
    MIM -->|"LMG_UnitRef"| UNT["Objet Unit / BL\n(attributs copiés\nsur Person)"]
    CMP & SIT & UNT -->|"Email calculé\nDisplayName mis à jour"| OUT["Attributs finaux\nprêts pour AD"]
```

---

## 4. Phase 3 — Provisionnement Active Directory

Une fois que l'objet a ses attributs calculés (AccountName, mot de passe initial, DNAD), il entre automatiquement dans le set de provisionnement.

```mermaid
flowchart LR
    COND["Conditions remplies :\n✅ AccountName calculé\n✅ InitialPassword généré\n✅ DNAD renseigné\n✅ Non dans le Set Admin"]

    COND --> SET2["Set: All LMG users Ready for AD provisioning\n/Person[starts-with(AccountName,'%')\nand starts-with(InitialPassword,'%')\nand starts-with(DNAD,'%')\nand not(LMG_RestoreAccount=True)]"]

    SET2 -->|"Set Transition (entrée)"| MPR3["📋 MPR: Provisioning to AD\n(SetTransition)"]
    MPR3 --> WF11["⚡ Provisioning to AD\n→ SynchronizationRuleActivity\n(Règle de sync outbound → AD)"]

    WF11 --> AD["Active Directory\n(objet créé dans l'OU cible)"]
    
    SET2B["Set: All LMG Users in EntraID\n/Person[LMG_mS-DS-ConsistencyGuid='True']"]
    AD -->|"GUID de consistance\ncommuniqué par AAD Connect"| SET2B
    SET2B -->|"Set Transition"| MPR4["📋 MPR: Set ADaccountstatus\n(SetTransition)"]
    MPR4 --> WF12["⚡ Set ADAccountStatus\n→ UpdateResources"]

    style COND fill:#d5f5e3,stroke:#27ae60
    style AD fill:#e8d5ff,stroke:#9b59b6
    style MPR3 fill:#fadbd8,stroke:#e74c3c
    style MPR4 fill:#fadbd8,stroke:#e74c3c
```

### Notification initiale au manager

Dès que le mot de passe initial est généré et l'utilisateur visible :

```mermaid
flowchart LR
    SET3["Set: All users with initial password\n/Person[starts-with(InitialPassword,'%')\nand starts-with(DisplayName,'%')\nand Visible=True]"]
    SET3 -->|"Set Transition"| MPR5["📋 MPR: Notification - Manager new user\n(SetTransition)"]
    MPR5 --> WF13["⚡ Notification Manager new user password\n→ AddDelay ⏱️\n→ RunPowerShellScript 📧\n(email au manager avec mot de passe)"]

    style MPR5 fill:#fadbd8,stroke:#e74c3c
```

> ⏱️ Le workflow inclut un **délai** avant l'envoi, pour s'assurer que l'account AD est prêt.

---

## 5. Phase 4 — Activation du compte

Le compte démarre **inactif**. Il est activé automatiquement via deux mécanismes :

### Mécanisme 1 — Activation automatique J-10

```mermaid
flowchart LR
    SET4["Set: Users - Start Date is in 10 days\n/Person[\nEmployeeStartDate < now()+10j\nand Visible=True]"]
    SET4 -->|"Set Transition (entrée)"| MPR6["📋 MPR: Activate User\n(SetTransition)"]
    MPR6 --> WF14["⚡ Set Active\n→ FunctionActivity\n(compte activé dans MIM et AD)"]

    style MPR6 fill:#fadbd8,stroke:#e74c3c
    style SET4 fill:#d6eaf8,stroke:#2980b9
```

### Mécanisme 2 — Activation forcée (ForceEnable)

```mermaid
flowchart LR
    FLAG["Admin pose :\nLMG_ForceEnable = True"]
    FLAG --> SET5["Set: All LMG Users not admin With ForceEnable to True\n/Person[LMG_ForceEnable=True]"]
    SET5 -->|"Set Transition"| MPR7["📋 MPR: Activate user - Force Enabled\n(SetTransition)"]
    MPR7 --> WF15["⚡ Activate O365 Licence\n→ UpdateResources × 3\n(licence O365 positionnée)"]
    MPR7 --> WF14B["⚡ Set Active\n→ FunctionActivity"]

    style MPR7 fill:#fadbd8,stroke:#e74c3c
    style FLAG fill:#fdebd0,stroke:#e67e22
```

---

## 6. Phase 5 — Vie active de l'utilisateur

Pendant la vie active, les MPRs surveillent les modifications d'attributs et propagent les changements en cascade.

```mermaid
flowchart TD
    USER["👤 Utilisateur actif dans MIM + AD"]

    USER -->|"Changement Company"| C["📋 !LMG - User : Update Company Attributes when LMG_CompanyRef Change\n→ Set Company Attributes from CompanyRef\n→ Recalcul Email"]
    USER -->|"Changement Site / SiteID"| S["📋 !LMG - User : Update Site attribute when LMG_SiteRef change\n→ Set LMG_SiteRef\n→ Set Site attributes\n(Country, City, Cluster mis à jour)"]
    USER -->|"Changement Unit / UnitCode"| U["📋 !LMG - User : Update Unit attributes when LMG_UnitRef change\n→ Set LMG_Unit\n→ Set Unit attributes"]
    USER -->|"Changement Manager"| M["📋 !LMG - User : Update Manager Refence From ManagerID\n→ ManagerRef ↔ ManagerID sync"]
    USER -->|"Changement Prénom/Nom"| N["📋 !LMG - User : Update FirstName LastName\n→ Recalcul DisplayName + Email"]
    USER -->|"Changement EmployeeEndDate"| E["📋 !LMG - User : Define Enddate UTC Windows from Enddate\n→ Calcul horodatage UTC"]
    USER -->|"Licence O365 modifiée"| L["📋 !LMG - User : Modification O365 Licence\n→ Activate O365 Licence\n→ Calcul Email"]
    USER -->|"Photo modifiée"| P["📋 !LMG - User : Update Photo To Entra ID\n→ PowerShell upload vers Entra ID"]
    USER -->|"LMG_PreferredLanguageRef"| PL["📋 !LMG - User : Change PreferredLanguage when LMG_PreferredLanguageRef Change\n→ Update PreferredLanguage"]
    USER -->|"LMG_GroupMemberOf modifié"| G["📋 !LMG - User : Add users to group\n→ Gestion adhésion aux groupes MIM"]

    style USER fill:#d5f5e3,stroke:#27ae60
```

### Particularité — Utilisateurs Permanent internes sans date de départ

```mermaid
flowchart LR
    SET6["Set: Internal Permanent with endDate without user_departure\n/Person[\nEmployeeType='Internal Permanent'\nand EmployeeEndDate > 2013-12-31\nand User_Departure=False\nand Visible=True]"]
    SET6 -->|"Set Transition"| MPR8["📋 MPR: Internal Permanent with endDate\n(SetTransition)"]
    MPR8 --> WF16["⚡ Set Internal Permanent end date\n→ UpdateResources\n(fixe une date de fin standard\npour les permanents sans départ déclaré)"]

    style MPR8 fill:#fadbd8,stroke:#e74c3c
```

---

## 7. Phase 6 — Blocage manuel

Un administrateur ou RH peut bloquer manuellement un compte sans attendre la date de fin.

```mermaid
flowchart TD
    ADMIN["👤 Administrateur / RH"]
    ADMIN -->|"Pose le flag"| FLAG2["LMG_BlockAccount = True"]
    
    FLAG2 --> SET7["Set: All LMG Users Not Admin with LMG_BlockAccount to True\n/Person[LMG_BlockAccount=True]"]
    
    SET7 -->|"Set Transition (entrée)"| MPR9["📋 !LMG - User : Block Account and Force Reset Password\n(SetTransition)"]
    MPR9 --> WF17["⚡ Set Inactive\n→ FunctionActivity (compte désactivé)"]
    MPR9 --> WF18["⚡ Reset AD User Password - Red Button\n→ UpdateResources + PowerShell\n(mot de passe réinitialisé d'urgence)"]
    
    FLAG2 --> AUTH["📋 !LMG - User : Block Account Activation if LMG_BlockAccount is True\n(Request · Modify)\n→ Workflow AuthZ bloque\ntout tentative d'activation\ntant que LMG_BlockAccount=True"]
    
    REVERT["Admin pose :\nLMG_BlockAccount = False\nou LMG_ForceEnable = True"]
    REVERT -->|"Quitte le Set"| REACTIVE["→ Phase 4 : Réactivation\n(ForceEnable)"]

    style MPR9 fill:#fadbd8,stroke:#e74c3c
    style FLAG2 fill:#fdebd0,stroke:#e65100
    style REVERT fill:#d5f5e3,stroke:#27ae60
```

---

## 8. Phase 7 — Réinitialisation du mot de passe AD

```mermaid
flowchart LR
    FLAG3["Admin / HR pose :\nResetADAccount = True"]
    FLAG3 --> SET8["Set: Users - Reset AD User\n/Person[ResetADAccount=True and Visible=True]"]
    SET8 -->|"Set Transition"| MPR10["📋 MPR: Reset AD User Password\n(SetTransition)"]
    MPR10 --> WF19["⚡ Reset AD User Password\n→ UpdateResources\n→ PowerShell (reset dans AD)"]
    MPR10 --> WF20["⚡ Notification Manager Reset Password\n→ UpdateResources\n(email au manager)"]

    style MPR10 fill:#fadbd8,stroke:#e74c3c
    style FLAG3 fill:#fdebd0,stroke:#e67e22
```

---

## 9. Phase 8 — Désactivation (fin de contrat)

La désactivation est **automatique**, pilotée par la `EmployeeEndDate`.

```mermaid
flowchart TD
    TIMER["🕐 Date actuelle > EmployeeEndDate\net Visible = True"]
    
    TIMER --> SET9["Set: Users - End Date was 1 day ago\n/Person[\nEmployeeEndDate < now()\nand Visible=True]"]
    
    SET9 -->|"Set Transition (entrée)"| MPR11["📋 !LMG - User : Disable User\n(SetTransition)"]
    MPR11 --> WF21["⚡ Set Inactive\n→ FunctionActivity\n(compte désactivé dans MIM + AD)"]
    WF21 --> AD_DISABLE["AD : compte désactivé\nmis en OU Quarantine"]

    SET9 -->|"Set Transition (sortie)\nsi EndDate repoussée"| MPR12["📋 !LMG - User : Set Active if EndDate is changed in future.\n(SetTransition)"]
    MPR12 --> WF22["⚡ Set Active\n→ FunctionActivity (réactivation)"]

    style MPR11 fill:#fadbd8,stroke:#e74c3c
    style MPR12 fill:#fadbd8,stroke:#e74c3c
    style AD_DISABLE fill:#e8d5ff,stroke:#9b59b6
    style TIMER fill:#fce4ec,stroke:#c62828
```

> 🔄 **Réversibilité :** Si la `EmployeeEndDate` est repoussée dans le futur, le compte quitte le set « End Date was 1 day ago » et la MPR `Set Active if EndDate is changed in future` se déclenche pour **réactiver** le compte automatiquement.

---

## 10. Phase 9 — Quarantaine et suppression

Après désactivation, l'utilisateur entre en période de **rétention de 180 jours** avant suppression définitive.

```mermaid
flowchart TD
    Q1["Compte inactif\nen OU Quarantine dans AD"]
    
    Q1 --> WAIT["⏳ Attente 180 jours après EmployeeEndDate"]
    
    WAIT --> SET10["Set: Users - EmployeeEndDate +180 days\n/Person[\nEmployeeEndDate > now()+180j\nand DN ends with OU=Quarantine,...\nand Visible=True]"]
    
    SET10 -->|"Set Transition"| MPR13["📋 ## Users - Delete User (+180 days)\n⛔ DISABLED actuellement\n(SetTransition)"]
    
    MPR13 --> WF23["⚡ Delete User (+180 days)\n→ DeleteResources\n(suppression définitive dans MIM + AD)"]

    style Q1 fill:#eceff1,stroke:#37474f
    style WAIT fill:#eceff1,stroke:#37474f
    style MPR13 fill:#bdbdbd,stroke:#616161
    style SET10 fill:#eceff1,stroke:#37474f
```

> ⚠️ **Note importante :** La MPR de suppression (`## Users - Delete User (+180 days)`) est actuellement **désactivée** (`Disabled = True`). Les suppressions ne se font donc pas automatiquement dans l'état actuel. Une action manuelle ou une réactivation de cette MPR est nécessaire pour purger les comptes expirés.

---

## 11. Cas particuliers selon EmployeeType

Le type de contrat (`EmployeeType`) influence directement la gestion de la `EmployeeEndDate`.

```mermaid
flowchart TD
    ET{"EmployeeType ?"}

    ET -->|"Permanent\n(source iHris)"| PERM["MPR: Erase EmployeeEndDate From iHris Permanent Users\nSet Transition : quitte le Set\n'Permanent Users with EmployeeEndDate'\n→ Erase employeeEndDate (Permanent)\n→ EmployeeEndDate supprimée\n(compte sans date de fin = permanent)"]

    ET -->|"Temporary\n(source iHris)"| TEMP["MPR: Erase EmployeeEndDate From iHris Temporary Users\nSet Transition : quitte le Set\n'Temporary Users with EmployeeEndDate'\n→ Erase employeeEndDate (Temporary)\n→ EmployeeEndDate conservée\n(date de fin maintenue)"]

    ET -->|"Internal Permanent\n(sans date de départ)"| INTPERM["MPR: Internal Permanent with endDate\nSet: /Person[EmployeeType='Internal Permanent'\nand EmployeeEndDate > 2013-12-31\nand User_Departure=False]\n→ Set Internal Permanent end date\n(date de fin standard calculée)"]

    style PERM fill:#d5f5e3,stroke:#27ae60
    style TEMP fill:#fff9c4,stroke:#f9a825
    style INTPERM fill:#e3f2fd,stroke:#1565c0
```

### iHris Export

Les utilisateurs éligibles sont exportés vers iHris selon :

```mermaid
flowchart LR
    SET11["Set: All LMG users for iHris export\n(critères iHris définis par filtre)"]
    SET11 -->|"Set Transition"| MPR14["📋 MPR: iHris Export\n(SetTransition)"]
    MPR14 --> WF24["⚡ iHris Export\n→ UpdateResources\n(données renvoyées vers iHris)"]

    style MPR14 fill:#fadbd8,stroke:#e74c3c
```

---

## 12. Attributs clés du cycle de vie

| Attribut | Type | Rôle dans le cycle de vie |
|----------|------|---------------------------|
| `EmployeeStartDate` | DateTime | Date d'activation automatique (J-10) |
| `EmployeeEndDate` | DateTime | Date de désactivation automatique |
| `EmployeeType` | String | `Permanent` / `Temporary` / `Internal Permanent` — pilote la gestion de la date de fin |
| `Visible` | Boolean | `True` = utilisateur actif et visible dans MIM. Passe à `False` à la désactivation |
| `AccountName` | String | Login AD (sAMAccountName). Généré de manière unique à la création |
| `InitialPassword` | String | Mot de passe initial stocké temporairement dans MIM |
| `DNAD` | String | Distinguished Name cible dans AD (ex. `CN=jdupont,OU=FR,...`) |
| `LMG_BlockAccount` | Boolean | Flag de blocage manuel. `True` → désactivation immédiate + reset mot de passe |
| `LMG_ForceEnable` | Boolean | Flag de forçage d'activation. `True` → activation immédiate + licence O365 |
| `ResetADAccount` | Boolean | Flag de réinitialisation mot de passe AD. `True` → reset + notification manager |
| `User_Departure` | Boolean | Indique un départ déclaré (pour les permanents internes) |
| `LMG_mS-DS-ConsistencyGuid` | String | GUID de consistance pour AAD Connect. Présence = utilisateur dans Entra ID |
| `LMG_CompanyRef` | Reference | Référence vers l'objet Company (source des attributs entreprise) |
| `LMG_SiteRef` | Reference | Référence vers l'objet Site (source : Country, City, Cluster...) |
| `LMG_UnitRef` | Reference | Référence vers l'objet Unit / BL |
| `LMG_GroupMemberOf` | MultiValue | Groupes MIM dont l'utilisateur doit être membre |
| `DisplayName` | String | Nom affiché, calculé depuis Prénom + NOM + règles de formatage |
| `AccountEnabled` | Boolean | Statut d'activation du compte AD |

---

## 13. Référence des MPRs et Sets impliqués

### MPRs du cycle de vie principal

| Phase | MPR | Type | Déclencheur / Set |
|-------|-----|------|-------------------|
| Création | `!LMG - User : Init Flags` | Request (Create) | Toute création d'objet Person |
| Création | `!LMG - User : User Creation` | SetTransition | Entre dans `All LMG Users not admin` |
| Création | `!LMG - User : Check Integrity Creation` | Request (Create) | Validation à la création |
| Création | `!LMG - User : Check Integrity Modification` | Request (Modify) | Validation des modifications |
| Attributs | `!LMG - User : Update LMG_CompanyRef when company_ID is updated` | Request (Create/Modify) | `company_ID` modifié |
| Attributs | `!LMG - User : Update LMG_SiteRef when LMG_SiteID Change` | Request (Create/Modify) | `LMG_SiteID` modifié |
| Attributs | `!LMG - User : Update LMG_Unit when LMG_UnitCode Change` | Request (Create/Modify) | `LMG_UnitCode` modifié |
| Attributs | `!LMG - User : Update Company Attributes when LMG_CompanyRef Change` | Request (Create/Modify) | `LMG_CompanyRef` modifié |
| Attributs | `!LMG - User : Update Site attribute when LMG_SiteRef change` | Request (Modify) | `LMG_SiteRef` modifié |
| Attributs | `!LMG - User : Update Unit attributes when LMG_UnitRef change` | Request (Create/Modify) | `LMG_UnitRef` modifié |
| Attributs | `!LMG - User : Update FirstName LastName` | Request (Modify) | Prénom ou Nom modifié |
| Attributs | `!LMG - User : Update Manager Refence From ManagerID` | Request (Modify) | `ManagerID` modifié |
| Attributs | `!LMG - User : Update ManagerID From ManagerRef` | Request (Create/Modify) | `ManagerRef` modifié |
| Attributs | `!LMG - User : Define Enddate UTC Windows from Enddate` | Request (Modify) | `EmployeeEndDate` modifié |
| Attributs | `!LMG - User : When EndDate and StartDate Change` | Request (Modify) | `EndDate`/`StartDate` modifié |
| Attributs | `!LMG - User : Modification EmployeeType` | Request (Modify) | `EmployeeType` modifié |
| Attributs | `!LMG - User : Modification O365 Licence` | Request (Modify/Create) | Licence O365 modifiée |
| Attributs | `!LMG - User : Update Photo To Entra ID` | Request (Modify) | `Photo` modifiée |
| Attributs | `!LMG - User : Change PreferredLanguage when LMG_PreferredLanguageRef Change` | Request (Modify) | Langue modifiée |
| Attributs | `!LMG - User : MailDomain change` | Request (Modify) | `MailDomain` modifié |
| Provisionnement | `!LMG - User : Provisioning to AD` | SetTransition | Entre dans `Ready for AD provisioning` |
| Provisionnement | `!LMG - User : Set ADaccountstatus` | SetTransition | Entre dans `All LMG Users in EntraID` |
| Provisionnement | `!LMG - User : Update Site attribute when LMG_SiteRef change - Creation` | SetTransition | Entre dans `users not admin with AccountName` |
| Notification | `!LMG - User : Notification - Manager new user` | SetTransition | Entre dans `All users with initial password` |
| Activation | `!LMG - User : Activate User` | SetTransition | Entre dans `Start Date is in 10 days` |
| Activation | `!LMG - User : Activate user - Force Enabled` | SetTransition | Entre dans `ForceEnable to True` |
| Blocage | `!LMG - User : Block Account and Force Reset Password` | SetTransition | Entre dans `LMG_BlockAccount to True` |
| Blocage | `!LMG - User : Block Account Activation if LMG_BlockAccount is True` | Request (Modify) | AuthZ : bloque activation si BlockAccount=True |
| Reset MDP | `!LMG - User : Reset AD User Password` | SetTransition | Entre dans `Reset AD User` |
| Unlock | `!LMG - User :  Unlock AD User` | SetTransition | Entre dans `Unlock AD User` |
| Désactivation | `!LMG - User : Disable User` | SetTransition | Entre dans `End Date was 1 day ago` |
| Réactivation | `!LMG - User : Set Active if EndDate is changed in future.` | SetTransition | Quitte `End Date was 1 day ago` |
| Suppression | `## Users - Delete User (+180 days)` ⛔ | SetTransition | Entre dans `EmployeeEndDate +180 days` |
| Permanent | `!LMG - User : Erase EmployeeEndDate From iHris Permanent Users` | SetTransition | Quitte `Permanent Users with EmployeeEndDate` |
| Temporaire | `!LMG - User : Erase EmployeeEndDate From iHris Temporary Users` | SetTransition | Quitte `Temporary Users with EmployeeEndDate` |
| Interne Perm. | `!LMG - User : Internal Permanent with endDate without user_departure` | SetTransition | Entre dans `Internal Permanent with endDate` |

---

*Documentation générée à partir de l'export policy.xml du service MIM — Mars 2026*
