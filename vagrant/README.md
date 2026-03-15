# Vagrant-based Kubernetes cluster for db-k8s-stack

This directory contains a Vagrantfile and provisioning scripts to create a three‑node Kubernetes cluster on VirtualBox. It is intended for local testing of the db-k8s-stack application.

## Requirements

- [Vagrant](https://www.vagrantup.com/) 2.2 or later
- [VirtualBox](https://www.virtualbox.org/) as the VM provider
- An x86_64 host machine with virtualization support and at least 8 GB of RAM (the VMs request 4 GB each)

## Nodes

| VM name | Role | IP address |
|--------|------|------------|
| `cp1` | Control plane | 192.168.56.10 |
| `worker1` | Worker node | 192.168.56.20 |
| `worker2` | Worker node | 192.168.56.21 |

All machines run Ubuntu 20.04 (focal64). The project repository is mounted in each VM at `/vagrant`.

## Provisioning overview

1. **provision-common.sh** – runs on every node, disables swap, installs containerd, adds the Kubernetes apt repository, and installs kubeadm/kubelet/kubectl with pinned versions. It also configures the necessary kernel modules and sysctl settings.
2. **provision-master.sh** – runs only on the control plane (`cp1`). It initializes the cluster with `kubeadm init`, applies the Flannel CNI plugin, writes a join script to `/vagrant/join.sh`, and deploys the db‑k8s‑stack application manifests.
3. **provision-worker.sh** – runs on each worker node. It executes the join script produced by the master to add the node to the cluster.

## Usage

From the repository root:

```sh
cd vagrant
vagrant up
```

Vagrant will download the base box, create the VMs, and run the provisioning scripts. The entire process can take several minutes.

### Access the cluster

SSH into the control plane and list nodes:

```sh
vagrant ssh cp1
kubectl get nodes
kubectl get pods -A
```

The Kubernetes configuration for `kubectl` is automatically placed in the vagrant user's home directory.

### Deploy updates

The master provisioning script deploys the application manifests found in `k8s/`. If you modify these manifests, you can apply them manually from cp1:

```sh
kubectl apply -f /vagrant/db-k8s-stack/k8s/...
```

### Destroy the cluster

To tear down all VMs and free resources:

```sh
vagrant destroy -f
```

This removes the VMs completely. You can run `vagrant up` again to recreate them.
