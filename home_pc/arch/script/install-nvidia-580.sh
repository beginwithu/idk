#!/usr/bin/env bash

 PACKAGES=(
    linux-zen-headers
    libva-nvidia-driver 
    lib32-opencl-nvidia-580xx 
    lib32-nvidia-580xx-utils 
    opencl-nvidia-580xx 
    nvidia-580xx-dkms 
    nvidia-580xx-utils 
    nvidia-580xx-settings
)

sudo pacman -Syu "${PACKAGES[@]}"
