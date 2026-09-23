#!/bin/bash

# 定义颜色变量
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
SKYBLUE='\033[1;36m'
NC='\033[0m'

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    printf "${RED}❌ 请使用 root 权限运行此脚本！\n${NC}"
    exit 1
fi

# ----------------- 实时精准安全检测函数 -----------------
get_distro_and_fw() {
    hash -r 2>/dev/null

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS="unknown"
    fi

    if [ -x /usr/sbin/ufw ] || [ -x /sbin/ufw ]; then
        FW_TYPE="ufw"
        return
    fi

    if [ -x /usr/bin/firewall-cmd ] || [ -x /sbin/firewall-cmd ]; then
        FW_TYPE="firewalld"
        return
    fi

    if [ -x /usr/sbin/iptables ] || [ -x /sbin/iptables ]; then
        if [ -n "$(iptables -L INPUT -n 2>/dev/null)" ] || dpkg -l | grep -q iptables-persistent 2>/dev/null || rpm -q iptables-services &>/dev/null; then
            FW_TYPE="iptables"
            return
        fi
    fi

    FW_TYPE="none"
}

# ----------------- 1. 检测系统防火墙安装与运行状态（含规则） -----------------
check_firewall_status() {
    get_distro_and_fw
    
    echo "=================================================="
    echo "=== 正在检测当前系统的防火墙状态与规则 ==="
    echo "系统类型: $OS | 当前防火墙: $FW_TYPE"
    echo "=================================================="

    case "$FW_TYPE" in
        ufw)
            if [ -x /usr/sbin/ufw ] || [ -x /sbin/ufw ]; then
                printf "${GREEN}✔ UFW 防火墙已安装\n${NC}"
                ufw status numbered | sed \
                    -e 's/Status: inactive/防火墙状态: 未激活 (已关闭)/g' \
                    -e 's/Status: active/防火墙状态: 已激活 (运行中)/g' \
                    -e 's/to/目标/g' \
                    -e 's/from/来自/g' \
                    -e 's/Anywhere/任何来源/g' \
                    -e 's/ALLOW/允许/g' \
                    -e 's/DENY/拒绝/g'
            else
                FW_TYPE="none"
                printf "${YELLOW}⚠️ 当前系统中未检测到任何可用的主流防火墙（已安全卸载或未安装）\n${NC}"
            fi
            ;;
        firewalld)
            if [ -x /usr/bin/firewall-cmd ] || [ -x /sbin/firewall-cmd ]; then
                printf "${GREEN}✔ Firewalld 防火墙已安装\n${NC}"
                systemctl status firewalld --no-pager
                echo "--- 已放行端口 ---"
                firewall-cmd --zone=public --list-ports 2>/dev/null
            else
                FW_TYPE="none"
                printf "${YELLOW}⚠️ 当前系统中未检测到任何可用的主流防火墙（已安全卸载或未安装）\n${NC}"
            fi
            ;;
        iptables)
            printf "${GREEN}✔ Iptables 防火墙已安装\n${NC}"
            iptables -L INPUT -n -v --line-numbers
            ;;
        none|*)
            printf "${YELLOW}⚠️ 当前系统中未检测到任何可用的主流防火墙（已安全卸载或未安装）\n${NC}"
            ;;
    esac
}

