# 日常维护手册

## 1. 日常巡检

### 1.1 服务状态检查

**每日检查命令**：
```bash
#!/bin/bash
# 服务状态检查脚本

echo "=== 服务状态检查 ==="
echo "时间: $(date)"
echo ""

# 检查所有服务状态
services=("prometheus" "node_exporter" "nginx_exporter" "mysql_exporter" "alertmanager" "grafana-server")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "[OK] $service is running"
    else
        echo "[ERROR] $service is not running"
        # 自动重启尝试
        systemctl restart "$service"
        if systemctl is-active --quiet "$service"; then
            echo "[RECOVERED] $service has been restarted"
        else
            echo "[FAILED] $service restart failed"
        fi
    fi
done

echo ""
echo "=== 端口监听状态 ==="
ports=(9090 3000 9100 9093 9113 9104)

for port in "${ports[@]}"; do
    if ss -tlnp | grep -q ":$port"; then
        echo "[OK] Port $port is listening"
    else
        echo "[ERROR] Port $port is not listening"
    fi
done
```

### 1.2 资源使用检查

**每日资源检查**：
```bash
#!/bin/bash
# 资源使用检查脚本

echo "=== 资源使用检查 ==="
echo "时间: $(date)"
echo ""

# CPU 使用率
echo "CPU 使用率:"
top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1

# 内存使用率
echo ""
echo "内存使用率:"
free -h | awk '/Mem/{printf "%.2f%%\n", $3/$2*100}'

# 磁盘使用率
echo ""
echo "磁盘使用率:"
df -h | awk '$NF=="/"{printf "%s\n", $5}'

# 磁盘空间检查
echo ""
echo "磁盘空间检查:"
df -h /opt/monitoring/

# 进程检查
echo ""
echo "监控相关进程:"
ps aux | grep -E "prometheus|grafana|alertmanager|node_exporter|nginx_exporter|mysql_exporter" | grep -v grep
```

### 1.3 告警状态检查

**每日告警检查**：
```bash
#!/bin/bash
# 告警状态检查脚本

echo "=== 告警状态检查 ==="
echo "时间: $(date)"
echo ""

# 检查 Prometheus 告警规则
echo "Prometheus 告警规则状态:"
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name: .name, state: .state}'

echo ""
echo "活跃告警:"
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state: .state, instance: .labels.instance}'

echo ""
echo "Alertmanager 告警:"
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | {name: .labels.alertname, status: .status.state}'
```

### 1.4 指标采集检查

**每日指标检查**：
```bash
#!/bin/bash
# 指标采集检查脚本

echo "=== 指标采集检查 ==="
echo "时间: $(date)"
echo ""

# 检查 Prometheus targets
echo "Prometheus Targets 状态:"
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health, lastScrape: .lastScrape}'

echo ""
echo "Target 统计:"
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | group_by(.health) | map({health: .[0].health, count: length})'

# 检查指标数量
echo ""
echo "指标数量统计:"
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data | length'
```

## 2. 周维护任务

### 2.1 配置备份

**每周配置备份**：
```bash
#!/bin/bash
# 配置备份脚本

BACKUP_DIR="/opt/monitoring/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "开始配置备份: $BACKUP_DIR"

# 备份 Prometheus 配置
cp -r /opt/monitoring/prometheus/prometheus.yml "$BACKUP_DIR/"
cp -r /opt/monitoring/prometheus/rules "$BACKUP_DIR/"

# 备份 Alertmanager 配置
cp -r /opt/monitoring/alertmanager/alertmanager.yml "$BACKUP_DIR/"
cp -r /opt/monitoring/alertmanager/templates "$BACKUP_DIR/"

# 备份 Grafana 配置
cp -r /etc/grafana "$BACKUP_DIR/"

# 备份 Exporter 配置
cp -r /opt/monitoring/exporters/mysqld_exporter/.my.cnf "$BACKUP_DIR/"

# 备份 Systemd 服务文件
cp /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
cp /etc/systemd/system/node_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/nginx_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/mysql_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/alertmanager.service "$BACKUP_DIR/"
cp /etc/systemd/system/grafana-server.service "$BACKUP_DIR/"

# 压缩备份
tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
rm -rf "$BACKUP_DIR"

echo "配置备份完成: $BACKUP_DIR.tar.gz"

# 清理 30 天前的备份
find /opt/monitoring/backup/ -name "*.tar.gz" -mtime +30 -delete
echo "已清理 30 天前的备份"
```

