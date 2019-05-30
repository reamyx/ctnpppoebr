#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

#持锁运行,避免重入
LKFL="./PbrLog.Lock"; exec 5<>"$LKFL" && flock -x -n 5 || exit 1

#DDNS注册
DDNSREG="./PeriodicRT-ddns-update"
[ -f "$DDNSREG" ] && ( chmod +x "$DDNSREG"; setsid "$DDNSREG" & )

#日志库表创建过程($1服务器名称,$2端口,$3账号,$4密码,$5库名称)
#操作过程仅尝试建立必要的数据库和表,不代表数据库连接或账号的有效性
PBRSRVDB_CREATE() {
    mysql -h"$1" -P"$2" -u"$3" -p"$4" -e "CREATE DATABASE IF NOT EXISTS $5;"
    mysql -h"$1" -P"$2" -u"$3" -p"$4" -D"$5" -e \
    "CREATE TABLE IF NOT EXISTS cninstlog (
        autoid INTEGER  PRIMARY KEY AUTO_INCREMENT,
        instid CHAR(16) NOT NULL,
        usname CHAR(16) NOT NULL,
        udstat CHAR(16) NOT NULL,
        usaddr CHAR(16) NOT NULL,
        uptime DATETIME NOT NULL,
        cntime INTEGER  DEFAULT NULL,
        upflow BIGINT   DEFAULT NULL,
        dwflow BIGINT   DEFAULT NULL,
        ustmac CHAR(20) DEFAULT NULL,
        acpmid INTEGER  DEFAULT NULL,
        UNIQUE KEY (instid, usname)
        ) ENGINE = INNODB;"
    mysql -h"$1" -P"$2" -u"$3" -p"$4" -D"$5" -e \
    "CREATE TABLE IF NOT EXISTS acinfo (
        acpmid INTEGER  PRIMARY KEY AUTO_INCREMENT,
        lacmac CHAR(20) NOT NULL,
        lndlnm CHAR(16) NOT NULL,
        gwaddr CHAR(16) NOT NULL,
        sgdns1 CHAR(16) NOT NULL,
        sgdns2 CHAR(16) NOT NULL,
        UNIQUE KEY (lacmac, lndlnm, gwaddr, sgdns1, sgdns2)
        ) ENGINE = INNODB;"; }

#数据库连通性测试,失败时终止运行
SQLSER_CHECK() {
    for ID in {1..20}; do 
    mysqladmin ping -h"$1" -P"$2" -u"$3" -p"$4" && break
    (( ID == 20 )) && exit 1; sleep 0.5; done; }
    
#环境变量未能提供配置数据时从配置文件读取
[ -z "$SRVCFG" ] && SRVCFG="$( jq -scM ".[0]|objects" "./workcfg.json" )"

#提取SQL配置参数(服务器,账号,密码,库名称),可以指示启用一个本地mysql服务
DBSER="$( echo "$SRVCFG" | jq -r ".pbrlog.sqlser|strings"  )"
DBSPT="$( echo "$SRVCFG" | jq -r ".pbrlog.sqlport|numbers" )"
DBUNM="$( echo "$SRVCFG" | jq -r ".pbrlog.sqluser|strings" )"
DBPWD="$( echo "$SRVCFG" | jq -r ".pbrlog.sqlpwd|strings"  )"
DBSNM="$( echo "$SRVCFG" | jq -r ".pbrlog.dbname|strings"  )"
ETCDS="$( echo "$SRVCFG" | jq -r ".pbrlog.etcdnm|strings"  )"
RTLOG="$( echo "$SRVCFG" | jq -r ".pbrlog.rtlogs|strings"  )"
NOBTH="$( echo "$SRVCFG" | jq -r ".pbrlog.nobth|numbers"   )"

