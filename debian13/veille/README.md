# Veille (S3) sur le MacBookPro13,3

État au 16/11/2026 : la veille reste interdite (`/etc/systemd/sleep.conf.d/pas-de-veille.conf`), mais la vraie
veille S3 fonctionne avec le pilote amdgpu patché et le mode 4 de `test-veille.sh`.

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
| Touch Bar | tactile OK, écran noir jusqu'au redémarrage (t1bridge #18) ; ni le rapport HID 3 (`02` = allumé), ni le rebind d'appletbdrm, ni la coupure du port USB ne la rallument |
| Thunderbolt (USB 3, réseau du dock) | contrôleurs en D3cold « inaccessibles » ; remove/rescan les fait disparaître (écrans externes compris) |
| Mode 1 (D3cold permis) | gel pendant l'endormissement, sans journal |