### 2.2 日志清理

**每周日志清理**：
```bash
#!/bin/bash
# 日志清理脚本

echo "开始日志清理..."

# 清理 Prometheus 日志
journalctl --vacuum-time=7d --unit=prometheus

# 清理 Alertmanager 日志
journalctl --vacuum-time=7d --unit=alertmanager

# 清理 Grafana 日志
find /var/log/grafana/ -name "*.log" -mtime +7 -delete

# 清理系统日志
journalctl --vacuum-time=7d

echo "日志清理完成"
```

### 2.3 数据清理

**每周数据清理**：
```bash
#!/bin/bash
# 数据清理脚本

echo "开始数据清理..."

# 检查 Prometheus 数据目录大小
PROMETHEUS_DATA_SIZE=$(du -sh /opt/monitoring/prometheus/data/ | awk '{print $1}')
echo "Prometheus 数据目录大小: $PROMETHEUS_DATA_SIZE"

# 检查磁盘空间
DISK_USAGE=$(df -h /opt/monitoring/ | awk 'NR==2{print $5}' | cut -d'%' -f1)
echo "磁盘使用率: $DISK_USAGE%"

# 如果磁盘使用率超过 80%，清理旧数据
if [ "$DISK_USAGE" -gt 80 ]; then
    echo "磁盘使用率超过 80%，开始清理旧数据..."
    
    # 停止 Prometheus
    systemctl stop prometheus
    
    # 清理 15 天前的数据块
    find /opt/monitoring/prometheus/data/ -name "*.db" -mtime +15 -delete
    
    # 启动 Prometheus
    systemctl start prometheus
    
    echo "数据清理完成"
else
    echo "磁盘使用率正常，无需清理"
fi
```

### 2.4 性能检查

**每周性能检查**：
```bash
#!/bin/bash
# 性能检查脚本

echo "=== 性能检查 ==="
echo "时间: $(date)"
echo ""

# Prometheus 性能检查
echo "Prometheus 性能指标:"
curl -s 'http://localhost:9090/api/v1/query?query=prometheus_engine_query_duration_seconds' | jq '.data.result[] | {quantile: .metric.quantile, value: .value[1]}'

echo ""
echo "Prometheus 采集延迟:"
curl -s 'http://localhost:9090/api/v1/query?query=scrape_duration_seconds' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'

echo ""
echo "Prometheus 内存使用:"
curl -s 'http://localhost:9090/api/v1/query?query=process_resident_memory_bytes{job="prometheus"}' | jq '.data.result[] | {value: .value[1]}'

# Grafana 性能检查
echo ""
echo "Grafana 性能指标:"
curl -s 'http://localhost:3000/api/health' | jq '.'

# Alertmanager 性能检查
echo ""
echo "Alertmanager 性能指标:"
curl -s 'http://localhost:9093/api/v2/alerts' | jq 'length'
```

## 3. 月维护任务

### 3.1 安全更新

**每月安全更新**：
```bash
#!/bin/bash
# 安全更新脚本

echo "开始安全更新..."

# 更新系统包
apt update
apt upgrade -y

# 更新监控组件（手动）
echo "请手动检查以下组件是否有新版本:"
echo "- Prometheus: https://github.com/prometheus/prometheus/releases"
echo "- Grafana: https://grafana.com/grafana/download"
echo "- Alertmanager: https://github.com/prometheus/alertmanager/releases"
echo "- Node Exporter: https://github.com/prometheus/node_exporter/releases"
echo "- Nginx Exporter: https://github.com/nginxinc/nginx-prometheus-exporter/releases"
echo "- MySQL Exporter: https://github.com/prometheus/mysqld_exporter/releases"

# 清理不需要的包
apt autoremove -y

echo "安全更新完成"
```

### 3.2 性能优化