#参数缺省时使用默认值,使用默认sql账号时会配置默认关联密码
DBSER="${DBSER:-localhost}"
DBSPT="${DBSPT:-3306}"
DBSNM="${DBSNM:-pbrlogdb}"
[ -z "$DBUNM" ] && { DBUNM="pbradmin"; DBPWD="pbrpw000"; }
ETCDS="${ETCDS:-http://etcdser:2379}"
NOBTH="${NOBTH:-200}"

#休眠指示,主机名称
DLTM="0"; LH="$HOSTNAME"

#测试SQL服务可用时配置目标库表或SQL服务失败时终止
SQLSER_CHECK "$DBSER" "$DBSPT" "$DBUNM" "$DBPWD"
PBRSRVDB_CREATE "$DBSER" "$DBSPT" "$DBUNM" "$DBPWD" "$DBSNM"

#实时日志收集: [暂未实现]


#缓存日志收集: 

#JSON解析参数
JSON_PM='.instid+" "+.usname+" "+.udstat+" "+.usaddr+" "+.uptime+" "+
(.cntime|numbers|tostring)+" "+(.upflow|numbers|tostring)+" "+
(.dwflow|numbers|tostring)+" "+.ustmac+" "+.lacmac+" "+.lndlnm+" "+
.gwaddr+" "+.sgdns1+" "+.sgdns2'
#SQL构造参数
ASQL_PM='NF==10{print "INSERT INTO cninstlog(instid,usname,udstat,\
usaddr,uptime,cntime,upflow,dwflow,ustmac,acpmid) VALUES(\""$1"\",\
\""$2"\",\""$3"\",\""$4"\",\""$5"\","$6","$7","$8",\""$9"\","$10") \
ON DUPLICATE KEY UPDATE udstat=VALUES(udstat),usaddr=VALUES(usaddr),\
uptime=VALUES(uptime),cntime=VALUES(cntime),upflow=VALUES(upflow),\
dwflow=VALUES(dwflow),ustmac=VALUES(ustmac),acpmid=VALUES(acpmid);"}'

#JSON数据解析过程: $1批次KEY文件,返回批次记录
JSON_EXTRACT() {
    local KEY="" RCDFL="./rcd.list"
    while read KEY; do etcdctl --endpoints "$ETCDS" get "$KEY" | \
    jq -rcM "$JSON_PM"; done < "$1" > "$RCDFL"; mv -f "$RCDFL" "$1"; }

#集中器参数模式匹配过程: $1批次记录文件,返回已匹配记录
IDSET=()
ACPM_MATCH() {
    local LR=() PMID="" LRID="" ID="" DBRFL="./dbr.list"
    while read LR[0]; do
        LR=( ${LR[0]} ); (( "${#LR[@]}" < 14 )) && continue; (( LOGCNT++ ))
        PMID=""; LRID="${LR[9]}-${LR[10]}-${LR[11]}-${LR[12]}-${LR[13]}"
        #缓存ID表查找模式ID失败时从数据库查找模式ID,不存在目标模式时添加到数据库
        for ID in "${IDSET[@]}"; do [[ "$ID" =~ ^"$LRID|" ]] && PMID="${ID##*|}" && break; done
        [ -z "$PMID" ] && {
            PMID="$( mysql -N -h"$DBSER" -P"$DBSPT" -u"$DBUNM" -p"$DBPWD" -D"pbrlogdb" -e "
            BEGIN; SET @id:=IFNULL((SELECT MAX(acpmid)+1 FROM acinfo), 1);
            INSERT INTO acinfo(acpmid, lacmac, lndlnm, gwaddr, sgdns1, sgdns2)
            VALUES(@id, \"${LR[9]}\", \"${LR[10]}\", \"${LR[11]}\", \"${LR[12]}\", \"${LR[13]}\")
            ON DUPLICATE KEY UPDATE lacmac=VALUES(lacmac);
            SELECT acpmid FROM acinfo WHERE lacmac=\"${LR[9]}\" AND lndlnm=\"${LR[10]}\" AND
            gwaddr=\"${LR[11]}\" AND sgdns1=\"${LR[12]}\" AND sgdns2=\"${LR[13]}\"; COMMIT;" )"
            PMID="${PMID:--1}"; IDSET=( "$LRID|$PMID" "${IDSET[@]}" ); }
        echo "${LR[*]:0:9} $PMID"; LR=(); done < "$1" > "$DBRFL"; mv -f "$DBRFL" "$1"; }

