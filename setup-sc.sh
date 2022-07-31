#!/bin/bash
# $Id: setup-sc.sh 463 2022-07-31 10:02:25Z bpahlawa $
# initially captured from Microsoft website
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2022-07-31 18:02:25 +0800 (Sun, 31 Jul 2022) $
# $Revision: 463 $


trap exitshell SIGINT SIGTERM
export NODENAME
export WKNODES
export SCDEPLOY_DIR=scdeploy
[[ ! -d $SCDEPLOY_DIR ]] && mkdir -p $SCDEPLOY_DIR
ENVFILE=.${0}.env

CURRDIR=$(pwd)

exitshell()
{
   echo -e "${NORMALFONT}Cancelling script....exiting....."
   stty sane
   exit 0
}

export THEUSER="${KUBE_USER:-arc}"
export ARCNAME

export SCRIPTDIR=`dirname $0` && [[ "$SCRIPTDIR" = "." ]] && SCRIPTDIR=`pwd`
export SHARENAME=""
export SKU=${SKU:-Premium_LRS}
export STORAGEKIND=${STORAGEKIND:-FileStorage}
export DISTRO=""
export VERSION_ID=""
export FULL_VERSION_ID=""
export HELMLINK="https://get.helm.sh/helm-v3.9.1-linux-amd64.tar.gz"
export LANG=en_US.UTF-8
# Wait for 5 minutes for the cluster to be ready.
#
export TIMEOUT=600
export RETRY_INTERVAL=5

enter_input()
{
   local QUESTION="$1"
   local HIDDEN="$2"
   if [ "$HIDDEN" != "" ]
   then
      read -sp "$QUESTION : " ANS
   else
      echo -e "$QUESTION"
      read -p "=> : " ANS
   fi
   export ANS
}

is_running()
{ 
   local HOST="$1"
   ping -c1 $HOST 1>/dev/null 2>/dev/null
   return $?
}

check_kubernetes_cluster()
{ 
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   echo "Checking kubernetes cluster..."
   if [ -f /etc/kubernetes/admin.conf ]
   then
      PODSTATE=$(kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -A -o custom-columns=NAME:.spec.nodeName,STATUS:.status.containerStatuses[*].ready | grep false )
      if [ "$PODSTATE" = "" ]
      then
	  echo "Kubernetes cluster is running and all pods are healthy..."
	  export KUBECONFIG=/etc/kubernetes/admin.conf
	  return 0
      else
	  echo "One or more pod is not healthy!!"
	  kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -A
	  exit 1
      fi
   else
      echo "Checking whether kubectl is configured on this node..."
      kubectl get pods -A 2>/dev/null 1>/dev/null
      if [ $? -eq 0 ]
      then
          PODSTATE=$(kubectl get pods -A -o custom-columns=NAME:.spec.nodeName,STATUS:.status.containerStatuses[*].ready | grep false )
	  if [ "$PODSTATE" = "" ]
	  then
	      echo "Kubernetes cluster is running and all pods are healthy..."
	      return 0
	  else
	      echo "One or more pod is not healthy!!"
              kubectl get pods -A
              exit 1
	  fi
      else
	  echo "kubectl is not configured to connect to kubernetes cluster.."
	  echo "please copy /etc/kubernetes/admin.conf from kubernetes master to ~/.kube/"
	  echo "then rename ~/.kube/admin.conf to ~/.kkube/config, after that re-run this script"
	  exit 1
      fi 
   fi

set +x
}



