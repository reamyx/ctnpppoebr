#官方centos7镜像初始化,镜像TAG: ctnpbrsrv

FROM        imginit
LABEL       function="ctnpbrsrv"

#添加本地资源
ADD     pbrsrv     /srv/pbrsrv/
ADD     pbrlog     /srv/pbrlog/

WORKDIR /srv/pbrsrv

#功能软件包
RUN     set -x \
        && cd ../imginit \
        && mkdir -p installtmp \
        && cd installtmp \
        \
        && yum -y install mariadb \
        && yum -y install gcc make automake zlib-devel \
        \
        && curl https://codeload.github.com/reamyx/rp-pppoe-zxmd/zip/master -o rp-pppoe-zxmd.zip \
        && unzip rp-pppoe-zxmd.zip \
        && cd rp-pppoe-zxmd-master/src \
        && ./configure \
        && make \
        && make install \
        && cd - \
        \
        && curl -L https://github.com/etcd-io/etcd/releases/download/v3.3.12/etcd-v3.3.12-linux-amd64.tar.gz \
           -o etcd-v3.3.12-linux-amd64.tar.gz \
        && tar -zxvf etcd-v3.3.12-linux-amd64.tar.gz \
        && cd etcd-v3.3.12-linux-amd64 \
        && \cp -f etcdctl /usr/bin \
        && cd - \
        \
        && cd ../ \
        && yum -y history undo last \
        && yum clean all \
        && rm -rf installtmp /tmp/* \
        && find ../ -name "*.sh" -exec chmod +x {} \;

ENV       ZXDK_THIS_IMG_NAME    "ctnpbrsrv"
ENV       SRVNAME               "pbrsrv"

# ENTRYPOINT CMD
CMD [ "../imginit/initstart.sh" ]
