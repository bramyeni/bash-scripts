# My bash script collections

## Setup Fully automated Kubernetes Cluster Master and X number of Worker nodes
This script will install cluster on Master node, then it automatically ssh to woker nodes and join the cluster. The number of worker nodes can be as many as you like

### Pre-requisites
- The Rule of worker node's name must have a base name (E.g: lxk8snode) which will be stored into env variable K8SNODE and then no of worker nodes (E.g: 100) which will be stored into env variable NOOFWORKERS
- The worker nodes must all be running and the login credential password must all be the same on all those 100 worker nodes and this login must have sudo root
- The parameter will be similar to setup-k8scrio.sh script

### Installing Kubernetes Cluster with 1 master and 100 worker nodes
#### Assumptions: 
<pre>
K8SMASTER = lxk8smaster
K8SNODE = lxk8sworker
NOOFWORKERS = 100
networking using calico
Relocate /var/lib/kubelet => /opt/kubelet
Reolocate /var/lib/container => /opt/container
Size of /opt = 32GB (all ephemeral storage will be allocated here)
</pre>
#### Run the installation
./setup-k8sfullcrio.sh -u k8s -k /opt/kubelet -c /opt/container -n c
NOTE: must run the above script on master node

#### Script routines
- Check all worker nodes are up and running
- Prompts for any required information if the above environment variables are not set
- The answers for all the above prompts will be stored into a file, so it can be sourced when script is re-run (due to failure)
- Login to a woker node using username and password which were prompted in previous step (password is encoded when it is stored into a file)
- The above login since it has sudo access therefore it will copy authorized_keys into root user, so master is able to establish root passwordless connection to all worker nodes
- Perform kubernetes cluster install on master (lxk8smaster)
- Perform kubernetes cluster install sequentially on all worker nodes (lxk8snode1, lxk8snode2 .... lxk8snode100)
- Display kubectl get nodes result
- Delete the nvironment variable's file when it is completed successfully


## Setup BDC single and multi nodes (SQL BDC is going to be EOL)
This script will install kubernetes and SQL Big Data Cluster

### Pre-requisites
- Storage class must be ready to use or uses local storage instead
- it covers Linux distros such as: Centos/RHEL, Debian/Ubuntu, OpenSUSE, Arch Linux
- it covers networking orchestrations such as: Calico, Flannel, Cilium and weave (NOTE: Flannel that works everytime, others need tweakings)
- Check DOCKER_TAG for latest BDC version, by the time i wrote this, the image has DOCKER_TAG="2019-CU8-ubuntu-16.04"

### Installing SQL BDC
The following is the paramemters of this script
<pre>
Usage:
    ./setup-bdc.sh -m [mode]  -u [k8s_user] -l [local_storage_path] -k [kubelet_storage] -d [docker_storage] -s [storage_class] -o [bdc-config-optio] -n [network-plugin]

    -m mode [destroy-all|reset-all|reset-single|reset-master|reset-worker|single|''(default)]
    -u k8s-user [any-name|k8s(default)]

    -l local-storage [any-mountpoint|/mnt/local-storage(default)]
    -k kubelet-storage [any-mountpoint|/var/lib/kubelet(default)]

    -d docker-storage [any-mountpoint|/var/lib/docker(default)]
    -s storageclass [any-storageclass|local-storage]

    -n network [f flannel|c calico(default)]|ci cilium|w weave
    -o bdc-config-option pre-defined-config-dir|none(default)

    destroy-all  #Reset all configurations and delete kubernetes packages
    reset-all    #Reset all configurations only
    reset-single #Reset all configuration then re-install single BDC cluster
    reset-master #Reset all configuration then re-install master BDC cluster
    reset-worker #Reset all configuration then re-install worker BDC cluster (requires BDC cluster master)

    E.g: ./setup-bdc.sh -m reset-single -u kube -l /opt/local-storage -k /opt/kubelet -d /opt/docker -n f
         ./setup-bdc.sh -m reset-master -u kube -l /opt/local-storage -d /opt/docker -s csi-rbd-ceph #using storageclass csi-rbd-ceph and calico network(default)
         ./setup-bdc.sh -m reset-master -u kuser -d /opt/docker #the rest parameters will be using default values

</pre>

## Setup/Install Kubernetes and docker community edition version
This script will install kubernetes cluster (master and its wokers) into Linux VM (supported: Redhat/Centos, suse, ubuntu, debian, arch linux)

### Installing kubernetes master
NOTES:
setup-k8scrio.sh will install kubernetes with cri-o runtime 
setup-k8stiny.sh will install kubernetes with containerd runtime
setup-k8s.sh will install kubernetes with docker runtime (including docker-ce package)
All parameters are the same between 3 scripts above
The parameter docker-storage on setup-k8scrio.sh and setup-kstiny.sh have been removed (i will modify this later as parameter to relocate ephemral disk of cri-o and containerd)
There still some known issues when using calico, therefore you either use flannel or weave (will add some other network plugins in the future such as cilium, etc)


<pre>
Usage:
    ./setup-k8scrio.sh -m [mode] -u [k8s_user] -l [local_storage_path] -k [kubelet_storage] -d [docker_storage] -s [storage_class] -n [network-plugin]

    -m mode [reset-all|destroy-all|reset-single|reset-master|reset-worker|single|''(default)]
    -u k8s-user [any-name|k8s(default)]

    -l local-storage [any-mountpoint|/mnt/local-storage(default)]
    -k kubelet-storage [any-mountpoint|/var/lib/kubelet(default)]

    -d docker-storage [any-mountpoint|/var/lib/docker(default)]
    -s storageclass [any-storageclass|local-storage]

    -n network [f flannel|c calico(default)]
    E.g: ./setup-k8scrio.sh -m reset-single -u kube -l /opt/local-storage -k /opt/kubelet -d /opt/docker -n f
         ./setup-k8scrio.sh -m reset-master -u kube -l /opt/local-storage -d /opt/docker -s csi-rbd-ceph #using storageclass csi-rbd-ceph and calico network(default)
         ./setup-k8scrio.sh -m reset-master -u kuser -d /opt/docker #the rest parameters will be using default values
       

 </pre>

### Issues on calico
Anyone can participate to fix this issue, based on my observations the following are the current issues:
1. all nodes are in Ready state, but when you create a pod in any worker node, for some reason it cant connect to coredns, it stills ping-able to outside word but i cant perform any apt update from within the pod and unable to ping to let say www.google.com
2. all nodes are in Ready state for all linux distros except centos (which i believe happens to redhat too), so when installing centos as a worker node, the node always in not-ready state
3. it seems minimum TLS 1.2 doesnt work properly with kubernetes, so this will impact debian 10 onwards and centos/redhat 8 onwards, therefore i must change the minimum TLS which originally defaulted to TLS 1.2 to TLS 1.1 (i am not sure whether this is fixed or not with kubernetes 1.20 onwards). there is a piece of codes in the script that alter this TLS from 1.2 to minimum 1.1