check_sc_node()
{

[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
  [[ -f $ENVFILE ]] && source $ENVFILE || touch $ENVFILE

  if [ "$STORAGE_CLASS" = "" -a "$STORAGECLASS" = "" ]
  then
      enter_input "Please specify storage class type [smb, nfs, azurenfs, azresmb] ?"
      STORAGECLASS=${ANS}
      echo "Specifying storage class type $STORAGECLASS ..."
      echo "export STORAGECLASS=$STORAGECLASS" >> $ENVFILE
  else
      [[ "$STORAGE_CLASS" != "" ]] && STORAGECLASS="$STORAGE_CLASS"
      sed -i "s/^\(export STORAGECLASS=\).*/\1${STORAGECLASS}/g" $ENVFILE
  fi

  if [[ $STORAGECLASS =~ azure.* ]]
  then
     if [ "$SUBSCRIPTION_ID" = "" -a "$SUBSCRIPTIONID" = "" ]
     then
        enter_input "Please specify azure subscription id ?"
        SUBSCRIPTIONID=${ANS}
        echo "Specifying subscription id $SUBSCRIPTIONID ..."
        echo "export SUBSCRIPTIONID=$SUBSCRIPTIONID" >> $ENVFILE
     else
        [[ "$SUBSCRIPTION_ID" != "" ]] && SUBSCRIPTIONID="$SUBSCRIPTION_ID"
         sed -i "s|^\(export SUBSCRIPTIONID=\).*|\1${SUBSCRIPTIONID}|g" $ENVFILE
     fi

     if [ "$LOCATION_ID" = "" -a "$LOCATION" = "" ]
     then
        enter_input "Please specify location ?"
        LOCATION=${ANS}
        echo "Specifying location $LOCATION ..."
        echo "export LOCATION=$LOCATION" >> $ENVFILE
     else
        [[ "$LOCATION_ID" != "" ]] && LOCATION="$LOCATION_ID"
        sed -i "s|^\(export LOCATION=\).*|\1${LOCATION}|g" $ENVFILE
     fi
 
     if [ "$STORAGE_ACCOUNT" = "" -a "$STORAGEACCOUNT" = "" ]
     then
        enter_input "Please specify storage account name ?"
        STORAGEACCOUNT=${ANS}
        echo "Specifying Storage Account $STORAGEACCOUNT ..."
        echo "export STORAGEACCOUNT=$STORAGEACCOUNT" >> $ENVFILE
     else
        [[ "$STORAGE_ACCOUNT" != "" ]] && STORAGEACCOUNT="$STORAGE_ACCOUNT"
        sed -i "s|^\(export STORAGEACCOUNT=\).*|\1${STORAGEACCOUNT}|g" $ENVFILE
     fi

     if [ "$RESOURCE_GROUP" = "" -a "$RESOURCEGROUP" = "" ]
     then
        enter_input "Please specify resource group name ?"
        RESOURCEGROUP=${ANS}
        echo "Specifying Resource group .."
        echo "export RESOURCEGROUP=$RESOURCEGROUP" >> $ENVFILE
     else
        [[ "$RESOURCE_GROUP" != "" ]] && RESOURCEGROUP="$RESOURCE_GROUP"
        sed -i "s|^\(export RESOURCEGROUP=\).*|\1${RESOURCEGROUP}|g" $ENVFILE
     fi

     if [ "$STORAGECLASS" = "azurenfs" ]
     then
        if [ "$VIRTUAL_NET" = "" -a "$VIRTUALNET" = "" ]
        then
	   enter_input "NFS share on azure requires restricted access on Virtual Net (VNET), Please specify VNET ?"
           VIRTUALNET=${ANS}
           echo "Specifying VNET .."
           echo "export VIRTUALNET=$VIRTUALNET" >> $ENVFILE
        else
           [[ "$VIRTUAL_NET" != "" ]] && VIRTUALNET="$VIRTUAL_NET"
           sed -i "s|^\(export VIRTUALNET=\).*|\1${VIRTUALNET}|g" $ENVFILE
        fi

        if [ "$SUB_NET" = "" -a "$SUBNET" = "" ]
        then
	   enter_input "Subnet ? default(default)"
           SUBNET=${ANS:-default}
           echo "Specifying subnet .."
           echo "export SUBNET=$SUBNET" >> $ENVFILE
        else
           [[ "$SUB_NET" != "" ]] && SUBNET="$SUB_NET"
           sed -i "s|^\(export SUBNET=\).*|\1${SUBNET}|g" $ENVFILE
        fi
     fi
  else
     echo "Checking server which hosting storage class..."
     if [ "$NODE_NAME" = "" -a "$NODENAME" = "" ]
     then
         enter_input "Please specify Node/Server name of $MODE"
         NODENAME=${ANS}
         if [ "$NODENAME" = $(hostname) ]
         then
             echo "This node $(hostname) will be hosting storage class..."
         else
             echo "Node $NODENAME will be hosting storage and class"
             is_running $NODENAME
             [[ $? -ne 0 ]] && echo "Node $NODENAME is not running.. exiting.." && exit 1 || echo "Node $NODENAME is alive !"
         fi
         echo "export NODENAME=$NODENAME" >> $ENVFILE
     else
         [[ "$NODE_NAME" != "" ]] && NODENAME="$NODE_NAME"
         is_running $NODENAME
         [[ $? -ne 0 ]] && echo "Node $NODENAME is not running.. exiting.." && exit 1 || echo "Node $NODENAME is alive !"
         sed -i "s/^\(export NODENAME=\).*/\1${NODENAME}/g" $ENVFILE
     fi
   

     if [ "$MOUNT_POINT" = "" -a "$MOUNTPOINT" = "" ]
     then
         enter_input "Please specify mountpoint ?"
         MOUNTPOINT=${ANS}
         echo "Specifying mountpoint to $MOUNTPOINT ..."
         echo "export MOUNTPOINT=$MOUNTPOINT" >> $ENVFILE
     else
         [[ "$MOUNT_POINT" != "" ]] && MOUNTPOINT="$MOUNT_POINT"
         sed -i "s|^\(export MOUNTPOINT=\).*|\1${MOUNTPOINT}|g" $ENVFILE
     fi
  fi

  set +x
}

    

get_distro_version()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
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
set +x
}




if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


# Name of virtualenv variable used.
#
export LOG_FILE="scdeploy.log"
export PROGRESS_FILE="scprogress.log"

# Make a directory for installing the scripts and logs.
#
cd $SCDEPLOY_DIR/
touch $LOG_FILE
touch $PROGRESS_FILE


modify_ssl_config()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
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

kubectl_delete()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local RESOURCE="$1"
   local ARTIFACTS="$2"

   for ART in $(echo $ARTIFACTS)
   do
       kubectl delete $RESOURCE $ART
   done
}



get_helm()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   echo "Checking helm ....."
   which helm 2>/dev/null 1>/dev/null
   if [ $? -ne 0 ]
   then
       echo "helm is not currently installed.. getting helm.."
       [[ -d /usr/local/bin ]] && mkdir /usr/local/bin
       curl -fsSL $HELMLINK | tar xvz -C /usr/local/bin --wildcards --no-anchored --strip-components 1 --no-same-owner helm
   else
       HELMVER=$(helm version 2>/dev/null| sed 's/.*Ver.*v\([0-9]\).*/\1/g')
       if [ 0$HELMVER -lt 3 ]
       then
	  HELMPATH=$(which helm)
	  HELMDIR=$(dirname $HELMPATH)
	  curl -fsSL $HELMLINK | tar xvz -C $HELMDIR --wildcards --no-anchored --strip-components 1 --no-same-owner helm
       fi
   fi
}

