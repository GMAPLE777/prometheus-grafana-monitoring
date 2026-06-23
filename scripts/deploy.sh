#!/bin/bash
# 一键部署脚本
# 功能：自动化部署所有监控组件

set -e

echo "开始部署 Prometheus + Grafana 监控体系..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统环境
check_system() {
    log_info "检查系统环境..."
    
    # 检查操作系统
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        log_warn "建议使用 Ubuntu 22.04 LTS"
    fi
    
    # 检查硬件资源
    CPU_CORES=$(nproc)
    MEMORY_GB=$(free -g | awk '/Mem/{print $2}')
    DISK_GB=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    
    if [ "$CPU_CORES" -lt 2 ]; then
        log_error "CPU 核心数不足，建议 2 核及以上"
        exit 1
    fi
    
    if [ "$MEMORY_GB" -lt 4 ]; then
        log_error "内存不足，建议 4GB 及以上"
        exit 1
    fi
    
    if [ "$DISK_GB" -lt 20 ]; then
        log_error "磁盘空间不足，建议 20GB 及以上"
        exit 1
    fi
    
    log_info "CPU 核心数: $CPU_CORES"
    log_info "内存大小: ${MEMORY_GB}GB"
    log_info "磁盘大小: ${DISK_GB}GB"
    
    # 检查网络连通性
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "网络连通性检查失败"
        exit 1
    fi
    
    # 检查必需端口
    REQUIRED_PORTS=(9090 3000 9100 9093 9113 9104)
    for port in "${REQUIRED_PORTS[@]}"; do
        if ss -tlnp | grep -q ":$port"; then
            log_error "端口 $port 已被占用"
            exit 1
        fi
    done
    
    log_info "系统环境检查通过"
}

# 安装基础依赖
install_dependencies() {
    log_info "安装基础依赖..."
    
    apt update
    apt install -y wget vim net-tools telnet curl jq chrony
    
    systemctl enable chrony
    systemctl start chrony
    
    log_info "基础依赖安装完成"
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."
    
    mkdir -p /opt/monitoring/{prometheus,alertmanager,exporters}
    mkdir -p /opt/monitoring/prometheus/{data,rules}
    mkdir -p /opt/monitoring/alertmanager/{data,templates}
    
    log_info "目录结构创建完成"
}