# ----------------- 2. 手动选择安装防火墙（安装后自动放行默认基础端口） -----------------
install_firewall() {
    get_distro_and_fw
    echo "请选择你要安装的防火墙类型："
    echo " 1. UFW (适用于 Ubuntu/Debian)"
    echo " 2. Firewalld (适用于 CentOS/RHEL/Fedora)"
    echo " 3. Iptables"
    echo " 0. 返回上一级菜单"
    read -p "请选择 [0-3]: " install_choice

    case "$install_choice" in
        1) TARGET_FW="ufw" ;;
        2) TARGET_FW="firewalld" ;;
        3) TARGET_FW="iptables" ;;
        0) echo "已取消安装，返回上一级菜单。"; return ;;
        *) printf "${RED}❌ 无效的选择。\n${NC}"; return ;;
    esac

    if [ "$FW_TYPE" != "none" ]; then
        if [ "$FW_TYPE" == "$TARGET_FW" ]; then
            printf "${YELLOW}⚠️ 检测到当前系统【已经安装】了 $TARGET_FW 防火墙，无需重复安装！\n${NC}"
            return
        else
            printf "${RED}❌ 检测到当前系统已存在 [$FW_TYPE] 防火墙。为避免冲突，请先通过第 6 项将其卸载，再安装新防火墙！\n${NC}"
            return
        fi
    fi

    echo "=== 正在配置 $TARGET_FW 防火墙 ==="
    case "$TARGET_FW" in
        ufw)
            ufw allow 22/tcp >/dev/null 2>&1
            ufw allow 80/tcp >/dev/null 2>&1
            ufw allow 443/tcp >/dev/null 2>&1
            systemctl enable ufw --now
            printf "${GREEN}✔ UFW 防火墙配置完成，并已自动放行默认基础端口 (22, 80, 443)。\n${NC}"
            ;;
        firewalld)
            systemctl enable firewalld --now
            firewall-cmd --permanent --zone=public --add-port=22/tcp >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --add-port=80/tcp >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --add-port=443/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            printf "${GREEN}✔ Firewalld 防火墙配置完成，并已自动放行默认基础端口 (22, 80, 443)。\n${NC}"
            ;;
        iptables)
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            iptables -A INPUT -p tcp --dport 80 -j ACCEPT
            iptables -A INPUT -p tcp --dport 443 -j ACCEPT
            if command -v netfilter-persistent &>/dev/null; then
                netfilter-persistent save >/dev/null 2>&1
            elif [ -d /etc/sysconfig ]; then
                iptables-save > /etc/sysconfig/iptables 2>/dev/null
            fi
            printf "${GREEN}✔ Iptables 配置完成，并已自动放行默认基础端口 (22, 80, 443)。\n${NC}"
            ;;
    esac
    hash -r 2>/dev/null
}

# ----------------- 3. 智能检测并启停防火墙（三大防火墙逻辑统一） -----------------
control_firewall() {
    get_distro_and_fw
    if [ "$FW_TYPE" == "none" ]; then
        printf "${RED}❌ 当前系统未检测到防火墙，请先通过第 2 项进行安装！\n${NC}"
        return
    fi

    case "$FW_TYPE" in
        ufw)
            if ufw status | grep -q "Status: active"; then
                read -p "防火墙运行中，是否将其【关闭】？[y/n]: " choice
                if [ "$choice" = "y" ]; then
                    ufw disable >/dev/null 2>&1
                    printf "${YELLOW}⚠️ 防火墙已关闭\n${NC}"
                fi
            else
                read -p "防火墙已关闭，是否将其【开启】？[y/n]: " choice
                if [ "$choice" = "y" ]; then
                    ufw allow 22/tcp >/dev/null 2>&1
                    ufw allow 80/tcp >/dev/null 2>&1
                    ufw allow 443/tcp >/dev/null 2>&1
                    ufw --force enable >/dev/null 2>&1
                    printf "${GREEN}✔ 防火墙已开启，并已自动安全放行默认基础端口 (22, 80, 443)\n${NC}"
                fi
            fi
            ;;
        firewalld)
            if systemctl is-active --quiet firewalld; then
                read -p "防火墙运行中，是否将其【关闭】？[y/n]: " choice
                if [ "$choice" = "y" ]; then
                    systemctl stop firewalld >/dev/null 2>&1
                    systemctl disable firewalld >/dev/null 2>&1
                    printf "${YELLOW}⚠️ 防火墙已关闭\n${NC}"
                fi
            else
                read -p "防火墙已关闭，是否将其【开启】？[y/n]: " choice
                if [ "$choice" = "y" ]; then
                    firewall-cmd --permanent --zone=public --add-port=22/tcp >/dev/null 2>&1
                    firewall-cmd --permanent --zone=public --add-port=80/tcp >/dev/null 2>&1
                    firewall-cmd --permanent --zone=public --add-port=443/tcp >/dev/null 2>&1
                    systemctl enable --now firewalld >/dev/null 2>&1
                    firewall-cmd --reload >/dev/null 2>&1
                    printf "${GREEN}✔ 防火墙已开启，并已自动安全放行默认基础端口 (22, 80, 443)\n${NC}"
                fi
            fi
            ;;
        iptables)
            RULE_COUNT=$(iptables -S INPUT 2>/dev/null | grep -v -- "-P INPUT ACCEPT" | wc -l)
            
            if [ "$RULE_COUNT" -gt 0 ]; then
                read -p "防火墙运行中，是否将其【关闭】？[y/n]: " choice
                if [ "$choice" = "y" ]; then
                    iptables -F
                    printf "${YELLOW}⚠️ 防火墙已关闭\n${NC}"
                fi
            else
                read -p "防火墙已关闭，是否将其【开启】？[y/n]: " choice
                if [ "$choice" = "y" ]; then
                    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
                    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
                    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
                    printf "${GREEN}✔ 防火墙已开启，并已自动安全放行默认基础端口 (22, 80, 443)\n${NC}"
                fi
            fi
            ;;
        *)
            printf "${RED}❌ 未知的防火墙类型。\n${NC}"
            ;;
    esac
}

