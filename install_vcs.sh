#!/bin/env bash


RED='\033[0;31m'
PLAIN='\033[0m'

check_root(){
	[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行本脚本！${PLAIN}" && exit 1
}

check_system() {
	if [ -f /etc/redhat-release ]; then
	    release="centos"
	elif cat /etc/issue | grep -Eqi "debian"; then
	    release="debian"
	elif cat /etc/issue | grep -Eqi "ubuntu"; then
	    release="ubuntu"
	elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
	    release="centos"
	elif cat /proc/version | grep -Eqi "debian"; then
	    release="debian"
	elif cat /proc/version | grep -Eqi "ubuntu"; then
	    release="ubuntu"
	elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
	    release="centos"
	fi
}

check_ffmpeg(){
    if [ ! -e '/usr/bin/ffmpeg' ]; then
        echo "1/4 正在安装ffmpeg"
            if [ "${release}" == "centos" ] ; then
                yum -y install epel-release > /dev/null 2>&1
                yum -y install wget > /dev/null 2>&1
                yum -y update > /dev/null 2>&1
                wget --no-check-certificate -qO ffmpeg.tar.xz https://ghproxy.com/https://github.com/zhai0122/OpenSourceCode/releases/download/ffmpeg/ffmpeg-git-amd64-static.tar.xz > /dev/null 2>&1
                tar xf ffmpeg.tar.xz && cp -f ./ffmpeg-git-20220722-amd64-static/ffmpeg /usr/bin/ffmpeg && rm ./ffmpeg-git-20220722-amd64-static ffmpeg.tar.xz -rf > /dev/null 2>&1
            else
                apt-get -y update > /dev/null 2>&1
                apt-get -y install wget > /dev/null 2>&1
                apt-get -y install ffmpeg > /dev/null 2>&1
            fi
    fi
}

check_mediainfo(){
    if [ ! -e '/usr/bin/mediainfo' ]; then
        echo "2/4 正在安装mediainfo"
            if [ "${release}" == "centos" ] ; then
                yum -y install epel-release > /dev/null 2>&1
                yum -y update > /dev/null 2>&1
                yum -y install mediainfo > /dev/null 2>&1
            else
                apt-get -y update > /dev/null 2>&1
                apt-get -y install mediainfo > /dev/null 2>&1
            fi
    fi
}

check_imagemagick(){
    if [ ! -e '/usr/bin/convert' ]; then
        echo "3/4 正在安装imagemagick"
            if [ "${release}" == "centos" ]; then
                yum -y update > /dev/null 2>&1
                yum -y install ImageMagick > /dev/null 2>&1
            else
                apt-get -y update > /dev/null 2>&1
                apt-get -y install imagemagick > /dev/null 2>&1
            fi

    fi


}

check_vcs(){

    echo "4/4 正在安装vcs"
    wget --no-check-certificate -qO vcs https://ghproxy.com/https://raw-gh.gcdn.mirr.one/zhai0122/install_vcs/remove-program/vcs-1.13.4_qu.bash > /dev/null 2>&1
    mv -f ./vcs /usr/bin/vcs && chmod u+x /usr/bin/vcs > /dev/null 2>&1
    source /etc/profile

}
main(){
    check_root;
    check_system;
    check_ffmpeg;
    check_mediainfo;
    check_imagemagick;
    check_vcs;
}
main
