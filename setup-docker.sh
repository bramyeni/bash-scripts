#!/bin/bash
# $Id: setup-docker.sh 367 2021-03-18 12:23:05Z bpahlawa $
# initially captured from Microsoft website
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2021-03-18 20:23:05 +0800 (Thu, 18 Mar 2021) $
# $Revision: 367 $


trap exitshell SIGINT SIGTERM

exitshell()
{
   echo -e "${NORMALFONT}Cancelling script....exiting....."
   stty sane
   exit 0
}

export SCRIPTDIR=`dirname $0` && [[ "$SCRIPTDIR" = "." ]] && SCRIPTDIR=`pwd`
export DOCKERSTORAGE="${DOCKER_STORAGE:-/var/lib/docker}"
export DOCKERMINSIZE=35
export DISTRO=""
export VERSION_ID=""
export LANG=en_US.UTF-8
# Wait for 5 minutes for the cluster to be ready.
#
export TIMEOUT=600
export RETRY_INTERVAL=5


get_distro_version()
{
   if [ -f /etc/os-release ]
   then
      ALLVER=`sed -n ':a;N;$bb;ba;:b;s/.*VERSION_ID="\([0-9\.]\+\)".*/\1/p' /etc/os-release`
      VERSION_ID=`echo $ALLVER | cut -f1 -d"."`
      export DISTRO=`sed -n 's/^ID[ \|=]\(.*\)/\1/p' /etc/os-release | sed 's/"//g'`
      DISTRO=${DISTRO^^}
   else
      echo "Unsupported operating system version!!"
      exit 1
   fi
}
   

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Name of virtualenv variable used.
#
export LOG_FILE="setup-docker.log"
export DEBIAN_FRONTEND=noninteractive
export PV_COUNT="${PVCOUNT:-30}"

# Make a directory for installing the scripts and logs.
#
touch $LOG_FILE

reset_docker()
{

 if [ `ps -ef | grep dockerd | grep -v grep | wc -l` -ne 0 ]
 then
   [[ `docker ps -a | grep " Up " | grep -v IMAGE | awk '{print $1}' | wc -l` -ne 0 ]] && echo "Stopping docker containers that are currently running.." && docker stop $(docker ps -a | grep " Up " | grep -v IMAGE | awk '{print $1}')
   [[ `docker ps -a | grep -v IMAGE | awk '{print $1}' | wc -l` -ne 0 ]] && echo "Removing docker containers...." && docker rm $(docker ps -a | grep -v IMAGE | awk '{print $1}')
   [[ `docker images | grep -v IMAGE | grep -v ${DOCKER_TAG} | awk '{print $3}' | wc -l` -ne 0 ]] && echo "Removing docker all docker images.. except $DOCKER_TAG image " && docker rmi $(docker images | grep -v IMAGE | grep -v ${DOCKER_TAG} | awk '{print $3}')
   [[ "$DESTROY_EVERYTHING" != "" ]] && docker rmi $(docker images | grep -v IMAGE | awk '{print $3}') 2>/dev/null
   systemctl stop docker
 fi
   [[ -d /var/lib/dockershim ]] && rm -rf /var/lib/dockershim
   [[ -d /var/log/containers ]] && rm -rf /var/log/containers

   ip link delete docker0
}

destroy_everything()
{
echo "#####################################################################"
echo "####### Destroying and Uninstalling Docker and its components #######"
echo "#####################################################################"
   reset_docker
   delete_ephemeral_disks
   
   [[ -f /etc/docker/daemon.json ]] && DIRTODELETE=`sed -n 's/.*data-root.*"\([a-zA-Z0-9/]\+\)",/\1/p' /etc/docker/daemon.json`
   if [ "$DIRTODELETE" != "" ]
   then
       rm -rf $DIRTODELETE
   fi
   get_distro_version
   case "$DISTRO" in
    "CENTOS"|"RHEL")
            yum remove -y docker* containerd*
	    ;;
    "UBUNTU"|"DEBIAN")
            apt-get purge -y docker*
	    ;;
    "ARCH")
	    ;;
    "SUSE") 
            zypper remove cri-o
            ;;
   esac
   [[ -d /etc/docker ]] && rm -rf /etc/docker

}

