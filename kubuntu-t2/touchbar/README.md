# Touch Bar t1bridge sur le MacBook Pro T2 (MacBookPro15,1, Kubuntu 26.04, KDE Plasma 6)

Portage du rendu Touch Bar de t1bridge (celui du 2016) sur le T2, à la place de tiny-dfr.
Source : `~/git/t1/t1bridge`, branche locale **`t2-port`** (issue de `macbook-local`), commit `3d4cc39` du 20/11.
Jamais poussée (le seul distant est le projet d'origine).

## Ce qui change par rapport à la T1

| Élément | T1 (2016) | T2 | Adaptation |
|---|---|---|---|
| Écran | DRM `appletbdrm`, 60x2170 portrait, XRGB8888 | idem (`card0`) | aucune, même rotation |
| Tactile | hidraw 05ac:8600, rapport de 52 octets | evdev hid-multitouch « Apple Inc. Touch Bar Display Touchpad » (05ac:8302), mêmes plages X 0-32767 / Y 0-127, 10 contacts | lecture evdev convertie en rapport T1 (`t1_touchbar_digitizer.c`) |
| Touche Fn | « Apple SPI Keyboard » (SPI) | « Apple Inc. Apple Internal Keyboard / Trackpad » (USB) | les deux acceptés (`t1_touchbar_fn.c`) |
| Rétroéclairage Touch Bar | rapport HID de la T1 | `appletb_backlight` (0-2, géré par `hid_appletb_kbd` : atténuation à 60 s, extinction 15 s après) | mis à 2 au démarrage du service (`ExecStartPre`) ; exclu de la recherche de l'écran |
| Luminosité écran | `gmux_backlight` | `gmux_backlight` | identique (pas de la Touch Bar par logind) |
| Clavier | `spi::kbd_backlight` | `:white:kbd_backlight` (recréé à chaque réveil) | trouvé par nom ; réglage par logind |
| Batterie / secteur | `BAT0` / `ADP1` | `macsmc-battery` / `macsmc-ac` | trouvés par type |
| Bureau | GNOME (gsd-power, Mutter, dconf) | KDE : PowerDevil `org.kde.ScreenBrightness`, KWin Night Color, `pactl` | `t1-desktop-provider-kde` + `native_status.rs` |

Pièges vus pendant le portage :
- **Sortie audio par défaut** : sur le T2, `wpctl status` ne marque aucune sortie par `*`, parce que la sortie par défaut est
  un filtre (DSP des haut-parleurs d'`apple-t2-audio-config`). `pactl list short sinks` donne les vraies sorties. Un casque
  débranché est « not available » : WirePlumber le refuse et revient sur la sortie précédente, il faut donc le sauter.
- **Veilleuse KWin 6.6** : `kwinrc` `[NightColor] Active` + `kwriteconfig6 --notify` (sans `--notify`, ni `reconfigure` ni
  rien d'autre ne la fait relire). État : `org.kde.KWin /org/kde/KWin/NightLight` propriété `enabled`.
- **Clavier après veille** : la LED est recréée et PowerDevil garde l'ancienne (réglage sans effet). Le fournisseur écrit
  donc par logind (`SetBrightness leds`). Il faut l'appeler depuis la session graphique (unité utilisateur) : depuis SSH,
  « Your session has no seat ».
- **Veille** : au réveil, le tactile est réinitialisé et `t1-touchbar-hw` sort en erreur. Une remise en veille pendant
  sa relance n'est **jamais revenue** (20/11 13:58, arrêt forcé). D'où le crochet `t1bridge-touchbar-sleep`, qui arrête le
  socket et le service avant la veille et les relance après. Testé OK le 20/11 à 14:15.
- Pas de luminosité automatique dans Plasma (le capteur `als` existe en iio) : bouton « auto » masqué. « Effets »
  (EasyEffects) masqué aussi.

## État depuis le 20/11 ~14:30 : t1bridge permanent

Bascule par le **témoin `/etc/t1bridge/touchbar-t1bridge`** : présent = t1bridge, absent = tiny-dfr.
- `/etc/systemd/system/tiny-dfr.service.d/t1bridge.conf` : `ConditionPathExists=!/etc/t1bridge/touchbar-t1bridge`
  (`tiny-dfr.service` est un fichier de `/etc/systemd/system`, livré tel quel par le paquet, donc `mask` est impossible) ;
- `/etc/systemd/system/t1-touchbar-hw.{service,socket}.d/condition.conf` : `ConditionPathExists=/etc/t1bridge/touchbar-t1bridge` ;
- `t1-touchbar-hw.socket` (+ `[Install] WantedBy=sockets.target` ajouté) et `.service` activés, renderer utilisateur activé
  (`graphical-session.target`).

**Retour à tiny-dfr** : `sudo rm /etc/t1bridge/touchbar-t1bridge`, puis redémarrer. Pour revenir à t1bridge : recréer le fichier,
puis redémarrer.

## Fichiers installés sur le T2

- `/usr/local/lib/t1bridge/t1-touchbar-hw` (root) et `/usr/local/lib/t1bridge/t1-touchbar` (renderer), compilés sur le
  poste Debian (`CARGO_TARGET_DIR=target-t2 cargo build --release -p t1-touchbar-hw --features service` et
  `-p t1-touchbar`), le T2 n'a pas de compilateur.
- `/etc/systemd/system/t1-touchbar-hw.{socket,service}` : unités du dépôt sans `BindsTo=dev-dri-touchbar.device`, chemin
  `/usr/local`, `ExecStartPre` rétroéclairage. **Non activées.**
- `/usr/lib/systemd/system-sleep/t1bridge-touchbar` = `t1bridge-touchbar-sleep` (n'agit que si le service tournait).
- Groupe système `t1bridge` (gid 975), benoit membre (le socket est `root:t1bridge 0660`).
- `~/.config/systemd/user/t1-touchbar.service` = `t1-touchbar.service` d'ici (renderer, **non activé**).
- `~/.local/bin/t1-desktop-provider` = `t1-desktop-provider-kde` d'ici (trace des actions dans
  `$XDG_RUNTIME_DIR/t1-desktop-provider.log`).
- tiny-dfr : **toujours activé au démarrage**, simplement arrêté pendant les essais.

## Lancer t1bridge (essai, jusqu'au prochain redémarrage)

```bash
sudo systemctl stop tiny-dfr
sudo systemctl start t1-touchbar-hw.socket t1-touchbar-hw.service
systemctl --user start t1-touchbar.service
```

## Retour à tiny-dfr

```bash
systemctl --user stop t1-touchbar.service
sudo systemctl stop t1-touchbar-hw.service t1-touchbar-hw.socket
sudo systemctl start tiny-dfr
```

Un redémarrage suffit aussi : rien de t1bridge n'est activé, tiny-dfr repart seul (sa règle udev le lance).
Si t1bridge a été rendu permanent (ci-dessous), défaire d'abord : `systemctl --user disable t1-touchbar.service`,
`sudo systemctl disable t1-touchbar-hw.socket`, `sudo systemctl unmask tiny-dfr`.

Tout retirer : supprimer les fichiers listés plus haut, `sudo systemctl daemon-reload`, `sudo groupdel t1bridge`.

## À vérifier au premier démarrage en mode permanent

Ordre socket/service avant l'ouverture de session ; écran de connexion SDDM (utilisateur `sddm` hors du groupe `t1bridge` :
pas de barre avant la connexion) ; retour à 80 % au rebranchement du chargeur.
