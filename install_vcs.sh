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
        echo "正在安装ffmpeg"
            if [ "${release}" == "centos" ] ; then
                yum -y install epel-release > /dev/null 2>&1
                yum -y install wget > /dev/null 2>&1
                yum update > /dev/null 2>&1
                wget --no-check-certificate -qO ffmpeg.tar.xz https://ghproxy.com/https://github.com/zhai0122/OpenSourceCode/releases/download/ffmpeg/ffmpeg-git-amd64-static.tar.xz > /dev/null 2>&1
                tar xf ffmpeg.tar.xz && cp -f ./ffmpeg-git-20220722-amd64-static/ffmpeg /usr/bin/ffmpeg && rm ./ffmpeg-git-20220722-amd64-static ffmpeg.tar.xz -rf > /dev/null 2>&1
            else
                apt-get update > /dev/null 2>&1
                apt-get -y install wget > /dev/null 2>&1
                apt-get -y install ffmpeg > /dev/null 2>&1
            fi
    fi
}

check_mediainfo(){
    if [ ! -e '/usr/bin/mediainfo' ]; then
        echo "正在安装mediainfo"
            if [ "${release}" == "centos" ] ; then
                yum -y install epel-release > /dev/null 2>&1
                yum update > /dev/null 2>&1
                yum -y install mediainfo > /dev/null 2>&1
            else
                apt-get update > /dev/null 2>&1
                apt-get -y install mediainfo > /dev/null 2>&1
            fi
    fi
}

check_ImageMagick(){
    if [ ! -e '/usr/bin/convert' ]; then
        echo "正在安装ImageMagick"
            if [ "${release}" == "centos" ]; then
                yum update > /dev/null 2>&1
                yum install ImageMagick -y > /dev/null 2>&1
            else
                apt-get update /dev/null 2>&1
                apt-get install imagemagick -y /dev/null 2>&1
            fi

    fi


}

check_vcs(){
    if [ ! -e '/usr/bin/vcs' ]; then
        echo "正在安装vcs"
        wget --no-check-certificate -qO vcs http://p.outlyer.net/files/vcs/vcs-1.13.4.bash > /dev/null 2>&1
        mv vcs /usr/bin/vcs && chmod u+x /usr/bin/vcs > /dev/null 2>&1
    fi
}
main(){
    check_root;
    check_system;
    check_ffmpeg;
    check_mediainfo;
    check_ImageMagick;
    check_vcs;
}
main