**每月性能优化**：
```bash
#!/bin/bash
# 性能优化脚本

echo "=== 性能优化检查 ==="
echo "时间: $(date)"
echo ""

# 检查 Recording Rules
echo "Recording Rules 状态:"
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | contains("recording")) | {name: .name, rules: .rules | length}'

# 检查查询性能
echo ""
echo "查询性能统计:"
curl -s 'http://localhost:9090/api/v1/query?query=topk(10, prometheus_engine_query_duration_seconds)' | jq '.data.result[] | {query: .metric.query, duration: .value[1]}'

# 检查采集性能
echo ""
echo "采集性能统计:"
curl -s 'http://localhost:9090/api/v1/query?query=topk(10, scrape_duration_seconds)' | jq '.data.result[] | {instance: .metric.instance, duration: .value[1]}'

# 检查存储使用
echo ""
echo "存储使用统计:"
du -sh /opt/monitoring/prometheus/data/
du -sh /opt/monitoring/alertmanager/data/
du -sh /var/lib/grafana/
```

### 3.3 容量规划

**每月容量规划**：
```bash
#!/bin/bash
# 容量规划脚本

echo "=== 容量规划报告 ==="
echo "时间: $(date)"
echo ""

# 磁盘使用趋势
echo "磁盘使用趋势:"
df -h /opt/monitoring/

# Prometheus 数据增长
echo ""
echo "Prometheus 数据增长:"
PROMETHEUS_DATA_SIZE=$(du -sh /opt/monitoring/prometheus/data/ | awk '{print $1}')
echo "当前数据大小: $PROMETHEUS_DATA_SIZE"

# 预计存储需求
echo ""
echo "预计存储需求:"
echo "当前采集指标数: $(curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data | length')"
echo "当前采集间隔: 15s"
echo "数据保留时间: 15d"
echo "预计每日数据增长: 约 $(echo "scale=2; $(du -sm /opt/monitoring/prometheus/data/ | awk '{print $1}') / 15" | bc) MB"

# 资源使用趋势
echo ""
echo "资源使用趋势:"
echo "CPU 核心数: $(nproc)"
echo "内存总量: $(free -h | awk '/Mem/{print $2}')"
echo "当前内存使用: $(free -h | awk '/Mem/{print $3}')"
```

### 3.4 配置审查

**每月配置审查**：
```bash
#!/bin/bash
# 配置审查脚本

echo "=== 配置审查 ==="
echo "时间: $(date)"
echo ""

# Prometheus 配置审查
echo "Prometheus 配置:"
cat /opt/monitoring/prometheus/prometheus.yml | grep -E "scrape_interval|evaluation_interval|retention"

echo ""
echo "告警规则数量:"
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules | length' | paste -sd+ | bc

# Alertmanager 配置审查
echo ""
echo "Alertmanager 配置:"
cat /opt/monitoring/alertmanager/alertmanager.yml | grep -E "group_by|group_wait|repeat_interval"

# Grafana 配置审查
echo ""
echo "Grafana 数据源配置:"
curl -s http://localhost:3000/api/datasources | jq '.[] | {name: .name, type: .type, url: .url}'

echo ""
echo "Grafana 大盘数量:"
curl -s http://localhost:3000/api/search | jq 'length'
```

## 4. 备份与恢复

### 4.1 完整备份

**完整备份脚本**：
```bash
#!/bin/bash
# 完整备份脚本

BACKUP_DIR="/opt/monitoring/backup/full_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "开始完整备份: $BACKUP_DIR"

# 停止服务
echo "停止监控服务..."
systemctl stop prometheus alertmanager grafana-server

# 备份 Prometheus 数据
echo "备份 Prometheus 数据..."
tar -czf "$BACKUP_DIR/prometheus_data.tar.gz" -C /opt/monitoring prometheus/data

# 备份 Prometheus 配置
echo "备份 Prometheus 配置..."
cp -r /opt/monitoring/prometheus/prometheus.yml "$BACKUP_DIR/"
cp -r /opt/monitoring/prometheus/rules "$BACKUP_DIR/"

# 备份 Alertmanager 数据和配置
echo "备份 Alertmanager 数据和配置..."
tar -czf "$BACKUP_DIR/alertmanager_data.tar.gz" -C /opt/monitoring alertmanager/data
cp -r /opt/monitoring/alertmanager/alertmanager.yml "$BACKUP_DIR/"
cp -r /opt/monitoring/alertmanager/templates "$BACKUP_DIR/"

# 备份 Grafana 数据和配置
echo "备份 Grafana 数据和配置..."
tar -czf "$BACKUP_DIR/grafana_data.tar.gz" -C /var/lib grafana
cp -r /etc/grafana "$BACKUP_DIR/"

# 备份 Systemd 服务文件
echo "备份 Systemd 服务文件..."
cp /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
cp /etc/systemd/system/node_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/nginx_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/mysql_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/alertmanager.service "$BACKUP_DIR/"
cp /etc/systemd/system/grafana-server.service "$BACKUP_DIR/"

# 启动服务
echo "启动监控服务..."
systemctl start prometheus alertmanager grafana-server

# 压缩备份
tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
rm -rf "$BACKUP_DIR"

echo "完整备份完成: $BACKUP_DIR.tar.gz"
echo "备份大小: $(du -sh "$BACKUP_DIR.tar.gz" | awk '{print $1}')"
```

