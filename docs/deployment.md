# 部署指南

## 1. 环境要求

### 1.1 操作系统
- Ubuntu 22.04 LTS（推荐）
- 其他 Linux 发行版（CentOS 7+、Debian 10+）

### 1.2 硬件配置
- CPU：2 核及以上
- 内存：4GB 及以上
- 磁盘：20GB 及以上（根据监控规模调整）

### 1.3 网络要求
- 服务器可访问外网（下载安装包）
- 开放以下端口：
  - 9090：Prometheus
  - 3000：Grafana
  - 9100：Node Exporter
  - 9093：Alertmanager
  - 9113：Nginx Exporter
  - 9104：MySQL Exporter

### 1.4 前置依赖
- Nginx（用于 Nginx Exporter 监控）
- MySQL（用于 MySQL Exporter 监控）
- curl、wget、jq 等基础工具

## 2. 一键部署

### 2.1 克隆项目
```bash
git clone <repository-url>
cd prometheus-grafana-monitoring
```

### 2.2 执行部署脚本
```bash
chmod +x scripts/deploy.sh
sudo ./scripts/deploy.sh
```

### 2.3 验证部署
```bash
# 检查所有服务状态
systemctl status prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 访问 Web UI
# Prometheus: http://服务器IP:9090
# Grafana: http://服务器IP:3000
# Alertmanager: http://服务器IP:9093
```

## 3. 手动部署

### 3.1 环境准备

#### 3.1.1 系统更新
```bash
apt update && apt upgrade -y
```

#### 3.1.2 安装基础工具
```bash
apt install -y wget vim net-tools telnet curl jq chrony
systemctl enable chrony
systemctl start chrony
```

#### 3.1.3 创建目录结构
```bash
mkdir -p /opt/monitoring/{prometheus,alertmanager,exporters}
```

### 3.2 部署 Prometheus

#### 3.2.1 下载安装
```bash
cd /opt/monitoring
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar -zxf prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64 prometheus
mkdir -p /opt/monitoring/prometheus/{data,rules}
```

#### 3.2.2 配置文件
复制配置文件：
```bash
cp config/prometheus/prometheus.yml /opt/monitoring/prometheus/
cp config/prometheus/rules/*.yml /opt/monitoring/prometheus/rules/
```

#### 3.2.3 创建 Systemd 服务
```bash
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
```

#### 3.2.4 启动服务
```bash
systemctl daemon-reload
systemctl start prometheus
systemctl enable prometheus
```

#### 3.2.5 验证
```bash
systemctl status prometheus
curl http://localhost:9090/-/healthy
```

### 3.3 部署 Node Exporter

#### 3.3.1 下载安装
```bash
cd /opt/monitoring/exporters
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar -zxf node_exporter-1.6.1.linux-amd64.tar.gz
mv node_exporter-1.6.1.linux-amd64 node_exporter
```

#### 3.3.2 创建 Systemd 服务
```bash
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
```

#### 3.3.3 启动服务
```bash
systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter
```

#### 3.3.4 验证
```bash
systemctl status node_exporter
curl http://localhost:9100/metrics | head -20
```

### 3.4 部署 Nginx Exporter

#### 3.4.1 配置 Nginx stub_status
```bash
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

nginx -t && systemctl restart nginx
```

#### 3.4.2 下载安装
```bash
cd /opt/monitoring/exporters
wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
tar -zxf nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz
mv nginx-prometheus-exporter nginx_exporter
```

#### 3.4.3 创建 Systemd 服务
```bash
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
```

#### 3.4.4 启动服务
```bash
systemctl daemon-reload
systemctl start nginx_exporter
systemctl enable nginx_exporter
```

#### 3.4.5 验证
```bash
systemctl status nginx_exporter
curl http://localhost:9113/metrics | grep nginx
```

### 3.5 部署 MySQL Exporter

#### 3.5.1 创建监控账号
```sql
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'Exporter@123';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
```

#### 3.5.2 下载安装
```bash
cd /opt/monitoring/exporters
wget https://github.com/prometheus/mysqld_exporter/releases/download/v0.15.0/mysqld_exporter-0.15.0.linux-amd64.tar.gz
tar -zxf mysqld_exporter-0.15.0.linux-amd64.tar.gz
mv mysqld_exporter-0.15.0.linux-amd64 mysqld_exporter
```

#### 3.5.3 创建配置文件
```bash
cat > /opt/monitoring/exporters/mysqld_exporter/.my.cnf << 'EOF'
[client]
user=exporter
password=Exporter@123
host=localhost
port=3306
EOF

chmod 600 /opt/monitoring/exporters/mysqld_exporter/.my.cnf
```

