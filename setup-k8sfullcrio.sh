#!/bin/bash
# $Id: setup-k8sfullcrio.sh 451 2022-05-10 05:29:17Z bpahlawa $
# initially captured from Microsoft website
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2022-05-10 13:29:17 +0800 (Tue, 10 May 2022) $
# $Revision: 451 $


trap exitshell SIGINT SIGTERM
export NOOFWORKERS
export K8SMASTER
export K8SNODE
ENVFILE=.${0}.env

CURRDIR=$(pwd)

exitshell()
{
   echo -e "${NORMALFONT}Cancelling script....exiting....."
   stty sane
   exit 0
}

export THEUSER="${KUBE_USER:-k8s}"
export SCRIPTDIR=`dirname $0` && [[ "$SCRIPTDIR" = "." ]] && SCRIPTDIR=`pwd`
export KUBEPARAMINIT="--pod-network-cidr=10.244.0.0/16"
export DEFAULT_STORAGE="/mnt/local-storage"
export KUBESTORAGE="${KUBE_STORAGE:-/var/lib/kubelet}"
export CONTAINERSTORAGE="${CONTAINER_STORAGE:-/var/lib/containers}"
export password=""
export password2="X"
export LOCALSTGMINSIZE=15
export DISTRO=""
export VERSION_ID=""
export FULL_VERSION_ID=""
export CRIO_VERSION="1.22"
export FLANNEL="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
export CALICO="https://docs.projectcalico.org/manifests/calico.yaml"
export CILIUM="https://raw.githubusercontent.com/cilium/cilium/1.7.2/install/kubernetes/quick-install.yaml"
#export DASHBOARD="https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml"
export DASHBOARD="https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended.yaml"
export LANG=en_US.UTF-8
# Wait for 5 minutes for the cluster to be ready.
#
export TIMEOUT=600
export RETRY_INTERVAL=5

enter_input()
{
   local QUESTION="$1"
   local HIDDEN="$2"
   [[ "$HIDDEN" != "" ]] && read -sp "$QUESTION : " ANS || read -p "$QUESTION : " ANS
   export ANS
}

is_running()
{ 
   local HOST="$1"
   ping -c1 $HOST 1>/dev/null 2>/dev/null
   return $?
}

check_master_worker()
{ 
  [[ -f $ENVFILE ]] && source $ENVFILE
  if [ "$K8SMASTER" = "" ]
  then
	  enter_input "Please specify Master Node default=$(hostname)"
	  K8SMASTER=${ANS:-$(hostname)}
	  echo "export K8SMASTER=\"$K8SMASTER\"" >> $ENVFILE
	  is_running $K8SMASTER
	  [[ $? -ne 0 ]] && echo "Master node $K8SMASTER is not running.. exiting.." && exit 1 || echo "Master Node $K8SMASTER is alive !"
  fi
  if [ "$K8SNODE" = "" ]
  then
	  enter_input "Please specify Worker Node base name"
	  K8SNODE="$ANS"
	  echo "export K8SNODE=\"$K8SNODE\"" >> $ENVFILE
  fi
  if [ "$NOOFWORKERS" = "" ]
  then
	  [[ "$NOOFWORKERS" = "" ]] && enter_input "Please specify no of worker nodes"
	  NOOFWORKERS="$ANS"
	  echo "export NOOFWORKERS=\"$NOOFWORKERS\"" >> $ENVFILE
  fi
  CNT=1
  while [ $CNT -le $NOOFWORKERS ]
  do
     is_running ${K8SNODE}${CNT}
     [[ $? -ne 0 ]] && echo "Worker node ${K8SNODE}${CNT} is not running.., all worker nodes must be running!!.. exiting.." && [[ -f $ENVFILE ]] && rm -f $ENVFILE && exit 1 || echo "Worker Node $K8SNODE${CNT} is alive !"
     CNT=$(( CNT + 1 ))
  done
}

    