get_kubectl()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   echo "Checking kubectl ...."
   which kubectl 2>/dev/null 1>/dev/null
   if [ $? -ne 0 ]
   then
       echo "kubectl is not currently installed.. getting kubectl.."
       [[ -d /usr/local/bin ]] && mkdir /usr/local/bin
       curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
       curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
       SHA256KUBE=$(sha256sum kubectl | awk '{print $1}')
       if [ "$SHA256KUBE" = "$(cat kubectl.sha256 2>/dev/null)"]
       then
	   mv kubectl /usr/local/bin
	   chown root:root /usr/local/bin/kubectl
	   [[ -f kubectl.sha256 ]] && rm -f kubectl.sha256
       else
	   echo "kubectl checksum mismatch.. please re-download..."
	   exit 1
       fi
   fi
}
            





setup_sc()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
[[ "$(grep SETUPARC $PROGRESS_FILE)" = "SETUPARC" ]] && echo -e ">>>>>>>>>> Kubernetes has been installed!.. skipping...\n" && return
echo "#########################################################################"
echo "###################  Setting up Kubernetes $THENODE  ####################"
echo "#########################################################################"


echo SETUPARC >> $PROGRESS_FILE
echo "export SETUPARC=1" >> $ENVFILE
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

install_sc_dashboard()
{

[[ "$(grep ARCDASHBOARD $PROGRESS_FILE)" = "ARCDASHBOARD" ]] && echo -e ">>>>>>>>>> Kubernetes dashboard has been installed!.. skipping...\n" && return

# Install the dashboard for Kubernetes.
#
su - $THEUSER -c "
kubectl apply -f $DASHBOARD
#kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
echo \"Kubernetes master setup done.\"
"
echo ARCDASHBOARD >> $PROGRESS_FILE
}


#this is how to use this script
usage_sc()
{
   echo -e "\nUsage: \n    $0 -m <mode> -s <storage_class> -n <nodename>"
   echo -e "\n    -m mode [destroy|setup(default)]"
   echo -e "\n    -s storage_class [azurenfs|azuresmb|smb|nfs]"
   echo -e "\n    -n node_name [azurenfs|azuresmb|smb|nfs hostname]"
   echo -e "\n    -l mount_point"
   echo -e "\nAdditional parameters only for azuresmb or azurenfs:"
   echo -e "\n    -i subscription_id"
   echo -e "\n    -a storage_account_name"
   echo -e "\n    -p location"
   echo -e "\n    -r resource_group"
   echo -e "\nExtra parameters only for azurenfs:"
   echo -e "\n    -v virtual_net"
   echo -e "\n    -b subnet [default(default)]"
   echo -e "    E.g: $0 -m setup -s nfs -n lxnfsserver -l /opt/nfs"
   echo -e "         $0 -m setup -s azuresmb -n storage.blob.azure.com"
   exit 1
}


get_params()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local OPTIND
   while getopts "m:s:n:l:i:a:p:r:v:b:hd" PARAM
   do
      case "$PARAM" in
      m) 
          #mode
          MODE=${OPTARG}
          [[ ! $MODE =~ setup|destroy ]] && echo "Invalid -m parameter" && usage_sc
          ;;
      s)
          #storage class
          STORAGE_CLASS=${OPTARG}
	  [[ ! $STORAGE_CLASS =~ nfs|smb|azurenfs|azuresmb| ]] && echo "Invalid -s parameter" && usage_sc
          ;;
      n)
	  #NFS/smb node
	  NODE_NAME=${OPTARG}
	  ;;
      l)
	  #mountpoint
	  MOUNT_POINT=${OPTARG}
	  ;;
      h)
          #display this usage
          usage_sc
          ;;
      d)
	  #debug is on
	  DEBUG=1
	  ;;
      i)
	  SUBSCRIPTION_ID=${OPTARG}
	  ;;
      a)
	  STORAGE_ACCOUNT=${OPTARG}
	  ;;
      p)
	  LOCATION_ID=${OPTARG}
	  ;;
      r)
	  RESOURCE_GROUP=${OPTARG}
	  ;;
      v)
	  VIRTUAL_NET=${OPTARG}
	  ;;
      b)
	  SUB_NET=${OPTARG}
	  ;;
      ?)
          echo -e "\nError:  Unknown parameter(s)...\n"
          usage_sc
      esac
    done

    shift $((OPTIND-1))
    [[ "$MODE" = "" ]] && MODE="setup"


set +x
}

check_mountpoint()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
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
set +x
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
set +x
}

remove_offending_key()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
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
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
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
set +x
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
   delete_ephemeral_disks "$KUBESTORAGE"
   delete_ephemeral_disks "$CONTAINERSTORAGE"

}


install_nfs_server()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local SSHCONNECT="$1"
   local NFSMOUNT="$2"
   echo "Installing NFS Server using connection $SSHCONNECT on directory $NFSMOUNT ..."
   ssh  -o "StrictHostKeyChecking no" $SSHCONNECT "