install_pkg_centos()
{
echo "Checking docker version..."
DOCKERVER=`docker --version | sed 's/.*version \([0-9]\+\).*/\1/g'`
[[ $DOCKERVER -lt 19 ]] && echo "Removing docker version $DOCKERVER on $DISTRO..." && yum remove -y docker*

# Install docker.
echo "Updating centos...."
yum update all
yum update -y
echo "Installing libraries....."
yum install -y curl ca-certificates software-properties-common yum-utils device-mapper-persistent-data lvm2 wget
echo "installing Docker ce and containerd...."
echo -e "$(curl --silent https://download.docker.com/linux/centos/7/x86_64/stable/Packages/ | grep "a href.*" | sed 's/<[^>\]*>//g'  | awk '{print $1}')\n" > /tmp/dockerpkglist.lst
if [ -f /tmp/dockerpkglist.lst ]
then
   CONTAINERDV=$( cat /tmp/dockerpkglist.lst | grep "containerd.*" | sed 's/[^0-9\.\-]*//g; s/^\.\|^[\-]*//g' | cut -f1-3 -d"." | sort -n | tail -1)
   echo "Latest containerd version is $CONTAINERDV"
   DOCKERCEV=$( cat /tmp/dockerpkglist.lst  | grep "docker-ce-cli.*" | sed 's/[^0-9\.\-]*//g; s/^\.\|^[\-]*//g' | cut -f1-3 -d"." | sort -n | tail -1)
   echo "Latest docker-ce-cli version is $DOCKERCEV"
   for PKGTOINSTALL in `cat /tmp/dockerpkglist.lst | egrep ".*$CONTAINERDV|.*$DOCKERCEV"`
   do
       echo "Installing $PKGTOINSTALL"
       yum install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/$PKGTOINSTALL
   done
   DOCKERCEV=$( cat /tmp/dockerpkglist.lst  | grep "docker-ce.*" | sed 's/[^0-9\.\-]*//g; s/^\.\|^[\-]*//g' | cut -f1-3 -d"." | sort -n | tail -1)
   echo "Latest docker-ce version is $DOCKERCEV"
   for PKGTOINSTALL in `cat /tmp/dockerpkglist.lst | egrep ".*$DOCKERCEV"`
   do
       echo "Installing $PKGTOINSTALL"
       yum install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/$PKGTOINSTALL
   done
fi
}

install_pkg_suse()
{
   zypper -n update
   zypper -n in curl socat
   zypper addrepo -G https://download.opensuse.org/repositories/home:darix:apps/SLE_15_SP1/home:darix:apps.repo
   zypper addrepo -G https://download.opensuse.org/repositories/home:RBrownSUSE:k118:v2/openSUSE_Tumbleweed/home:RBrownSUSE:k118:v2.repo
   zypper ref
   zypper -n in cri-o
}
   
install_pkg_ubuntu()
{

   echo "Checking docker version..."
   DOCKERVER=`docker --version 2>/dev/null| sed 's/.*version \([0-9]\+\).*/\1/g' 2>/dev/null`
   [[ $DOCKERVER -lt 19 ]] && echo "Removing docker version $DOCKERVER on UBUNTU..." && apt --yes purge docker*
   apt --yes install curl lsb-release
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
   curl -sL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
   if [ ! -f /etc/apt/sources.list.d/docker.list ]
   then
       echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu/ $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
   fi
   apt-get update -q
   apt --yes install apt-transport-https software-properties-common selinux-utils
   apt-get install -q --yes docker-ce --allow-downgrades --allow-change-held-packages
   [[ $? -ne 0 ]] && echo "Can not install docker.. please check the problem.. exiting...." && exit 1
   locale-gen en_US.UTF-8


}

