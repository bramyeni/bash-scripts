#!/bin/bash
# $Id: setup-azdata.sh 314 2020-07-08 17:35:48Z bpahlawa $
# initially created by bpahlawa (Bram Pahlawanto)
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2020-07-09 01:35:48 +0800 (Thu, 09 Jul 2020) $
# $Revision: 314 $


trap exitshell SIGINT SIGTERM

exitshell()
{
   echo -e "${NORMALFONT}Cancelling script....exiting....."
   stty sane
   exit 0
}

export THEUSER="${AZUSER:-root}"
export SCRIPTDIR=`dirname $0` && [[ "$SCRIPTDIR" = "." ]] && SCRIPTDIR=`pwd`
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
export LOG_FILE="install-azdata.log"
export DEBIAN_FRONTEND=noninteractive
export PIP=pip
export VIRTUALENV_NAME="installazdata"
export REQUIREMENTS_LINK="https://aka.ms/azdata"
touch $LOG_FILE


install_pkg_centos()
{
echo "Checking kubernetes version..."
K8SVER=`kubelet --version | sed -n  's/.*v[0-9].\([0-9]\+\)./\1/p'`
[[ $K8SVER -lt 170 ]] && echo "Removing kubernetes version $K8SVER on $DISTRO..." && yum remove -y kube*
echo "Checking docker version..."
DOCKERVER=`docker --version | sed 's/.*version \([0-9]\+\).*/\1/g'`
[[ $DOCKERVER -lt 19 ]] && echo "Removing docker version $DOCKERVER on $DISTRO..." && yum remove -y docker*

# Install docker.
echo "Updating centos...."
yum update all
yum update -y
echo "Installing libraries....."
yum install -y curl ca-certificates software-properties-common yum-utils device-mapper-persistent-data lvm2 wget
echo "Installing libsqlite3 development headers...."
yum install -y libsqlite3-devel
echo "Install python3 and its libraries..."
yum install -y python3 python3-pip
yum install -y python3-devel 
if [ $? -ne 0 ]
then
   if [ "$DISTRO" = "RHEL" ]
   then
      echo "Using RHEL from cloud, therefore optional package needs to be enabled"
      REPO2USE=`yum repolist disabled | grep "optional\-rpms" | awk '{print $1}')`
      [[ "$REPO2USE" != "" ]] && yum -y install --enablerepo=$REPO2USE python3-devel || echo "Can not find optional package..please install python3-devel manually...exiting..." && exit 1
   fi
fi
echo "Install kerberos 5 development..."
yum install -y krb5-devel
echo "Install unixODB and gcc..."
yum install -y unixODBC-devel gcc gcc-c++
PIP="pip3"

}

install_pkg_suse()
{
   zypper -n update
   zypper -n in curl socat ebtables 
   zypper -n in python3 python3-pip python3-devel bridge-utils
   zypper -n in krb5-devel sqlite3-devel unixODBC-devel gcc-c++ gcc
   zypper ref
   PIP=pip3
}
   
install_pkg_ubuntu()
{

   apt --yes install curl lsb-release
   apt-get update -q
   apt --yes install apt-transport-https software-properties-common selinux-utils ebtables ethtool
   apt-get install -q -y python3 python3-pip python3-dev locales bridge-utils
   apt-get install -q -y libkrb5-dev libsqlite3-dev unixodbc-dev
   apt-get install -q -y cpp 
   locale-gen en_US.UTF-8
   PIP=pip3
}

install_pkg_debian()
{
   apt --yes install curl lsb-release
   [[ $VERSION_ID -ge 10 ]] && apt --yes install gnupg2
   case "$VERSION_ID" in
   10)
       apt-get update -t buster-backports
       ;;
   *)  apt-get update -q
       ;;
   esac
   apt --yes install apt-transport-https ca-certificates gnupg gnupg-agent software-properties-common selinux-utils ebtables ethtool
   apt-get install -q -y python3 python3-pip python3-dev locales bridge-utils
   apt-get update -q 
   apt-get install -q -y libkrb5-dev libsqlite3-dev unixodbc-dev 
   apt-get install -q -y libssl-dev 
   apt-get install -q -y cpp 
   locale-gen en_US.UTF-8
   PIP=pip3

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
   pacman -Sy --noconfirm curl git sudo wget ebtables ethtool unzip
   pacman -Sy --noconfirm python fakeroot binutils
   wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
   python /tmp/get-pip.py
   pacman -Sy --noconfirm sqlite unixodbc krb5 gcc
   pacman -Sc --noconfirm
   [[ `grep "git " /etc/sudoers | wc -l` -eq 0 ]] && echo "git ALL=(ALL)   NOPASSWD: ALL" >> /etc/sudoers
   PIP=pip

}




install_azdata()
{

echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "\nVirtual env is installed under user   : $THEUSER "
echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n"

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

which $PIP
[[ $? -ne 0 ]] && echo -e "\n\nThe previous installation was partially complete, therefore you must use -m parameter..\nRun $0 -h to see the list of parameter\n\n" && exit 1

$PIP install --upgrade pip
[[ $? -ne 0 ]] && python3 -m pip install --upgrade pip
$PIP install wheel

echo "Upgrade python pip to the latest..."
$PIP install requests --upgrade

# Install and create virtualenv.
#
echo "Install virtualenv and upgrade it..."
$PIP install --upgrade virtualenv

su - $THEUSER -c "
virtualenv -p python3 \"$VIRTUALENV_NAME\"
source ~/$VIRTUALENV_NAME/bin/activate

# Install azdata cli.
#
export LANG=en_US.UTF-8
echo \"Install $REQUIREMENTS_LINK components\"
$PIP install -r $REQUIREMENTS_LINK
"

echo "Packages installed."

}

#this is how to use this script
usage()
{
   echo -e "\nUsage: \n    $0 -m reinstall -u <user> [any-name|root[default]"
   echo -e "    E.g: $0 -m reinstall -u azuser"
   exit 1
}


get_params()
{
   local OPTIND
   while getopts "m:u:h" PARAM
   do
      case "$PARAM" in
      m) 
          #mode
          MODE=${OPTARG}
          ;;
      u)
          #Kube user
          AZUSER=${OPTARG}
          THEUSER=$AZUSER
          ;;
      h)
          #display this usage
          usage
          ;;
      ?)
          echo -e "\nError:  Unknown parameter(s)...\n"
          usage
      esac
    done

    shift $((OPTIND-1))

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

{
   get_params "$@"
   
   get_distro_version

   id $THEUSER 2>/dev/null 1>/dev/null
   if [ $? -ne 0 ]
   then
      [[ -d /home ]] && useradd -d /home/$THEUSER -m $THEUSER || useradd -m $THEUSER
   fi

   if [ "$MODE" != "reinstall" ]
   then
      su - $THEUSER -c "virtualenv -p python3 $VIRTUALENV_NAME
source ~/$VIRTUALENV_NAME/bin/activate;azdata 2>/dev/null 1>/dev/null" 2>/dev/null 1>/dev/null
      [[ $? -eq 0 ]] && echo "Virtual env $VIRTUALENV_NAME has already been installed!!.. " || install_azdata
   else
      install_azdata
   fi
   echo -e "How to use the virtualenv $VIRTUALENV_NAME"
   echo -e "\nLogin as $THEUSER , then run the following"
   echo -e "\nvirtualenv -p python3 $VIRTUALENV_NAME
source ~/$VIRTUALENV_NAME/bin/activate
"

} | tee $LOG_FILE