DEBUG=$DEBUG
DISTRO=$DISTRO
$(typeset -f install_pkg)
$(typeset -f get_distro_version)
[[ ! -d $NFSMOUNT ]] && mkdir -p $NFSMOUNT
install_pkg nfs-server
echo \"$NFSMOUNT *(rw,sync,no_subtree_check)\" > /etc/exports
systemctl start nfs-server
systemctl enable nfs-server
exportfs -a
exportfs
"
set +x
}


install_smb_server()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local SSHCONNECT="$1"
   local SMBMOUNT="$2"
   DISKUSERNAME="smb-user"
   DISKPASSWORD=$(cat /proc/sys/kernel/random/uuid | base64)
   echo "Installing smb Server using connection $SSHCONNECT on directory $SMBMOUNT ..."
   ssh  -o "StrictHostKeyChecking no" $SSHCONNECT "
DEBUG=$DEBUG
DISTRO=$DISTRO
$(typeset -f install_pkg)
$(typeset -f get_distro_version)
useradd -u 9999 $DISKUSERNAME
[[ ! -d $SMBMOUNT ]] && mkdir -p $SMBMOUNT
chown smb-user $SMBMOUNT
install_pkg samba
SMBCONFIG=\$(find /etc -name smb.conf | tail -1)
if [ \"\$SMBCONFIG\" = \"\" ]
then
   echo \"Configuration file smb.conf under /etc directory could not be found!!\"
   echo \"smb software must not be installed properly, please re-install manually.. exiting..\"
   exit 1
fi
echo \"
[$SHARENAME]
  path = $SMBMOUNT
  browseable = yes
  read only = no
  force user = $DISKUSERNAME
\" >> \$SMBCONFIG
echo -ne \"${DISKPASSWORD}\n${DISKPASSWORD}\" | smbpasswd -sa $DISKUSERNAME
systemctl start smbd
systemctl enable smbd
"
set +x
}

remove_smb_server()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local SSHCONNECT="$1"
   DISKUSERNAME="smb-user"
   echo "Removing smb Server using connection $SSHCONNECT"
   ssh  -o "StrictHostKeyChecking no" $SSHCONNECT "
DEBUG=$DEBUG
DISTRO=$DISTRO
$(typeset -f remove_pkg)
$(typeset -f get_distro_version)
systemctl stop smbd
remove_pkg samba
userdel -r $DISKUSERNAME
"
set +x
}

remove_nfs_server()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local SSHCONNECT="$1"
   echo "Removing nfs Server using connection $SSHCONNECT"
   ssh  -o "StrictHostKeyChecking no" $SSHCONNECT "
DEBUG=$DEBUG
DISTRO=$DISTRO
$(typeset -f remove_pkg)
$(typeset -f get_distro_version)
systemctl stop nfs-server
remove_pkg nfs-server
"
set +x
}


setup_nfs_sc()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   SHARENAME="nfsmount"
   if [ "$STORAGECLASS" != "azurenfs" ]
   then 
      install_nfs_server root@$NODENAME "$MOUNTPOINT"
   else
      install_az
      check_az_storageacc $STORAGEACCOUNT "NFS"
      MOUNTPOINT=$STORAGEACCOUNT/$SHARENAME
   fi
   get_helm
   if [ "$(helm repo list 2>/dev/null| awk '{print $1}' | grep csi-driver-nfs )" = "" ]
   then
      helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
   else
      echo "Helm repo csi-driver-nfs exists..."
   fi
   if [ "$(helm list -n kube-system -q 2>/dev/null| grep csi-driver-nfs )" = "" ]
   then
      helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --version 4.0.0
      RESULT=$(kubectl get csidriver 2>/dev/null)
      [[ "$RESULT" = "" ]] && echo "creating storage class type nfs has failed!!.. exiting..." && exit
   else
      echo "helm release csi-driver-nfs exists..."
   fi

   SCNAME="nfs-csi"
   RESULT=$(kubectl get sc $SCNAME 2>/dev/null| grep nfs)
   [[ "$RESULT" != "" ]] && kubectl delete sc $SCNAME


   echo "Creating storage class $SCNAME on a server $NODENAME using mountpoint $MOUNTPOINT ..."

   echo "
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $SCNAME
provisioner: nfs.csi.k8s.io
parameters:
  server: $NODENAME
  share: $MOUNTPOINT
  # csi.storage.k8s.io/provisioner-secret is only needed for providing mountOptions in DeleteVolume
  # csi.storage.k8s.io/provisioner-secret-name: \"mount-options\"
  # csi.storage.k8s.io/provisioner-secret-namespace: \"default\"
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - nconnect=8  # only supported on linux kernel version >= 5.3
  - nfsvers=4.1
" | kubectl apply -f -

set +x
}