install_pkg_debian()
{
   echo "Checking docker version..."
   DOCKERVER=`docker --version | sed 's/.*version \([0-9]\+\).*/\1/g'`
   [[ $DOCKERVER -lt 19 ]] && echo "Removing docker version $DOCKERVER on DEBIAN..." && apt --yes purge docker*
   apt --yes install curl lsb-release
   curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
   curl -sL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
   if [ ! -f /etc/apt/sources.list.d/docker.list ]
   then
       echo "deb [arch=amd64] https://download.docker.com/linux/debian/ $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
   fi
   case "$VERSION_ID" in
   10)
       apt-get update -t buster-backports
       ;;
   *)  apt-get update -q
       ;;
   esac
   apt-get install -q --yes docker-ce 
   apt-get install -q --yes docker-ce-cli containerd.io
   [[ $? -ne 0 ]] && echo "Can not install docker or containerd.. please check the problem.. exiting...." && exit 1
   apt --yes install apt-transport-https ca-certificates gnupg gnupg-agent software-properties-common selinux-utils
   apt-get install -q -y locales bridge-utils
   apt-get update -q 
   locale-gen en_US.UTF-8

}

install_pkg_archlinux()
{
   while [[ `ps -ef | grep "pacman " | grep -v grep | wc -l` -ne 0 ]]
   do
      echo "Waiting for pacman to finish!!"
      sleep 5
   done
   [[ -f /var/lib/pacman/db.lck ]] && rm -f /var/lib/pacman/db.lck
   pacman -Sy archlinux-keyring --noconfirm
   pacman -Syu --noconfirm
   pacman -Sy --noconfirm curl git sudo wget unzip conntrack-tools socat
   pacman -Sy --noconfirm docker
   pacman -Sc --noconfirm

}




install_prereqs()
{

echo ""
echo "#########################################################################"
echo "######## Gathering Linux Distro and Installing Required packages ########"
echo "#########################################################################"



case "$DISTRO" in
    "CENTOS"|"RHEL")
	    install_pkg_centos
	    ;;

    "UBUNTU")
	    install_pkg_ubuntu
	    ;;
    "ARCH")
	    install_pkg_archlinux
	    ;;
    "DEBIAN") 
            install_pkg_debian
            ;;
    "SUSE") 
            install_pkg_suse
            ;;
esac

[[ ! -d /etc/docker ]] && mkdir -p /etc/docker && echo "{}" > /etc/docker/daemon.json
echo "Enabling docker systemd..."
systemctl enable docker

echo "Checking group docker..."
[[ `grep docker /etc/group | wc -l` -eq 0 ]] && groupadd docker

echo "Adding group docker to $(whoami)  ..."
usermod --append --groups docker "$(whoami)"

# Set SELinux in permissive mode (effectively disabling it)
echo "Check selinux and disable it....."
SELINUXFILE=/etc/sysconfig/selinux
which getenforce 2>/dev/null
if [ $? -eq 0 ]
then
   [[ $(getenforce) = 'Enforcing' ]] && setenforce 0 && sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' $SELINUXFILE
else
   if [ -f $SELINUXFILE ]
   then
      if [ `sed -n 's/^SELINUX[ =]\+\([[:alpha:]]\+\).*$/\1/p' $SELINUXFILE | egrep 'disabled|permissive' | wc -l` -ne 0 ]
      then
          setenforce 0 
          sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' $SELINUXFILE
      fi
   fi
fi

echo "Packages installed."

echo "#####################################################################"
echo "############## Setting up pre-requisites for Docker #################"
echo "#####################################################################"

[[ $(grep $(hostname) /etc/hosts | wc -l) -eq 0 ]] && echo "$(hostname -i) $(hostname)" >> /etc/hosts

