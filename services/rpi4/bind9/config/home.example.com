$TTL 2d

$ORIGIN home.example.com.

@            IN       SOA ns.home.example.com. example.gmail.com. (
                                              20250623; serial
                                              12h ; refresh
                                              15m ; retry
                                              3w ; serial
                                              2h ; minimum ttl
                                              )
          IN       NS bastion.home.example.com.
bastion   IN       A   192.168.1.216
plex      IN       A   192.168.1.45
nas       IN       A   192.168.1.42
proxmox   IN       A   192.168.1.210
proxmoxn1 IN       A   192.168.1.252
xteve     IN       A   192.168.1.75
jellyfin  IN       A   192.168.1.134
rpi5      IN       A   192.168.1.146
localstorage IN    A   192.168.1.190
k8s-c01-n01 IN A 192.168.1.17
k8s-c01-n02 IN A 192.168.1.209
k8s-c01-n03 IN A 192.168.1.137