remove_nfs_sc()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   SHARENAME="nfsmount"
   SCNAME="nfs-csi"
   get_helm
   if [ "$(helm list -n kube-system -q 2>/dev/null| grep csi-driver-nfs )" != "" ]
   then
      helm uninstall csi-driver-nfs --namespace kube-system
      RESULT=$(kubectl get csidriver | grep nfs)
      [[ "$RESULT" != "" ]] && echo "Deleting csi-driver-nfs failed!!, you must do it manually..exiting..." && exit
      IS_AZURE=$(kubectl get sc nfs-csi -o jsonpath="{.parameters.source}" | grep "core.windows.net" | grep $SHARENAME)
      if [[ "$IS_AZURE" != "" || $STORAGECLASS =~ azure.* ]]
      then
         install_az
         echo "Checking storage account $STORAGEACCOUNT ..."
         ALLVAR=$(az storage account show --name $STORAGEACCOUNT --query "{location:location,id:id,endpoint:primaryEndpoints.file}" --output tsv)
         if [ "$ALLVAR" = "" ]
         then
            echo "Storage account $STORAGEACCOUNT does not exist... ignoring.."
         else
            echo "Checking share $SHARENAME on storage account $STORAGEACCOUNT ..."
            az storage share-rm show --storage-account $STORAGEACCOUNT --name $SHARENAME -o none 2>/dev/null
            if [ $? -ne 0 ]
            then
               echo "Share $SHARENAME does not exist.. ignoring.."
            else
               echo "Deleting share $SHARENAME from storage account $STORAGEACCOUNT ..."
               az storage share-rm delete --yes --name $SHARENAME --storage-account $STORAGEACCOUNT
            fi
         fi
       else
         remove_nfs_server root@$NODENAME
       fi
   fi


   kubectl delete sc $SCNAME
   if [ "$(helm repo list | awk '{print $1}' | grep csi-driver-nfs)" != "" ]
   then
      echo "Deleting repo csi-driver-nfs ..."
      helm repo remove csi-driver-nfs
   fi

set +x
}


remove_smb_sc()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   SHARENAME="smbmount"
   SCNAME="smb-csi"
   get_helm
   if [ "$(helm list -n kube-system -q 2>/dev/null| grep csi-driver-smb )" != "" ]
   then
      helm uninstall csi-driver-smb --namespace kube-system
      RESULT=$(kubectl get csidriver | grep smb)
      [[ "$RESULT" != "" ]] && echo "Deleting csi-driver-smb failed!!, you must do it manually..exiting..." && exit
      IS_AZURE=$(kubectl get sc smb-csi -o jsonpath="{.parameters.source}" | grep "core.windows.net" | grep $SHARENAME)
      if [[ "$IS_AZURE" != "" || $STORAGECLASS =~ azure.* ]]
      then
         install_az
	 echo "Checking storage account $STORAGEACCOUNT ..."
	 ALLVAR=$(az storage account show --name $STORAGEACCOUNT --query "{location:location,id:id,endpoint:primaryEndpoints.file}" --output tsv)
         if [ "$ALLVAR" = "" ]
         then
            echo "Storage account $STORAGEACCOUNT does not exist... ignoring.."
	 else
	    echo "Checking share $SHARENAME on storage account $STORAGEACCOUNT ..."
	    az storage share-rm show --storage-account $STORAGEACCOUNT --name $SHARENAME -o none 2>/dev/null
	    if [ $? -ne 0 ]
            then
	       echo "Share $SHARENAME does not exist.. ignoring.."
            else
	       echo "Deleting share $SHARENAME from storage account $STORAGEACCOUNT ..."
	       az storage share-rm delete --yes --name $SHARENAME --storage-account $STORAGEACCOUNT
	    fi
	 fi
       else
	 remove_smb_server root@$NODENAME
       fi
   fi


   kubectl delete sc $SCNAME
   if [ "$(helm repo list | awk '{print $1}' | grep csi-driver-smb)" != "" ]
   then
      echo "Deleting repo csi-driver-smb ..."
      helm repo remove csi-driver-smb
   fi

   echo "Removing secrets which contains username and password...."
   kubectl delete secret smbcreds

set +x
}

setup_smb_sc()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   SHARENAME="smbmount"
   if [ "$STORAGECLASS" != "azuresmb" ]
   then 
      install_smb_server root@$NODENAME "$MOUNTPOINT"
   else
      install_az
      check_az_storageacc $STORAGEACCOUNT "SMB"
   fi
   get_helm
   if [ "$(helm repo list 2>/dev/null| awk '{print $1}' | grep csi-driver-smb)" = "" ]
   then
      helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts
   else
      echo "Helm repo csi-driver-smb exists..."
   fi
   if [ "$(helm list -n kube-system -q 2>/dev/null| grep csi-driver-smb )" = "" ]
   then
      helm install csi-driver-smb csi-driver-smb/csi-driver-smb --namespace kube-system --version 1.6.0
      RESULT=$(kubectl get csidriver 2>/dev/null| grep smb)
      [[ "$RESULT" = "" ]] && echo "creating storage class type smb has failed!!.. exiting..." && exit
   else
      echo "helm release csi-driver-smb exists..."
   fi

   echo "Creating secrets which contains username and password...."
   kubectl create secret generic smbcreds --from-literal username=$DISKUSERNAME --from-literal password="$DISKPASSWORD" --dry-run=client -o yaml | kubectl apply -f -

   SCNAME="smb-csi"
   RESULT=$(kubectl get sc $SCNAME 2>/dev/null)
   [[ "$RESULT" != "" ]] && kubectl delete sc $SCNAME

   echo "Creating storage class $SCNAME on a server $NODENAME using mountpoint $MOUNTPOINT ..."

   echo "
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $SCNAME
provisioner: smb.csi.k8s.io
parameters:
  source: \"//$NODENAME/$SHARENAME\"
  # if csi.storage.k8s.io/provisioner-secret is provided, will create a sub directory
  # with PV name under source
  csi.storage.k8s.io/provisioner-secret-name: \"smbcreds\"
  csi.storage.k8s.io/provisioner-secret-namespace: \"default\"
  csi.storage.k8s.io/node-stage-secret-name: \"smbcreds\"
  csi.storage.k8s.io/node-stage-secret-namespace: \"default\"
