#!/bin/sh

mount /dev/$1  /mnt
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys 
chroot /mnt 