# ----------------- 4. 放行端口（带 TCP/UDP 协议选择与端口范围校验） -----------------
allow_port() {
    get_distro_and_fw
    if [ "$FW_TYPE" == "none" ]; then
        printf "${RED}❌ 当前系统无防火墙，无法放行端口！\n${NC}"
        return
    fi

    read -p "请输入要放行的端口或范围 (例如 80 或 8000-8009): " PORT
    if [ -z "$PORT" ]; then
        printf "${RED}❌ 端口不能为空！\n${NC}"
        return
    fi

    # 校验端口是否在 1-65535 范围内（支持单个端口或范围格式如 8000-8009）
    if [[ "$PORT" =~ ^[0-9]+-[0-9]+$ ]]; then
        P_START=$(echo "$PORT" | cut -d'-' -f1)
        P_END=$(echo "$PORT" | cut -d'-' -f2)
        if [ "$P_START" -lt 1 ] || [ "$P_START" -gt 65535 ] || [ "$P_END" -lt 1 ] || [ "$P_END" -gt 65535 ] || [ "$P_START" -gt "$P_END" ]; then
            printf "${RED}❌ 错误：端口范围必须在 1 到 65535 之间，且起始端口不能大于结束端口！\n${NC}"
            return
        fi
    elif [[ "$PORT" =~ ^[0-9]+$ ]]; then
        if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            printf "${RED}❌ 错误：端口号必须在 1 到 65535 之间！\n${NC}"
            return
        fi
    else
        printf "${RED}❌ 错误：输入的端口格式无效！\n${NC}"
        return
    fi

    echo "请选择协议类型："
    echo " 1. TCP"
    echo " 2. UDP"
    echo " 3. TCP 和 UDP 同时放行"
    read -p "请选择 [1-3]: " proto_choice

    case "$proto_choice" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) printf "${RED}❌ 无效的选择，默认采用 TCP。\n${NC}"; PROTO="tcp" ;;
    esac

    if [ "$FW_TYPE" == "ufw" ] && ([ -x /usr/sbin/ufw ] || [ -x /sbin/ufw ]); then
        UFW_PORT=$(echo "$PORT" | tr '-' ':')
        if [ "$PROTO" == "both" ]; then
            ufw allow "$UFW_PORT"/tcp
            ufw allow "$UFW_PORT"/udp
            printf "${GREEN}✔ 端口 ${PORT} (TCP与UDP) 已成功放行！\n${NC}"
        else
            ufw allow "$UFW_PORT"/"$PROTO"
            printf "${GREEN}✔ 端口 ${PORT} (${PROTO^^}) 已成功放行！\n${NC}"
        fi
    elif [ "$FW_TYPE" == "firewalld" ]; then
        if [ "$PROTO" == "both" ]; then
            firewall-cmd --permanent --zone=public --add-port="$PORT"/tcp >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --add-port="$PORT"/udp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            printf "${GREEN}✔ 端口 ${PORT} (TCP与UDP) 已成功放行！\n${NC}"
        else
            firewall-cmd --permanent --zone=public --add-port="$PORT"/"$PROTO" >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            printf "${GREEN}✔ 端口 ${PORT} (${PROTO^^}) 已成功放行！\n${NC}"
        fi
    elif [ "$FW_TYPE" == "iptables" ]; then
        if [ "$PROTO" == "both" ]; then
            iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
            iptables -A INPUT -p udp --dport "$PORT" -j ACCEPT
            printf "${GREEN}✔ 端口 ${PORT} (TCP与UDP) 已成功放行！\n${NC}"
        else
            iptables -A INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT
            printf "${GREEN}✔ 端口 ${PORT} (${PROTO^^}) 已成功放行！\n${NC}"
        fi
    fi
}