volumeBindingMode: Immediate
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - vers=3.0
  - actimeo=30
  - noserverino
" | kubectl apply -f -

set +x
}


run_setup()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x

   get_distro_version
   echo -e "You are running Linux distro : $DISTRO $ALLVER ....."
   echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
   echo -e "$THEMESSAGE"
   echo -e "\nRunning kubernetes cluster with the following information"
   kubectl cluster-info
   echo -e "\nExecuting script to $MODE the following :"
   echo -e "\nStorage class    : $STORAGECLASS "
   case "$MODE" in
     "setup")
              case "$STORAGECLASS" in
		"nfs")
	            echo -e "\nCreating NFS file share storage class on Azure Storage account $STORAGEACCOUNT"
	            setup_nfs_sc
		    ;; 
		"azurenfs")
		    echo -e "\nCreating NFS file share storage class"
		    setup_nfs_sc
		    ;;
		"smb")
	            echo -e "\nCreating SMB file share storage class on Azure Storage account $STORAGEACCOUNT"
		    setup_smb_sc
		    ;;
		"azuresmb")
	            echo -e "\nCreating SMB file share storage class"
		    setup_smb_sc
		    ;;

	      esac
	      ;;
      "destroy")
              case "$STORAGECLASS" in
		"nfs")
		    echo -e "\nRemoving NFS file share storage class"
	            remove_nfs_sc
		    ;;
		"azurenfs")
	            echo -e "\nRemoving NFS file share storage class from Azure Storage account $STORAGEACCOUNT"
	            remove_nfs_sc
		    ;;
	        "smb")
	            echo -e "\nRemoving SMB file share storage class"
		    remove_smb_sc
		    ;;
	        "azuresmb")
	            echo -e "\nRemoving SMB file share storage class from Azure Storage account $STORAGEACCOUNT"
		    remove_smb_sc
		    ;;
	      esac
	      ;;
    esac
   echo -e "\nShare name       : $SHARENAME "
   echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n"



set +x
}

create_user_pubkey()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   REGUSER="$1"
   echo "Creating public key for user $REGUSER"
   if [ "$REGUSER" != "" ]
   then
      su - $REGUSER -c "[[ ! -f ~/.ssh/id_rsa.pub ]] && echo -n \" CREATING id_rsa.pub for user $REGUSER ...\" && ssh-keygen -f ~/.ssh/id_rsa -P \"\" && [[ \$? -ne 0 ]] && echo -e \"\nFailed to create public key for user $REGUSER ... \""
   fi
set +x
}

remove_pkg()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local PKGNAME="$1"
   get_distro_version
   case "$DISTRO" in
    "CENTOS"|"RHEL")
            if [ "$PKGNAME" = "sshpass" ]
            then
               yum -y remove sshpass
            else
               yum remove -y $PKGNAME
            fi
            ;;

    "UBUNTU")
            apt-get update
            apt-get purge -y $PKGNAME
            ;;
    "ARCH")
            pacman -R --noconfirm $PKGNAME
            ;;
    "DEBIAN")
            apt-get update
            apt-get purge -y $PKGNAME
            ;;
    *SUSE*)
            zypper -n rm $PKGNAME
            ;;
esac
set +x
}


install_pkg()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   local PKGNAME="$1"
   get_distro_version
   case "$DISTRO" in
    "CENTOS"|"RHEL")
            if [ "$PKGNAME" = "sshpass" ]
            then
               yum -y install https://cbs.centos.org/kojifiles/packages/sshpass/1.09/1.el8s/x86_64/sshpass-1.09-1.el8s.x86_64.rpm
            else
               yum install -y $PKGNAME
            fi
            ;;

    "UBUNTU")
            apt-get update
            apt-get install -q -y $PKGNAME
            ;;
    "ARCH")
            pacman -Sy --noconfirm $PKGNAME
            ;;
    "DEBIAN")
            apt-get update
            apt-get install -q -y $PKGNAME
            ;;
    *SUSE*)
            zypper -n in $PKGNAME
            ;;
esac
set +x
}


create_trusted_ssh()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   [[ ! -f ~/.ssh/id_rsa.pub ]] && echo -n " CREATING..." && ssh-keygen -f ~/.ssh/id_rsa -P "" && [[ $? -ne 0 ]] && echo -e "\nFailed to create public key for user $USER ...exiting.." && exit 1

   if [ "$USERNAME" = "" ]
   then
      enter_input "Enter Username to connect to $NODENAME ($STORAGECLASS) server ?"
      USERNAME="$ANS"
      echo "export USERNAME=\"$USERNAME\"" >> $ENVFILE
   else
      enter_input "Enter Username to connect to $NODENAME ($STORAGECLASS) server ? default: $USERNAME ?"
      [[ "$ANS" != "" ]] && USERNAME="$ANS"
   fi

   if [ "$PASSWORD" = "" ]
   then
      enter_input "Enter password to connect to $NODENAME ($STORAGECLASS) server ?" 1
      PASSWORD="$ANS"
      PASSENCRYPTED=$(echo $PASSWORD | base64)
      echo "export PASSWORD=\"$PASSENCRYPTED\"" >> $ENVFILE
   else
      PASSWORD=$(echo $PASSWORD | base64 -d)
   fi
   sshpass 2>/dev/null 1>/dev/null
   [[ $? -ne 0 ]] && install_pkg sshpass

   if [ "$STORAGECLASS" = "smb" -o "$STORAGECLASS" = "nfs" ]
   then
      echo "Copying public key from $(hostname) to $NODENAME ..."
      sshpass -p "$PASSWORD" ssh-copy-id -o "StrictHostKeyChecking no" $USERNAME@${NODENAME}
      [[ $? -ne 0 ]] && echo "password you typed must be wrong!!, please set the correct password and try again.. removing pssword from the file.. plese re-run..." && sed -i "/^export PASSWORD.*/d" $ENVFILE && exit 1
      ssh  -o "StrictHostKeyChecking no" $USERNAME@${NODENAME} "
