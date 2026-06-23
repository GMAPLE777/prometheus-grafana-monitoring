#!/bin/bash
# 监控系统健康检查脚本

set -euo pipefail

LOG_FILE="/var/log/monitoring_health.log"

# 配置阈值（可通过环境变量覆盖）
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-80}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-3}"

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
            
            # 自动重启尝试（限制次数）
            local restart_count=0
            while [ $restart_count -lt $MAX_RESTART_ATTEMPTS ]; do
                log "尝试重启 $service... (第 $((restart_count+1)) 次)"
                systemctl restart "$service" || true
                sleep 5
                
                if systemctl is-active --quiet "$service"; then
                    log "[RECOVERED] $service has been restarted"
                    break
                fi
                ((restart_count++))
            done
            
            if [ $restart_count -eq $MAX_RESTART_ATTEMPTS ]; then
                log "[FAILED] $service restart failed after $MAX_RESTART_ATTEMPTS attempts"
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
    
    local targets
    if ! targets=$(curl -sf --max-time 10 http://localhost:9090/api/v1/targets 2>/dev/null); then
        log "[ERROR] 无法连接到 Prometheus"
        return 1
    fi
    
    local total
    local up
    local down
    total=$(echo "$targets" | jq '.data.activeTargets | length')
    up=$(echo "$targets" | jq '[.data.activeTargets[] | select(.health == "up")] | length')
    down=$(echo "$targets" | jq '[.data.activeTargets[] | select(.health != "up")] | length')
    
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
    
    local alerts
    if ! alerts=$(curl -sf --max-time 10 http://localhost:9090/api/v1/alerts 2>/dev/null); then
        log "[ERROR] 无法连接到 Prometheus"
        return 1
    fi
    
    local active_alerts
    active_alerts=$(echo "$alerts" | jq '.data.alerts | length')
    
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
    
    # CPU 使用率（使用 /proc/stat）
    local cpu_idle
    cpu_idle=$(awk '/^cpu / {print $5}' /proc/stat)
    local cpu_total
    cpu_total=$(awk '/^cpu / {sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}' /proc/stat)
    local cpu_usage
    cpu_usage=$(echo "scale=2; (1 - $cpu_idle / $cpu_total) * 100" | bc 2>/dev/null || echo "0")
    log "CPU 使用率: ${cpu_usage}%"
    
    # 内存使用率
    local memory_usage
    memory_usage=$(free | awk '/Mem/{printf "%.2f", $3/$2*100}')
    log "内存使用率: ${memory_usage}%"
    
    # 磁盘使用率
    local disk_usage
    disk_usage=$(df -h /opt/monitoring/ | awk 'NR==2{print $5}' | cut -d'%' -f1)
    log "磁盘使用率: ${disk_usage}%"
    
    # 检查阈值（使用整数比较）
    local cpu_int
    cpu_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    if [ "${cpu_int:-0}" -gt "$CPU_THRESHOLD" ]; then
        log "[WARNING] CPU 使用率过高"
    fi
    
    local mem_int
    mem_int=$(echo "$memory_usage" | cut -d'.' -f1)
    if [ "${mem_int:-0}" -gt "$MEMORY_THRESHOLD" ]; then
        log "[WARNING] 内存使用率过高"
    fi
    
    if [ "${disk_usage:-0}" -gt "$DISK_THRESHOLD" ]; then
        log "[WARNING] 磁盘使用率过高"
    fi
    
    return 0
}

# 检查 HTTP 接口
check_http() {
    log "=== 检查 HTTP 接口 ==="
    
    local urls=(
        "http://localhost:9090/-/healthy|Prometheus"
        "http://localhost:3000/api/health|Grafana"
        "http://localhost:9093/-/healthy|Alertmanager"
    )
    
    for url_info in "${urls[@]}"; do
        local url
        local name
        url=$(echo "$url_info" | cut -d'|' -f1)
        name=$(echo "$url_info" | cut -d'|' -f2)
        
        local status_code
        status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
        
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
    
    local datasources
    if ! datasources=$(curl -sf --max-time 10 http://localhost:3000/api/datasources 2>/dev/null); then
        log "[ERROR] 无法连接到 Grafana"
        return 1
    fi
    
    local datasource_count
    datasource_count=$(echo "$datasources" | jq 'length')
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