### 4.2 配置备份

**配置备份脚本**：
```bash
#!/bin/bash
# 配置备份脚本

BACKUP_DIR="/opt/monitoring/backup/config_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "开始配置备份: $BACKUP_DIR"

# 备份 Prometheus 配置
cp -r /opt/monitoring/prometheus/prometheus.yml "$BACKUP_DIR/"
cp -r /opt/monitoring/prometheus/rules "$BACKUP_DIR/"

# 备份 Alertmanager 配置
cp -r /opt/monitoring/alertmanager/alertmanager.yml "$BACKUP_DIR/"
cp -r /opt/monitoring/alertmanager/templates "$BACKUP_DIR/"

# 备份 Grafana 配置
cp -r /etc/grafana "$BACKUP_DIR/"

# 备份 Exporter 配置
cp -r /opt/monitoring/exporters/mysqld_exporter/.my.cnf "$BACKUP_DIR/"

# 备份 Systemd 服务文件
cp /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
cp /etc/systemd/system/node_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/nginx_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/mysql_exporter.service "$BACKUP_DIR/"
cp /etc/systemd/system/alertmanager.service "$BACKUP_DIR/"
cp /etc/systemd/system/grafana-server.service "$BACKUP_DIR/"

# 压缩备份
tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
rm -rf "$BACKUP_DIR"

echo "配置备份完成: $BACKUP_DIR.tar.gz"
```

### 4.3 恢复流程

**完整恢复流程**：
```bash
#!/bin/bash
# 完整恢复脚本

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
    echo "使用方法: $0 <备份文件>"
    echo "示例: $0 /opt/monitoring/backup/full_20231201_120000.tar.gz"
    exit 1
fi

echo "开始完整恢复: $BACKUP_FILE"

# 停止服务
echo "停止监控服务..."
systemctl stop prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 解压备份
TEMP_DIR=$(mktemp -d)
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"
BACKUP_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d | head -1)

# 恢复 Prometheus 数据
echo "恢复 Prometheus 数据..."
rm -rf /opt/monitoring/prometheus/data/*
tar -xzf "$BACKUP_DIR/prometheus_data.tar.gz" -C /opt/monitoring

# 恢复 Prometheus 配置
echo "恢复 Prometheus 配置..."
cp "$BACKUP_DIR/prometheus.yml" /opt/monitoring/prometheus/
cp -r "$BACKUP_DIR/rules" /opt/monitoring/prometheus/

# 恢复 Alertmanager 数据和配置
echo "恢复 Alertmanager 数据和配置..."
rm -rf /opt/monitoring/alertmanager/data/*
tar -xzf "$BACKUP_DIR/alertmanager_data.tar.gz" -C /opt/monitoring
cp "$BACKUP_DIR/alertmanager.yml" /opt/monitoring/alertmanager/
cp -r "$BACKUP_DIR/templates" /opt/monitoring/alertmanager/

# 恢复 Grafana 数据和配置
echo "恢复 Grafana 数据和配置..."
rm -rf /var/lib/grafana/*
tar -xzf "$BACKUP_DIR/grafana_data.tar.gz" -C /var/lib
cp -r "$BACKUP_DIR/grafana" /etc/

# 恢复 Systemd 服务文件
echo "恢复 Systemd 服务文件..."
cp "$BACKUP_DIR/prometheus.service" /etc/systemd/system/
cp "$BACKUP_DIR/node_exporter.service" /etc/systemd/system/
cp "$BACKUP_DIR/nginx_exporter.service" /etc/systemd/system/
cp "$BACKUP_DIR/mysql_exporter.service" /etc/systemd/system/
cp "$BACKUP_DIR/alertmanager.service" /etc/systemd/system/
cp "$BACKUP_DIR/grafana-server.service" /etc/systemd/system/

# 重新加载 Systemd
systemctl daemon-reload

# 启动服务
echo "启动监控服务..."
systemctl start prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 清理临时目录
rm -rf "$TEMP_DIR"

echo "完整恢复完成"
echo "请检查服务状态: systemctl status prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server"
```