# ----------------- 5. 删除端口（带 TCP/UDP 协议选择） -----------------
delete_port() {
    get_distro_and_fw
    if [ "$FW_TYPE" == "none" ]; then
        printf "${RED}❌ 当前系统无防火墙！\n${NC}"
        return
    fi

    read -p "请输入要删除的端口或范围: " PORT
    if [ -z "$PORT" ]; then
        printf "${RED}❌ 端口不能为空！\n${NC}"
        return
    fi

    echo "请选择要删除的协议类型："
    echo " 1. TCP"
    echo " 2. UDP"
    echo " 3. TCP 和 UDP 都删除"
    read -p "请选择 [1-3]: " proto_choice

    case "$proto_choice" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) printf "${RED}❌ 无效的选择，默认操作 TCP。\n${NC}"; PROTO="tcp" ;;
    esac

    if [ "$FW_TYPE" == "ufw" ] && ([ -x /usr/sbin/ufw ] || [ -x /sbin/ufw ]); then
        UFW_PORT=$(echo "$PORT" | tr '-' ':')
        if [ "$PROTO" == "both" ]; then
            ufw delete allow "$UFW_PORT"/tcp >/dev/null 2>&1
            ufw delete allow "$UFW_PORT"/udp >/dev/null 2>&1
            printf "${GREEN}✔ 端口 ${PORT} (TCP与UDP) 规则已移除。\n${NC}"
        else
            ufw delete allow "$UFW_PORT"/"$PROTO" >/dev/null 2>&1
            printf "${GREEN}✔ 端口 ${PORT} (${PROTO^^}) 规则已移除。\n${NC}"
        fi
    elif [ "$FW_TYPE" == "firewalld" ]; then
        if [ "$PROTO" == "both" ]; then
            firewall-cmd --permanent --zone=public --remove-port="$PORT"/tcp >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --remove-port="$PORT"/udp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            printf "${GREEN}✔ 端口 ${PORT} (TCP与UDP) 规则已移除。\n${NC}"
        else
            firewall-cmd --permanent --zone=public --remove-port="$PORT"/"$PROTO" >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            printf "${GREEN}✔ 端口 ${PORT} (${PROTO^^}) 规则已移除。\n${NC}"
        fi
    elif [ "$FW_TYPE" == "iptables" ]; then
        if [ "$PROTO" == "both" ]; then
            iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
            iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
            printf "${GREEN}✔ 端口 ${PORT} (TCP与UDP) 规则已移除。\n${NC}"
        else
            iptables -D INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT 2>/dev/null
            printf "${GREEN}✔ 端口 ${PORT} (${PROTO^^}) 规则已移除。\n${NC}"
        fi
    fi
}

# ----------------- 6. 完全卸载当前防火墙服务 -----------------
uninstall_firewall() {
    get_distro_and_fw
    echo "=================================================="
    echo "=== 正在准备清理防火墙 ==="
    echo "当前识别的防火墙类型: $FW_TYPE"
    echo "=================================================="

    if [ "$FW_TYPE" == "none" ]; then
        printf "${YELLOW}⚠️ 系统中当前没有识别到任何可操作的防火墙。\n${NC}"
        return
    fi

    read -p "⚠️ 确认要清空防火墙规则并停用服务吗？[y/N]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "操作已取消。"
        return
    fi

    case "$FW_TYPE" in
        ufw)
            ufw disable >/dev/null 2>&1
            rm -f /usr/sbin/ufw /sbin/ufw
            rm -rf /etc/ufw /lib/ufw /etc/default/ufw
            printf "${GREEN}✔ UFW 防火墙已停用并深度清理相关配置！\n${NC}"
            ;;
        firewalld)
            systemctl disable --now firewalld >/dev/null 2>&1
            rm -rf /etc/firewalld
            printf "${GREEN}✔ Firewalld 防火墙已停用！\n${NC}"
            ;;
        iptables)
            iptables -F
            printf "${GREEN}✔ Iptables 规则已清空！\n${NC}"
            ;;
    esac
    
    hash -r 2>/dev/null
    get_distro_and_fw
    echo "当前最新状态已重置为: $FW_TYPE"
}

# ----------------- 主菜单循环 -----------------
while true; do
    echo ""
    printf "${SKYBLUE}=========================================\n${NC}"
    printf "${SKYBLUE}        多系统防火墙管理子脚本        \n${NC}"
    printf "${SKYBLUE}=========================================\n${NC}"
    echo " 1. 检测系统防火墙安装、状态与端口规则"
    echo " 2. 安装指定防火墙"
    echo " 3. 智能开启 / 关闭防火墙服务"
    echo " 4. 放行指定端口或范围"
    echo " 5. 删除指定端口或范围规则"
    echo " 6. 完全卸载当前防火墙服务"
    echo " 0. 退出当前防火墙子菜单"
    printf "${SKYBLUE}=========================================\n${NC}"
    read -p "请选择操作 [0-6]: " CHOICE

    case "$CHOICE" in
        1) check_firewall_status ;;
        2) install_firewall ;;
        3) control_firewall ;;
        4) allow_port ;;
        5) delete_port ;;
        6) uninstall_firewall ;;
        0) echo "已退出防火墙管理子菜单。"; break ;;
        *) printf "${RED}❌ 无效选项，请输入 0 到 6 之间的数字。\n${NC}" ;;
    esac
done
