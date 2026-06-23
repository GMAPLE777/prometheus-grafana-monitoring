#!/bin/bash
# 数据备份脚本

set -e

BACKUP_DIR="/opt/monitoring/backup/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/monitoring_backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 创建备份目录
create_backup_dir() {
    log "创建备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

# 备份 Prometheus 配置
backup_prometheus_config() {
    log "备份 Prometheus 配置..."
    
    cp -r /opt/monitoring/prometheus/prometheus.yml "$BACKUP_DIR/"
    cp -r /opt/monitoring/prometheus/rules "$BACKUP_DIR/"
    
    log "Prometheus 配置备份完成"
}

# 备份 Prometheus 数据
backup_prometheus_data() {
    log "备份 Prometheus 数据..."
    
    # 创建快照
    curl -X POST http://localhost:9090/api/v1/admin/tsdb/snapshot
    
    # 备份快照数据
    SNAPSHOT_DIR=$(ls -t /opt/monitoring/prometheus/data/snapshots/ | head -1)
    if [ -n "$SNAPSHOT_DIR" ]; then
        tar -czf "$BACKUP_DIR/prometheus_data.tar.gz" -C /opt/monitoring/prometheus/data/snapshots "$SNAPSHOT_DIR"
        log "Prometheus 数据备份完成"
    else
        log "未找到 Prometheus 快照"
    fi
}

# 备份 Alertmanager 配置
backup_alertmanager_config() {
    log "备份 Alertmanager 配置..."
    
    cp -r /opt/monitoring/alertmanager/alertmanager.yml "$BACKUP_DIR/"
    cp -r /opt/monitoring/alertmanager/templates "$BACKUP_DIR/"
    
    log "Alertmanager 配置备份完成"
}

# 备份 Alertmanager 数据
backup_alertmanager_data() {
    log "备份 Alertmanager 数据..."
    
    tar -czf "$BACKUP_DIR/alertmanager_data.tar.gz" -C /opt/monitoring alertmanager/data
    
    log "Alertmanager 数据备份完成"
}

# 备份 Grafana 配置
backup_grafana_config() {
    log "备份 Grafana 配置..."
    
    cp -r /etc/grafana "$BACKUP_DIR/"
    
    log "Grafana 配置备份完成"
}

# 备份 Grafana 数据
backup_grafana_data() {
    log "备份 Grafana 数据..."
    
    tar -czf "$BACKUP_DIR/grafana_data.tar.gz" -C /var/lib grafana
    
    log "Grafana 数据备份完成"
}

# 备份 Exporter 配置
backup_exporter_config() {
    log "备份 Exporter 配置..."
    
    cp -r /opt/monitoring/exporters/mysqld_exporter/.my.cnf "$BACKUP_DIR/"
    
    log "Exporter 配置备份完成"
}

# 备份 Systemd 服务文件
backup_systemd_services() {
    log "备份 Systemd 服务文件..."
    
    cp /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
    cp /etc/systemd/system/node_exporter.service "$BACKUP_DIR/"
    cp /etc/systemd/system/nginx_exporter.service "$BACKUP_DIR/"
    cp /etc/systemd/system/mysql_exporter.service "$BACKUP_DIR/"
    cp /etc/systemd/system/alertmanager.service "$BACKUP_DIR/"
    cp /etc/systemd/system/grafana-server.service "$BACKUP_DIR/"
    
    log "Systemd 服务文件备份完成"
}

# 压缩备份
compress_backup() {
    log "压缩备份文件..."
    
    tar -czf "$BACKUP_DIR.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
    rm -rf "$BACKUP_DIR"
    
    log "备份压缩完成: $BACKUP_DIR.tar.gz"
    log "备份大小: $(du -sh "$BACKUP_DIR.tar.gz" | awk '{print $1}')"
}

# 清理旧备份
cleanup_old_backups() {
    log "清理旧备份..."
    
    # 保留最近 30 天的备份
    find /opt/monitoring/backup/ -name "*.tar.gz" -mtime +30 -delete
    
    log "旧备份清理完成"
}

# 验证备份
verify_backup() {
    log "验证备份..."
    
    if [ -f "$BACKUP_DIR.tar.gz" ]; then
        log "[OK] 备份文件存在"
        
        # 检查备份文件大小
        local size=$(du -sh "$BACKUP_DIR.tar.gz" | awk '{print $1}')
        log "备份文件大小: $size"
        
        # 检查备份文件完整性
        if tar -tzf "$BACKUP_DIR.tar.gz" > /dev/null 2>&1; then
            log "[OK] 备份文件完整"
        else
            log "[ERROR] 备份文件损坏"
            return 1
        fi
    else
        log "[ERROR] 备份文件不存在"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    log "=========================================="
    log "开始数据备份"
    log "=========================================="
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        log "[ERROR] 请使用 root 用户运行此脚本"
        exit 1
    fi
    
    create_backup_dir
    backup_prometheus_config
    backup_prometheus_data
    backup_alertmanager_config
    backup_alertmanager_data
    backup_grafana_config
    backup_grafana_data
    backup_exporter_config
    backup_systemd_services
    compress_backup
    verify_backup
    cleanup_old_backups
    
    log "=========================================="
    log "数据备份完成"
    log "=========================================="
}

main "$@"