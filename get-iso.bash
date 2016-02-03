
addir="${1}"
target="${2}"
username="${3}"
groupname="${4}"
unset status
deps="wget curl mkpasswd mkisofs isohybrid"

# Check/group exists before going further
function check_user() {
    if [[ -z ${username} ]]; then
        username='libvirt-qemu'
    fi

    if [[ -z ${groupname} ]]; then
        groupname='kvm'
    fi

    local ret=0

    if ! grep -q ${username} /etc/passwd; then
        local ret=1
    elif ! grep -q ${groupname} /etc/group; then
       ! local ret=1
    fi

    if [[ ${ret} -eq 1 ]]; then
        status="Please install wget curl whois genisoimage syslinux"
    fi

    return ${ret}
}

# Check program is installed
function is_installed {
    local installed=0
    type $1 >/dev/null 2>&1 || { local installed=1; }
    echo $installed
}

# Check all dependencies are installed
function check_deps {
    deps=0
    for i in $@; do
        if [[ ! $(is_installed "${i}") -eq 0 ]]; then
            deps=1
        fi
    done

    if [[ ! -d ${target} ]]; then
        status="${target} does not exist"
        deps=1
    fi

    return $deps
}

# Get the latest iso for each Unbuntu LTS release
function get_ubuntu_isos() {
    local releases=$(curl http://releases.ubuntu.com/ 2> /dev/null | grep -o -E '[0-9][02468]\.[0-9][02468]' | sort | uniq)
    for i in ${releases}; do
        local urlbase="http://releases.ubuntu.com/${i}"
        local release=$(curl ${urlbase} --location 2> /dev/null | grep -o -m1 -E '[0-9][02468]\.[0-9][02468](\.[0-9]|)')
        local iso="ubuntu-${release}-server-amd64.iso"
        local finaliso=$(echo ${iso} | sed s/server/server-unattended/g | rev | cut -d'/' -f 1 | rev)

        #Check if the iso already exists
        if [[ ! -f ${target}/${iso} ]]; then
            if ! wget --quiet --output-document=${downloaddir}/${iso} ${urlbase}/${iso}; then
                status="Unable to download ${iso}"
                return 1
            elif ! mv ${downloaddir}/${iso} ${target}/${iso}; then
                status="Unable to move ${downloaddir}/${iso}"
                return 1
            elif ! chown ${username}:${groupname} ${target}/${iso}; then
                status="Unable to own ${target}/${iso}"
                return 1
            fi
        fi

        # If the final iso does not exist create it
        if [[ ! -f ${target}/${finaliso} ]]; then
            if ! make_ubuntu_unattended ${target}/${iso}; then
                return 1
            elif ! cleanup; then
                echo "Unable to cleanup"
                echo "Please make sure /dev/loop1 is unmounted and /tmp/iso_org & /tmp/iso_new are deleted"
                return 1
            fi
        fi
    done
}

function make_ubuntu_unattended() {
    local iso="$1"
    local finaliso=$(echo ${iso} | sed s/server/server-unattended/g | rev | cut -d'/' -f 1 | rev)

    umount ${iso} 2> /dev/null

    if ! mkdir -p /tmp/iso_org > /dev/null 2>&1; then
        status="Unable to create working dir"
    elif ! mount -o loop ${iso} /tmp/iso_org > /dev/null 2>&1; then
        status="Unable to mount iso"
        return 1
    elif ! cp -r /tmp/iso_org /tmp/iso_new > /dev/null 2>&1; then
        status="Unable to copy iso to working dir"
        return 1
    elif ! echo "en_GB" > /tmp/iso_new/isolinux/lang; then
        status="Unable to set iso language"
        return 1
    elif ! cat << EOF > /tmp/iso_new/preseed/ubuntu.seed
# regional setting
d-i debian-installer/language                               string      en_GB:en
d-i debian-installer/country                                string      GB
d-i debian-installer/locale                                 string      en_GB
d-i debian-installer/splash                                 boolean     false
d-i localechooser/supported-locales                         multiselect en_GB.UTF-8
d-i pkgsel/install-language-support                         boolean     true

# keyboard selection
d-i preseed/early_command                                   string      umount /media || /bin/true
d-i console-setup/ask_detect                                boolean     false
d-i keyboard-configuration/modelcode                        string      pc105
d-i keyboard-configuration/layoutcode                       string      gb
d-i keyboard-configuration/variantcode                      string      English (UK)
d-i keyboard-configuration/xkb-keymap                       select      gb
d-i debconf/language                                        string      en_GB:en

# network settings
d-i netcfg/choose_interface                                 select      auto
d-i netcfg/dhcp_timeout                                     string      5
d-i netcfg/get_hostname                                     string      ubuntu
d-i netcfg/get_domain                                       string

# mirror settings
d-i mirror/country                                          string      manual
d-i mirror/http/hostname                                    string      archive.ubuntu.com
d-i mirror/http/directory                                   string      /ubuntu
d-i mirror/http/proxy                                       string

# clock and timezone settings
d-i time/zone                                               string      Europe/London
d-i clock-setup/utc                                         boolean     false
d-i clock-setup/ntp                                         boolean     true

# user account setup
d-i passwd/root-login                                       boolean     false
d-i passwd/make-user                                        boolean     true
d-i passwd/user-fullname                                    string      ubuntu
d-i passwd/username                                         string      ubuntu
d-i passwd/user-password-crypted                            password    \$6\$Jj4KowgZHvW\$kKoLAc3bPGpWncffrxirmSYx0s2I8Powd4ymzdN49PbD52HeQP2JMVmwwRG04rVXiMI1wRlg8eQGPJVCUr.PZ1
d-i passwd/user-uid                                         string
d-i user-setup/allow-password-weak                          boolean     false
d-i passwd/user-default-groups                              string      adm cdrom dialout lpadmin plugdev sambashare
d-i user-setup/encrypt-home                                 boolean     false

# configure apt
d-i apt-setup/restricted                                    boolean     true
d-i apt-setup/universe                                      boolean     true
d-i apt-setup/backports                                     boolean     true
d-i apt-setup/services-select                               multiselect security
d-i apt-setup/security_host                                 string      security.ubuntu.com
d-i apt-setup/security_path                                 string      /ubuntu
tasksel tasksel/first                                       multiselect Basic Ubuntu server
tasksel tasksel/first                                       multiselect openssh-server
d-i pkgsel/upgrade                                          select      safe-upgrade
d-i pkgsel/update-policy                                    select      none
d-i pkgsel/updatedb                                         boolean     true

# disk partitioning
d-i partman/confirm_write_new_label                         boolean     true
d-i partman/choose_partition                                select      finish
d-i partman/confirm_nooverwrite                             boolean     true
d-i partman/confirm                                         boolean     true
d-i partman-auto/purge_lvm_from_device                      boolean     true
d-i partman-lvm/device_remove_lvm                           boolean     true
d-i partman-md/device_remove_md                             boolean     true
d-i partman-lvm/confirm                                     boolean     true
d-i partman-lvm/confirm_nooverwrite                         boolean     true
d-i partman-auto-lvm/no_boot                                boolean     true
d-i partman-md/confirm                                      boolean     true
d-i partman-md/confirm_nooverwrite                          boolean     true
d-i partman-auto/method                                     string      lvm
d-i partman-auto-lvm/guided_size                            string      max
d-i partman-partitioning/confirm_write_new_label            boolean     true

# grub boot loader
d-i grub-installer/only_debian                              boolean     true
d-i grub-installer/with_other_os                            boolean     true

# finish installation
d-i finish-install/reboot_in_progress                       note
d-i finish-install/keep-consoles                            boolean     false
d-i cdrom-detect/eject                                      boolean     true
d-i debian-installer/exit/halt                              boolean     false
d-i debian-installer/exit/poweroff                          boolean     false
EOF
    then
        status="Unable to set seedfile"
        return 1
    elif ! cat << EOF > /tmp/iso_new/isolinux/txt.cfg
default unattended
label unattended
  menu label ^Unattended Install
  kernel /install/vmlinuz
  append file=/cdrom/preseed/ubuntu.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/ubuntu.seed preseed/file/checksum=$seed_checksum --
label install
  menu label ^Install Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/ubuntu-server.seed vga=788 initrd=/install/initrd.gz quiet --
label cloud
  menu label ^Multiple server install with MAAS
  kernel /install/vmlinuz
  append   modules=maas-enlist-udeb vga=788 initrd=/install/initrd.gz quiet --
label check
  menu label ^Check disc for defects
  kernel /install/vmlinuz
  append   MENU=/bin/cdrom-checker-menu vga=788 initrd=/install/initrd.gz quiet --
label memtest
  menu label Test ^memory
  kernel /install/mt86plus
label hd
  menu label ^Boot from first hard disk
  localboot 0x80
timeout 10
EOF
then
        status="Unable to set menu"
        return 1
    elif ! sed -i s/timeout.*/timeout\ 10/ /tmp/iso_new/isolinux/isolinux.cfg; then
        status="Unable to set menu timeout"
        return 1
    elif ! mkisofs -D -r -V "UBUNTU_UNATTENDED" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o /tmp/${finaliso} /tmp/iso_new > /dev/null 2>&1; then
        status="Unable to create iso"
        return 1
    elif ! isohybrid /tmp/${finaliso} > /dev/null 2>&1; then
        status="Unable to make iso bootable"
        return 1
    elif ! mv /tmp/${finaliso} ${target}/${finaliso} > /dev/null 2>&1; then
        status="Unable to move iso to the final directory: ${target}/${finaliso}"
        return 1
    elif ! chown ${username}:${groupname} ${target}/${finaliso}; then
        status="Unable to own ${target}/${fileiso}"
        return 1
    fi
}

function cleanup() {
    if grep -q '/dev/loop1' /proc/mounts; then
        if ! umount /tmp/iso_org > /dev/null 2>&1; then
            status="Unable to unmount iso"
            return 1
        fi
    elif ! rm -rf /tmp/iso_new; then
        status="Unable to remove /tmp/iso_new"
        return 1
    elif ! rm -rf /tmp/iso_org; then
        status="Unable to remove /tmp/iso_org"
        return 1
    fi
}

function main {
    if ! $(check_deps ${deps}); then
        echo $status
        exit 1
    elif ! check_user; then
        echo "User ${status}"
        exit 1
    elif ! get_ubuntu_isos; then
        echo "iso ${status}"
        exit 1
    elif ! cleanup; then
        echo "Unable to cleanup"
        echo "Please make sure /dev/loop1 is unmounted and /tmp/iso_org & /tmp/iso_new are deleted"
        exit 1
    fi
}

main