## 5. 监控脚本

### 5.1 健康检查脚本

**health_check.sh**：
```bash
#!/bin/bash
# 健康检查脚本

LOG_FILE="/var/log/monitoring_health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        log "[OK] $service is running"
        return 0
    else
        log "[ERROR] $service is not running"
        systemctl restart "$service"
        if systemctl is-active --quiet "$service"; then
            log "[RECOVERED] $service has been restarted"
            return 0
        else
            log "[FAILED] $service restart failed"
            return 1
        fi
    fi
}

check_port() {
    local port=$1
    if ss -tlnp | grep -q ":$port"; then
        log "[OK] Port $port is listening"
        return 0
    else
        log "[ERROR] Port $port is not listening"
        return 1
    fi
}

check_http() {
    local url=$1
    local name=$2
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
        log "[OK] $name HTTP check passed"
        return 0
    else
        log "[ERROR] $name HTTP check failed"
        return 1
    fi
}

main() {
    log "=== 开始健康检查 ==="
    
    # 检查服务状态
    check_service "prometheus"
    check_service "node_exporter"
    check_service "nginx_exporter"
    check_service "mysql_exporter"
    check_service "alertmanager"
    check_service "grafana-server"
    
    # 检查端口
    check_port 9090
    check_port 3000
    check_port 9100
    check_port 9093
    check_port 9113
    check_port 9104
    
    # 检查 HTTP 接口
    check_http "http://localhost:9090/-/healthy" "Prometheus"
    check_http "http://localhost:3000/api/health" "Grafana"
    check_http "http://localhost:9093/-/healthy" "Alertmanager"
    
    # 检查 Prometheus targets
    TARGETS_DOWN=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | .labels.instance' | wc -l)
    if [ "$TARGETS_DOWN" -gt 0 ]; then
        log "[WARNING] $TARGETS_DOWN Prometheus targets are DOWN"
    else
        log "[OK] All Prometheus targets are UP"
    fi
    
    log "=== 健康检查完成 ==="
}

main
```

### 5.2 性能监控脚本

**performance_monitor.sh**：
```bash
#!/bin/bash
# 性能监控脚本

LOG_FILE="/var/log/monitoring_performance.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

monitor_prometheus() {
    log "=== Prometheus 性能监控 ==="
    
    # 查询性能
    QUERY_DURATION=$(curl -s 'http://localhost:9090/api/v1/query?query=prometheus_engine_query_duration_seconds{quantile="0.9"}' | jq '.data.result[0].value[1]' | tr -d '"')
    log "查询延迟(P90): ${QUERY_DURATION}s"
    
    # 内存使用
    MEMORY_USAGE=$(curl -s 'http://localhost:9090/api/v1/query?query=process_resident_memory_bytes{job="prometheus"}' | jq '.data.result[0].value[1]' | tr -d '"')
    MEMORY_MB=$(echo "scale=2; $MEMORY_USAGE / 1024 / 1024" | bc)
    log "内存使用: ${MEMORY_MB}MB"
    
    # 采集延迟
    SCRAPE_DURATION=$(curl -s 'http://localhost:9090/api/v1/query?query=max(scrape_duration_seconds)' | jq '.data.result[0].value[1]' | tr -d '"')
    log "采集延迟(最大): ${SCRAPE_DURATION}s"
}

monitor_grafana() {
    log "=== Grafana 性能监控 ==="
    
    # 响应时间
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://localhost:3000/api/health)
    log "响应时间: ${RESPONSE_TIME}s"
    
    # 数据源状态
    DATASOURCE_STATUS=$(curl -s http://localhost:3000/api/datasources | jq '.[0].jsonData.timeInterval')
    log "数据源采集间隔: $DATASOURCE_STATUS"
}

monitor_alertmanager() {
    log "=== Alertmanager 性能监控 ==="
    
    # 告警数量
    ALERT_COUNT=$(curl -s http://localhost:9093/api/v2/alerts | jq 'length')
    log "活跃告警数: $ALERT_COUNT"
    
    # 通知队列
    QUEUE_LENGTH=$(curl -s http://localhost:9093/api/v2/alerts/groups | jq 'length')
    log "告警分组数: $QUEUE_LENGTH"
}

monitor_system() {
    log "=== 系统性能监控 ==="
    
    # CPU 使用率
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    log "CPU 使用率: ${CPU_USAGE}%"
    
    # 内存使用率
    MEMORY_USAGE=$(free | awk '/Mem/{printf "%.2f", $3/$2*100}')
    log "内存使用率: ${MEMORY_USAGE}%"
    
    # 磁盘使用率
    DISK_USAGE=$(df -h /opt/monitoring/ | awk 'NR==2{print $5}' | cut -d'%' -f1)
    log "磁盘使用率: ${DISK_USAGE}%"
}

main() {
    log "=== 开始性能监控 ==="
    
    monitor_system
    monitor_prometheus
    monitor_grafana
    monitor_alertmanager
    
    log "=== 性能监控完成 ==="
}

main
```

