```
#1
sudo pacman -S qemu-full qemu-img libvirt virt-install virt-manager dnsmasq libosinfo edk2-ovmf

#2
sudo systemctl enable --now libvirtd

#3
sudo usermod -aG libvirt $(whoami)
newgrp libvirt

#4
sudo ufw allow in on virbr0
sudo ufw allow out on virbr0
sudo ufw route allow in on virbr0
sudo ufw route allow out on virbr0

#5
systemctl restart systemd-networkd systemd-resolved
```