if [ ! -f "/etc/docker/daemon.json" ]
then
   echo -e "Docker /etc/docker/daemon.json is not available!\nCreating it!\n" 
   echo "{}" > /etc/docker/daemon.json
fi

echo "Checking whether $DOCKERSTORAGE has been set into /etc/docker/daemon.json"
if [ `grep "native.cgroupdriver=systemd" /etc/docker/daemon.json | wc -l` -eq 0 -o `grep ${DOCKERSTORAGE} /etc/docker/daemon.json | wc -l` -eq 0 ]
then
   [[ ! -d ${DOCKERSTORAGE} ]] && mkdir -p ${DOCKERSTORAGE}
   echo "Configuring docker daemon.json..."
   cat > /etc/docker/daemon.json <<EOF
   {
      "exec-opts": ["native.cgroupdriver=systemd"],
      "log-driver": "json-file",
      "data-root": "${DOCKERSTORAGE}",
      "log-opts": {
      "max-size": "100m"
    },
    "storage-driver": "overlay2"
   }
EOF

   [[ ! -d /etc/systemd/system/docker.service.d ]] && mkdir -p /etc/systemd/system/docker.service.d
fi
   
# Disable Ipv6 for cluster endpoints.
#
echo "Adding necessary kernel parameters to /etc/sysctl.conf..."
echo net.ipv6.conf.all.disable_ipv6=1 > /etc/sysctl.conf
echo net.ipv6.conf.default.disable_ipv6=1 >> /etc/sysctl.conf
echo net.ipv6.conf.lo.disable_ipv6=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf

echo "Activating kernel parameters..."
sysctl --system

echo "Docker pre-requisites have been completed."
}

setup_docker()
{
echo "###########################################################"
echo "###################  Setting up Docker ####################"
echo "###########################################################"


   for MNTPOINT in `df --output=target | egrep "docker"`
   do
       umount $MNTPOINT
   done

   delete_ephemeral_disks

   systemctl start docker
   [[ $? -ne 0 ]] && echo "Failed to start docker.....please check and re-run this script!!...exiting......" && exit 1
   
   echo "Using current configuration.........."
   echo "Restarting docker.. just in case....."
   systemctl daemon-reload
   systemctl restart docker

}

kill_docker()
{
   echo "Checking whether docker daemon is running.."
   [[ `ps -ef | grep dockerd | grep -v grep | wc -l` -ne 0 ]] && echo "Stopping docker daemon..." && systemctl stop docker
   MYPID=$$
   for listproc in `ps -ef | egrep "container|docker" | grep -v "$MYPID " | awk '{print $2}'`
   do
      kill -9 $listproc 2>/dev/nulll 1>/dev/null
   done
}

#this is how to use this script
usage_docker()
{
   echo -e "\nUsage: \n    $0 -m <mode> -d <docker_storage>"
   echo -e "\n    -m mode [reset|destroy|''(default)]\n    -d docker-storage [any-mountpoint|/var/lib/docker(default)]"
   echo -e "    E.g: $0 -m reset -d /opt/docker"
   echo -e "         $0 -m destroy -d /opt/docker"
   exit 1
}


get_params()
{
   local OPTIND
   while getopts "m:d:h" PARAM
   do
      case "$PARAM" in
      m) 
          #mode
          MODE=${OPTARG}
          ;;
      d)
          #docker storage
          DOCKER_STORAGE=${OPTARG}
          DOCKERSTORAGE=$DOCKER_STORAGE
          ;;
      h)
          #display this usage
          usage_docker
          ;;
      ?)
          echo -e "\nError:  Unknown parameter(s)...\n"
          usage_docker
      esac
    done

    shift $((OPTIND-1))

}

