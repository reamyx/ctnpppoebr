#!/bin/env sh
exit 0

#POE桥接实例,批量管理,非守护执行,因集群管理暂缺配置为持久容器
OPT="stop"; \
for ID in {96..96}; do CNM="poebr$ID"
SRVCFG='{"initdelay":3,"workstart":"./pbrsrvstart.sh",
"workwatch":"","workintvl":5,"firewall":{"icmppermit":"yes"},
"pbrsrv":{"lnuser":"a15368400819","lnpswd":"a123456",
"maxcnct":3,"etcdnm":"http://etcdser:2379"}}'
docker stop "$CNM"; docker rm "$CNM"
[ "$OPT" == "stop" ] && continue
docker container run --detach --restart always \
--name "$CNM" --hostname "$CNM" \
--network imvn --cap-add NET_ADMIN \
--sysctl "net.ipv4.ip_forward=1" \
--device /dev/ppp --device /dev/net/tun \
--volume /etc/localtime:/etc/localtime:ro \
--dns 192.168.15.192 --dns-search local \
--env "SRVCFG=$SRVCFG" ctnpppoebr;
docker network connect emvn "$CNM"; done

docker container exec -it poebr96 bash


#POE桥节点
POE桥节点(pbr225)      192.168.15.226      #非托管
容器网段               192.168.8.96-127/27

POE桥节点(pbr226)      192.168.15.226      #非托管
容器网段               192.168.8.128-159/27


#mac地址查看
for ID in {128..159}; do CNM="poebr$ID"
docker container exec "$CNM" ip link show eth1 | awk '$1=="link/ether"{print $2}'
done


#日志实例:

#数据库: mrdb198 参看mariadb测试

#pbrlog185 推荐无状态,集群管理暂缺时配置为持久容器
SRVCFG='{"initdelay":2,"workstart":"./pbrsrvlogstart.sh",
"workwatch":0,"workintvl":5,"firewall":{"icmppermit":"yes"},
"pbrlog":{"sqlser":"mrdb198","etcdnm":"http://etcdser:2379"}}'; \
docker stop pbrlog185; docker rm pbrlog185; \
docker container run --detach --restart always \
--name pbrlog185 --hostname pbrlog185 \
--network imvn --cap-add NET_ADMIN \
--volume /etc/localtime:/etc/localtime:ro \
--ip 192.168.15.185 --dns 192.168.15.192 --dns-search local \
--env "SRVNAME=pbrlog" --env "SRVCFG=$SRVCFG" ctnpppoebr

docker container exec -it pbrlog185 bash


#pbrlog184 推荐无状态,集群管理暂缺时配置为持久容器
SRVCFG='{"initdelay":2,"workstart":"./pbrsrvlogstart.sh",
"workwatch":0,"workintvl":5,"firewall":{"icmppermit":"yes"},
"pbrsrvlog":{"sqlser":"192.168.15.198","etcdnm":"http://etcdser:2379"}}'; \
docker stop pbrlog184; docker rm pbrlog184; \
docker container run --detach --restart always  \
--name pbrlog184 --hostname pbrlog184 \
--network imvn --cap-add NET_ADMIN \
--volume /etc/localtime:/etc/localtime:ro \
--ip 192.168.15.184 --dns 192.168.15.192 --dns-search local \
--env "SRVNAME=pbrlog" --env "SRVCFG=$SRVCFG" ctnpppoebr

docker container exec -it pbrlog184 bash