ROOTHOME=\$(cat /etc/passwd | grep root | cut -f6 -d:)
sudo cp ~/.ssh/authorized_keys \$ROOTHOME/.ssh
"
   else
      run_azsetup
   fi

set +x

}

install_az()
{

[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   CURRDIR=$(pwd)
   echo -n "Checking az command has been installed....."
   [[ -d $CURRDIR/bin ]] && export PATH=$CURRDIR/bin:$PATH
   
   az --version &
   sleep 2
   CTR=1
   PID=$(ps -ef | egrep "az \-\-version| azure\-cli " | grep -v grep | awk '{print $2}')
   while [ $CTR -le 4 -a "$PID" != "" ]
   do
     echo "az or azure-cli is running.............................................."
     PID=$(ps -ef | egrep "az \-\-version| azure\-cli " | grep -v grep | awk '{print $2}')
     CTR=$(( CTR + 1 ))
     sleep 2
   done
   
   PID=$(ps -ef | egrep "az \-\-version| azure\-cli " | grep -v grep | awk '{print $2}')
   if [ $CTR -ge 4 ]
   then
     while [ "$PID" != "" ]
     do
        PID=$(ps -ef | egrep "az | azure\.cli " | grep -v grep | awk '{print $2}')
        for PID in $(ps -ef | egrep "az | azure\-cli " | grep -v grep | awk '{print $2}')
        do
          kill $PID
        done
     done
     AZLOC=$(which az)
     AZDIR=$(dirname $AZLOC)
     [[ -d $AZDIR ]] && rm -rf $AZDIR
     REINSTALLAZ=1
   fi
   
   
   if [ "$REINSTALLAZ" = "1" ]
   then
      [[ -d ~/lib/azure-cli ]] && rm -rf ~/lib/azure-cli
      curl -L https://aka.ms/InstallAzureCli -o installaz
      sed -i "s|< \$_TTY|<<\!|g" installaz
      echo -e "\n\n!" >> installaz
      bash installaz
      [[ $? -ne 0 ]] && echo -e "\nFailed to install az command....exiting..." && exit 1
   
   else
     az config set auto-upgrade.prompt=no
     az config set auto-upgrade.enable=yes
     if [ $? -ne 0 ]
     then
        echo -e "az is already the latest version.."
     else
        echo -e " OK\n"
     fi
   fi
   export PATH=$(pwd)/bin:$PATH
   cd $CURRDIR

   echo -n "Checking SUBSCRIPTION $SUBSCRIPTIONID...."
   SID=`az account list --output tsv 2>&1 | grep "$SUBSCRIPTIONID" | awk '{print $3}'`
   while [ "$SID" = "" ]
   do
      echo -e "\nSubscription ID $SID is not available...trying to relogin..."
      az login
      SID=`az account list --output tsv 2>/dev/null | grep "$SUBSCRIPTIONID" | awk '{print $3}'`
      [[ $? -ne 0 ]] && echo "Unable to login !!.. exiting... " && exit 1
      sleep 10
   done
   echo -e " OK\n"

   echo -n "Using subscription ID $SID...."
   az account set -s $SID 2>&1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting..." && exit 1
   echo -e " OK\n"

   CHECKRG=$(az group show --name $RESOURCEGROUP --output table  2>&1 | grep "az login")
   if [ "$CHECKRG" != "" ]
   then
     echo -n "Trying to perform Device login...."
     az login
     [[ $? -ne 0 ]] && echo -e " Failed!\nUnable to login !!.. exiting... \n" && exit 1
     az account set -s $SID
     [[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting...\n" | tee -a $LOGFILE && exit 1
     echo -e " OK\n"
   fi


set +x
}

check_az_storageacc()
{
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
    local STORAGEACCOUNT="$1"
    local SHAREDTYPE="$2" 
    ALLVAR=$(az storage account show --name $STORAGEACCOUNT --resource-group $RESOURCEGROUP --query "{location:location,id:id,endpoint:primaryEndpoints.file}" --output tsv)
    if [ "$ALLVAR" = "" ]
    then
        echo "Storage account $STORAGEACCOUNT does not exist..."
	echo "Checking Resource group $RESOURCEGROUP ..."
	RGROUP_LOCATION=$(az group list --query '[*].{name:name,location:location}' -o tsv | tr '[:upper:]' '[:lower:]' | grep $RESOURCEGROUP )
        [[ "$RGROUP_LOCATION" = "" ]] && echo "Resource group $RESOURCEGROUP does not exist.. you must create resource group $RESOURCEGROUP before running this script..exiting..." && exit 1
        if [ "$LOCATION" = "auto" ]
        then
            LOCATION=$(echo $RGROUP_LOCATION | awk '{print $2}')
            echo "Using location from resource group $RESOURCEGROUP that is $LOCATION ..." 
        else
	    RESULT=$(az account list-locations --query "[?name=='$LOCATION'].{name:name}" -o tsv)
            if [ "$RESULT" = "" ]
            then
              echo "Location is not recognized...the following is the list of all locations:"
              az account list-locations --query "[*].{Location:name}" -o tsv
              exit 1
            else
              echo "Using location $LOCATION ..."
            fi
        fi
        echo "Creating storage account along with file server..."
        az storage account create \
        --name $STORAGEACCOUNT \
        --resource-group $RESOURCEGROUP \
        --kind $STORAGEKIND \
        --sku $SKU \
	--enable-large-file-share \
	--output none
	[[ $? -ne 0 ]] && echo "Creating storage account $STORAGEACCOUNT failed!! exiting..." && exit 1

        az storage share-rm create \
        --resource-group $RESOURCEGROUP \
        --storage-account $STORAGEACCOUNT \
        --name $SHARENAME \
        --quota 1024 \
	--enabled-protocols $SHAREDTYPE \
        --output none
	[[ $? -ne 0 ]] && echo "Creating file share $SHARENAME on account $STORAGEACCOUNT failed!! exiting..." && exit 1
        ALLVAR=$(az storage account show --name $STORAGEACCOUNT --resource-group $RESOURCEGROUP --query "{location:location,id:id,endpoint:primaryEndpoints.file}" --output tsv)
        FILESERVER=$(echo $ALLVAR | awk '{print $NF}')
    else
       LOCATION=$(echo $ALLVAR | awk '{print $1}')
       echo "Using location from storage account $STORAGEACCOUNT that is $LOCATION"
       FILESERVER=$(echo $ALLVAR | awk '{print $NF}')

       az storage share-rm create \
       --resource-group $RESOURCEGROUP \
       --storage-account $STORAGEACCOUNT \
       --name $SHARENAME \
       --quota 1024 \
       --enabled-protocols $SHAREDTYPE \
       --output none
       [[ $? -ne 0 ]] && echo "Creating file share $SHARENAME on account $STORAGEACCOUNT failed!! exiting..." && exit 1
   fi
   
   if [ "$SHAREDTYPE" = "SMB" ]
   then
      echo "Getting smb username and password from storage account $STORAGEACCOUNT ..."
      CONNECTSTRING=$(az storage account show-connection-string --name $STORAGEACCOUNT -o tsv)
      export DISKUSERNAME=$(echo $CONNECTSTRING | cut -f3 -d";" | cut -f2 -d=)
      export DISKPASSWORD=$(echo $CONNECTSTRING | cut -f4 -d";" | cut -f2-5 -d=)
   else
      az storage account update \
      --resource-group $RESOURCEGROUP \
      --name $STORAGEACCOUNT \
      --bypass "AzureServices" \
      --default-action "Deny" \
      --output none
      [[ $? -ne 0 ]] && echo "Restricting storage account $STORAGEACCOUNT failed!! exiting..." && exit 1

      echo "Getting SUBNET $SUBNET and VNET $VIRTUALNET information..."
      SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCEGROUP --vnet-name $VIRTUALNET --name $SUBNET --query "id" -o tsv 2>/dev/null)
      if [ "$SUBNET_ID" = "" ]
      then
	 echo "Either subnet $SUBNET or VNET $VIRTUALNET does not exist.."
	 echo "Trying to list all subnets under VNET $VIRTUALNET"
	 az network vnet show --resource-group $RESOURCEGROUP --name $VIRTUALNET --query "subnets[*].{id:id}" -o tsv 2>/dev/null
	 exit 1
      else
	 echo "Found $SUBNET_ID"
      fi
      echo "Getting service endpoint(s)..."
      SVCENDPOINT=$(az network vnet subnet show \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VIRTUALNET \
        --name $SUBNET \
        --query "serviceEndpoints[].service" \
        --output tsv)
      [[ "$SVCENDPOINT" != "Microsoft.Storage" ]] && echo "Service endpoint is not Microsoft Storage.. exiting..." && exit 1

      echo "Found service endpoint $SVCENDPOINT ..."
      echo "Adding service endpoint $SVCENDPOINT into subnet $SUBNET ..."
      az network vnet subnet update \
            --ids $SUBNET_ID \
            --service-endpoints $SVCENDPOINT \
            --output none
      [[ $? -ne 0 ]] && echo "Adding service endpoint $SVCENDPOINT to subnet $SUBNET failed!!..." && exit 1


   fi
   NODENAME=$(echo $FILESERVER | sed "s/^.*:\/\///g" | sed "s|/||g") 
   
set +x        
}


check_node_conn()
{ 
[[ "$DEBUG" = "1" ]] && echo -e "\n\n\n\n===========================< ${FUNCNAME[0]} >==================================\n" && set -x
   ssh  -o "StrictHostKeyChecking no" root@${NODENAME} "echo successfully establishing passwordless connection to root@\$(hostname)"
   [[ $? -ne 0 ]] && echo "Failed to connect to ${NODENAME} using root..."
set +x
}

[[ "$DEBUG" = "1" ]] && echo "\n\n\n================================ Main ======================================\n"

MODE=""
{
get_params "$@"
check_sc_node
check_kubernetes_cluster
if [ "$STORAGECLASS" = "smb" -o "$STORAGECLASS" = "nfs" ]
then
   create_trusted_ssh
   check_node_conn
fi
run_setup
} | tee -a $LOG_FILE
