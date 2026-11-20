# MacBook Pro T2 (MacBookPro15,1, 2018 15") sous Kubuntu 26.04 (t2linux)

Suite du travail fait sur le 2016 (T1, [`debian13/`](../debian13/README.md)), portée sur un Mac à puce **T2**.
Base : ISO Kubuntu de [t2linux](https://wiki.t2linux.org/), noyau `7.3.5-1-t2-resolute`, KDE Plasma 6 / Wayland.

## Machine

| | |
|---|---|
| Modèle | MacBookPro15,1 (2018 15") |
| CPU | i7-8750H 6c/12t, base 2,2 GHz, turbo 4,1 GHz |
| GPU | Intel UHD 630 (i915) + Radeon Pro 555X ; écran eDP sur la **Radeon** (iGPU non utilisable, voir plus bas) |
| Disque | `/boot` ext4 séparé + LUKS2 → ext4 `/` ; macOS (APFS) gardé pour Touch ID |
| Batterie | `macsmc-battery`, seuil de charge pris en charge (`charge_control_end_threshold`) |

## Statut

| Chantier | Statut | Dossier |
|---|---|---|
| Wi-Fi, son, clavier, trackpad, veille S3 | ✅ fournis par t2linux (veille `deep` : Wi-Fi, Touch Bar, son reviennent) | — |
| **Touch Bar** | ✅ rendu t1bridge du 2016 (pages, jauges, page Énergie, touche « 100 % ») à la place de tiny-dfr ; bascule par un témoin | [`touchbar/`](touchbar/README.md) |
| **Touch ID** | ✅ `t2-touchid` (KaiT2en) + invite sur la Touch Bar ; liaison `t2_ncm` réveillée au démarrage | [`touchid/`](touchid/), [`touchbar/`](touchbar/README.md) |
| **Profils d'énergie** | ✅ réglages mesurés sur batterie (économie 2200 MHz sans turbo + EPP `balance_performance`) | [`energie/`](energie/) |
| **Seuil de charge 80 %** | ✅ au démarrage et au branchement du chargeur ; touche « 100 % » sur la Touch Bar | [`systeme/`](systeme/) |
| **Écran de démarrage** (LUKS) | ✅ thème « pomme » du 2016, corrigé pour la Touch Bar vue comme 2e écran | [`demarrage/`](demarrage/) |
| iGPU Intel pour l'écran interne | ❌ `apple-gmux` sans `force_igd` dans ce noyau ; réveil de la Radeon en D3cold → gel. Attendre la série apple-gmux/amdgpu d'André Eikmeyer | — |

## Pièges propres au T2

- **Touch ID exige une connexion macOS par mot de passe** depuis la dernière mise sous tension de la T2 (« SEP still
  locked »). Un redémarrage simple garde le déverrouillage ; un arrêt complet, un arrêt forcé ou une panique le perdent.
- **`t2_ncm` sans porteuse au démarrage** (lien CDC-NCM vers la T2, utilisé par Touch ID), que `cdc_ncm` soit chargé dans
  l'initramfs ou après : `touchid/t2-ncm-reveil` réautorise le périphérique USB (`authorized` 0/1), ce qui relance la
  négociation. Il est ordonné avant `kait2en-t2-touchid` : un `systemctl restart` de ce service doit y être `--no-block`.
- **Cycle d'ordre avec power-profiles-daemon** : Kubuntu le démarre `After=multi-user.target` ; un service
  `WantedBy=multi-user.target` qui se met `After=power-profiles-daemon` est supprimé au démarrage sans erreur visible.
- **Clavier interne à la saisie LUKS** : `t2bce_dma t2bce_core t2bce_vhci usbhid hid_generic hid_apple` dans
  `/etc/initramfs-tools/modules`.
- **Plymouth et la Touch Bar** : `appletbdrm` (60x2170) est dans l'initramfs et compte comme un écran ;
  `Window.GetWidth()` sans indice renvoie la plus petite largeur → thème centré sur 60 px. Le thème choisit le plus grand écran.
- Kubuntu n'a pas `plymouth-set-default-theme` : le thème passe par l'alternative `default.plymouth`.

## Dossiers

```
kubuntu-t2/
  energie/    mesure énergie/performance (RAPL, Radeon, batterie), résultats, service profil-energie-sync
  touchbar/   fournisseur KDE pour t1bridge, invite Touch ID (fprintd), unités, crochet de veille, README du portage
  touchid/    t2-ncm-reveil (service de démarrage)
  demarrage/  installeur du thème Plymouth « pomme » (fichiers du thème dans ../debian13/demarrage/)
  systeme/    correctifs du 20/11 (profils, t2-ncm-reveil, swapfile, règle amdgpu, i2c des écrans)
```

Le binaire t1bridge pour le T2 vient d'une branche locale `t2-port` du projet t1bridge (lecture evdev du tactile, Fn
USB, batterie `macsmc-*`) ; elle n'est pas encore exportée en correctif dans ce dépôt.
