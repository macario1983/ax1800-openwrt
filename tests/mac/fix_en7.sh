#!/bin/zsh
echo "=== fix en7 $(date '+%H:%M:%S') ==="
networksetup -setmanual "Lenovo USB-C Hub" 192.168.31.100 255.255.255.0 2>/dev/null
ipconfig set en7 MANUAL 192.168.31.100 255.255.255.0
sleep 3
ifconfig en7 -alias 192.168.1.199 2>/dev/null
route -n add -net 192.168.31.0/24 -interface en7 2>/dev/null
route -n add -host 192.168.1.2 -interface en7 2>/dev/null
arp -d 192.168.1.2 2>/dev/null
echo "-- en7 inet:"; ifconfig en7 | grep 'inet '
echo "-- rotas 31/1.2:"; netstat -rn -f inet | grep -E '^192\.168\.(31|1)\.' | head -6
echo "-- ping 31.1:"; ping -c 2 -t 3 192.168.31.1 | tail -2
echo "-- ping 1.2:"; ping -c 2 -t 3 192.168.1.2 | tail -2
echo "-- arp final:"; arp -an | grep -E '\(192\.168\.31\.1\)|\(192\.168\.1\.2\)|\(192\.168\.31\.100\)'