### 5.3 告警监控脚本

**alert_monitor.sh**：
```bash
#!/bin/bash
# 告警监控脚本

LOG_FILE="/var/log/monitoring_alerts.log"
ALERT_HISTORY_FILE="/tmp/alert_history.txt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_alerts() {
    log "=== 检查告警状态 ==="
    
    # 获取活跃告警
    ALERTS=$(curl -s http://localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname)|\(.labels.instance)|\(.state)"')
    
    if [ -z "$ALERTS" ]; then
        log "无活跃告警"
        return
    fi
    
    # 检查新告警
    while IFS='|' read -r alertname instance state; do
        ALERT_KEY="${alertname}_${instance}"
        
        # 检查是否为新告警
        if ! grep -q "$ALERT_KEY" "$ALERT_HISTORY_FILE" 2>/dev/null; then
            log "[NEW ALERT] $alertname on $instance (State: $state)"
            echo "$ALERT_KEY" >> "$ALERT_HISTORY_FILE"
        fi
    done <<< "$ALERTS"
    
    # 检查恢复的告警
    if [ -f "$ALERT_HISTORY_FILE" ]; then
        while IFS= read -r alert_key; do
            if ! echo "$ALERTS" | grep -q "${alert_key%_*}" 2>/dev/null; then
                log "[RECOVERED] ${alert_key%_*} on ${alert_key#*_}"
                sed -i "/$alert_key/d" "$ALERT_HISTORY_FILE"
            fi
        done < "$ALERT_HISTORY_FILE"
    fi
}

check_alertmanager() {
    log "=== 检查 Alertmanager 状态 ==="
    
    # 检查 Alertmanager 告警
    AM_ALERTS=$(curl -s http://localhost:9093/api/v2/alerts | jq 'length')
    log "Alertmanager 告警数: $AM_ALERTS"
    
    # 检查通知状态
    NOTIFICATIONS=$(curl -s http://localhost:9093/api/v2/alerts/groups | jq 'length')
    log "告警分组数: $NOTIFICATIONS"
}

check_alert_rules() {
    log "=== 检查告警规则状态 ==="
    
    # 获取告警规则状态
    RULES=$(curl -s http://localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | "\(.name)|\(.state)|\(.lastEvaluation)"')
    
    while IFS='|' read -r name state last_eval; do
        log "规则: $name | 状态: $state | 最后评估: $last_eval"
    done <<< "$RULES"
}

main() {
    log "=== 开始告警监控 ==="
    
    check_alerts
    check_alertmanager
    check_alert_rules
    
    log "=== 告警监控完成 ==="
}

main
```

## 6. 维护计划表

### 6.1 每日维护

| 时间 | 任务 | 负责人 | 备注 |
|------|------|--------|------|
| 09:00 | 服务状态检查 | 运维工程师 | 检查所有服务运行状态 |
| 09:30 | 资源使用检查 | 运维工程师 | 检查 CPU、内存、磁盘使用率 |
| 10:00 | 告警状态检查 | 运维工程师 | 检查活跃告警和通知状态 |
| 10:30 | 指标采集检查 | 运维工程师 | 检查 Prometheus targets 状态 |
| 18:00 | 日志检查 | 运维工程师 | 检查错误日志和异常信息 |

### 6.2 每周维护

