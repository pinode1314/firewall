#!/bin/bash

# 定义颜色变量
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
SKYBLUE='\033[1;36m'
NC='\033[0m' # 恢复默认颜色

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    printf "${RED}❌ 请使用 root 权限运行此脚本！\n${NC}"
    exit 1
fi

# ----------------- 系统发行版与防火墙工具识别 -----------------
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

# ----------------- 1. 检测系统防火墙安装与运行状态 -----------------
check_firewall_status() {
    echo "=================================================="
    echo "=== 正在检测当前系统的防火墙状态 ==="
    echo "系统类型: $OS | 防火墙类型: $FW_TYPE"
    echo "=================================================="

    case "$FW_TYPE" in
        ufw)
            if command -v ufw >/dev/null 2>&1; then
                printf "${GREEN}✔ UFW 防火墙已安装\n${NC}"
                ufw status verbose | sed \
                    -e 's/Status: inactive/防火墙状态: 未激活 (已关闭)/g' \
                    -e 's/Status: active/防火墙状态: 已激活 (运行中)/g' \
                    -e 's/to/目标/g' \
                    -e 's/from/来自/g' \
                    -e 's/Anywhere/任何来源/g' \
                    -e 's/ALLOW/允许/g' \
                    -e 's/DENY/拒绝/g'
            else
                printf "${YELLOW}⚠️ UFW 防火墙未安装\n${NC}"
            fi
            ;;
        firewalld)
            if command -v firewall-cmd >/dev/null 2>&1; then
                printf "${GREEN}✔ Firewalld 防火墙已安装\n${NC}"
                systemctl status firewalld --no-pager | sed \
                    -e 's/Active: active (running)/运行状态: 正在运行 (已开启)/g' \
                    -e 's/Active: inactive (dead)/运行状态: 未运行 (已关闭)/g'
            else
                printf "${YELLOW}⚠️ Firewalld 防火墙未安装\n${NC}"
            fi
            ;;
        iptables)
            if command -v iptables >/dev/null 2>&1; then
                printf "${GREEN}✔ Iptables 防火墙已安装\n${NC}"
                iptables -L -n -v
            else
                printf "${YELLOW}⚠️ Iptables 防火墙未安装\n${NC}"
            fi
            ;;
        *)
            printf "${RED}❌ 未能自动识别适配的防火墙组件\n${NC}"
            ;;
    esac
}

# ----------------- 2. 查看已放行的端口列表 -----------------
list_allowed_ports() {
    echo "=================================================="
    echo "=== 正在获取当前已放行的端口规则 ==="
    echo "=================================================="

    case "$FW_TYPE" in
        ufw)
            if command -v ufw >/dev/null 2>&1; then
                echo "--- UFW 放行规则列表 ---"
                ufw status numbered | sed \
                    -e 's/Status: inactive/防火墙状态: 未激活 (已关闭)/g' \
                    -e 's/Status: active/防火墙状态: 已激活 (运行中)/g' \
                    -e 's/To/目标端口/g' \
                    -e 's/Action/执行动作/g' \
                    -e 's/From/来源/g' \
                    -e 's/Anywhere/任何来源/g' \
                    -e 's/ALLOW/允许/g' \
                    -e 's/DENY/拒绝/g'
            else
                printf "${YELLOW}⚠️ UFW 防火墙未安装\n${NC}"
            fi
            ;;
        firewalld)
            if command -v firewall-cmd >/dev/null 2>&1; then
                echo "--- Firewalld 已放行端口 ---"
                ports=$(firewall-cmd --zone=public --list-ports)
                [ -z "$ports" ] && echo "暂无自定义放行端口" || echo "$ports"
                
                echo "--- Firewalld 已放行服务 ---"
                services=$(firewall-cmd --zone=public --list-services)
                [ -z "$services" ] && echo "暂无放行服务" || echo "$services"
            else
                printf "${YELLOW}⚠️ Firewalld 防火墙未安装\n${NC}"
            fi
            ;;
        iptables)
            if command -v iptables >/dev/null 2>&1; then
                echo "--- Iptables 输入(INPUT)规则 ---"
                iptables -L INPUT -n -v --line-numbers
            else
                printf "${YELLOW}⚠️ Iptables 防火墙未安装\n${NC}"
            fi
            ;;
        *)
            printf "${RED}❌ 无法识别的防火墙类型\n${NC}"
            ;;
    esac
}

