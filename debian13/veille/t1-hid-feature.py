#!/usr/bin/env python3
"""Lit ou écrit un rapport « feature » HID de la T1 (interface 6 = hub de capteurs, /dev/hidrawN).

appletbdrm « gare » l'écran de la Touch Bar avant la veille en envoyant le rapport 3 = 03 01 f4 01 …
(15 octets) sur cette interface ; rien ne le défait au réveil. Ce script sert à comparer l'état du
rapport avant/après et à tester la valeur qui rallume l'écran.

  sudo python3 t1-hid-feature.py                 lire le rapport 3
  sudo python3 t1-hid-feature.py 3 02 f4 01      écrire le rapport 3 (octets après l'ID, complétés par des 0)
  sudo python3 t1-hid-feature.py tout            lire les rapports 1 à 8 (comparer Touch Bar allumée / éteinte)
"""
import fcntl
import glob
import os
import sys

SIZE = 15  # ID compris, comme dans appletbdrm_t1_park()


def ioc(direction, nr, size):
    return (direction << 30) | (size << 16) | (ord("H") << 8) | nr


def hidraw():
    for path in glob.glob("/sys/bus/hid/devices/0003:05AC:8600.*"):
        if os.path.realpath(path).split("/")[-2].endswith(":2.6"):
            return "/dev/" + os.listdir(path + "/hidraw")[0]
    sys.exit("interface 6 de la T1 introuvable")


def main():
    dev = hidraw()
    if len(sys.argv) > 1 and sys.argv[1] == "tout":
        with open(dev, "rb+", buffering=0) as f:
            for rid in range(1, 9):
                buf = bytearray([rid] + [0] * 63)
                try:
                    n = fcntl.ioctl(f, ioc(3, 0x07, len(buf)), buf, True)
                    print(f"rapport {rid} : {bytes(buf[:n]).hex(' ')}")
                except OSError as error:
                    print(f"rapport {rid} : {error.strerror}")
        return
    rid = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    with open(dev, "rb+", buffering=0) as f:
        if len(sys.argv) > 2:
            data = bytes([rid] + [int(x, 16) for x in sys.argv[2:]]).ljust(SIZE, b"\0")
            fcntl.ioctl(f, ioc(3, 0x06, len(data)), data)  # HIDIOCSFEATURE
            print(f"{dev} écrit : {data.hex(' ')}")
        buf = bytearray([rid] + [0] * (SIZE - 1))
        n = fcntl.ioctl(f, ioc(3, 0x07, len(buf)), buf, True)  # HIDIOCGFEATURE
        print(f"{dev} rapport {rid} : {bytes(buf[:max(n, 1)]).hex(' ')}")


if __name__ == "__main__":
    main()