#### 3.5.4 创建 Systemd 服务
```bash
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
```

#### 3.5.5 启动服务
```bash
systemctl daemon-reload
systemctl start mysql_exporter
systemctl enable mysql_exporter
```

#### 3.5.6 验证
```bash
systemctl status mysql_exporter
curl http://localhost:9104/metrics | grep mysql
```

### 3.6 部署 Alertmanager

#### 3.6.1 下载安装
```bash
cd /opt/monitoring
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -zxf alertmanager-0.26.0.linux-amd64.tar.gz
mv alertmanager-0.26.0.linux-amd64 alertmanager
mkdir -p /opt/monitoring/alertmanager/{data,templates}
```

#### 3.6.2 配置文件
复制配置文件：
```bash
cp config/alertmanager/alertmanager.yml /opt/monitoring/alertmanager/
cp config/alertmanager/templates/*.tmpl /opt/monitoring/alertmanager/templates/
```

#### 3.6.3 创建 Systemd 服务
```bash
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
```

#### 3.6.4 启动服务
```bash
systemctl daemon-reload
systemctl start alertmanager
systemctl enable alertmanager
```

#### 3.6.5 验证
```bash
systemctl status alertmanager
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

### 3.7 部署 Grafana

#### 3.7.1 安装依赖
```bash
apt install -y adduser libfontconfig1 musl
```

#### 3.7.2 下载安装
```bash
wget https://dl.grafana.com/oss/release/grafana_10.0.3_amd64.deb
dpkg -i grafana_10.0.3_amd64.deb
```

#### 3.7.3 启动服务
```bash
systemctl start grafana-server
systemctl enable grafana-server
```

#### 3.7.4 验证
```bash
systemctl status grafana-server
curl http://localhost:3000/api/health
```

## 4. 配置 Grafana

### 4.1 访问 Grafana
- 地址：http://服务器IP:3000
- 默认账号：admin
- 默认密码：admin
- 首次登录需修改密码

### 4.2 配置数据源
1. 左侧菜单 → Connections → Data sources
2. 点击 "Add data source"
3. 选择 "Prometheus"
4. 配置：
   - Name: Prometheus
   - URL: http://localhost:9090
   - Access: Server (default)
   - Scrape interval: 15s
5. 点击 "Save & test"

### 4.3 导入监控大盘

#### 4.3.1 主机监控大盘
1. 左侧菜单 → Dashboards → Import
2. 输入 Dashboard ID: 8919
3. 选择 Prometheus 数据源
4. 点击 Import

#### 4.3.2 MySQL 监控大盘
1. 左侧菜单 → Dashboards → Import
2. 输入 Dashboard ID: 7362
3. 选择 Prometheus 数据源
4. 点击 Import

#### 4.3.3 Nginx 监控大盘
1. 左侧菜单 → Dashboards → Import
2. 输入 Dashboard ID: 12708
3. 选择 Prometheus 数据源
4. 点击 Import

## 5. 配置告警通知

### 5.1 钉钉机器人配置
1. 在钉钉群中添加自定义机器人
2. 获取 Webhook 地址
3. 编辑 `/opt/monitoring/alertmanager/alertmanager.yml`
4. 替换 `access_token=YOUR_TOKEN` 为实际的 token
5. 重启 Alertmanager：`systemctl restart alertmanager`

### 5.2 验证告警
```bash
# 检查告警规则
curl http://localhost:9090/api/v1/rules

# 检查活跃告警
curl http://localhost:9090/api/v1/alerts

# 测试告警触发（停止 Node Exporter 会触发 InstanceDown 告警）
# 停止 Node Exporter 服务
systemctl stop node_exporter

# 等待 1 分钟后检查告警
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname == "InstanceDown")'

# 恢复 Node Exporter 服务
systemctl start node_exporter
```

## 6. 部署验证

### 6.1 服务状态检查
```bash
# 检查所有服务状态
systemctl status prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 检查端口监听
ss -tlnp | grep -E '9090|3000|9100|9093|9113|9104'
```

### 6.2 指标采集验证
```bash
# 检查 Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'

# 执行 PromQL 查询
# CPU 使用率
curl 'http://localhost:9090/api/v1/query?query=100-(avg%20by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100)'

# 内存使用率
curl 'http://localhost:9090/api/v1/query?query=(1-node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)*100'
```

### 6.3 告警验证
```bash
# 检查告警规则
curl http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {alertname: .name, state: .state}'