# ----------------- 3. 手动选择安装防火墙（带版本冲突检测） -----------------
install_firewall() {
    echo "请选择你要安装的防火墙类型："
    echo " 1. UFW (适用于 Ubuntu/Debian)"
    echo " 2. Firewalld (适用于 CentOS/RHEL/Fedora)"
    echo " 3. Iptables (适用于 Alpine 或通用底层)"
    read -p "请选择 [1-3]: " install_choice

    case "$install_choice" in
        1)
            TARGET_FW="ufw"
            ;;
        2)
            TARGET_FW="firewalld"
            ;;
        3)
            TARGET_FW="iptables"
            ;;
        *)
            printf "${RED}❌ 无效的选择。\n${NC}"
            return
            ;;
    esac

    # 检查系统中是否已经安装了“别的不同版本”的防火墙
    has_other_fw=0
    other_fw_name=""

    if [ "$TARGET_FW" != "ufw" ] && command -v ufw >/dev/null 2>&1; then
        has_other_fw=1
        other_fw_name="UFW"
    elif [ "$TARGET_FW" != "firewalld" ] && command -v firewall-cmd >/dev/null 2>&1; then
        has_other_fw=1
        other_fw_name="Firewalld"
    elif [ "$TARGET_FW" != "iptables" ] && command -v iptables >/dev/null 2>&1; then
        # 简单判定 iptables 是否存在（大多数系统自带基础 iptables，这里主要防范用户装了完整包）
        if dpkg -l 2>/dev/null | grep -q iptables-persistent || rpm -q iptables-services 2>/dev/null | grep -q iptables; then
            has_other_fw=1
            other_fw_name="Iptables"
        fi
    fi

    # 如果要安装的正是当前已经安装的
    if [ "$TARGET_FW" == "ufw" ] && command -v ufw >/dev/null 2>&1; then
        printf "${GREEN}✔ 检测到系统已经安装了 UFW 防火墙，无需重复安装！\n${NC}"
        return
    elif [ "$TARGET_FW" == "firewalld" ] && command -v firewall-cmd >/dev/null 2>&1; then
        printf "${GREEN}✔ 检测到系统已经安装了 Firewalld 防火墙，无需重复安装！\n${NC}"
        return
    fi

    # 如果检测到存在其他防火墙，提示先卸载
    if [ "$has_other_fw" -eq 1 ]; then
        printf "${RED}❌ 检测到系统当前已安装了【${other_fw_name}】防火墙！\n${NC}"
        printf "${YELLOW}⚠️ 为了防止多防火墙冲突导致规则失效，请先手动卸载现有的 ${other_fw_name} 后再尝试安装新防火墙。\n${NC}"
        return
    fi

    echo "=== 正在开始安装 $TARGET_FW 防火墙 ==="
    case "$TARGET_FW" in
        ufw)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y && apt-get install -y ufw
            systemctl enable ufw --now
            printf "${GREEN}✔ UFW 防火墙安装并已设置开机自启完成。\n${NC}"
            ;;
        firewalld)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y firewalld
            elif command -v apt-get >/dev/null 2>&1; then
                apt-get update -y && apt-get install -y firewalld
            else
                yum install -y firewalld
            fi
            systemctl enable firewalld --now
            printf "${GREEN}✔ Firewalld 防火墙安装并已设置开机自启完成。\n${NC}"
            ;;
        iptables)
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update -y && apt-get install -y iptables iptables-persistent
            elif command -v yum >/dev/null 2>&1; then
                yum install -y iptables iptables-services
            elif command -v apk >/dev/null 2>&1; then
                apk update && apk add --no-cache iptables
            fi
            printf "${GREEN}✔ Iptables 防火墙安装完成。\n${NC}"
            ;;
    esac
    
    # 重新获取一次当前的防火墙类型
    get_distro_and_fw
}

# ----------------- 4. 启停与控制防火墙（自带默认放行常用端口规则） -----------------
control_firewall() {
    echo " 1. 开启 / 启动防火墙"
    echo " 2. 关闭 / 停止防火墙"
    read -p "请选择操作 [1-2]: " sub_choice
    
    case "$sub_choice" in
        1)
            echo "正在自动放行常用远程连接端口 (如 22 端口)，防止断开..."
            if [ "$FW_TYPE" == "ufw" ]; then
                ufw allow 22/tcp >/dev/null 2>&1
                ufw enable
            elif [ "$FW_TYPE" == "firewalld" ]; then
                firewall-cmd --zone=public --add-service=ssh --permanent >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
                systemctl enable --now firewalld
            elif [ "$FW_TYPE" == "iptables" ]; then
                iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            fi
            printf "${GREEN}✔ 防火墙已成功开启，并已自动放行常用 SSH 端口（22）。\n${NC}"
            ;;
        2)
            if [ "$FW_TYPE" == "ufw" ]; then
                ufw disable
            elif [ "$FW_TYPE" == "firewalld" ]; then
                systemctl disable --now firewalld
            fi
            printf "${YELLOW}⚠️ 防火墙已关闭。\n${NC}"
            ;;
        *)
            echo "无效选项"
            ;;
    esac
}