# 部署 Prometheus
deploy_prometheus() {
    log_info "部署 Prometheus..."
    
    cd /opt/monitoring
    
    # 下载 Prometheus
    if [ ! -f "prometheus-2.45.0.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
    fi
    
    # 解压并重命名
    tar -zxf prometheus-2.45.0.linux-amd64.tar.gz
    mv prometheus-2.45.0.linux-amd64 prometheus
    
    # 复制配置文件
    cp "$(dirname "$0")/../config/prometheus/prometheus.yml" /opt/monitoring/prometheus/
    cp "$(dirname "$0")/../config/prometheus/rules/"*.yml /opt/monitoring/prometheus/rules/
    
    # 创建 Systemd 服务
    cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Server
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/monitoring/prometheus/prometheus \
  --config.file=/opt/monitoring/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/monitoring/prometheus/data \
  --storage.tsdb.retention.time=15d \
  --storage.tsdb.retention.size=5GB \
  --web.console.libraries=/opt/monitoring/prometheus/console_libraries \
  --web.console.templates=/opt/monitoring/prometheus/consoles \
  --web.enable-lifecycle \
  --web.enable-admin-api
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl start prometheus
    systemctl enable prometheus
    
    log_info "Prometheus 部署完成"
}

# 部署 Node Exporter
deploy_node_exporter() {
    log_info "部署 Node Exporter..."
    
    cd /opt/monitoring/exporters
    
    # 下载 Node Exporter
    if [ ! -f "node_exporter-1.6.1.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
    fi
    
    # 解压并重命名
    tar -zxf node_exporter-1.6.1.linux-amd64.tar.gz
    mv node_exporter-1.6.1.linux-amd64 node_exporter
    
    # 创建 Systemd 服务
    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/monitoring/exporters/node_exporter/node_exporter \
  --collector.cpu \
  --collector.diskstats \
  --collector.filesystem \
  --collector.loadavg \
  --collector.meminfo \
  --collector.netdev \
  --collector.stat \
  --collector.time \
  --collector.uname \
  --collector.vmstat \
  --web.listen-address=:9100
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl start node_exporter
    systemctl enable node_exporter
    
    log_info "Node Exporter 部署完成"
}

# 部署 Nginx Exporter
deploy_nginx_exporter() {
    log_info "部署 Nginx Exporter..."
    
    # 配置 Nginx stub_status
    cat > /etc/nginx/conf.d/status.conf << 'EOF'
server {
    listen 8080;
    server_name localhost;
    
    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        allow 172.17.0.0/16;
        deny all;
    }
    
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # 重启 Nginx
    nginx -t && systemctl restart nginx
    
    cd /opt/monitoring/exporters
    
    # 下载 Nginx Exporter
    if [ ! -f "nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz" ]; then
        wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
    fi
    
    # 解压并重命名
    tar -zxf nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
    mv nginx-prometheus-exporter nginx_exporter
    
    # 创建 Systemd 服务
    cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Nginx Exporter
Documentation=https://github.com/nginxinc/nginx-prometheus-exporter
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/monitoring/exporters/nginx_exporter \
  -nginx.scrape-uri=http://127.0.0.1:8080/nginx_status \
  -web.listen-address=:9113
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl start nginx_exporter
    systemctl enable nginx_exporter
    
    log_info "Nginx Exporter 部署完成"
}

# 部署 MySQL Exporter
deploy_mysql_exporter() {
    log_info "部署 MySQL Exporter..."
    
    cd /opt/monitoring/exporters
    
    # 下载 MySQL Exporter
    if [ ! -f "mysqld_exporter-0.15.0.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/mysqld_exporter/releases/download/v0.15.0/mysqld_exporter-0.15.0.linux-amd64.tar.gz
    fi
    
    # 解压并重命名
    tar -zxf mysqld_exporter-0.15.0.linux-amd64.tar.gz
    mv mysqld_exporter-0.15.0.linux-amd64 mysqld_exporter
    
    # 创建配置文件
    cat > /opt/monitoring/exporters/mysqld_exporter/.my.cnf << 'EOF'
[client]
user=exporter
password=Exporter@123
host=localhost
port=3306
EOF
    
    chmod 600 /opt/monitoring/exporters/mysqld_exporter/.my.cnf
    
    # 创建 Systemd 服务
    cat > /etc/systemd/system/mysql_exporter.service << 'EOF'
[Unit]
Description=MySQL Exporter
Documentation=https://github.com/prometheus/mysqld_exporter
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/monitoring/exporters/mysqld_exporter/mysqld_exporter \
  --config.my-cnf=/opt/monitoring/exporters/mysqld_exporter/.my.cnf \
  --web.listen-address=:9104 \
  --collect.global_status \
  --collect.global_variables \
  --collect.slave_status \
  --collect.info_schema.innodb_metrics \
  --collect.info_schema.processlist \
  --collect.info_schema.query_response_time \
  --collect.engine_innodb_status
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl start mysql_exporter
    systemctl enable mysql_exporter
    
    log_info "MySQL Exporter 部署完成"
}

# 部署 Alertmanager
deploy_alertmanager() {
    log_info "部署 Alertmanager..."
    
    cd /opt/monitoring
    
    # 下载 Alertmanager
    if [ ! -f "alertmanager-0.26.0.linux-amd64.tar.gz" ]; then
        wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
    fi
    
    # 解压并重命名
    tar -zxf alertmanager-0.26.0.linux-amd64.tar.gz
    mv alertmanager-0.26.0.linux-amd64 alertmanager
    
    # 复制配置文件
    cp "$(dirname "$0")/../config/alertmanager/alertmanager.yml" /opt/monitoring/alertmanager/
    cp "$(dirname "$0")/../config/alertmanager/templates/"*.tmpl /opt/monitoring/alertmanager/templates/
    
    # 创建 Systemd 服务
    cat > /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=Alertmanager
Documentation=https://prometheus.io/docs/alerting/alertmanager/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/monitoring/alertmanager/alertmanager \
  --config.file=/opt/monitoring/alertmanager/alertmanager.yml \
  --storage.path=/opt/monitoring/alertmanager/data \
  --web.external-url=http://localhost:9093 \
  --cluster.listen-address=0.0.0.0:9094 \
  --log.level=info
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl start alertmanager
    systemctl enable alertmanager
    
    log_info "Alertmanager 部署完成"
}

# 部署 Grafana
deploy_grafana() {
    log_info "部署 Grafana..."
    
    # 安装依赖
    apt install -y adduser libfontconfig1 musl
    
    # 下载 Grafana
    if [ ! -f "grafana_10.0.3_amd64.deb" ]; then
        wget https://dl.grafana.com/oss/release/grafana_10.0.3_amd64.deb
    fi
    
    # 安装 Grafana
    dpkg -i grafana_10.0.3_amd64.deb
    
    # 启动服务
    systemctl start grafana-server
    systemctl enable grafana-server
    
    log_info "Grafana 部署完成"
}

# 验证部署
verify_deployment() {
    log_info "验证部署..."
    
    # 检查服务状态
    services=("prometheus" "node_exporter" "nginx_exporter" "mysql_exporter" "alertmanager" "grafana-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "$service 运行正常"
        else
            log_error "$service 运行异常"
            return 1
        fi
    done
    
    # 检查端口监听
    ports=(9090 3000 9100 9093 9113 9104)
    
    for port in "${ports[@]}"; do
        if ss -tlnp | grep -q ":$port"; then
            log_info "端口 $port 监听正常"
        else
            log_error "端口 $port 未监听"
            return 1
        fi
    done
    
    # 检查 Prometheus targets
    sleep 10
    TARGETS_DOWN=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | .labels.instance' | wc -l)
    
    if [ "$TARGETS_DOWN" -gt 0 ]; then
        log_warn "有 $TARGETS_DOWN 个 Prometheus target 状态异常"
    else
        log_info "所有 Prometheus target 状态正常"
    fi
    
    log_info "部署验证完成"
}

# 主函数
main() {
    log_info "=========================================="
    log_info "Prometheus + Grafana 监控体系部署脚本"
    log_info "=========================================="
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
    
    check_system
    install_dependencies
    create_directories
    deploy_prometheus
    deploy_node_exporter
    deploy_nginx_exporter
    deploy_mysql_exporter
    deploy_alertmanager
    deploy_grafana
    verify_deployment
    
    log_info "=========================================="
    log_info "部署完成！"
    log_info "=========================================="
    log_info ""
    log_info "访问地址："
    log_info "  Prometheus:   http://localhost:9090"
    log_info "  Grafana:      http://localhost:3000"
    log_info "  Alertmanager: http://localhost:9093"
    log_info ""
    log_info "默认账号密码："
    log_info "  Grafana: admin / admin"
    log_info ""
    log_info "下一步："
    log_info "  1. 访问 Grafana 并修改默认密码"
    log_info "  2. 配置 Prometheus 数据源"
    log_info "  3. 导入监控大盘"
    log_info "  4. 配置钉钉告警通知"
    log_info "=========================================="
}

main "$@"