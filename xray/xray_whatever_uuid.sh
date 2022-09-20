#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin; export PATH

# tempfile & rm it when exit
trap 'rm -f "$TMPFILE"' EXIT; TMPFILE=$(mktemp) || exit 1

########
[[ $# != 1 ]] && [[ $# != 2 ]] && echo Err  !!! Useage: bash this_script.sh uuid my.domain.com && exit 1
[[ $# == 1 ]] && uuid="$(cat /proc/sys/kernel/random/uuid)" && domain="$1"
[[ $# == 2 ]] && uuid="$1" && domain="$2"
xtlsflow="xtls-rprx-direct" && ssmethod="chacha20-ietf-poly1305"
trojanpath="${uuid}-trojan"
vlesspath="${uuid}-vless"
vlessh2path="${uuid}-vlessh2"
vmesstcppath="${uuid}-vmesstcp"
vmesswspath="${uuid}-vmess"
vmessh2path="${uuid}-vmessh2"
shadowsockspath="${uuid}-ss"
configxray=${configxray:-https://raw.githubusercontent.com/cary-sas/across/master/xray/etc/xray.json}
configcaddy=${configcaddy:-https://raw.githubusercontent.com/cary-sas/across/master/xray/etc/caddy.json}
########

function install_xray_caddy(){
    # xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
	
    # install caddy through apt install
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo tee /etc/apt/trusted.gpg.d/caddy-stable.asc
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install caddy
    caddy_url=https://github.com/lxhao61/integrated-examples/releases	
    #caddy_version=$(curl -k -s  $caddy_url | grep /lxhao61/integrated-examples/releases/tag/  | head -1 | awk -F'"' '{print $6}' | awk -F/ '{print $NF}')
    caddy_version="20220507"
    wget --no-check-certificate -O $TMPFILE "${caddy_url}/download/${caddy_version}/caddy-linux-$(dpkg --print-architecture).tar.gz" && tar -xf  $TMPFILE -C ./
    mv caddy /usr/bin/caddy && chmod +x /usr/bin/caddy
 
    sed -i "s/caddy\/Caddyfile$/caddy\/Caddyfile\.json/g" /lib/systemd/system/caddy.service && systemctl daemon-reload
}

function config_xray_caddy(){
    # xrayconfig
    wget -O /usr/local/etc/xray/config.json $configxray
    sed -i -e "s/\$uuid/$uuid/g" -e "s/\$xtlsflow/$xtlsflow/g" -e "s/\$ssmethod/$ssmethod/g" -e "s/\$trojanpath/$trojanpath/g" -e "s/\$vlesspath/$vlesspath/g" \
           -e "s/\$vlessh2path/$vlessh2path/g" -e "s/\$vmesstcppath/$vmesstcppath/g" -e "s/\$vmesswspath/$vmesswspath/g" -e "s/\$vmessh2path/$vmessh2path/g" \
           -e "s/\$shadowsockspath/$shadowsockspath/g" -e "s/\$domain/$domain/g" /usr/local/etc/xray/config.json
    # caddyconfig
    wget -qO- $configcaddy | sed -e "s/\$domain/$domain/g" -e "s/\$uuid/$uuid/g" -e "s/\$vlessh2path/$vlessh2path/g" -e "s/\$vlesspath/$vlesspath/g" -e "s/\$vmesswspath/$vmesswspath/g" -e "s/\$vmessh2path/$vmessh2path/g" >/etc/caddy/Caddyfile.json
}

function cert_acme(){
    apt install socat -y
    curl https://get.acme.sh | sh && source  ~/.bashrc
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    ~/.acme.sh/acme.sh --register-account -m my@example.com
    ~/.acme.sh/acme.sh --issue -d $domain --standalone --pre-hook "systemctl stop caddy xray" --post-hook "~/.acme.sh/acme.sh --installcert -d $domain --fullchain-file /usr/local/etc/xray/$domain.crt --key-file /usr/local/etc/xray/$domain.key --reloadcmd \"systemctl restart caddy xray\""
    ~/.acme.sh/acme.sh --installcert -d $domain --fullchain-file /usr/local/etc/xray/$domain.crt --key-file /usr/local/etc/xray/$domain.key --reloadcmd "systemctl restart xray"
}

function start_info(){
    systemctl enable caddy xray && systemctl restart caddy xray && sleep 3 && systemctl status caddy xray | grep -A 2 "service"
    cat <<EOF >$TMPFILE
{
  "v": "2",
  "ps": "$domain-ws",
  "add": "$domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "$domain",
  "path": "$vmesswspath",
  "tls": "tls"
}
EOF
vmesswsinfo="$(echo "vmess://$(base64 -w 0 $TMPFILE)")"

    cat <<EOF >$TMPFILE
{
  "v": "2",
  "ps": "$domain-h2",
  "add": "$domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "net": "h2",
  "type": "none",
  "host": "$domain",
  "path": "$vmessh2path",
  "tls": "tls"
}
EOF
vmessh2info="$(echo "vmess://$(base64 -w 0 $TMPFILE)")"

    cat <<EOF >$TMPFILE
{
  "v": "2",
  "ps": "$domain-grpc",
  "add": "$domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "net": "grpc",
  "type": "none",
  "host": "none",
  "path": "$vmesswspath",
  "tls": "tls"
}
EOF
vmessgrpcinfo="$(echo "vmess://$(base64 -w 0 $TMPFILE)")"

    cat <<EOF >$TMPFILE
$(date) $domain vmess:
uuid: $uuid
tcppath: $vmesstcppath
ws+tls: $vmesswsinfo
h2+tls: $vmessh2info
gRPC  : $vmessgrpcinfo

$(date) $domain vless:
uuid: $uuid
wspath: $vlesspath
h2path: $vlessh2path
serviceName: $vlesspath
xtls  : vless://$uuid@$domain:443?encryption=none&security=xtls&type=tcp&headerType=none&flow=xtls-rprx-splice#$domain-vless(xtls)
ws+tls: vless://$uuid@$domain:443?sni=&host=$domain&type=ws&security=tls&path=$vlesspath&encryption=none#$domain-vless(ws) 
h2+tls: vless://$uuid@$domain:443?sni=&host=$domain&type=h2&security=tls&path=$vlessh2path&encryption=none#$domain-vless(h2) 
gRPC  : vless://$uuid@$domain:443?sni=&host=$domain&type=grpc&security=tls&serviceName=$vlesspath&encryption=none#$domain-vless(gRPC) 

$(date) $domain trojan:
password: $uuid
path: $trojanpath
tcp+tls: trojan://$uuid@$domain:443#$domain-trojan
ws+tls : trojan-go://$uuid@$domain:443?sni=&host=$domain&type=ws&security=tls&path=$trojanpath#$domain-trojan(ws) 

$(date) $domain shadowsocks+v2ray-plugin:   
ss://$(echo -n "${ssmethod}:${uuid}" | base64 | tr "\n" " " | sed s/[[:space:]]//g | tr -- "+/=" "-_ " | sed -e 's/ *$//g')@${domain}:443?plugin=v2ray-plugin%3Bpath%3D%2F${shadowsockspath}%3Bhost%3D${domain}%3Btls%3Bloglevel%3Dnone#${domain}

$(date) $domain naiveproxy:
probe_resistance: $uuid.com
proxy: https://$uuid:$uuid@$domain

$(date) Visit: https://$domain
EOF

    cat $TMPFILE | tee /var/log/${TMPFILE##*/} && echo && echo $(date) Info saved: /var/log/${TMPFILE##*/}
}

function remove_purge(){
    apt purge caddy -y
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    bash <(curl https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove; systemctl disable v2ray
    ~/.acme.sh/acme.sh --uninstall
    return 0
}

function main(){
    [[ "$domain" == "remove_purge" ]] && remove_purge && exit 0
    install_xray_caddy
    config_xray_caddy
    cert_acme
    start_info
}

main