get_distro_version()
{
   if [ -f /etc/os-release ]
   then
      ALLVER=`sed -n ':a;N;$bb;ba;:b;s/.*VERSION_ID="\([0-9\.]\+\)".*/\1/p' /etc/os-release`
      [[ "$ALLVER" = "" ]] && ALLVER="0"
      FULL_VERSION_ID="$ALLVER"
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

export K8SDEPLOY_DIR=k8sdeploy

# Name of virtualenv variable used.
#
export LOG_FILE="k8sdeploy.log"
export PROGRESS_FILE="k8sprogress.log"
export DEBIAN_FRONTEND=noninteractive
export PV_COUNT="${PVCOUNT:-30}"

# Kube version.
#
#KUBE_DPKG_VERSION=1.17.4-00
#KUBE_VERSION=1.17.4

# Make a directory for installing the scripts and logs.
#
mkdir -p $K8SDEPLOY_DIR
cd $K8SDEPLOY_DIR/
touch $LOG_FILE
touch $PROGRESS_FILE

reset_kubeadm()
{

   rm -rf /etc/cni
   rm -rf /etc/kubernetes
   rm -rf /var/lib/cni
   rm -rf /var/lib/etcd
   rm -rf /etc/cni
   rm -rf /var/run/kubernetes
   rm -rf /var/log/pods
   rm -rf /var/log/containers
   [[ -d /var/lib/etcd ]] && rm -rf /var/lib/etcd/*
   ip link list kube-ipvs0 2>/dev/null 1>/dev/null
   [[ $? -eq 0 ]] && echo "Deleting kube-ipvs0...." && ip link set dev kube-ipvs0 down && ip link delete kube-ipvs0
   [[ -d /run/calico ]] && rm -rf /run/calico
   [[ $(ip link list | grep tunl0  | wc -l) -ne 0 ]] && echo "Deleting interface calico tunl0...." && modprobe -r ipip
   [[ -d /run/flannel ]] && rm -rf /run/flannel
   ip link list flannel.1 2>/dev/null 1>/dev/null
   [[ $? -eq 0 ]] && echo "Deleting interface flannel flannel.1...." && ip link set dev flannel.1 down && ip link delete flannel.1

   [[ -d /run/cilium ]] && rm -rf /run/cilium
   ip link list cilium_host 2>/dev/null 1>/dev/null
   [[ $? -eq 0 ]] && echo "Deleting interface cilium host and net...." && ip link delete cilium_vxlan && ip link delete cilium_net && ip link delete cilium_host

   ip link list weave 2>/dev/null 1>/dev/null
   if [ $? -eq 0 ]
   then
      echo "Deleting interface weavenet weave...." 
      [[ -d /usr/local/bin ]] && mkdir -p /usr/local/bin
      curl -L git.io/weave -o /usr/local/bin/weave 
      chmod ugo+x /usr/local/bin/weave
      /usr/local/bin/weave stop
      /usr/local/bin/weave reset --force
      ip link set dev weave down 
      ip link delete weave
   fi
   ip link list datapath 2>/dev/null 1>/dev/null
   [[ $? -eq 0 ]] && curl -L git.io/weave -o /tmp/weave && chmod ugo+rx /tmp/weave

   ip link list cni0 2>/dev/null 1>/dev/null
   if [ $? -eq 0 ]
   then
      echo "Deleting interface cni0...."
      ip link set dev cni0 down
      ip link delete cni0
   fi

}

destroy_everything()
{
echo "#########################################################################"
echo "####### Destroying and Uninstalling Kubernetes and its components #######"
echo "#########################################################################"
   KUBEPID=$(ps -eo pid,cmd | grep "bin/kubelet" | grep -v grep | awk '{print $1}')
   [[ "$KUBEPID" != "" ]] && echo "Killing kubelet..." && systemctl stop kubelet && kill -9 $KUBEPID 2>/dev/null 1>/dev/null
   kubeadm reset ${KUBEADMARG} -f <<EOF
y
EOF
    systemctl stop crio
   iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
   which nft
   [[ $? -eq 0 ]] && nft flush ruleset
   for MNTPOINT in `df | awk '{print $NF}' | egrep "kubelet|\/vol|containers|overlay on"`
   do
       umount $MNTPOINT
   done
   for MNTPOINT in `mount | egrep "kubelet|\/vol|containers|overlay on" | awk '{print $3}'`
   do
      umount $MNTPOINT
      rm -rf $MNTPOINT
   done

   reset_kubeadm
   delete_ephemeral_disks
   
   [[ -L /var/lib/kubelet ]] && rm -rf $(readlink /var/lib/kubelet) && rm -f /var/lib/kubelet
   [[ -d /var/lib/kubelet ]] && rm -rf /var/lib/kubelet
   [[ -L /var/lib/containers ]] && rm -rf $(readlink /var/lib/containers) && rm -f /var/lib/containers
   [[ -d /var/lib/containers ]] && rm -rf /var/lib/containers
   get_distro_version
   case "$DISTRO" in
    "CENTOS"|"RHEL")
	    [[ -f /lib/systemd/system/containerd.service ]] && yum remove -y containerd*
            yum remove -y kube*
	    yum remove -y crio*
            [[ -f /etc/yum.repos.d/kubernetes.repo ]] && rm -f /etc/yum.repos.d/kubernetes.repo
	    ;;

    "UBUNTU"|"DEBIAN")
            apt-get purge -y kube*
            [[ -f /lib/systemd/system/containerd.service ]] && apt-get purge -y containerd*
	    apt-get purge -y cri-o cri-o-runc
            [[ -f /etc/apt/sources.list.d/kubernetes.list ]] && rm -f /etc/apt/sources.list.d/kubernetes.list
	    ;;
    "ARCH")
	    pacman -Rs kubeadm-bin kubelet-bin kubectl-bin kubernetes-cni-bin cri-o crictl
	    ;;
    "SUSE") 
            zypper remove cri-o
            ;;
   esac

   find / \( -name "kubelet" \) -exec rm -rf {} \;  2>/dev/null
   cd $CURRDIR 
   [[ -d $K8SDEPLOY_DIR ]] && rm -rf $K8SDEPLOY_DIR

}

modify_ssl_config()
{
    if [ "$DISTRO" = "DEBIAN" -a "$VERSION_ID" -ge 10 ]
    then
       SSLCONFIG=`find /etc -name "openssl*cnf"`
       if [ "$SSLCONFIG" != "" ]
       then
          DEBIAN10SSLCONFIG=`sed -n "s/^\(\[default_conf.*\)/\1/p" $SSLCONFIG`
          if [ "$DEBIAN10SSLCONFIG" != "" ]
          then
          echo "Modifying $SSLCONFIG as Kubernetes is not compatible with TLS v1.2 or later...."
             sed -i "s/^\(\[default_conf.*\)/\n#Commented out by setup-bdc.sh $(date)\n#\1/g; s/^\(ssl_conf.*\|openssl_conf.*\)/#\1/g" $SSLCONFIG
          fi
       fi
       update-alternatives --set iptables /usr/sbin/iptables-legacy
       update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
       [[ -f /usr/sbin/arptables-legacy ]] && update-alternatives --set arptables /usr/sbin/arptables-legacy
       update-alternatives --set ebtables /usr/sbin/ebtables-legacy

    elif [ \( "$DISTRO" = "CENTOS" -o "$DISTRO" = "RHEL" \) -a $VERSION_ID -ge 8 ]
    then
       echo "Checking crypto policy of $DISTRO $VERSION_ID"
       CRYPTOVER=`update-crypto-policies --show`
       echo "Current crypto policy is $CRYPTOVER"
       [[ "$CRYPTOVER" != "LEGACY" ]] && echo "Setting crypto policy to LEGACY.." && update-crypto-policies --set LEGACY
    else
       echo "Current crypto policy is suitable for this kubernetes cluster..........."
    fi
}

install_pkg_centos()
{
   echo "Checking kubernetes version..."
   K8SVER=`kubelet --version | sed -n  's/.*v[0-9].\([0-9]\+\)./\1/p'`
      [[ $K8SVER -lt 170 ]] && echo "Removing kubernetes version $K8SVER on $DISTRO..." && yum remove -y kube*
   
   echo "Updating centos...."
   yum-complete-transaction --cleanup-only
   yum update all
   yum update -y
   echo "Installing libraries....."
   yum install -y curl ca-certificates software-properties-common yum-utils device-mapper-persistent-data lvm2 wget
   
   if [ ! -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list ]
   then
       curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_${VERSION_ID}/devel:kubic:libcontainers:stable.repo > /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo
       curl -L http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/CentOS_${VERSION_ID}/devel:kubic:libcontainers:stable:cri-o:1.22.repo > /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.22.repo
   fi
   
   echo "Adding kubernetes repo...."
   cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

   echo "Install kubelet kubeadm and kubectl..."
   yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
   echo "Installing ebtables and ethtool..."
   yum install -y ebtables ethtool
   echo "Installing cri-o and cri-o-runc..."
   yum install -y cri-o cri-o-runc
   add_crio_netconfig
   systemctl restart crio
   export KUBEADMARG="--cri-socket /var/run/crio/crio.sock"


}

install_pkg_suse()
{
   zypper -n update
   zypper -n in curl socat ebtables 
   zypper -n in bridge-utils
   zypper addrepo -G https://download.opensuse.org/repositories/home:darix:apps/SLE_15_SP1/home:darix:apps.repo
   zypper addrepo -G https://download.opensuse.org/repositories/home:RBrownSUSE:k118:v2/openSUSE_Tumbleweed/home:RBrownSUSE:k118:v2.repo
   zypper ref
   zypper -n in cri-o kubernetes-kubeadm
   zypper -n in kubernetes-kubelet
   zypper -n remove kubernetes-client
   zypper -n in kubernetes-client
   if [ -f /etc/sysconfig/kubelet ]
   then
      if [ `grep "KUBELET_EXTRA_ARGS" /etc/sysconfig/kubelet | wc -l` -ne 0 ]
      then
         [[ -f /usr/lib/cni/bridge ]] && sed -i 's/\(KUBELET_EXTRA_ARGS.*\)"\(.*\)"/\1"--cni-bin-dir=\/usr\/lib\/cni"/g' /etc/sysconfig/kubelet
      else
         echo "KUBELET_EXTRA_ARGS=\"--cni-bin-dir=/usr/lib/cni\"" >> /etc/sysconfig/kubelet
      fi
   fi
   export KUBEADMARG="--cri-socket /var/run/dockershim.sock"
}

install_pkg_ubuntu()
{

   if [ `grep "^en_US.UTF-8" /etc/locale.gen | wc -l` -eq 0 ]
   then
      echo "en_US.UTF-8 UTF-8" >>  /etc/locale.gen
      dpkg-reconfigure locales
   fi

   echo "Checking kubernetes version..."
   K8SVER=`kubelet --version 2>/dev/null| sed -n  's/.*v[0-9].\([0-9]\+\)./\1/p' 2>/dev/null`
   [[ $K8SVER -lt 170 ]] && echo "Removing kubernetes version $K8SVER on UBUNTU..." && apt --yes purge kube*
   apt --yes install curl lsb-release
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
   curl -sL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
   if [ ! -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list ]
   then
       echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${FULL_VERSION_ID}/ /"| tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
       curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${FULL_VERSION_ID}/Release.key | sudo apt-key add -
       echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/xUbuntu_${FULL_VERSION_ID}/ /"|sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list
       curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${FULL_VERSION_ID}/Release.key | sudo apt-key add -
   fi
   if [ ! -f /etc/apt/sources.list.d/kubernetes.list ]
   then
      K8SREPO=`curl -L http://apt.kubernetes.io/dists | grep "kubernetes-$(lsb_release -cs)" | sed 's/.*>\([a-z\-]\+\)<.*/\1/g' | grep -Ev 'update|unstable'`
      [[ "$K8SREPO" = "" ]] && K8SREPO="kubernetes-xenial"
      cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ $K8SREPO main
EOF
   fi
   apt-get update -q
   apt-get upgrade -y -q
   apt --yes install apt-transport-https software-properties-common selinux-utils ebtables ethtool
   apt-get install -q -y python3 python3-pip python3-dev locales bridge-utils
   apt-get install -q -y libkrb5-dev libsqlite3-dev unixodbc-dev
   apt-get install -q -y kubelet kubeadm kubectl
   apt-get install -q -y cpp
   apt-get install -q -y cri-o cri-o-runc
   locale-gen en_US.UTF-8
   export KUBEADMARG="--cri-socket /var/run/crio/crio.sock"
   PIP=pip3
   add_crio_netconfig
   systemctl restart crio
}


install_pkg_debian()
{
   if [ `grep "^en_US.UTF-8" /etc/locale.gen | wc -l` -eq 0 ]
   then
      echo "en_US.UTF-8 UTF-8" >>  /etc/locale.gen
      dpkg-reconfigure locales
   fi

   if [ -f /var/lib/dpkg/lock ]
   then
      rm -f /var/lib/dpkg/lock
      dpkg --configure -a
   fi

   echo "Checking kubernetes version..."
   K8SVER=`kubelet --version 2>/dev/null| sed -n  's/.*v[0-9].\([0-9]\+\)./\1/p'`
   [[ $K8SVER -lt 170 ]] && echo "Removing kubernetes version $K8SVER on DEBIAN..." && apt --yes purge kube*
   apt --yes install curl lsb-release
   if [ $VERSION_ID -ge 10 ]
   then
      apt --yes purge iptables && apt --yes install gnupg2
   fi
   apt-get update
   curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
   curl -sL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
   if [ ! -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list ]
   then
       echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_${VERSION_ID}/ /"| tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
       curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_${VERSION_ID}/Release.key | sudo apt-key add -
       echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/Debian_${VERSION_ID}/ /"|sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list
       curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_${VERSION_ID}/Release.key | sudo apt-key add -

   fi
   if [ ! -f /etc/apt/sources.list.d/kubernetes.list ]
   then
      cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
   fi
   case "$VERSION_ID" in
   10)
       apt-get update -t buster-backports
       ;;
   *)  apt-get update -q
       ;;
   esac
   apt --yes install apt-transport-https ca-certificates gnupg2 software-properties-common selinux-utils ebtables ethtool
   apt-get install --yes python3 python3-pip python3-dev locales bridge-utils
   apt-get update -q
   apt-get upgrade -q
   apt-get install -y libkrb5-dev libsqlite3-dev unixodbc-dev
   apt-get install -y kubelet kubeadm kubectl
   apt-get install -y libssl-dev
   apt-get install -y cpp
   apt-get install --yes cri-o cri-o-runc
   locale-gen en_US.UTF-8
   export KUBELET_EXTRA_ARGS="--cgroup-driver=systemd --cni-bin-dir=/usr/lib/cni"
   export KUBEADMARG="--cri-socket /var/run/crio/crio.sock"
   PIP=pip3
   add_crio_netconfig
   systemctl restart crio
}