check_mountpoint()
{
local STORAGE="$1"
        [[ "$STORAGE" = "" ]] && return 0
	if [ ! -d $STORAGE ]
        then
            STORAGEPARENT=$(dirname $STORAGE)
            echo "The mountpoint $STORAGE is not available, however the parent directory is mounted under $STORAGEPARENT"
            STORAGEPARENT=$(df $STORAGEPARENT | awk '{print $NF}' | grep -v 'Mounted on')
            if [ "$STORAGEPARENT" = "/" ]
            then
               echo -e "\nThe mount $STORAGE will be created under root '/' filesystem, please mount it on a different filesystem\n" && exit 1
            else
	       DFSIZE=`df -m $STORAGEPARENT | awk '{print $4}' |  grep -v "Avail"`
               CURRSIZE=0
               MOUNTPOINT=`df $STORAGEPARENT | awk '{print $NF}' | tail -1`
            fi
        else
            if [ "$(df $STORAGE | awk '{print $NF}')" = "/" ]
            then
               echo -e "\nThe mount $STORAGE will be created under root '/' filesystem, please mount it on a different filesystem\n" && exit 1
            else
	       CURRSIZE=`du -sm $STORAGE | awk '{print $1}'`
	       [[ $CURRSIZE -gt 0 ]] && CURRSIZE=$((CURRSIZE/1024))
	       DFSIZE=`df -m $STORAGE | awk '{print $4}' | grep -v "Avail"`
               MOUNTPOINT=`df $STORAGE | awk '{print $NF}' | tail -1`
            fi
        fi
}

check_diskspace()
{
   if [ "$MODE" != "" -a "$MODE" != "single" ]
   then
      echo "Checking Docker storage"
      check_mountpoint "$DOCKERSTORAGE"
      DCURRSIZE=$CURRSIZE
      DFREESIZE=$((DFSIZE/1024))
      DMOUNTPOINT=$MOUNTPOINT
      echo "Checking Local storage"
      check_mountpoint "$LOCALSTORAGE"
      LCURRSIZE=$CURRSIZE
      LFREESIZE=$((DFSIZE/1024))
      LMOUNTPOINT=$MOUNTPOINT

      if [ "$DMOUNTPOINT" = "$LMOUNTPOINT" ]
      then 
	 if [ $((LFREESIZE+DCURRSIZE+LCURRSIZE)) -lt $((DOCKERMINSIZE+LOCALSTGMINSIZE)) ]
         then
	     echo -e "\nThe mount $DOCKERSTORAGE and $LOCALSTORAGE are on the same mountpoint $DMOUNTPOINT !"
             echo -e "\nFree space: $LFREESIZE GB, current docker size $DCURRSIZE GB and current local-storage size $LCURRSIZE GB"
             echo -e "\nBDC Requires free space at least $((DOCKERMINSIZE+LOCALSTGMINSIZE)) GB\nAdditional diskspace is required\n"
             exit 1
         else
             echo -e "\nThe mount $DOCKERSTORAGE and $LOCALSTORAGE are on the same mountpoint $DMOUNTPOINT !"
             echo -e "\nFree space: $LFREESIZE GB, current docker size $DCURRSIZE GB and current local-storage size $LCURRSIZE GB"
             echo -e "\nBDC Requires free space at least $((DOCKERMINSIZE+LOCALSTGMINSIZE)) GB\nThe current free diskspace is sufficient\n"
         fi
      else
         echo -e "\n$LOCALSTORAGE is mounted on $LMOUNTPOINT !"
         echo -e "\nFree space: $LFREESIZE GB, current local-storage size $LCURRSIZE GB"
         if [ "$((LFREESIZE+LCURRSIZE))" -lt $LOCALSTGMINSIZE ]
         then
             echo -e "\nBDC Requires free space at least $LOCALSTGMINSIZE GB\nAdditional diskspace is required\n"
             exit 1
         else
             echo -e "\nBDC Requires free space at least $LOCALSTGMINSIZE GB\nThe current free diskspace is sufficient"
         fi
         echo -e "\n$DOCKERSTORAGE is mounted on $DMOUNTPOINT !"
         echo -e "\nFree space: $DFREESIZE GB, current docker storage size $DCURRSIZE GB"
         if [ "$((DFREESIZE+DCURRSIZE))" -lt $DOCKERMINSIZE ]
         then
             echo -e "\nBDC Requires free space at least $DOCKERMINSIZE GB\nAdditional diskspace is required\n"
             exit 1
         else
             echo -e "\nBDC Requires free space at least $DOCKERMINSIZE GB\nThe current free diskspace is sufficient\n"
         fi
      fi
   fi
}


