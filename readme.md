# My bash script collections

## Setup BDC single and multi nodes
This script will install kubernetes and SQL Big Data Cluster

### Pre-requisites
- Storage class must be ready to use or uses local storage instead
- it covers Linux distros such as: Centos/RHEL, Debian/Ubuntu, OpenSUSE, Arch Linux
- it covers networking orchestrations such as: Calico, Flannel, Cilium and weave (NOTE: Flannel that works everytime, others need tweakings)
- Check DOCKER_TAG for latest BDC version, by the time i wrote this, the image has DOCKER_TAG="2019-CU8-ubuntu-16.04"

### Installing BDC
The following is the paramemters of this script
<pre>
Usage:
    ./setup-bdc.sh -m ``<mode``> -u `<k8s_user`> -l \<local_storage_path\> -k \<kubelet_storage\> -d \<docker_storage\> -s \<storage_class\> -o \<bdc-config-optio\n> -n \<network-plugin\>

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