add_crio_netconfig()
{
   
   if [ -d /etc/crio/crio.conf.d ]
   then
	   if [ $(grep "\/opt\/cni\/bin" /etc/crio/crio.conf.d/* | wc -l) -eq 0 ]
	   then
		 echo "Adding crio network configuration..."

		 echo -e "[crio.network]
network_dir = \"/etc/cni/net.d/\"
plugin_dirs = [
        \"/opt/cni/bin/\",
        \"/usr/libexec/cni/\",
]
" > /etc/crio/crio.conf.d/10-crio-network.conf
           else
	       echo "crio network has been configure.."
	   fi
   else
         mkdir -p /etc/crio/crio.conf.d
         echo -e "[crio.network]
network_dir = \"/etc/cni/net.d/\"
plugin_dirs = [
        \"/opt/cni/bin/\",
        \"/usr/libexec/cni/\",
]
" > /etc/crio/crio.conf.d/10-crio-network.conf
 
	 echo "Added crio.network into /etc/crio/crio.conf.d/10-crio-network.conf"
   fi
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
   pacman -Sy --noconfirm curl git sudo wget ebtables ethtool unzip conntrack-tools socat cni-plugins
   pacman -Sy --noconfirm python fakeroot binutils make
   wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
   python /tmp/get-pip.py
   pacman -Sy --noconfirm sqlite unixodbc krb5 gcc
   pacman -Sc --noconfirm
   [[ `grep "git " /etc/sudoers | wc -l` -eq 0 ]] && echo "git ALL=(ALL)   NOPASSWD: ALL" >> /etc/sudoers
   su - git -s /bin/bash -c "
cd /tmp
git clone https://aur.archlinux.org/kubernetes-cni-bin.git
cd kubernetes-cni-bin
makepkg -si --noconfirm
cd ..
rm -rf kubernetes-cni-bin
git clone https://aur.archlinux.org/kubelet-bin.git
cd kubelet-bin
makepkg -si --noconfirm
cd ..
rm -rf kubelet-bin
git clone https://aur.archlinux.org/kubeadm-bin.git
cd kubeadm-bin
makepkg -si --noconfirm
cd ..
rm -rf kubeadm-bin
git clone https://aur.archlinux.org/kubectl-bin.git
cd kubectl-bin
makepkg -si --noconfirm
cd ..
rm -rf kubectl-bin
"
   pacman -Sy --noconfirm cri-o crictl
   export KUBEADMARG="--cri-socket /var/run/crio/crio.sock"
   export KUBELET_EXTRA_ARGS="--cni-bin-dir=/opt/cni/bin --cni-conf-dir=/etc/cni/net.d"
   systemctl restart kubelet
   PIP=pip
   add_crio_netconfig



}


install_prereqs()
{

[[ "$(grep PREREQS $PROGRESS_FILE)" = "PREREQS" ]] && echo -e ">>>>>>>>>> All prerequisites have been installed!.. skipping...\n" && return
#
#
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

if [ `grep $THEUSER /etc/passwd | wc -l` -eq 0 ]
then
   echo "Creating user $THEUSER ..."
   [[ ! -d /home/$THEUSER ]] && mkdir -p /home/$THEUSER
   useradd -d /home/$THEUSER $THEUSER
else
   echo "Checking user $THEUSER ..."
   [[ ! -d /home/$THEUSER ]] && mkdir -p /home/$THEUSER && usermod -d /home/$THEUSER $THEUSER
fi

[[ `cat $PROGRESS_FILE | grep "USER=" | wc -l` -eq 0 ]] && echo "USER=${THEUSER}" >> $PROGRESS_FILE
[[ `grep "${THEUSER}.*bash" /etc/passwd | wc -l` -eq 0 ]] && usermod -s /bin/bash $THEUSER
chown -Rh $(grep "^${THEUSER}:" /etc/passwd | cut -f3-4 -d":") /home/${THEUSER}

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

# Load all pre-requisites for Kubernetes.
#
echo "#########################################################################"
echo "############## Setting up pre-requisites for Kubernetes #################"
echo "#########################################################################"

[[ $(grep $(hostname) /etc/hosts | wc -l) -eq 0 ]] && echo "$(hostname -i) $(hostname)" >> /etc/hosts

echo "Swap must be turned off and modify /etc/fstab to exclude swap"
swapoff -a
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab


echo "Enabling kubelet on systemd..."
systemctl enable kubelet

# Holding the version of kube packages.
#
echo "Downloading helm..."
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash

echo -e "overlay\nbr_netfilter" > /etc/modules-load.d/containerd.conf
modprobe br_netfilter
modprobe overlay

# Disable Ipv6 for cluster endpoints.
#
echo "Adding necessary kernel parameters to /etc/sysctl.conf..."
echo net.ipv6.conf.all.disable_ipv6=1 > /etc/sysctl.conf
echo net.ipv6.conf.default.disable_ipv6=1 >> /etc/sysctl.conf
echo net.ipv6.conf.lo.disable_ipv6=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf
echo net.bridge.bridge-nf-call-ip6tables=1 >> /etc/sysctl.conf


echo "Activating kernel parameters..."
sysctl --system

echo "Kubernetes pre-requisites have been completed."
echo PREREQS >> $PROGRESS_FILE
}

install_calico_nftables()
{
    wget -O /tmp/calico.yaml $CALICO
    sed -i ':a;N;$!ba;s/# Disable IPv6 on Kubernetes.\n/# Added by setup-k8s for nfttable\n            - name: FELIX_IPTABLESBACKEND\n              value: "Auto"\n/g' /tmp/calico.yaml
    echo "Installing calico nftables"
    kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /tmp/calico.yaml
}


install_network()
{
echo "#########################################################################"
echo "#####################  Installing Network plugin ########################"
echo "#########################################################################"
   echo "Installing CNI plugin...."
   case "$DISTRO" in 
   'DEBIAN')
	   if [ "$VERSION_ID" -ge "10" ] 
           then
               #echo "This linux version uses nftables, therefore calico plugin must be used!" 
               #install_calico_nftables
               update-alternatives --set iptables /usr/sbin/iptables-legacy
               update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
               [[ -f /usr/sbin/arptables-legacy ]] && update-alternatives --set arptables /usr/sbin/arptables-legacy
               update-alternatives --set ebtables /usr/sbin/ebtables-legacy
               #return
           fi
           ;;
   'CENTOS'|'RHEL')
	   [[ "$VERSION_ID" -ge "8" ]] && echo "This linux version uses nftables................"
           ;;
   *)
	   echo "Using network plugin $CNIPLUGIN"
           ;;
   esac
   [[ "$CNIPLUGIN" = "WEAVENET" ]] && CNIPLUGIN="https://cloud.weave.works/k8s/net?k8s-version=$(kubectl --kubeconfig /etc/kubernetes/admin.conf version | base64 | tr -d '\n')" && /usr/local/bin/weave reset
   [[ -f /tmp/weave ]] && /tmp/weave reset && rm -f /tmp/weave
   kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f $CNIPLUGIN

}

setup_k8s()
{
[[ "$(grep SETUPK8S $PROGRESS_FILE)" = "SETUPK8S" ]] && echo -e ">>>>>>>>>> Kubernetes has been installed!.. skipping...\n" && return
echo "#########################################################################"
echo "###################  Setting up Kubernetes $THENODE  ####################"
echo "#########################################################################"


if [ "$MODE" = "add-worker" ]
then
   CURRHOST=$(kubectl get nodes --no-headers=true --output=custom-columns=NAME:.metadata.name `hostname` 2>/dev/null 1>/dev/null)
   [[ "$CURRHOST" != "" ]] && kubectl delete node $CURRHOST
fi

if [ `ps -ef | grep "bin/kubelet" | grep -v grep | wc -l` -gt 0 ]
then
   KUBEPID=`ps -eo pid,cmd | grep "bin/kubelet" | grep -v grep | awk '{print $1}'`
   [[ "$KUBEPID" != "" ]] && echo "Killing kubelet..." && systemctl stop kubelet && kill -9 $KUBEPID 2>/dev/null 1>/dev/null
fi

if ([ `ps -ef | grep "bin/kubelet" | grep -v grep | wc -l` -lt 2 ] && ([ "$MODE" = "reset-master" ] || [ "$MODE" = "reset-single" ])) || ([ "$MODE" = "add-worker" ] || [ "$MODE" = "reset-worker" ])
then
   KUBEPID=`ps -eo pid,cmd | grep "bin/kubelet" | grep -v grep | awk '{print $1}'`
   [[ "$KUBEPID" != "" ]] && echo "Killing kubelet..." && systemctl stop kubelet && kill -9 $KUBEPID 2>/dev/null 1>/dev/null
   kubeadm reset ${KUBEADMARG} -f <<EOF
y
EOF

if [ `ps -ef | grep "bin/crio" | grep -v grep | wc -l` -gt 0 ]
then
   for CONTAINERDPID in `ps -eo pid,cmd | grep "bin/crio" | grep -v grep | awk '{print $1}'`
   do
      echo "Killing crio..." && systemctl stop crio && kill -9 $CONTAINERDPID 2>/dev/null 1>/dev/null
   done
   systemctl restart crio
   for CONTAINERDPID in `ps -eo pid,cmd | grep "bin/conmon" | grep -v grep | awk '{print $1}'`
   do
      echo "Killing conmon..." && kill -9 $CONTAINERDPID 2>/dev/null 1>/dev/null
   done
fi
   iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
   which nft
   [[ $? -eq 0 ]] && nft flush ruleset
   for MNTPOINT in `df --output=target | egrep "kubelet"`
   do
       umount $MNTPOINT
   done

   reset_kubeadm
   delete_ephemeral_disks
   
   if [ "$KUBESTORAGE" != "/var/lib/kubelet" ]
   then
      echo "Relocating /var/lib/kubelet to $KUBESTORAGE ...." 
      [[ -d /var/lib/kubelet ]] && rm -rf /var/lib/kubelet
      mkdir -p $KUBESTORAGE
      [[ $? -ne 0 ]] && echo "Failed to create $KUBESTORAGE, exiting..." && exit 1
      ln -s $KUBESTORAGE /var/lib/kubelet
   fi


   if [ "$CONTAINERSTORAGE" != "/var/lib/containers" ]
   then
      echo "Relocating /var/lib/containers to $CONTAINERSTORAGE ...." 
      [[ -d /var/lib/containers ]] && rm -rf /var/lib/containers
      mkdir -p $CONTAINERSTORAGE
      [[ $? -ne 0 ]] && echo "Failed to create $CONTAINERSTORAGE, exiting..." && exit 1
      ln -s $CONTAINERSTORAGE /var/lib/containers
   fi

   systemctl restart crio
   if [ "$(echo $MODE | grep worker | cut -f2 -d'-')" = "worker" ]
   then
      echo "Joining cluster...."
      echo "Executing command $KUBEADM_JOIN_CMD $KUBEADMARG ...................."
      sleep 5
      $KUBEADM_JOIN_CMD $KUBEADMARG
      [[ ! -d /home/$THEUSER/.kube ]] && mkdir -p /home/$THEUSER/.kube
      #MASTERNODE=`echo $KUBEADM_JOIN_CMD $KUBEADMARG | awk '{print $3}' | cut -f1 -d':'`
      #scp ${MASTERNODE}:/etc/kubernetes/admin.conf /home/${THEUSER}/.kube/config
      [[ -d /etc/kubernetes ]] && [[ -f /home/$THEUSER/.kube/config ]] && cp /home/${THEUSER}/.kube/config /etc/kubernetes/admin.conf
      chown -Rh $(grep "^${THEUSER}:" /etc/passwd | cut -f3-4 -d":") /home/${THEUSER}
   elif [ "$(echo $MODE | grep master | cut -f2 -d'-')" = "master" -o "$(echo $MODE | grep single | cut -f2 -d'-')" = "single" ]
   then
      echo "Initializing master/single node...."
      echo "Executing kubeadm init $KUBEPARAMINIT $KUBEADMARG"
      set -x
      ps -ef | grep container
      kubeadm init ${KUBEPARAMINIT} ${KUBEADMARG}
      [[ ! -d /home/$THEUSER/.kube ]] && mkdir -p /home/$THEUSER/.kube
    
      cp -f /etc/kubernetes/admin.conf /home/$THEUSER/.kube/config
      chown -Rh $(grep "^${THEUSER}:" /etc/passwd | cut -f3-4 -d":") /home/${THEUSER}
      install_network
      set +x
   else
      echo "Resuming...................."
   fi
else
   echo "Using current configuration.........."
fi

# To enable a single node cluster remove the taint that limits the first node to master only service.
#
echo SETUPK8S >> $PROGRESS_FILE
}

untaint_master_node()
{
echo -e "\nUn-taint master node......\n"
su - $THEUSER -c "
master_node=\`kubectl get nodes --no-headers=true --output=custom-columns=NAME:.metadata.name\`
kubectl taint nodes \${master_node} node-role.kubernetes.io/master:NoSchedule- 2>/dev/null 
"
}

setup_local_disk()
{
[[ "$(grep SETUPLOCALDISK $PROGRESS_FILE)" = "SETUPLOCALDISK" ]] && echo -e ">>>>>>>>>> Local disk storage has been created !.. skipping...\n" && return
echo -e "\nSetting up local disk storage.....\n"

# Setting up the persistent volumes for the kubernetes.
echo "#########################################################################"
echo "##############  Setting up local disk for persistent volume #############"
echo "#########################################################################"
echo "Creating local persistent volumes under directory ${LOCALSTORAGE}..."
for i in $(seq 1 $PV_COUNT); do

  vol="vol$i"
  [[ ! -d ${LOCALSTORAGE}/$vol ]] && mkdir -p ${LOCALSTORAGE}/$vol
  [[ "$(df ${LOCALSTORAGE}/$vol | awk '{print $NF}' | sed 1d)" = "${LOCALSTORAGE}/$vol" ]] && umount ${LOCALSTORAGE}/$vol && rm -rf ${LOCALSTORAGE}/$vol/*

  mount --bind ${LOCALSTORAGE}/$vol ${LOCALSTORAGE}/$vol
  [[ $? -ne 0 ]] && echo "Error: mounting local-storage............................" && exit 1

done

[[ -f /tmp/local-storage-provisioner.yaml ]] && chown $THEUSER /tmp/local-storage-provisioner.yaml

su - $THEUSER -c "

wget https://raw.githubusercontent.com/microsoft/sql-server-samples/master/samples/features/sql-big-data-cluster/deployment/kubeadm/ubuntu/local-storage-provisioner.yaml -O /tmp/local-storage-provisioner.yaml

if [ -f /tmp/local-storage-provisioner.yaml ]
then
   echo \"Modifying file local-storage-provisioner.yaml\"
   THEMOUNT=\`grep mountDir /tmp/local-storage-provisioner.yaml | awk '{print \$2}' | sed 's/\//\\\\\\\\\//g'\`
   THESTORAGE=\`echo ${LOCALSTORAGE} | sed 's/\//\\\\\\\\\//g'\`
   echo \"Replacing \$THEMOUNT with \$THESTORAGE .....\"
   sed -i \"s/\${THEMOUNT}/\${THESTORAGE}/g\" /tmp/local-storage-provisioner.yaml
   kubectl apply -f /tmp/local-storage-provisioner.yaml
   rm -f /tmp/local-storage-provisioner.yaml
fi
helm init
"

echo SETUPLOCALDISK >> $PROGRESS_FILE
}


is_cluster_ready()
{
# Verify that the cluster is ready to be used.
#
su - $THEUSER -c "
TIMEOUT=${TIMEOUT}
echo \"Verifying that the cluster is ready for use...\"
while true ; do
    if [ \$TIMEOUT -le 0 ]
    then
        echo \"Cluster node failed to reach the 'Ready' state. Kubeadm setup failed.\"
        exit 1
    fi

    STAT=\`kubectl get nodes --no-headers=true | egrep \"$(hostname -s) |$(hostname -f) \" | awk '{print \$2}'\`

    if [ \"\$STAT\" = \"Ready\" ]; then
        break
    fi

    sleep $RETRY_INTERVAL

    TIMEOUT=\$((\$TIMEOUT-$RETRY_INTERVAL))

    echo \"## $(hostname -s) ## Cluster not ready. Retrying...\"
done
"
}

install_k8s_dashboard()
{

[[ "$(grep K8SDASHBOARD $PROGRESS_FILE)" = "K8SDASHBOARD" ]] && echo -e ">>>>>>>>>> Kubernetes dashboard has been installed!.. skipping...\n" && return

# Install the dashboard for Kubernetes.
#
su - $THEUSER -c "
kubectl apply -f $DASHBOARD
#kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
echo \"Kubernetes master setup done.\"
"
echo K8SDASHBOARD >> $PROGRESS_FILE
}

kill_kubelet_and_k8s()
{
   echo "Checking whether kubelet is running..."
   [[ `ps -ef | grep "bin/kubelet" | grep -v grep | wc -l` -ne 0 ]] && echo "Stopping kubelet..." && systemctl stop kubelet
   MYPID=$$
   for listproc in `ps -ef | egrep "kubelet|crio" | grep -v "$MYPID " | awk '{print $2}'`
   do
      kill -9 $listproc 2>/dev/nulll 1>/dev/null
   done
}

#this is how to use this script
usage_k8s()
{
   echo -e "\nUsage: \n    $0 -u <k8s_user> -l <local_storage_path> -k <kubelet_storage> -c <container_storage> -s <storage_class> -n <network-plugin>"
   echo -e "\n    -m mode [reset-all|destroy-all|reset-single|reset|single|''(default)]\n    -u k8s-user [any-name|k8s(default)]"
   echo -e "\n    -l local-storage [any-mountpoint|/mnt/local-storage(default)]\n    -k kubelet-storage [any-mountpoint|/var/lib/kubelet(default)]"
   echo -e "\n    -c container-storage [any-mountpoint|/var/lib/containers(default)]\n    -s storageclass [any-storageclass|local-storage]"
   echo -e "\n    -n network [f flannel|c calico(default)]"
   echo -e "    E.g: $0 -m reset-single -u kube -l /opt/local-storage -k /opt/kubelet -c /opt/containers -n f"
   echo -e "         $0 -m reset-master -u kube -l /opt/local-storage -c /opt/containers -s csi-rbd-ceph #using storageclass csi-rbd-ceph and calico network(default)"
   echo -e "         $0 -m reset-master -u kuser -c /opt/containers #the rest parameters will be using default values\n"
   exit 1
}


get_params()
{
   local OPTIND
   while getopts "m:u:l:s:k:c:n:o:h" PARAM
   do
      case "$PARAM" in
      m) 
          #mode
          MODE=${OPTARG}
          ;;
      u)
          #Kube user
          KUBE_USER=${OPTARG}
          THEUSER=$KUBE_USER
          ;;
      l)
          #local storage
          LOCAL_STORAGE=${OPTARG}
          LOCALSTORAGE=$LOCAL_STORAGE
          ;;
      s)
          #storage class
          STORAGE_CLASS=${OPTARG}
          ;;

      k)
          #kubelet storage
          KUBE_STORAGE=${OPTARG}
          KUBESTORAGE=$KUBE_STORAGE
          ;;
      c)
          #containers storage
          CONTAINER_STORAGE=${OPTARG}
          CONTAINERSTORAGE=$CONTAINER_STORAGE
          ;;
      n)
	  #network orchestration
	  CNIPARAM=${OPTARG}
	  ;;
      h)
          #display this usage
          usage_k8s
          ;;
      ?)
          echo -e "\nError:  Unknown parameter(s)...\n"
          usage_k8s
      esac
    done

    shift $((OPTIND-1))

    case "$CNIPARAM" in
    'f')
        CNIPLUGIN="$FLANNEL"
        NETPLUGIN="Flannel"
	;;
    'c')
	CNIPLUGIN="$CALICO"
        NETPLUGIN="Calico"
	export KUBEPARAMINIT="$KUBEPARAMINIT --service-cidr=10.245.0.0/16"
        ;;
    'ci')
	CNIPLUGIN="$CILIUM"
        NETPLUGIN="Cilium"
        ;;
    'w')
	CNIPLUGIN="WEAVENET"
        [[ ! -d /usr/local/bin ]] && mkdir -p /usr/local/bin 
        [[ ! -f /usr/local/bin/weave ]] &&  curl -L git.io/weave -o /usr/local/bin/weave && chmod ugo+rx /usr/local/bin/weave
        NETPLUGIN="Weave"
	 export KUBEPARAMINIT=""
        ;;
    *)
	CNIPLUGIN="$CALICO"
        NETPLUGIN="Calico"
	export KUBEPARAMINIT="$KUBEPARAMINIT --service-cidr=10.245.0.0/16"
    esac

}

check_mountpoint()
{
local STORAGE="$1"
        [[ "$STORAGE" = "" ]] && return 0
	if [ ! -d $STORAGE ]
        then
            STORAGEPARENT=$(dirname $STORAGE)
            echo "The mountpoint $STORAGE is not available, however the parent directory is mounted under $STORAGEPARENT"
            STORAGEPARENT=$(df $STORAGEPARENT | awk '{print $NF}' | tail -1)
            if [ "$STORAGEPARENT" = "/" ]
            then
               echo -e "\nThe mount $STORAGE will be created under root '/' filesystem, please mount it on a different filesystem\n" && exit 1
            else
	       DFSIZE=`df -m $STORAGEPARENT | awk '{print $4}' | tail -1`
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
	       DFSIZE=`df -m $STORAGE | awk '{print $4}' | tail -1`
               MOUNTPOINT=`df $STORAGE | awk '{print $NF}' | tail -1`
            fi
        fi
}

check_diskspace()
{
   if [ "$MODE" != "" -a "$MODE" != "single" ]
   then
      echo "Checking Local storage"
      check_mountpoint "$LOCALSTORAGE"
      LCURRSIZE=$CURRSIZE
      LFREESIZE=$((DFSIZE/1024))
      LMOUNTPOINT=$MOUNTPOINT

   fi
}

remove_offending_key()
{
set -x
   local IPADDR="$1"
   OFFENDINGLINE=$(ssh-copy-id $IPADDR 2>&1 | grep "ERROR: Offending ECDSA key in")
   if [ "$OFFENDINGLINE" != "" ]
   then
      THELINE=$(echo $OFFENDINGLINE | awk '{print $NF}' | tr -d '\r')
      OLINE=$(echo $THELINE | cut -f1 -d:)
      OLINENO=$(echo $THELINE | cut -f2 -d:)
      if [ $OLINENO -gt 0 ]
      then
         sed -i "${OLINENO}d" $OLINE
      fi
   fi
set +x
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
         remove_offending_key "$IPADDR"         
         echo "\nIf you dont know the root password press Ctrl+c then please ask someone who knows !!...\n"
         ssh-copy-id $IPADDR
         sleep 2
      done
   else
      yes 'y' | ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
      ssh-copy-id $IPADDR
      while [ $? -ne 0 ]
      do
         remove_offending_key "$IPADDR"
         echo -e "\nIf you dont know the root password press Ctrl+c then please ask someone who knows !!...\n"
         ssh-copy-id $IPADDR
         sleep 2
      done
   fi
}


reset_only()
{
   su - $THEUSER -c "kubectl get nodes 2>/dev/null 1>/dev/null"
   if [ $? -eq 0 ]
   then
      HOSTNAME=`hostname`
      HOST2DELETE=`su - $THEUSER -c "kubectl get nodes --no-headers=true | grep -v master | grep $HOSTNAME |awk '{print \$1}'"`
      if [ "$HOST2DELETE" != "" ]
      then
          su - $THEUSER -c "kubectl drain $HOSTNAME --delete-emptydir-data --force --ignore-daemonsets"
          su - $THEUSER -c "kubectl delete node $HOSTNAME"
      else
          for host2del in `su - $THEUSER -c "kubectl get nodes --no-headers=true | grep -v $HOSTNAME | awk '{print \$1}'"`
          do
              su - $THEUSER -c "kubectl drain $HOSTNAME --delete-emptydir-data --force --ignore-daemonsets"
              su - $THEUSER -c "kubectl delete node $HOSTNAME"
          done
      fi
   fi
   if [ `ps -ef | grep "bin/kubelet" | grep -v grep | wc -l` -gt 0 ]
   then
       KUBEPID=`ps -eo pid,cmd | grep "bin/kubelet" | grep -v grep | awk '{print $1}'`
       [[ "$KUBEPID" != "" ]] && echo "Killing kubelet..." && systemctl stop kubelet && kill -9 $KUBEPID 2>/dev/null 1>/dev/null
   fi
   reset_kubeadm
   delete_ephemeral_disks

}

   
delete_ephemeral_disks()
{
   if [ -d /var/lib/kubelet ]
   then
        for MTPOINT in `mount  | grep "\\/var\\/lib\\/kubelet" | awk '{print $3}'`
        do
            echo "Unmounting kubelet bind volume $MTPOINT"
            umount $MTPOINT 2>/dev/null 1>/dev/null
        done
        rm -rf /var/lib/kubelet/*
   elif [ "$(readlink /var/lib/kubelet)" != "/var/lib/kubelet" -a "$(readlink /var/lib/kubelet)" != "" ]
   then
        KUBELETDIRPATTERN="$(readlink /var/lib/kubelet | sed 's|/|\\\/|g')"
        for MTPOINT in `mount  | grep "$KUBELETDIRPATTERN" | awk '{print $3}'`
        do
            echo "Unmounting kubelet bind volume $MTPOINT"
            umount $MTPOINT 2>/dev/null 1>/dev/null
        done
        rm -rf /var/lib/kubelet/*
   fi

   if [ -d /var/lib/containers ]
   then
        for MTPOINT in `mount  | grep "\\/var\\/lib\\/containers" | awk '{print $3}'`
        do
            echo "Unmounting containers bind volume $MTPOINT"
            umount $MTPOINT 2>/dev/null 1>/dev/null
        done
        rm -rf /var/lib/containers/*
   elif [ "$(readlink /var/lib/containers)" != "/var/lib/containers" -a "$(readlink /var/lib/containers)" != "" ]
   then
        CONTAINERSPATTERN="$(readlink /var/lib/containers | sed 's|/|\\\/|g')"
        for MTPOINT in `mount  | grep "$CONTAINERSPATTERN" | awk '{print $3}'`
        do
            echo "Unmounting containers bind volume $MTPOINT"
            umount $MTPOINT 2>/dev/null 1>/dev/null
        done
        rm -rf /var/lib/containers/*
   fi


   for MTPOINT in `mount  | grep "local-storage" | awk '{print $3}'`
   do
       echo "Unmounting local-storage bind volume $MTPOINT"
       umount $MTPOINT 2>/dev/null 1>/dev/null
       [[ $? -eq 0 ]] && rm -rf $MTPOINT
   done

}


run_setup()
{
  MODE="$1"
  {

   if [ "$MODE" = "reset-all" ]
   then
      echo "Resetting anything related to kubernetes..........."
      reset_only
      exit 0
   elif [ "$MODE" = "destroy-all" ]
   then
      echo "Destroying and Removing anything related to kubernetes..........."
      destroy_everything
      exit 0
   fi
   
   [[ "$(echo $MODE | grep reset | cut -f1 -d'-')" = "reset" ]] && RESET=1

   if [ "$(echo $MODE | grep worker | cut -f2 -d'-')" = "worker" ]
   then
      THENODE="WORKER"
   elif [ "$(echo $MODE | grep master | cut -f2 -d'-')" = "master" ]
   then
      THENODE="MASTER"
      THEMESSAGE="\nBootstraping a Kubernetes cluster.............."
   elif [ "$MODE" = "single" ]
   then
      THENODE="SINGLE"
      THEMESSAGE="\nResuming Kubernetes single cluster installation.."
      LOCALSTORAGE=`dirname $(mount  | grep "local-storage\/vol" | awk '{print $3}' | head -1) 2>/dev/null`
      if [ "$LOCALSTORAGE" != "" ]
      then
          STORAGE_CLASS="local-storage"
      else
          STORAGE_CLASS=`su - $THEUSER -c "kubectl get sc -A -o=jsonpath='{.items[0].metadata.name}' 2>/dev/null" 2>/dev/null`
      fi
   elif [ "$MODE" = "reset-single" ]
   then
      THENODE="SINGLE"
      THEMESSAGE="\nInstalling Kubernetes on a single cluster.."
   else
      if [ -d ../$K8SDEPLOY_DIR ]
      then
	 if [ $(cat $PROGRESS_FILE | wc -l) -eq 0 ]
         then
	     echo -e "\n\nit seems progress file has no entry.. please run setup-k8s.sh with the following parameters...."
	     usage_k8s
	     exit 0
	 fi
      else
	 echo -e "\n\nit seems you have never installed Kubernetes using this script before.. please run setup-k8s.sh with the the folling parameters :"
	 usage_k8s
	 exit 0
      fi
      THENODE="MASTER/WORKER"
   fi


   if [ "$RESET" = "1" ]
   then
      if [ "$LOCAL_STORAGE" != "" ]
      then 
          if [ "$STORAGE_CLASS" != "" ]
          then
             echo "Parameter -l (local storage location) is more precedence than parameter -s (storage class)"
             echo "Setting storage class to local-storage"
          fi
          STORAGE_CLASS="local-storage"
      else
	  if [ "$STORAGE_CLASS" != "" ]
          then
             echo -e "\nSetting storage class to $STORAGE_CLASS "
             echo -e "Please NOTE, if it is on a single cluster then you have to make sure this storage class \"$STORAGE_CLASS\" is available, otherwise the Kubernetes will fail!!"
             echo -e "             if it is on a master, you must ensure this storage class \"$STORAGE_CLASS\" is available before worker node is joined to this cluster!!\n\n"
	  fi
      fi 
   else
      if [ "$STORAGE_CLASS" = "" -a "$LOCALSTORAGE" != "" ]
      then
         echo -e "\nTrying to gather storage class from kubernetes cluster..."
         STORAGE_CLASS=`kubectl --kubeconfig=/etc/kubernetes/admin.conf get pv -o custom-columns=STORAGECLASS:.spec.storageClassName 2>/dev/null| grep -v "STORAGECLASS" | head -1`
         if [ $? -ne 0 ]
         then 
   	    echo "No storage class is defined....therefore $LOCALSTORAGE is used!...enforcing storage class=local-storage" 
   	    STORAGE_CLASS="local-storage"
         else
            LOCALSTORAGE=`kubectl --kubeconfig=/etc/kubernetes/admin.conf get pv -o custom-columns=LOCALSTG:.spec.local.path 2>/dev/null | grep -v "LOCALSTG" | head -1`
            if [ "$LOCALSTORAGE" = "" ]
            then
               LOCALSTORAGE="$LOCAL_STORAGE"
               STORAGE_CLASS="local-storage"
            else
   	       LOCALSTORAGE=`dirname $LOCALSTORAGE`
            fi
         fi
      elif [ "$LOCAL_STORAGE" != "" -a "$STORAGE_CLASS" != "" ]
      then
         echo "-l parameter is ignored as storage class has been specified!!"
         echo "Using kubernetes storage class $STORAGE_CLASS"
         LOCALSTORAGE="None"
      else
         echo "Using local storage previous setting....."
      fi
   fi 

   if [ `echo $STORAGE_CLASS | grep local | wc -l` -ne 0 ]
   then
      check_diskspace
   fi

   get_distro_version

   [[ "$(echo $MODE | grep reset | cut -f1 -d'-')" = "reset" || "$MODE" = "add-worker" ]] && > $PROGRESS_FILE && > $LOG_FILE && echo -e "\n\nResetting all configuration.... Reinstall everything from scratch!...\n" && echo -e "Shutdown kubelet and kubernetes..... " 
#&& kill_kubelet_and_k8s

   export KUBEADMARG=""
   USERFROMFILE=`sed -n 's/^USER=\([a-zA-Z0-9]\+\)/\1/p' $PROGRESS_FILE`
   if [ "$USERFROMFILE" != "$THEUSER" -a "$USERFROMFILE" != "" ]
   then
      [[ -d /home/$USERFROMFILE ]] && THEUSER="$USERFROMFILE"
   fi

   echo -e "You are running Linux distro : $DISTRO $ALLVER ....."
   echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
   echo -e "$THEMESSAGE"
   echo -e "\nRunning kubernetes on a $THENODE node"
   echo -e "\nKube Regular user   : $THEUSER "
   echo -e "\nKubelet storage     : $KUBESTORAGE " 
   echo -e "\nContainers storage  : $CONTAINERSTORAGE " 
   echo -e "\nUsing storage class : $STORAGE_CLASS "
   [[ "$MODE" = "reset-worker" || "$MODE" = "add-worker" ]] && NETPLUGIN="follow Master node"
   echo -e "\nNetwork plugin      : $NETPLUGIN "
   echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n"
   install_prereqs
   modify_ssl_config
   setup_k8s
   [[ "$MODE" = "single"  || "$MODE" = "reset-single" ]] && untaint_master_node

   ERROR=`su - $THEUSER -c "kubectl get nodes | grep \".*error.*\"" 2>&1`
   while [ "$ERROR" != "" ]
   do
      [[ "$ERROR" =~ .*command[[:space:]]not[[:space:]].* ]] && echo "Corrupted installation, exiting..." && exit 1
      echo "Error $ERROR , the kubelet may not be running, or kubernetes is broken..exiting...." 
      echo "However, it may be the problem with the config file is not copied.."
      if [ "$(echo $MODE | grep worker | cut -f2 -d'-')" = "worker" ]
      then
         [[ -f /etc/kubernetes/admin.conf ]] && cp /etc/kubernetes/admin.conf /home/$THEUSER/.kube/config
      fi
      ERROR=`su - $THEUSER -c "kubectl get nodes | grep \".*error.*\"" 2>&1`
      sleep 2
   done

   is_cluster_ready
   [[ "$MODE" = "single"  || "$MODE" = "reset-single" ]] && untaint_master_node
   [[ "$MODE" = "reset-master" ]] && echo "Installing k8s dashboard...." && install_k8s_dashboard


   if [ `echo $STORAGE_CLASS | grep local | wc -l` -ne 0 ]
   then
      setup_local_disk
   fi

   if [ "$MODE" = "reset-worker" ]
   then 
      echo "Setting this server as a worker node.." 
   elif [ "$MODE" = "reset-single" ]
   then
      [[ "$LOCALSTORAGE" = "$LOCAL_STORAGE" ]] && setup_local_disk
   elif [ "$MODE" = "add-worker" ]
   then
      echo "Adding worker node only... exiting...."
      exit 0
   else
      ROLE=`su - $THEUSER -c "kubectl get nodes --no-headers=true | grep $(hostname -s) | awk '{print \\$3}'"`
      if [ "$MODE" = "single" ]
      then
         echo "Using storage class $STORAGE_CLASS"
	 if [ "$STORAGE_CLASS" = "local-storage" ]
	 then
            echo "Mounting local-storage ${LOCALSTORAGE}..."
            for i in $(seq 1 $PV_COUNT); do
                vol="vol$i"
                [[ ! -d ${LOCALSTORAGE}/$vol ]] && mkdir -p ${LOCALSTORAGE}/$vol
                if [ "$(df ${LOCALSTORAGE}/$vol | awk '{print $NF}' | sed 1d)" = "${LOCALSTORAGE}/$vol" ]
	        then
		   rm -rf ${LOCALSTORAGE}/$vol/*
                else
                   mount --bind ${LOCALSTORAGE}/$vol ${LOCALSTORAGE}/$vol
	        fi
            done
	 fi
      else
         if [ "$ROLE" = "master" ]
         then
            echo "This server $(hostname -s) is $ROLE node"
            echo "Exiting..."
            exit 1
         fi
      fi
   fi
 } | tee $LOG_FILE
}

create_trusted_ssh()
{
   [[ ! -f ~/.ssh/id_rsa.pub ]] && echo -n " CREATING..." && ssh-keygen -f ~/.ssh/id_rsa -P "" && [[ $? -ne 0 ]] && echo -e "\nFailed to create public key for user $USER ...exiting.." && exit 1
   if [ "$USERNAME" = "" ]
   then
      enter_input "Enter Username to connect to all worker nodes?"
      USERNAME="$ANS"
      echo "export USERNAME=\"$USERNAME\"" >> $ENVFILE
   fi
   if [ "$PASSWORD" = "" ]
   then
      enter_input "Enter password to connect to all worker nodes?" 1
      PASSWORD="$ANS"
      PASSENCRYPTED=$(echo $PASSWORD | base64)
      echo "export PASSWORD=\"$PASSENCRYPTED\"" >> $ENVFILE
   else
      PASSWORD=$(echo $PASSWORD | base64 -d)
   fi
   sshpass 2>/dev/null 1>/dev/null
   [[ $? -ne 0 ]] && echo "sshpass must be installed!!...exiting.." && exit 1
   CNT=1
   while [ $CNT -le $NOOFWORKERS ]
   do
      sshpass -p "$PASSWORD" ssh-copy-id -o "StrictHostKeyChecking no" $USERNAME@${K8SNODE}${CNT}
      [[ $? -ne 0 ]] && echo "password you typed must be wrong!!, please set the correct password and try again.. exiting..." && exit 1
      ssh  -o "StrictHostKeyChecking no" $USERNAME@${K8SNODE}${CNT} "
ROOTHOME=\$(cat /etc/passwd | grep root | cut -f6 -d:)
sudo cp ~/.ssh/authorized_keys \$ROOTHOME/.ssh
"
      CNT=$(( CNT + 1 ))
   done
}

check_worker_conn()
{
   CNT=1
   while [ $CNT -le $NOOFWORKERS ]
   do
      ssh  -o "StrictHostKeyChecking no" root@${K8SNODE}${CNT} "echo successfully establishing passwordless connection to root@\$(hostname)"
      [[ $? -ne 0 ]] && echo "Failed to connect to ${K8SNODE}${CNT} using root..."
      CNT=$(( CNT + 1 ))
   done
}

MODE=""
get_params "$@"
check_master_worker
create_trusted_ssh
check_worker_conn
if [ "$MODE" = "reset" -o "$MODE" = "" ]
then
   MODE="reset-master"
   WORKERMODE="reset-worker"
else
   WORKERMODE="$MODE"
fi
[[ "$MODE" != "$WORKERMODE" ]] && run_setup ${MODE} && export KUBEADM_JOIN_CMD="$(cat k8sdeploy.log | egrep 'kubeadm join |--discovery-token')"
CNT=1
while [ $CNT -le $NOOFWORKERS ]
do
   if [ "$MODE" != "$WOKERMODE" ]
   then
      ssh -o "StrictHostKeyChecking no" root@${K8SNODE}${CNT} "[[ ! -d /home/$THEUSER/.kube ]] && mkdir -p /home/$THEUSER/.kube"  
      echo "Copying admin.conf from $K8SMASTER to ${K8SNODE}${CNT}"
      scp -o "StrictHostKeyChecking no" /etc/kubernetes/admin.conf  root@${K8SNODE}${CNT}:/home/$THEUSER/.kube/config
      WORKERNAME=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes ${K8SNODE}${CNT} -o NAME 2>/dev/null)
      [[ "$WORKERNAME" != "" ]] && kubectl --kubeconfig=/etc/kubernetes/admin.conf delete $WORKERNAME 
   fi
   ssh -o "StrictHostKeyChecking no" root@${K8SNODE}${CNT} "
export THENODE=$THENODE
export THEUSER=$THEUSER
export KUBESTORAGE=$KUBESTORAGE
export CONTAINERSTORAGE=$CONTAINERSTORAGE
export STORAGE_CLASS=$STORAGE_CLASS
export MODE=reset-worker
export CRIO_VERSION=$CRIO_VERSION
export TIMEOUT=600
export RETRY_INTERVAL=5
export KUBEADM_JOIN_CMD=\"$KUBEADM_JOIN_CMD\"
$(typeset -f run_setup)
$(typeset -f get_distro_version)
$(typeset -f install_prereqs)
$(typeset -f modify_ssl_config)
$(typeset -f setup_k8s)
$(typeset -f is_cluster_ready)
$(typeset -f reset_only)
$(typeset -f destroy_everything)
$(typeset -f usage_k8s)
$(typeset -f untaint_master_node)
$(typeset -f install_k8s_dashboard)
$(typeset -f install_pkg_ubuntu)
$(typeset -f add_crio_netconfig)
$(typeset -f reset_kubeadm)
$(typeset -f delete_ephemeral_disks)
$(typeset -f install_network)
export K8SDEPLOY_DIR=k8sdeploy
export LOG_FILE=k8sdeploy.log
export PROGRESS_FILE=k8sprogress.log
export DEBIAN_FRONTEND=noninteractive
export PV_COUNT=${PVCOUNT:-30}
mkdir -p \$K8SDEPLOY_DIR
cd \$K8SDEPLOY_DIR/
touch \$LOG_FILE
touch \$PROGRESS_FILE
run_setup $WORKERMODE -u $THEUSER -c $CONTAINERSTORAGE -k $KUBESTORAGE"

      CNT=$(( CNT + 1 ))
done
[[ "$MODE" = "$WORKERMODE" ]] && run_setup ${MODE} || kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
[[ -f $ENVFILE ]] && rm -f $ENVFILE
