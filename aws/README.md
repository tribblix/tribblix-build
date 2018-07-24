Tribblix AMI construction
=========================

These are the Xen configuration files used to create the Tribblix AMIs.

The basic process is:

Have an Ubuntu 16.04 system with Xen installed, and the iso images present.

As root on that system:

cd /root
truncate -s 8G ami-m5.img
xl create /home/ptribble/ami-m5.cfg 

Point vncviewer at the system, and install Tribblix:

./live_install.sh -B c2t0d0 ec2-baseline

reboot and the instance exits.

As yourself on the Ubuntu system, run the VMDX stream converter:

./VMDK-stream-converter-0.2/VMDKstream.py ami-m5.img ami-m5.vmdk

Use ec2ivol to push that vmdk image up to S3, where it will get converted
into a volume.

Use ec2dct to monitor progress, and get the volume ID.

Use ec2addsnap to create a snapshot of that volume.

Monitor with ec2dsnap to make sure it's complete.

Use ec2reg to register an AMI.

    ec2reg --region eu-west-2 -s snap-017489bb0feb774b8 \
    -d "$AWS_AMI_DESC" -n "$AWS_AMI_NAME" -a x86_64 \
    --root-device-name /dev/xvda --virtualization-type hvm

Launch that AMI. You'll be able to log in as jack and su to root.

Clean up the instance:

    dumpadm -d none
    zfs destroy rpool/dump
    sed -i 's:PermitRootLogin no:PermitRootLogin without-password:' /etc/ssh/sshd_config
    svcadm restart ssh
    [ verify root login works ! ]
    [ and log in as root ]
    userdel jack
    rm -fr /jack
    passwd -N root
    rm /etc/ssh/*key*
    rm -fr /root/.ssh
    rm /root/.bash_history
    rm -f /var/adm/messages.*
    cat /dev/null > /var/adm/messages
    cat /dev/null > /var/adm/wtmpx
    cat /dev/null > /var/adm/utmpx
    sync

Create an image from that instance. This is the final image.

To clean up the import:

* deregister the initial ami
* delete the initial volume
* delete any loose snapshots
* delete any s3 debris