# ----------------- 5. 放行端口功能（全防火墙强化适配） -----------------
allow_port() {
    read -p "请输入要放行的端口号 (例如 80 或 443): " PORT
    read -p "请选择协议类型 [1. tcp / 2. udp / 3. 两者都要]: " PROTO_CHOICE

    case "$PROTO_CHOICE" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) PROTO="tcp" ;;
    esac

    if [ -z "$PORT" ]; then
        printf "${RED}❌ 端口号不能为空！\n${NC}"
        return
    fi

    echo "=== 正在放行端口: $PORT ($PROTO) [防火墙类型: $FW_TYPE] ==="
    
    if [ "$FW_TYPE" == "ufw" ]; then
        if [ "$PROTO" == "both" ]; then
            ufw allow "$PORT"/tcp
            ufw allow "$PORT"/udp
        else
            ufw allow "$PORT"/"$PROTO"
        fi
        ufw reload
    elif [ "$FW_TYPE" == "firewalld" ]; then
        if [ "$PROTO" == "both" ]; then
            firewall-cmd --zone=public --add-port="$PORT"/tcp --permanent
            firewall-cmd --zone=public --add-port="$PORT"/udp --permanent
        else
            firewall-cmd --zone=public --add-port="$PORT"/"$PROTO" --permanent
        fi
        firewall-cmd --reload
    elif [ "$FW_TYPE" == "iptables" ]; then
        if [ "$PROTO" == "both" ]; then
            iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
            iptables -A INPUT -p udp --dport "$PORT" -j ACCEPT
        else
            iptables -A INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
        fi
    else
        printf "${RED}❌ 未知的防火墙类型，无法放行端口。\n${NC}"
        return
    fi
    
    printf "${GREEN}✔ 端口 ${PORT} (${PROTO}) 放行规则已成功写入并生效！\n${NC}"
}

# ----------------- 6. 删除/关闭已放行端口功能 -----------------
delete_port() {
    read -p "请输入要删除/关闭的端口号: " PORT
    read -p "请选择协议类型 [1. tcp / 2. udp / 3. 两者都要]: " PROTO_CHOICE

    case "$PROTO_CHOICE" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) PROTO="tcp" ;;
    esac

    if [ -z "$PORT" ]; then
        printf "${RED}❌ 端口号不能为空！\n${NC}"
        return
    fi

    echo "=== 正在移除端口规则: $PORT ($PROTO) ==="
    if [ "$FW_TYPE" == "ufw" ]; then
        if [ "$PROTO" == "both" ]; then
            ufw delete allow "$PORT"/tcp >/dev/null 2>&1
            ufw delete allow "$PORT"/udp >/dev/null 2>&1
        else
            ufw delete allow "$PORT"/"$PROTO" >/dev/null 2>&1
        fi
        ufw reload
    elif [ "$FW_TYPE" == "firewalld" ]; then
        if [ "$PROTO" == "both" ]; then
            firewall-cmd --zone=public --remove-port="$PORT"/tcp --permanent
            firewall-cmd --zone=public --remove-port="$PORT"/udp --permanent
        else
            firewall-cmd --zone=public --remove-port="$PORT"/"$PROTO" --permanent
        fi
        firewall-cmd --reload
    elif [ "$FW_TYPE" == "iptables" ]; then
        if [ "$PROTO" == "both" ]; then
            iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT
            iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT
        else
            iptables -D INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
        fi
    fi
    printf "${GREEN}✔ 端口 ${PORT} 规则已移除。\n${NC}"
}

# ----------------- 主菜单循环 -----------------
while true; do
    echo ""
    printf "${SKYBLUE}=========================================\n${NC}"
    printf "${SKYBLUE}       🛡️ 多系统防火墙管理子脚本 🛡️        \n${NC}"
    printf "${SKYBLUE}=========================================\n${NC}"
    echo " 1. 检测系统防火墙安装与运行状态"
    echo " 2. 查看已放行的端口列表"
    echo " 3. 安装指定防火墙 (带冲突检测)"
    echo " 4. 开启 / 关闭防火墙服务"
    echo " 5. 放行指定端口 (TCP/UDP)"
    echo " 6. 删除指定端口规则"
    echo " 0. 退出当前防火墙子菜单"
    printf "${SKYBLUE}=========================================\n${NC}"
    read -p "请选择操作 [0-6]: " CHOICE

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
            echo "已退出防火墙管理子菜单。"
            break
            ;;
        *)
            printf "${RED}❌ 无效选项，请输入 0 到 6 之间的数字。\n${NC}"
            ;;
    esac
done
