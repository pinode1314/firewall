#!/bin/bash

# 定义颜色变量
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
SKYBLUE='\033[1;36m'
NC='\033[0m' # 恢复默认颜色

# 检查是否为 root 用户 / Check if user is root
if [ "$EUID" -ne 0 ]; then
    printf "${RED}❌ 请使用 root 权限运行此脚本！ / Please run this script with root privileges!\n${NC}"
    exit 1
fi

# ----------------- 系统发行版与防火墙工具识别 / Get Distro & Firewall Type -----------------
get_distro_and_fw() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    else
        OS="unknown"
    fi

    case "$OS" in
        ubuntu|debian|raspbian)
            FW_TYPE="ufw"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            FW_TYPE="firewalld"
            ;;
        alpine)
            FW_TYPE="iptables"
            ;;
        *)
            FW_TYPE="unknown"
            ;;
    esac
}

get_distro_and_fw

# ----------------- 1. 检测系统防火墙安装与运行状态 / Check Firewall Status -----------------
check_firewall_status() {
    echo "=================================================="
    echo "=== 正在检测当前系统的防火墙状态 / Checking Firewall Status ==="
    echo "系统类型 / OS: $OS | 防火墙类型 / Firewall: $FW_TYPE"
    echo "=================================================="

    case "$FW_TYPE" in
        ufw)
            if command -v ufw >/dev/null 2>&1; then
                printf "${GREEN}✔ UFW 已安装 / UFW Installed\n${NC}"
                # 捕获并汉化 UFW 状态
                ufw status verbose | sed 's/Status: inactive/状态: 未激活 (已关闭)/g; s/Status: active/状态: 已激活 (运行中)/g'
            else
                printf "${YELLOW}⚠️ UFW 未安装 / UFW Not Installed\n${NC}"
            fi
            ;;
        firewalld)
            if command -v firewall-cmd >/dev/null 2>&1; then
                printf "${GREEN}✔ Firewalld 已安装 / Firewalld Installed\n${NC}"
                systemctl status firewalld --no-pager
            else
                printf "${YELLOW}⚠️ Firewalld 未安装 / Firewalld Not Installed\n${NC}"
            fi
            ;;
        iptables)
            if command -v iptables >/dev/null 2>&1; then
                printf "${GREEN}✔ Iptables 已安装 / Iptables Installed\n${NC}"
                iptables -L -n -v
            else
                printf "${YELLOW}⚠️ Iptables 未安装 / Iptables Not Installed\n${NC}"
            fi
            ;;
        *)
            printf "${RED}❌ 未能自动识别适配的防火墙组件 / Unsupported Firewall\n${NC}"
            ;;
    esac
}

# ----------------- 2. 查看已放行的端口列表 / List Allowed Ports -----------------
list_allowed_ports() {
    echo "=================================================="
    echo "=== 正在获取当前已放行的端口规则 / Fetching Allowed Ports ==="
    echo "=================================================="

    case "$FW_TYPE" in
        ufw)
            if command -v ufw >/dev/null 2>&1; then
                echo "--- UFW 放行规则列表 / UFW Rules List ---"
                ufw status numbered
            else
                printf "${YELLOW}⚠️ UFW 未安装 / UFW Not Installed\n${NC}"
            fi
            ;;
        firewalld)
            if command -v firewall-cmd >/dev/null 2>&1; then
                echo "--- Firewalld 已放行端口 / Allowed Ports ---"
                firewall-cmd --zone=public --list-ports
                echo "--- Firewalld 已放行服务 / Allowed Services ---"
                firewall-cmd --zone=public --list-services
            else
                printf "${YELLOW}⚠️ Firewalld 未安装 / Firewalld Not Installed\n${NC}"
            fi
            ;;
        iptables)
            if command -v iptables >/dev/null 2>&1; then
                echo "--- Iptables INPUT 规则 / Iptables INPUT Rules ---"
                iptables -L INPUT -n -v --line-numbers
            else
                printf "${YELLOW}⚠️ Iptables 未安装 / Iptables Not Installed\n${NC}"
            fi
            ;;
        *)
            printf "${RED}❌ 无法识别的防火墙类型 / Unknown Firewall Type\n${NC}"
            ;;
    esac
}

# ----------------- 3. 安装防火墙功能 / Install Firewall -----------------
install_firewall() {
    echo "=== 正在根据系统类型安装防火墙组件 / Installing Firewall ==="
    case "$OS" in
        ubuntu|debian|raspbian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y && apt-get install -y ufw
            systemctl enable ufw --now
            printf "${GREEN}✔ UFW 安装并已设置开机自启完成。/ UFW installed and enabled.\n${NC}"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y firewalld
            else
                yum install -y firewalld
            fi
            systemctl enable firewalld --now
            printf "${GREEN}✔ Firewalld 安装并已设置开机自启完成。/ Firewalld installed and enabled.\n${NC}"
            ;;
        alpine)
            apk update && apk add --no-cache iptables
            printf "${GREEN}✔ Iptables 安装完成。/ Iptables installed.\n${NC}"
            ;;
        *)
            printf "${RED}❌ 暂不支持该系统的自动安装防火墙 / Auto-install not supported for this OS\n${NC}"
            ;;
    esac
}

