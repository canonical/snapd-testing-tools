#!/bin/bash

set -e
set -x 

# finally build the uc20 image
ubuntu-image snap \
    -i 8G \
    --snap upstream-core20.snap \
    --snap snapd.snap \
    --snap pc-kernel.snap \
    --snap pc-gadget.snap \
    ubuntu-core-20-amd64-dangerous.model

# setup some data we will inject into ubuntu-seed partition of the image above
# that snapd.spread-tests-run-mode-tweaks.service will ingest

# this sets up some /etc/passwd and group magic that ensures the test and ubuntu
# users are working, mostly copied from snapd spread magic
mkdir -p /root/test-etc
# NOTE that we don't use the real extrausers db on the host VM here because that
# could be used to actually login to the L1 VM, which we don't want to allow, so
# put it in a fake dir that login() doesn't actually look at for the host L1 VM.
mkdir -p /root/test-var/lib/extrausers
touch /root/test-var/lib/extrausers/sub{uid,gid}
for f in group gshadow passwd shadow; do
    # don't include the ubuntu user here, we manually add that later on
    grep -v "^root:" /etc/"$f" | grep -v "^ubuntu:" /etc/"$f" > /root/test-etc/"$f"
    grep "^root:" /etc/"$f" >> /root/test-etc/"$f"
    chgrp --reference /etc/"$f" /root/test-etc/"$f"
    # append test user for testing
    grep "^test:" /etc/"$f" >> /root/test-var/lib/extrausers/"$f"
    # check test was copied
    MATCH "^test:" < /root/test-var/lib/extrausers/"$f"
done

# TODO: could we just do this in the script above with adduser --extrausers and
# echo ubuntu:ubuntu | chpasswd ?
# dynamically create the ubuntu user in our fake extrausers with password of 
# ubuntu
#shellcheck disable=SC2016
echo 'ubuntu:$6$5jPdGxhc$8DgCHDdjj9IQxefS9atknQq4JVVYqy6KiPV/p4fDf5NUI6dqKTAf0vUZNx8FUru/pNgOQMwSMzS5pFj3hp4pw.:18492:0:99999:7:::' >> /root/test-var/lib/extrausers/shadow
#shellcheck disable=SC2016
echo 'ubuntu:$6$5jPdGxhc$8DgCHDdjj9IQxefS9atknQq4JVVYqy6KiPV/p4fDf5NUI6dqKTAf0vUZNx8FUru/pNgOQMwSMzS5pFj3hp4pw.:18492:0:99999:7:::' >> /root/test-etc/shadow
echo 'ubuntu:!::' >> /root/test-var/lib/extrausers/gshadow
# use gid of 1001 in case sometimes the lxd group sneaks into the extrausers image somehow...
echo "ubuntu:x:1000:1001:Ubuntu:/home/ubuntu:/bin/bash" >> /root/test-var/lib/extrausers/passwd
echo "ubuntu:x:1000:1001:Ubuntu:/home/ubuntu:/bin/bash" >> /root/test-etc/passwd
echo "ubuntu:x:1001:" >> /root/test-var/lib/extrausers/group

# add the test user to the systemd-journal group if it isn't already
sed -r -i -e 's/^systemd-journal:x:([0-9]+):$/systemd-journal:x:\1:test/' /root/test-etc/group

# mount fresh image and add all our SPREAD_PROJECT data
# for the lxd backend this step is a bit different as the device mapper kernel module
# is not supported by lxd containers. We thus have to do some manual setup of the image
# partition mount.
if [ "${SPREAD_BACKEND}" = "lxd-nested" ]; then
    devloop=$(losetup -f)
    losetup $devloop pc.img -o 2097152
    mkdir /mnt/p2
    mount $devloop /mnt/p2

    # add the data that snapd.spread-tests-run-mode-tweaks.service reads to the 
    # mounted partition
    tar -c -z \
        -f /mnt/p2/run-mode-overlay-data.tar.gz \
        /root/test-etc /root/test-var/lib/extrausers

    umount /mnt/p2
    losetup -d $devloop
else
    kpartx -avs pc.img
    # losetup --list --noheadings returns:
    # /dev/loop1   0 0  1  1 /var/lib/snapd/snaps/ohmygiraffe_3.snap                0     512
    # /dev/loop57  0 0  1  1 /var/lib/snapd/snaps/http_25.snap                      0     512
    # /dev/loop19  0 0  1  1 /var/lib/snapd/snaps/test-snapd-netplan-apply_75.snap  0     512
    devloop=$(losetup --list --noheadings | grep pc.img | awk '{print $1}')
    dev=$(basename "$devloop")

    # mount it so we can use it now
    mkdir -p /mnt
    mount "/dev/mapper/${dev}p2" /mnt

    # add the data that snapd.spread-tests-run-mode-tweaks.service reads to the 
    # mounted partition
    tar -c -z \
        -f /mnt/run-mode-overlay-data.tar.gz \
        /root/test-etc /root/test-var/lib/extrausers

    # tear down the mounts
    umount /mnt
    kpartx -d pc.img
fi

# the image is now ready to be booted
