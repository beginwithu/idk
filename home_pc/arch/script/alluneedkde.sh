#!/usr/bin/env bash

PACKAGES={
          plasma-meta 
          gamemode 
          lib32-gamemode 
          xdg-utils 
          smartmontools 
          openssh 
          wget 
          networkmanager 
          git 
          base-devel 
          fastfetch
          flatpak 
          htop
          btop 
         fish 
         starship 
         eza
         power-profiles-daemon 
         dolphin
         ffmpegthumbs 
         ark
         konsole 
         kate
         gwenview 
         haruna 
         ttf-jetbrains-mono-nerd 
         baobab
         nano 
         nvim
         micro 
    }

 sudo pacman -Syu "${PACKAGES[@]}"