# ----------------- 4. 启停与控制防火墙 / Control Firewall -----------------
control_firewall() {
    echo " 1. 开启/启动防火墙 / Enable Firewall"
    echo " 2. 关闭/停止防火墙 / Disable Firewall"
    read -p "请选择操作 / Please select [1-2]: " sub_choice
    
    case "$sub_choice" in
        1)
            if [ "$FW_TYPE" == "ufw" ]; then
                ufw enable
            elif [ "$FW_TYPE" == "firewalld" ]; then
                systemctl enable --now firewalld
            fi
            printf "${GREEN}✔ 防火墙已尝试开启。/ Firewall enabled attempt completed.\n${NC}"
            ;;
        2)
            if [ "$FW_TYPE" == "ufw" ]; then
                ufw disable
            elif [ "$FW_TYPE" == "firewalld" ]; then
                systemctl disable --now firewalld
            fi
            printf "${YELLOW}⚠️ 防火墙已关闭。/ Firewall disabled.\n${NC}"
            ;;
        *)
            echo "无效选项 / Invalid option"
            ;;
    esac
}

# ----------------- 5. 放行端口功能 / Allow Port -----------------
allow_port() {
    read -p "请输入要放行的端口号 (例如 80 或 443) / Enter port (e.g., 80 or 443): " PORT
    read -p "请选择协议类型 / Select protocol [1. tcp / 2. udp / 3. 两者都要/both]: " PROTO_CHOICE

    case "$PROTO_CHOICE" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) PROTO="tcp" ;;
    esac

    if [ -z "$PORT" ]; then
        printf "${RED}❌ 端口号不能为空！/ Port cannot be empty!\n${NC}"
        return
    fi

    echo "=== 正在放行端口 / Allowing Port: $PORT ($PROTO) ==="
    if [ "$FW_TYPE" == "ufw" ]; then
        if [ "$PROTO" == "both" ]; then
            ufw allow ${PORT}/tcp
            ufw allow ${PORT}/udp
        else
            ufw allow ${PORT}/${PROTO}
        fi
        ufw reload
    elif [ "$FW_TYPE" == "firewalld" ]; then
        if [ "$PROTO" == "both" ]; then
            firewall-cmd --zone=public --add-port=${PORT}/tcp --permanent
            firewall-cmd --zone=public --add-port=${PORT}/udp --permanent
        else
            firewall-cmd --zone=public --add-port=${PORT}/${PROTO} --permanent
        fi
        firewall-cmd --reload
    elif [ "$FW_TYPE" == "iptables" ]; then
        if [ "$PROTO" == "both" ]; then
            iptables -A INPUT -p tcp --dport ${PORT} -j ACCEPT
            iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT
        else
            iptables -A INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT
        fi
    fi
    printf "${GREEN}✔ 端口 ${PORT} 放行操作已执行完成。/ Port ${PORT} allowed successfully.\n${NC}"
}

# ----------------- 6. 删除/关闭已放行端口功能 / Delete Port Rule -----------------
delete_port() {
    read -p "请输入要删除/关闭的端口号 / Enter port to remove: " PORT
    read -p "请选择协议类型 / Select protocol [1. tcp / 2. udp / 3. 两者都要/both]: " PROTO_CHOICE

    case "$PROTO_CHOICE" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) PROTO="tcp" ;;
    esac

    if [ -z "$PORT" ]; then
        printf "${RED}❌ 端口号不能为空！/ Port cannot be empty!\n${NC}"
        return
    fi

    echo "=== 正在移除端口规则 / Removing Port Rule: $PORT ($PROTO) ==="
    if [ "$FW_TYPE" == "ufw" ]; then
        if [ "$PROTO" == "both" ]; then
            ufw delete allow ${PORT}/tcp
            ufw delete allow ${PORT}/udp
        else
            ufw delete allow ${PORT}/${PROTO}
        fi
        ufw reload
    elif [ "$FW_TYPE" == "firewalld" ]; then
        if [ "$PROTO" == "both" ]; then
            firewall-cmd --zone=public --remove-port=${PORT}/tcp --permanent
            firewall-cmd --zone=public --remove-port=${PORT}/udp --permanent
        else
            firewall-cmd --zone=public --remove-port=${PORT}/${PROTO} --permanent
        fi
        firewall-cmd --reload
    elif [ "$FW_TYPE" == "iptables" ]; then
        if [ "$PROTO" == "both" ]; then
            iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT
            iptables -D INPUT -p udp --dport ${PORT} -j ACCEPT
        else
            iptables -D INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT
        fi
    fi
    printf "${GREEN}✔ 端口 ${PORT} 规则已移除。/ Port ${PORT} rule removed.\n${NC}"
}

# ----------------- 主菜单循环 / Main Menu Loop -----------------
while true; do
    echo ""
    printf "${SKYBLUE}==================================================\n${NC}"
    printf "${SKYBLUE}      🛡️ 多系统防火墙管理子脚本 / Multi-Firewall Manager 🛡️      \n${NC}"
    printf "${SKYBLUE}==================================================\n${NC}"
    echo " 1. 检测系统防火墙安装与运行状态 / Check Status"
    echo " 2. 查看已放行的端口列表 / List Allowed Ports"
    echo " 3. 安装当前系统对应防火墙 / Install Firewall"
    echo " 4. 开启 / 关闭防火墙服务 / Enable or Disable Firewall"
    echo " 5. 放行指定端口 (TCP/UDP) / Allow Port"
    echo " 6. 删除指定端口规则 / Delete Port"
    echo " 0. 退出当前防火墙子菜单 / Exit"
    printf "${SKYBLUE}==================================================\n${NC}"
    read -p "请选择操作 / Please select [0-6]: " CHOICE

    case "$CHOICE" in
        1)
            check_firewall_status
            ;;
        2)
            list_allowed_ports
            ;;
        3)
            install_firewall
            ;;
        4)
            control_firewall
            ;;
        5)
            allow_port
            ;;
        6)
            delete_port
            ;;
        0)
            echo "已退出防火墙管理子脚本。 / Exiting firewall manager."
            break
            ;;
        *)
            printf "${RED}❌ 无效选项，请输入 0 到 6 之间的数字。/ Invalid option, please enter 0-6.\n${NC}"
            ;;
    esac
done
