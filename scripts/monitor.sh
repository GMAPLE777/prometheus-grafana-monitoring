#!/bin/bash
# 监控系统健康检查脚本

LOG_FILE="/var/log/monitoring_health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查所有服务状态
check_services() {
    log "=== 检查服务状态 ==="
    
    local services=("prometheus" "node_exporter" "nginx_exporter" "mysql_exporter" "alertmanager" "grafana-server")
    local all_ok=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "[OK] $service is running"
        else
            log "[ERROR] $service is not running"
            all_ok=false
            
            # 自动重启尝试
            log "尝试重启 $service..."
            systemctl restart "$service"
            sleep 5
            
            if systemctl is-active --quiet "$service"; then
                log "[RECOVERED] $service has been restarted"
            else
                log "[FAILED] $service restart failed"
            fi
        fi
    done
    
    if [ "$all_ok" = false ]; then
        return 1
    fi
    return 0
}

# 检查端口监听
check_ports() {
    log "=== 检查端口监听 ==="
    
    local ports=(9090 3000 9100 9093 9113 9104)
    local all_ok=true
    
    for port in "${ports[@]}"; do
        if ss -tlnp | grep -q ":$port"; then
            log "[OK] Port $port is listening"
        else
            log "[ERROR] Port $port is not listening"
            all_ok=false
        fi
    done
    
    if [ "$all_ok" = false ]; then
        return 1
    fi
    return 0
}

# 检查 Prometheus targets
check_targets() {
    log "=== 检查 Prometheus Targets ==="
    
    local targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log "[ERROR] 无法连接到 Prometheus"
        return 1
    fi
    
    local total=$(echo "$targets" | jq '.data.activeTargets | length')
    local up=$(echo "$targets" | jq '[.data.activeTargets[] | select(.health == "up")] | length')
    local down=$(echo "$targets" | jq '[.data.activeTargets[] | select(.health != "up")] | length')
    
    log "Targets 总数: $total"
    log "Targets 正常: $up"
    log "Targets 异常: $down"
    
    if [ "$down" -gt 0 ]; then
        log "[WARNING] 以下 Targets 状态异常:"
        echo "$targets" | jq -r '.data.activeTargets[] | select(.health != "up") | "  - \(.labels.instance): \(.health)"'
        return 1
    fi
    
    log "[OK] 所有 Targets 状态正常"
    return 0
}

# 检查告警状态
check_alerts() {
    log "=== 检查告警状态 ==="
    
    local alerts=$(curl -s http://localhost:9090/api/v1/alerts 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log "[ERROR] 无法连接到 Prometheus"
        return 1
    fi
    
    local active_alerts=$(echo "$alerts" | jq '.data.alerts | length')
    
    log "活跃告警数: $active_alerts"
    
    if [ "$active_alerts" -gt 0 ]; then
        log "[WARNING] 存在活跃告警:"
        echo "$alerts" | jq -r '.data.alerts[] | "  - \(.labels.alertname) on \(.labels.instance): \(.state)"'
        return 1
    fi
    
    log "[OK] 无活跃告警"
    return 0
}

# 检查资源使用
check_resources() {
    log "=== 检查资源使用 ==="
    
    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    log "CPU 使用率: ${cpu_usage}%"
    
    # 内存使用率
    local memory_usage=$(free | awk '/Mem/{printf "%.2f", $3/$2*100}')
    log "内存使用率: ${memory_usage}%"
    
    # 磁盘使用率
    local disk_usage=$(df -h /opt/monitoring/ | awk 'NR==2{print $5}' | cut -d'%' -f1)
    log "磁盘使用率: ${disk_usage}%"
    
    # 检查阈值
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        log "[WARNING] CPU 使用率过高"
    fi
    
    if (( $(echo "$memory_usage > 80" | bc -l) )); then
        log "[WARNING] 内存使用率过高"
    fi
    
    if [ "$disk_usage" -gt 80 ]; then
        log "[WARNING] 磁盘使用率过高"
    fi
    
    return 0
}

# 检查 HTTP 接口
check_http() {
    log "=== 检查 HTTP 接口 ==="
    
    local urls=(
        "http://localhost:9090/-/healthy:Prometheus"
        "http://localhost:3000/api/health:Grafana"
        "http://localhost:9093/-/healthy:Alertmanager"
    )
    
    for url_info in "${urls[@]}"; do
        local url=$(echo "$url_info" | cut -d':' -f1-2)
        local name=$(echo "$url_info" | cut -d':' -f3)
        
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        
        if [ "$status_code" = "200" ]; then
            log "[OK] $name HTTP 接口正常"
        else
            log "[ERROR] $name HTTP 接口异常 (状态码: $status_code)"
        fi
    done
    
    return 0
}

# 检查 Grafana 数据源
check_grafana_datasource() {
    log "=== 检查 Grafana 数据源 ==="
    
    local datasources=$(curl -s http://localhost:3000/api/datasources 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log "[ERROR] 无法连接到 Grafana"
        return 1
    fi
    
    local datasource_count=$(echo "$datasources" | jq 'length')
    log "数据源数量: $datasource_count"
    
    if [ "$datasource_count" -gt 0 ]; then
        log "[OK] Grafana 数据源配置正常"
    else
        log "[WARNING] Grafana 未配置数据源"
    fi
    
    return 0
}

# 主函数
main() {
    log "=========================================="
    log "监控系统健康检查"
    log "=========================================="
    
    local exit_code=0
    
    check_services || exit_code=1
    check_ports || exit_code=1
    check_targets || exit_code=1
    check_alerts || exit_code=1
    check_resources
    check_http
    check_grafana_datasource
    
    log "=========================================="
    
    if [ $exit_code -eq 0 ]; then
        log "[OK] 所有检查通过"
    else
        log "[ERROR] 存在检查失败项"
    fi
    
    log "=========================================="
    
    return $exit_code
}

main "$@"