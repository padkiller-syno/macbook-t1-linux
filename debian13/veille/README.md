# Veille (S3) sur le MacBookPro13,3

État au 16/11/2026 : **veille S3 activée** par `install-veille.sh` (pilote amdgpu patché obligatoire).

## Installation au quotidien

`sudo bash install-veille.sh` (`annuler` pour revenir en arrière, sauvegardes dans `/root/backup-veille/installation`) :

- `sleep.conf.d/veille-s3.conf` : veille S3 autorisée, hibernation interdite (jamais testée) ;
- règle udev `90-macbook-pas-de-d3cold.rules` : aucun périphérique PCI en D3cold (sinon gel à l'endormissement) ;
- `system-sleep/veille-macbook` : Thunderbolt éteint/rallumé, T1 prévenue par le SMC (`SOCW`) et Touch Bar
  « dégarée », rechargement de brcmfmac au réveil (Wi-Fi) ;
- son : `/lib/firmware/hda-macbook13-3.patch` + `/etc/modprobe.d/veille-macbook-son.conf` (option `patch=` de
  snd-hda-intel) et `son-recharger.sh`, lancé 3 s après le réveil (unité `veille-son`) ;
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
- `t1-socw.sh etat|0|1` : appel ACPI `ASOC.SOCW` à la main (signal veille/réveil à la T1 par le SMC).
- `test-t1-reveil.sh` : ancien essai (séquence HID macOS + réénumération), inutile depuis `SOCW` ; perd le tactile.

## Après un réveil (mode 4)

| Élément | État |
|---|---|
| Radeon, session, écrans externes, souris | OK |
| Wi-Fi (BCM43602) | 2,4 GHz OK ; **5 GHz refusé jusqu'au redémarrage**, voir « Wi-Fi 5 GHz » ci-dessous |
| Son, micros | **OK** depuis le 16/11 (`son-recharger.sh`), voir « Son » ci-dessous |
| Touch Bar, Touch ID | **OK** depuis le 16/11 (hook : `SOCW` + rapport 3 = `02 f4 01`), voir « Touch Bar » ci-dessous |
| Thunderbolt (USB 3, réseau du dock) | **OK** depuis le 16/11 (hook : SXFP avant, TRPE + rescan après, 14/14, écrans et réseau du dock OK) ; sauf le côté où un chargeur est branché pendant la veille |
| Mode 1 (D3cold permis) | gel pendant l'endormissement, sans journal |

## Son : résolu le 16/11 (`son-recharger.sh` + `hda-macbook13-3.patch`)

- **Symptôme** : après S3, plus de son ni de micro (PipeWire en lecture, rien ne sort ; capture figée).
- **Cause** : le pilote `snd_hda_macbookpro` ne configure les puces voisines du CS8409 (amplis MAX98706, CS42L83,
  micros, en I2C) qu'au démarrage du codec (`cs_8409_apple_boot_init`) ; son `resume` ne le refait pas. Et un
  codec remis à zéro perd ce que l'EFI y a écrit : identifiant Apple `0x106b3900` et broches → « UNKNOWN
  subsystem id », probe en `-22`, pilote générique sans sorties.
- **Correctif** : `hda-macbook13-3.patch` (identifiant + 34 broches relevées après démarrage, appliqué à chaque
  détection par l'option `patch=` de snd-hda-intel) ; au réveil, `son-recharger.sh` détache le seul contrôleur
  `00:1f.3`, recharge `snd_hda_codec_cs8409` et le rattache, **3 s après, hors du hook** (`systemd-run`).
- **Pièges** : détacher aussi le HDMI de la Radeon (`01:00.1`) juste après le réveil a figé la machine (écran
  noir) ; snd_hda_intel ne réutilise pas les numéros de carte (32 max par chargement) → ~30 veilles par démarrage.

## Wi-Fi 5 GHz : non résolu (16/11)

- Après S3, la Freebox 5 GHz est refusée (`ASSOC-REJECT status 16`, bssid = dernier point d'accès utilisé) ;
  le 2,4 GHz passe ; seul un redémarrage répare.
- Cause 1 (contournée) : une borne voisine du même réseau annonçait le pays GB → canal DFS 116 en « No IR ».
- Cause 2 : la puce n'est **jamais mise hors tension sous Linux** : DSDT `RP01.APPD/APPU`, `DPWR` (`EC.APWC`)
  et `DRST` (GPIO `0x01000012`) ne font rien hors macOS (`If (!OSDW ())`). Elle garde son état : sans effet =
  rechargement de brcmfmac (ou déchargement avant veille, hook actuel), reset PCI, `feature_disable=0x82000`,
  rechargement de cfg80211, redémarrage de wpa_supplicant/NetworkManager.
- À essayer : couper l'alimentation comme macOS (`APWC` = bit 3 du registre EC `0x03`, via `ec_sys`).
- Outils : `wifi-photo.sh` (photo de l'état), `test-wifi-reset.sh`, `test-wifi-apres-veille.sh`.

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

## Touch Bar : résolu le 16/11 (`t1-socw.sh`, intégré au hook)

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
- **Cause** : macOS prévient la T1 **par le SMC** de la veille et du réveil. Le pilote `AppleEmbeddedOSSupportHost`
  (kext de `SystemKernelExtensions.kc`, rattaché à l'ACPI `APP7777` = `\_SB.PCI0.XHC1.RHUB.ASOC`, SSDT8) appelle
  `ASOC.SOCW(0)` sur `kIOMessageSystemWillSleep` (`0xe0000280`) et `SOCW(1)` sur `kIOMessageSystemHasPoweredOn`
  (`0xe0000320`), journal `log show --predicate 'sender == "AppleEmbeddedOSSupportHost"'`. `SOCW` appelle `MBOX`
  (DSDT : commande dans l'EC `INDX`/`DATA`/`CMDS` puis poignée de main GPIO `0x0106000A`/`0x0106000F`, active si
  `MBXC` ≠ 0, ici 2) : `SOCW(0)` = `MBOX(1)`, `SOCW(1)` = `MBOX(6)` puis `MBOX(2)`. Linux ne l'appelait jamais.
- Sans `SOCW(1)`, tout a l'air normal côté USB : REDY, images acceptées (`UDCL` avec horodatage valide), rapports HID
  « allumé »… mais la dalle reste noire. `SOCW(1)` à la main : `0x0` en 82 ms (88 ms sous macOS), dalle rallumée.
- Il faut aussi « dégarer » : appletbdrm envoie rapport 3 = `01 f4 01` à l'endormissement, et rien ne le défait →
  dalle allumée mais à luminosité minimale (rapport 3 = `01`, rapport 4 à zéro). macOS envoie `02 f4 01` au réveil.
- Touch ID marche aussi après le réveil (le masquage de fprintd est retiré du hook).
- La réénumération (`persist=0`) et les rapports 2/5 de macOS sont inutiles.

## Thunderbolt et ACPI Apple (`tb-acpi.sh`, ancienne piste)

SSDT `TbtPEG12` (décompilée avec `acpidump -b` + `iasl`) : Linux répond `_OSI("Darwin")`, donc les méthodes
« macOS » sont actives. `_PS3` des ponts coupe le courant (GPIO via `UGIO`) si `RTBT`/`RUSB` = 0 ; `_PS0` ne le
remet pas ; c'est `PCED` (sur `UPSB`, `NHI0`, `XHC2`/`XHC3`) qui rallume, comme le fait macOS.

- À chaud : `tb-acpi.sh retirer` puis `rallumer` (PCED + rescan des ports racine `00:01.1`/`00:01.2`) ramène
  les 14 périphériques.
- Après une veille : `rallumer` ne fait rien (les variables ACPI en RAM disent encore « allumé »).
  `reveil` (RTPC 0 + `_PS3`, puis PCED) a provoqué un **reset complet de la machine** : ne pas l'utiliser.
- Piste : la séquence exacte du pilote macOS (`AppleThunderboltNHI`), à observer ou désassembler.