copy_public_key()
{
   local IPADDR="$1"
   echo "Trying to copy public key from .ssh directory..."
   echo "Trying to create trusted connection from this host $(hostname -f) to $IPADDR"
   if [ -f ~/.ssh/id_rsa.pub ]
   then
      ssh-copy-id $IPADDR
      while [ $? -ne 0 ]
      do
         echo "\nIf you dont know the root password press Ctrl+c then please ask someone who knows !!...\n"
         ssh-copy-id $IPADDR
         sleep 2
      done
   else
      yes 'y' | ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
      ssh-copy-id $IPADDR
      while [ $? -ne 0 ]
      do
         echo -e "\nIf you dont know the root password press Ctrl+c then please ask someone who knows !!...\n"
         ssh-copy-id $IPADDR
         sleep 2
      done
   fi
}

reset_only()
{
   systemctl stop docker
   delete_ephemeral_disks
}

   
delete_ephemeral_disks()
{

   if [ -f /etc/docker/daemon.json ]
   then
       DIRTODELETE=`sed -n 's/.*data-root.*"\([a-zA-Z0-9/]\+\)",/\1/p' /etc/docker/daemon.json`
       if [ "$DIRTODELETE" != "" ]
       then
          DIRTODELETEPATTERN=`echo $DIRTODELETE | sed 's|/|\\\/|g'`
          for MTPOINT in `mount  | grep "$DIRTODELETEPATTERN" | awk '{print $3}'`
          do
              echo "Unmounting docker bind volume $MTPOINT"
              umount $MTPOINT 2>/dev/null 1>/dev/null
          done
          rm -rf ${DIRTODELETE}/*
       fi
   fi
   if [ -d $DOKERSTORAGE ]
   then
       DSTORAGEPATTERN=`echo $DOCKERSTORAGE | sed 's|/|\\\/|g'`
       for MTPOINT in `mount  | grep "$DSTORAGEPATTERN" | awk '{print $3}'`
       do
           echo "Unmounting docker bind volume $MTPOINT"
           umount $MTPOINT 2>/dev/null 1>/dev/null
       done
       rm -rf ${DOCKERSTORAGE}/*
   else
       if [ -d /var/lib/docker ]
       then
           for MTPOINT in `mount  | grep "\\/var/\\/lib\\/docker" | awk '{print $3}'`
           do
              echo "Unmounting docker bind volume $MTPOINT"
              umount $MTPOINT 2>/dev/null 1>/dev/null
           done
           rm -rf /var/lib/docker/*
       fi
   fi
}


{
   get_params "$@"

   if [ "$MODE" = "reset" ]
   then
      echo "Resetting anything related to docker..........."
      reset_only
      exit 0
   elif [ "$MODE" = "destroy" ]
   then 
      DESTROY_EVERYTHING=YES
      echo "Destroying and Removing anything related to docker..........."
      destroy_everything
      exit 0
   fi
   
   get_distro_version

   [[ "$MODE" = "reset" ]] && > $LOG_FILE && echo -e "\n\nResetting all configuration.... Reinstall everything from scratch!...\n" && echo -e "Shutdown docker..... " && kill_docker

   echo -e "You are running Linux distro : $DISTRO $ALLVER ....."
   echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
   echo -e "$THEMESSAGE"
   echo -e "\nDocker storage      : $DOCKERSTORAGE " 
   echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n"
   install_prereqs
   setup_docker

} | tee $LOG_FILE
