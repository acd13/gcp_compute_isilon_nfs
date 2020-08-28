#!/bin/bash
sudo yum install -y nfs-utils
sudo mkdir /mnt/nfsdir1
sudo mount 10.128.0.2:/ifs/nfsdir1 /mnt/nfsdir1/
