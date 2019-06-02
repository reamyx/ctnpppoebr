#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

IFNM="eth1"

#清除IP地址,v4和v6
ADDR="$( ip -4 -o addr show "$IFNM" | awk '$3=="inet"{print $4;exit}' )"
ip -4 addr del dev "$IFNM" "$ADDR"
ADDR="$( ip -6 -o addr show "$IFNM" | awk '$3=="inet"{print $4;exit}' )"
ip -6 addr del dev "$IFNM" "$ADDR"


#更改eth1接口MAC地址,在eth0基础上生成eth1的新mac地址,变更8-15位
MA=( $( ip link show "eth0" | awk '$1=="link/ether"{gsub(":"," ",$2);print $2}' ) )
[ -z "${MA[0]}" ] && exit 1
[ "${MA[1]}" == "7d" ] && MA[1]="8f" || MA[1]="7d"
ip link set dev "$IFNM" address "${MA[0]}:${MA[1]}:${MA[2]}:${MA[3]}:${MA[4]}:${MA[5]}"

exit 0