| 时间 | 任务 | 负责人 | 备注 |
|------|------|--------|------|
| 周一 09:00 | 配置备份 | 运维工程师 | 备份所有配置文件 |
| 周二 09:00 | 日志清理 | 运维工程师 | 清理 7 天前的日志 |
| 周三 09:00 | 数据清理 | 运维工程师 | 检查磁盘空间，清理旧数据 |
| 周四 09:00 | 性能检查 | 运维工程师 | 检查系统性能指标 |
| 周五 09:00 | 安全检查 | 运维工程师 | 检查安全更新和漏洞 |

### 6.3 每月维护

| 时间 | 任务 | 负责人 | 备注 |
|------|------|--------|------|
| 每月 1 日 | 安全更新 | 运维工程师 | 更新系统和组件 |
| 每月 5 日 | 性能优化 | 运维工程师 | 优化配置和查询 |
| 每月 10 日 | 容量规划 | 运维工程师 | 评估存储和资源需求 |
| 每月 15 日 | 配置审查 | 运维工程师 | 审查配置合理性 |
| 每月 20 日 | 完整备份 | 运维工程师 | 执行完整备份 |
| 每月 25 日 | 恢复测试 | 运维工程师 | 测试备份恢复流程 |

## 7. 故障升级流程

### 7.1 故障等级定义

| 等级 | 定义 | 响应时间 | 解决时间 |
|------|------|----------|----------|
| P0 | 监控系统完全不可用 | 5 分钟 | 30 分钟 |
| P1 | 核心功能不可用 | 15 分钟 | 2 小时 |
| P2 | 部分功能异常 | 30 分钟 | 4 小时 |
| P3 | 非关键功能异常 | 1 小时 | 24 小时 |

### 7.2 升级流程

**P0 故障升级**：
1. 立即通知运维团队负责人
2. 启动应急响应流程
3. 15 分钟内未解决，升级至技术总监
4. 30 分钟内未解决，升级至 CTO

**P1 故障升级**：
1. 通知运维团队负责人
2. 30 分钟内未解决，升级至技术总监
3. 2 小时内未解决，升级至 CTO

**P2/P3 故障升级**：
1. 记录故障工单
2. 按优先级安排处理
3. 定期汇报处理进度

### 7.3 故障处理流程

1. **故障发现**：监控系统告警或用户报告
2. **故障确认**：确认故障真实性和影响范围
3. **故障定位**：分析日志和监控数据，定位故障原因
4. **故障处理**：采取临时或永久解决方案
5. **故障恢复**：验证系统恢复正常
6. **故障总结**：编写故障报告，总结经验教训

## 8. 文档更新

### 8.1 文档维护计划

| 文档 | 更新频率 | 负责人 | 备注 |
|------|----------|--------|------|
| README.md | 每次变更 | 运维工程师 | 记录重大变更 |
| deployment.md | 每次部署 | 运维工程师 | 更新部署步骤 |
| configuration.md | 每次配置变更 | 运维工程师 | 更新配置说明 |
| troubleshooting.md | 每次故障 | 运维工程师 | 记录故障处理 |
| maintenance.md | 每月 | 运维工程师 | 更新维护计划 |

### 8.2 版本控制

**Git 提交规范**：
```
feat: 新增功能
fix: 修复 bug
docs: 文档更新
style: 代码格式调整
refactor: 代码重构
test: 测试相关
chore: 构建/工具相关
```

**提交示例**：
```bash
git add README.md
git commit -m "docs: 更新 README 文档，添加新功能说明"
```

## 9. 培训计划

### 9.1 新员工培训

| 培训内容 | 时长 | 培训方式 | 备注 |
|----------|------|----------|------|
| 监控系统架构 | 2 小时 | 讲解 | 了解整体架构 |
| 日常运维操作 | 4 小时 | 实操 | 掌握日常操作 |
| 故障处理流程 | 4 小时 | 案例分析 | 学习故障处理 |
| 工具使用 | 2 小时 | 实操 | 熟悉运维工具 |

### 9.2 技能提升

| 培训主题 | 频率 | 参与人员 | 备注 |
|----------|------|----------|------|
| 新技术分享 | 每月 | 全体运维 | 了解新技术趋势 |
| 故障案例分析 | 每周 | 全体运维 | 总结故障经验 |
| 性能优化培训 | 每季度 | 高级运维 | 提升优化能力 |
| 安全培训 | 每季度 | 全体运维 | 增强安全意识