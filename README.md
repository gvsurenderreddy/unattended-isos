# unattended-isos
Script to make unattended iso for use with libvirt/kvm this is meant to be used in conjunction with some for of config management or automated scripted install method, so obviously the default user/pass should be changes ASAP!

This script will download the all the latest isos for Ubuntu LTS from http://releases.ubuntu.com/ and convert them into an unattended installer with the following details:

hostname: ubuntu
user: ubuntu
pass: ubuntu

The ubuntu user will also have full sudo

# Usage

Needs root to run

`sudo ./get-iso.bash /path/to/temp/dir /path/for/finaliso`

You can also optionally set the username/group for the iso to be owned by on the filesystem

`sudo ./get-iso.bash /tmp /var/lib/libvirt/images yourname yourgroup`

Defaults to user: `libvirt-qemu` group: `kvm`
