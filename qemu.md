```
#1
sudo pacman -S qemu-full qemu-img libvirt virt-install virt-manager dnsmasq libosinfo edk2-ovmf

#2
sudo systemctl enable --now libvirtd

#3
sudo usermod -aG libvirt $(whoami)
newgrp libvirt
```
