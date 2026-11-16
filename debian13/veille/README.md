# Veille (S3) sur le MacBookPro13,3

État au 16/11/2026 : **veille S3 activée** par `install-veille.sh` (pilote amdgpu patché obligatoire).

## Installation au quotidien

`sudo bash install-veille.sh` (`annuler` pour revenir en arrière, sauvegardes dans `/root/backup-veille/installation`) :

- `sleep.conf.d/veille-s3.conf` : veille S3 autorisée, hibernation interdite (jamais testée) ;
- règle udev `90-macbook-pas-de-d3cold.rules` : aucun périphérique PCI en D3cold (sinon gel à l'endormissement) ;
- `system-sleep/veille-macbook` : rechargement de brcmfmac au réveil (Wi-Fi) ;
- `veille-garde.service` : bloque la veille (`systemd-inhibit`) si le module amdgpu patché n'est pas chargé ;
- `logind.conf.d/10-capot-verrouille.conf` : capot = veille sur batterie, verrouillage sur secteur, rien si écran externe.

Depuis, `test-veille.sh` n'est plus utilisable tel quel (il attend `pas-de-veille.conf`).

## Radeon (résolu)

Le firmware Apple place la VRAM de la Radeon Pro 455/460 à l'adresse `0x0`. Après toute réinitialisation par
Linux (réveil, reset GPU), le SMC n'arrive plus à charger les microcodes : `SMU load firmware failed`,
`UcodeLoadStatus=0x2`, écran noir. Correctif : ajouter la carte (`1002:67ef`, `106b:0166`, rév. `c7`) à
`vi_reset_quirks` (vi.c), comme les Radeon Pro 555/555X/560X déjà présentes. amdgpu réinitialise et POSTe alors la
carte au démarrage, la VRAM passe à `0xF400000000`, et le réveil comme les resets GPU réussissent.

- `patches/amdgpu-t1-smc-restart.patch` : la quirk + des traces `amdgpu-t1` (état du SMC, `need_post`, adresses).
  Le redémarrage forcé du SMC qu'il contient ne marche pas (SMC en mode protégé) : à retirer avant un envoi upstream.
- `install-amdgpu-t1.sh compiler|installer|annuler` : module hors arbre pour le noyau en cours
  (`/lib/modules/<noyau>/updates/amdgpu-t1/`). Les autres noyaux gardent le pilote d'origine.
- `test-reset-gpu.sh 0|5` : reset GPU à chaud (5 = BACO en 7.2 ; 4 = LINK, retombe en reset legacy).

## Essais

- `test-veille.sh <mode>` (sudo) : lève l'interdiction le temps d'un essai, service de secours qui la remet au
  démarrage suivant en cas de gel, réveil RTC au bout de 30 s (`WAKE=`), journal dans `/var/log/t1-sleep/`.
  Modes : 1 normal, 2 Radeon sans D3cold, 3 SSD sans D3cold, 4 **aucun périphérique PCI en D3cold** (seul mode
  qui ne gèle pas). Options : `PMTEST=devices|platform|processors|core` (veille simulée), `MEMSLEEP=s2idle`,
  `T1UNBIND=1` (appletbdrm détaché pendant la veille).
- `reparer-reveil.sh wifi|touchbar|tb` : remises en route après réveil.
- `t1-hid-feature.py [tout | 3 <octets>]` : rapports HID feature de la T1 (interface 6).

## Après un réveil (mode 4)

| Élément | État |
|---|---|
| Radeon, session, écrans externes, souris | OK |
| Wi-Fi (BCM43602) | ne s'associe plus ; OK après `reparer-reveil.sh wifi` (reload brcmfmac) |
| Touch Bar | tactile OK, écran noir jusqu'au redémarrage (t1bridge #18) ; voir « Touch Bar » ci-dessous (séquence macOS rejouée sans effet) |
| Thunderbolt (USB 3, réseau du dock) | **OK** depuis le 16/11 (hook : SXFP avant, TRPE + rescan après, 14/14, écrans et réseau du dock OK) ; sauf le côté où un chargeur est branché pendant la veille |
| Mode 1 (D3cold permis) | gel pendant l'endormissement, sans journal |

## Thunderbolt : résolu le 16/11 (`tb-go2sx.sh`, intégré au hook)

Trouvé en observant macOS 13.7.8 sur un MacBookPro14,3 (mêmes Alpine Ridge JHL6540, même SSDT) : traces
`AppleThunderboltNHIType3` activées par `boot-args="tblog=0xffff"` (posé depuis la récupération, SIP refuse sinon),
et désassemblage du kext extrait de `BootKernelExtensions.kc` (capstone ; l'objet pointe sur `vtable+0x10`).

- **Cause** : un Alpine Ridge **alimenté** pendant S3 a son firmware figé au réveil (port racine en détection,
  LTSSM `0xC74` = 0/1 au lieu de 3, LnkSta x0). Ni TRPE, ni Retrain Link, ni Secondary Bus Reset, ni Link Disable ne
  le relancent après coup. macOS l'éteint dès qu'il ne sert plus (`enablePower(0)`, runtime PM) : il passe S3 hors
  tension et redémarre à froid.
- **Correctif** (hook `system-sleep/veille-macbook`) : `pre` = retrait PCI des ponts amont (`04:00.0`, `7a:00.0`) puis
  `NHI0.SXFP(0)` (broches « force power » à 0) ; `post` = `NHI0.TRPE(1,0)` puis rescan des ports racine `00:01.1`/`.2`.
  Une veille propre ressuscite même un contrôleur figé par la précédente.
- **Limite** : un chargeur branché pendant la veille garde le contrôleur USB-C de son côté actif et fige l'Alpine
  Ridge de ce côté (PEG1 = ports gauches, PEG2 = droite). Sans conséquence pour le capot (veille sur batterie seulement).
- **Go2Sx** (`VSEC 0x500` + `0x4c` ← 5, écho attendu à + `0x48`) : macOS l'envoie, mais le firmware n'a jamais répondu
  sous Linux (ni à chaud, ni NHI en D3hot) ; inutile ici.
- `XRST` ne pose qu'un drapeau ACPI lu nulle part. `_WAK` n'appelle `ICMB` (démarrage du firmware ICM) que hors Darwin.
- ACPI décompilé avec les références externes résolues : `~/git/t1/acpi/resolu/` ; kernel collection du 14,3 :
  `~/git/t1/mac2017/`.

## Touch Bar (non résolu, 16/11)

Capture USB de la T1 sous macOS 13.7.8 (MacBookPro14,3, SIP désactivé, `ifconfig XHC20 up` + `tcpdump`,
`~/git/t1/mac2017/t1-veille.pcap` et `capture-veille.sh`). Interface 6 (hub de capteurs, SET_REPORT feature) :

| Moment | macOS | Linux |
|---|---|---|
| endormissement | rapport 3 = `01 f4 01` (garage) + CLRD ×2 ; rapport 2 = `01 02` | appletbdrm : garage + CLRD |
| réveil | **la T1 se déconnecte d'elle-même** (« connect change »), réénumération, REDY **spontané** de la T1, puis GINF/REDY/CLRD, rapport 5 = `01 00…00 0b 00…` (116 o), rapport 3 = `02 f4 01`, rapport 2 = `01 01`, images | reset-resume (même périphérique), appletbdrm_t1_rearm (GINF/REDY/CLRD), rien d'autre |

- Rejoué à l'identique (`test-t1-reveil.sh` : rapport 2 avant la veille, `persist=0` pour réénumérer, puis rapports
  5/3/2) : la T1 accepte tout, se réénumère, mais l'écran reste noir ; et le tactile est perdu (pire que sans).
- bridgeOS reste vivant après la veille (ping `fe80::aede:48ff:fe33:4455%eth0` OK, capteur de lumière OK).
- Rapports (descripteur HID) : 2 = `0x20` u8, `0x21` u8 (2 = éteint, 1 = allumé), `0x22`, `0x23` u32 (rampe
  150 → 1000) ; 3 = `0x31` état d'affichage, `0x32`, `0x50`, `0x51` u64 ; 4 = mesures en direct (pas un réglage) ;
  5 = écriture, puis relisible. L'interface 2.7 (`ff/f9/11`, DRCS) sert à Touch ID.
- Piste restante : ce qui fait redémarrer l'affichage de bridgeOS (REDY spontané) sous macOS et pas sous Linux.

## Thunderbolt et ACPI Apple (`tb-acpi.sh`, ancienne piste)

SSDT `TbtPEG12` (décompilée avec `acpidump -b` + `iasl`) : Linux répond `_OSI("Darwin")`, donc les méthodes
« macOS » sont actives. `_PS3` des ponts coupe le courant (GPIO via `UGIO`) si `RTBT`/`RUSB` = 0 ; `_PS0` ne le
remet pas ; c'est `PCED` (sur `UPSB`, `NHI0`, `XHC2`/`XHC3`) qui rallume, comme le fait macOS.

- À chaud : `tb-acpi.sh retirer` puis `rallumer` (PCED + rescan des ports racine `00:01.1`/`00:01.2`) ramène
  les 14 périphériques.
- Après une veille : `rallumer` ne fait rien (les variables ACPI en RAM disent encore « allumé »).
  `reveil` (RTPC 0 + `_PS3`, puis PCED) a provoqué un **reset complet de la machine** : ne pas l'utiliser.
- Piste : la séquence exacte du pilote macOS (`AppleThunderboltNHI`), à observer ou désassembler.
