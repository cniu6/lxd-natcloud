#!/usr/bin/env bash
# from
# https://github.com/spiritLHLS/lxd
# 2023.09.02

# 输入
# ./modify.sh 服务器名称 SSH端口 外网起端口 外网止端口 下载速度 上传速度 是否启用IPV6(Y or N)
# 如果 外网起端口 外网止端口 都设置为0则不做区间外网端口映射了，只映射基础的SSH端口，注意不能为空，不进行映射需要设置为0

# 创建容器
cd /root >/dev/null 2>&1
name="${1:-test}"
sshn="${2:-20001}"
nat1="${3:-20002}"
nat2="${4:-20025}"
in="${5:-300}"
out="${6:-300}"
# 支持docker虚拟化
lxc config set "$name" security.nesting true
ori=$(date | md5sum)
passwd=${ori:2:9}
lxc start "$name"
sleep 1
/usr/local/bin/check-dns.sh
if echo "$system" | grep -qiE "centos|almalinux"; then
    lxc exec "$name" -- sudo yum update -y
    lxc exec "$name" -- sudo yum install -y curl
    lxc exec "$name" -- sudo yum install -y dos2unix
elif echo "$system" | grep -qiE "alpine"; then
    lxc exec "$name" -- apk update
    lxc exec "$name" -- apk add --no-cache curl
else
    lxc exec "$name" -- sudo apt-get update -y
    lxc exec "$name" -- sudo apt-get install curl -y --fix-missing
    lxc exec "$name" -- sudo apt-get install dos2unix -y --fix-missing
fi
if echo "$system" | grep -qiE "alpine"; then
    if [ ! -f /usr/local/bin/alpinessh.sh ]; then
        curl -L https://raw.githubusercontent.com/spiritLHLS/lxd/main/scripts/alpinessh.sh -o /usr/local/bin/alpinessh.sh
        chmod 777 /usr/local/bin/alpinessh.sh
        dos2unix /usr/local/bin/alpinessh.sh
    fi
    cp /usr/local/bin/alpinessh.sh /root
    lxc file push /root/alpinessh.sh "$name"/root/
    lxc exec "$name" -- chmod 777 alpinessh.sh
    lxc exec "$name" -- ./alpinessh.sh ${passwd}
else
    if [ ! -f /usr/local/bin/ssh.sh ]; then
        curl -L https://raw.githubusercontent.com/spiritLHLS/lxd/main/scripts/ssh.sh -o /usr/local/bin/ssh.sh
        chmod 777 /usr/local/bin/ssh.sh
        dos2unix /usr/local/bin/ssh.sh
    fi
    cp /usr/local/bin/ssh.sh /root
    lxc file push /root/ssh.sh "$name"/root/
    lxc exec "$name" -- chmod 777 ssh.sh
    lxc exec "$name" -- dos2unix ssh.sh
    lxc exec "$name" -- sudo ./ssh.sh $passwd
    if [ ! -f /usr/local/bin/config.sh ]; then
        curl -L https://raw.githubusercontent.com/spiritLHLS/lxd/main/scripts/config.sh -o /usr/local/bin/config.sh
        chmod 777 /usr/local/bin/config.sh
        dos2unix /usr/local/bin/config.sh
    fi
    cp /usr/local/bin/config.sh /root
    lxc file push /root/config.sh "$name"/root/
    lxc exec "$name" -- chmod +x config.sh
    lxc exec "$name" -- dos2unix config.sh
    lxc exec "$name" -- bash config.sh
    lxc exec "$name" -- history -c
fi
lxc config device add "$name" ssh-port proxy listen=tcp:0.0.0.0:$sshn connect=tcp:127.0.0.1:22
# 是否要创建V6地址
if [ -n "$7" ]; then
    if [ "$7" == "Y" ]; then
        if [ ! -f "./build_ipv6_network.sh" ]; then
            # 如果不存在，则从指定 URL 下载并添加可执行权限
            curl -L https://raw.githubusercontent.com/spiritLHLS/lxd/main/scripts/build_ipv6_network.sh -o build_ipv6_network.sh && chmod +x build_ipv6_network.sh >/dev/null 2>&1
        fi
        ./build_ipv6_network.sh "$name" >/dev/null 2>&1
    fi
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
    lxc config device add "$name" nattcp-ports proxy listen=tcp:0.0.0.0:$nat1-$nat2 connect=tcp:127.0.0.1:$nat1-$nat2
    lxc config device add "$name" natudp-ports proxy listen=udp:0.0.0.0:$nat1-$nat2 connect=udp:127.0.0.1:$nat1-$nat2
fi
# 网速
lxc stop "$name"
lxc config device override "$name" eth0 limits.egress="$out"Mbit limits.ingress="$in"Mbit
lxc start "$name"
rm -rf ssh.sh config.sh alpinessh.sh
if echo "$system" | grep -qiE "alpine"; then
    sleep 3
    lxc stop "$name"
    lxc start "$name"
fi
if [ "$nat1" != "0" ] && [ "$nat2" != "0" ]; then
    echo "$name $sshn $passwd $nat1 $nat2" >"$name"
    echo "$name $sshn $passwd $nat1 $nat2"
    exit 1
fi
if [ "$nat1" == "0" ] && [ "$nat2" == "0" ]; then
    echo "$name $sshn $passwd" >"$name"
    echo "$name $sshn $passwd"
fi