#批次更新过程: $1列表KEY文件
BATCH_UPDATA_DB() {
    local KEY="" LNS="${NOBTH:-200}" BTHFL="./bth.list" DELFL="./del.list"
    #分批次提取日志key依次进行数据解析和入库操作
    while [ -s "$1" ]; do
        sed -n "1,${LNS}p" "$1" > "$BTHFL"; sed -i "1,${LNS}d" "$1"
        cat "$BTHFL" > "$DELFL"; JSON_EXTRACT "$BTHFL"; ACPM_MATCH "$BTHFL"
        #数据库可用时构造sql语句并执行到数据库,成功后从etcd目录清除日志缓存
        SQLSER_CHECK "$DBSER" "$DBSPT" "$DBUNM" "$DBPWD"
        awk "$ASQL_PM" "$BTHFL" | \
        mysql -h"$DBSER" -P"$DBSPT" -u"$DBUNM" -p"$DBPWD" -D"$DBSNM" && \
        while read KEY; do etcdctl --endpoints "$ETCDS" rm "$KEY"; done < "$DELFL"
        done; }

#持锁处理过程: $1加锁目录文件
PROCESS_WITH_LOCK() {
    local UDIR="" KEYFL="./key.list"
    #遍历且锁定目标目录成功时获取KEY列表分批处理
    while read UDIR; do
        etcdctl --endpoints "$ETCDS" mk -ttl 60 "${UDIR}Lock/LogSrv" "$LH" || continue
        etcdctl --endpoints "$ETCDS" ls -p "${UDIR}" | grep -E "[^/]$" > "$KEYFL"
        BATCH_UPDATA_DB "$KEYFL"; done < "$1"; }

#日志处理主LOOP
while true; do
    #重置日志计数器和锁定单元列表文件,参数模式集合
    LOGCNT=0 DLTM=40 IDSET=() UNMFL="./unm.list"; >"$UNMFL"
    #从etcd服务器更新用户目录列表后加锁处理
    etcdctl --endpoints "$ETCDS" ls -p "/pbrsrvlog" | grep -E "/$" > "$UNMFL"
    PROCESS_WITH_LOCK "$UNMFL"
    #根据日志计数器重新确定周期延时
    (( LOGCNT > 50 )) && DLTM=20; (( LOGCNT > 100 )) && continue
    ECHO "Extract $LOGCNT logs for last time ,Delay for $DLTM seconds."; sleep "$DLTM"
    done

exit 127

#PBR集群etcd目录规划
#认证账户: "/pbrsrvauth/* KEY:账户名称
#状态记录:  /pbrsrvst/*   KEY:名称-地址-实例ID,实时监视
#日志记录:  /pbrsrvlog/<name>/*  KEY:实例UUID,周期查询

#实时日志收集方法: 
# 1. 监视"/pbrsrvst"目录中的[update]事件以添加用户拨入信息到数据库
# 2. 监视"/pbrsrvst"目录中的[delete]事件以更新用户离线信息到数据库
# 3. 完成用户离线信息更新后尝试清理对应的离线缓存记录
# 4. 监视"/pbrsrvst"目录中的[expire]事件以触发异常离线更新
# 5. 异常离线更新即更改目标记录的用户状态"Activated">"AbnormalOffline"

#缓存日志收集方法:
# 1. 扫描目录"/pbrsrvlog"拉取用户名称列表到临时文件
# 2. 遍历用户名称列表并持锁处理目标用户缓存日志
# 2. 拉取并分批次执行当前用户日志数据格式化及持久化操作
# 3. 持久化存储成功后及时清除当前批次的缓存记录
# 4. 周期任务完成后根据日志计数器确定合适的期末延时