# 检查 Alertmanager 告警
curl http://localhost:9093/api/v2/alerts
```

### 6.4 Grafana 验证
- 访问 http://服务器IP:3000
- 查看导入的 Dashboard
- 确认图表数据正常显示

## 7. 常见问题

### 7.1 服务启动失败
```bash
# 查看服务日志
journalctl -u prometheus -f
journalctl -u node_exporter -f
journalctl -u nginx_exporter -f
journalctl -u mysql_exporter -f
journalctl -u alertmanager -f
journalctl -u grafana-server -f
```

### 7.2 端口冲突
```bash
# 检查端口占用
ss -tlnp | grep :9090
ss -tlnp | grep :3000
ss -tlnp | grep :9100
ss -tlnp | grep :9093
ss -tlnp | grep :9113
ss -tlnp | grep :9104

# 杀死占用进程
kill -9 <PID>
```

### 7.3 配置文件语法错误
```bash
# 验证 Prometheus 配置
/opt/monitoring/prometheus/prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml --check

# 验证 Alertmanager 配置
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

### 7.4 采集失败
```bash
# 检查 Exporter 状态
curl http://localhost:9100/metrics
curl http://localhost:9113/metrics
curl http://localhost:9104/metrics

# 检查网络连通性
telnet localhost 9100
telnet localhost 9113
telnet localhost 9104
```

## 8. 卸载指南

### 8.1 停止服务
```bash
systemctl stop prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server
systemctl disable prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server
```

### 8.2 删除 Systemd 服务
```bash
rm /etc/systemd/system/prometheus.service
rm /etc/systemd/system/node_exporter.service
rm /etc/systemd/system/nginx_exporter.service
rm /etc/systemd/system/mysql_exporter.service
rm /etc/systemd/system/alertmanager.service
rm /etc/systemd/system/grafana-server.service
systemctl daemon-reload
```

### 8.3 删除安装文件
```bash
rm -rf /opt/monitoring
dpkg -r grafana
```

### 8.4 删除配置文件
```bash
rm /etc/nginx/conf.d/status.conf
nginx -t && systemctl restart nginx
```

## 9. 升级指南

### 9.1 备份配置
```bash
# 备份 Prometheus 配置
cp -r /opt/monitoring/prometheus/prometheus.yml /opt/monitoring/prometheus/prometheus.yml.bak
cp -r /opt/monitoring/prometheus/rules /opt/monitoring/prometheus/rules.bak

# 备份 Alertmanager 配置
cp -r /opt/monitoring/alertmanager/alertmanager.yml /opt/monitoring/alertmanager/alertmanager.yml.bak

# 备份 Grafana 配置
cp -r /etc/grafana /etc/grafana.bak
```

### 9.2 下载新版本
```bash
# 下载新版本 Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v<new-version>/prometheus-<new-version>.linux-amd64.tar.gz

# 下载新版本 Exporters
wget https://github.com/prometheus/node_exporter/releases/download/v<new-version>/node_exporter-<new-version>.linux-amd64.tar.gz
```

### 9.3 停止服务
```bash
systemctl stop prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server
```

### 9.4 替换二进制文件
```bash
# 备份旧版本
mv /opt/monitoring/prometheus/prometheus /opt/monitoring/prometheus/prometheus.old
mv /opt/monitoring/exporters/node_exporter/node_exporter /opt/monitoring/exporters/node_exporter/node_exporter.old

# 解压新版本
tar -zxf prometheus-<new-version>.linux-amd64.tar.gz
mv prometheus-<new-version>.linux-amd64/prometheus /opt/monitoring/prometheus/

tar -zxf node_exporter-<new-version>.linux-amd64.tar.gz
mv node_exporter-<new-version>.linux-amd64/node_exporter /opt/monitoring/exporters/node_exporter/
```

### 9.5 启动服务
```bash
systemctl start prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server
```

### 9.6 验证升级
```bash
# 检查版本
/opt/monitoring/prometheus/prometheus --version
/opt/monitoring/exporters/node_exporter/node_exporter --version

# 检查服务状态
systemctl status prometheus node_exporter
```

### 9.7 回滚（如需）
```bash
# 停止服务
systemctl stop prometheus node_exporter

# 恢复旧版本
mv /opt/monitoring/prometheus/prometheus.old /opt/monitoring/prometheus/prometheus
mv /opt/monitoring/exporters/node_exporter/node_exporter.old /opt/monitoring/exporters/node_exporter/node_exporter

# 启动服务
systemctl start prometheus node_exporter
```