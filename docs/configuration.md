# 配置说明

## 1. Prometheus 配置

### 1.1 主配置文件

**文件路径**：`/opt/monitoring/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s          # 采集间隔
  evaluation_interval: 15s      # 规则评估间隔
  external_labels:              # 外部标签
    cluster: 'production'
    environment: 'ubuntu-2204'

# 告警规则文件路径
rule_files:
  - "rules/*.yml"

# 告警管理器地址
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["localhost:9093"]

# 采集任务配置
scrape_configs:
  # Prometheus 自身监控
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # 主机监控
  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.*)'
        target_label: instance
        replacement: '${1}'

  # Nginx 监控
  - job_name: "nginx_exporter"
    static_configs:
      - targets: ["localhost:9113"]

  # MySQL 监控
  - job_name: "mysql_exporter"
    static_configs:
      - targets: ["localhost:9104"]
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.*)'
        target_label: instance
        replacement: '${1}'
```

### 1.2 全局配置参数

| 参数 | 说明 | 默认值 | 建议值 |
|------|------|--------|--------|
| scrape_interval | 采集间隔 | 15s | 15s-60s |
| evaluation_interval | 规则评估间隔 | 15s | 15s-60s |
| scrape_timeout | 采集超时 | 10s | 10s |
| external_labels | 外部标签 | 无 | 根据环境配置 |

### 1.3 采集任务配置

**任务配置参数**：
```yaml
scrape_configs:
  - job_name: "任务名称"
    metrics_path: "/metrics"      # 指标路径
    scheme: "http"                # 协议
    scrape_interval: "15s"        # 采集间隔（覆盖全局）
    scrape_timeout: "10s"         # 采集超时（覆盖全局）
    static_configs:               # 静态配置
      - targets: ["host:port"]
        labels:                   # 额外标签
          key: "value"
    relabel_configs:              # 重标签配置
      - source_labels: [__address__]
        regex: '(.*)'
        target_label: instance
        replacement: '${1}'
```

### 1.4 重标签配置

**重标签配置示例**：
```yaml
relabel_configs:
  # 保留标签
  - source_labels: [__address__]
    regex: '(.*)'
    target_label: instance
    replacement: '${1}'

  # 过滤指标
  - source_labels: [__name__]
    regex: 'node_cpu_.*'
    action: keep

  # 删除标签
  - action: labeldrop
    regex: 'instance'
```

## 2. 告警规则配置

### 2.1 规则文件结构

**文件路径**：`/opt/monitoring/prometheus/rules/*.yml`

```yaml
groups:
  - name: 组名称
    rules:
      - alert: 告警名称
        expr: PromQL 表达式
        for: 持续时间
        labels:
          severity: 级别
        annotations:
          summary: "摘要"
          description: "描述"
```

### 2.2 主机告警规则

**文件路径**：`/opt/monitoring/prometheus/rules/host_rules.yml`

```yaml
groups:
  - name: host_alerts
    rules:
      # 主机宕机告警
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "实例 {{ $labels.instance }} 宕机"
          description: "{{ $labels.job }} 服务已超过1分钟不可用"

      # CPU使用率告警
      - alert: CPUHighUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "主机 {{ $labels.instance }} CPU使用率过高"
          description: "CPU 使用率已超过 85%，当前值：{{ $value | printf \"%.2f\" }}%"

      # 内存使用率告警
      - alert: MemoryHighUsage
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "主机 {{ $labels.instance }} 内存使用率过高"
          description: "内存使用率已超过 85%，当前值：{{ $value | printf \"%.2f\" }}%"

      # 磁盘使用率告警
      - alert: DiskHighUsage
        expr: 100 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"} * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "主机 {{ $labels.instance }} 磁盘使用率过高"
          description: "挂载点 {{ $labels.mountpoint }} 使用率已超过 85%"
```

### 2.3 Nginx 告警规则

**文件路径**：`/opt/monitoring/prometheus/rules/nginx_rules.yml`

```yaml
groups:
  - name: nginx_alerts
    rules:
      # Nginx 服务宕机
      - alert: NginxDown
        expr: nginx_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Nginx 服务宕机"
          description: "Nginx 服务已超过1分钟不可用"

      # 活跃连接数过高
      - alert: NginxHighConnections
        expr: nginx_connections_active > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Nginx 活跃连接数过高"
          description: "活跃连接数已超过 1000，当前值：{{ $value }}"

      # 5xx 错误率过高
      - alert: NginxHighErrorRate
        expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Nginx 5xx 错误率过高"
          description: "5xx 错误率已超过 5%，当前值：{{ $value | printf \"%.2f\" }}%"
```

### 2.4 MySQL 告警规则

**文件路径**：`/opt/monitoring/prometheus/rules/mysql_rules.yml`

```yaml
groups:
  - name: mysql_alerts
    rules:
      # MySQL 服务宕机
      - alert: MySQLDown
        expr: mysql_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MySQL 服务宕机"
          description: "MySQL 服务已超过1分钟不可用"

      # 连接数过高
      - alert: MySQLHighConnections
        expr: mysql_global_status_threads_connected > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL 连接数过高"
          description: "当前连接数已超过 100，当前值：{{ $value }}"

      # 慢查询过多
      - alert: MySQLSlowQueries
        expr: rate(mysql_global_status_slow_queries[5m]) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL 慢查询过多"
          description: "慢查询速率已超过 1/s，当前值：{{ $value | printf \"%.2f\" }}/s"

      # 主从复制延迟
      - alert: MySQLReplicationLag
        expr: mysql_slave_status_seconds_behind_master > 30
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL 主从复制延迟"
          description: "复制延迟已超过 30 秒，当前值：{{ $value }}s"
```

### 2.5 告警规则参数

| 参数 | 说明 | 示例 |
|------|------|------|
| alert | 告警名称 | InstanceDown |
| expr | PromQL 表达式 | up == 0 |
| for | 持续时间 | 1m, 5m, 1h |
| labels | 标签 | severity: critical |
| annotations | 注解 | summary, description |

### 2.6 告警级别

| 级别 | 说明 | 通知策略 |
|------|------|----------|
| critical | 紧急告警 | 立即通知，重复间隔 30m |
| warning | 警告 | 延迟通知，重复间隔 2h |
| info | 信息 | 仅记录，不通知 |

## 3. Alertmanager 配置

### 3.1 主配置文件

**文件路径**：`/opt/monitoring/alertmanager/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m
  # 钉钉机器人配置
  # 替换为实际的钉钉机器人 webhook 地址
  # dingtalk_api_url: 'https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN'

# 告警模板
templates:
  - '/opt/monitoring/alertmanager/templates/*.tmpl'

# 路由配置
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'dingtalk-webhook'
  
  routes:
    # 紧急告警（立即通知）
    - match:
        severity: critical
      receiver: 'dingtalk-webhook'
      group_wait: 5s
      repeat_interval: 30m
    
    # 警告告警（延迟通知）
    - match:
        severity: warning
      receiver: 'dingtalk-webhook'
      group_wait: 30s
      repeat_interval: 2h

# 接收器配置
receivers:
  - name: 'dingtalk-webhook'
    webhook_configs:
      - url: 'https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN'
        send_resolved: true
        http_config:
          follow_redirects: true
          enable_http2: true

# 抑制规则
inhibit_rules:
  # 当 critical 告警触发时，抑制同一实例的 warning 告警
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

### 3.2 全局配置参数

| 参数 | 说明 | 默认值 | 建议值 |
|------|------|--------|--------|
| resolve_timeout | 解析超时 | 5m | 5m |
| smtp_from | 发件人地址 | 无 | 根据配置 |
| smtp_smarthost | SMTP 服务器 | 无 | 根据配置 |
| smtp_auth_username | SMTP 用户名 | 无 | 根据配置 |
| smtp_auth_password | SMTP 密码 | 无 | 根据配置 |

### 3.3 路由配置

**路由配置参数**：
```yaml
route:
  group_by: ['标签1', '标签2']    # 分组依据
  group_wait: 10s                  # 分组等待时间
  group_interval: 10s              # 分组间隔
  repeat_interval: 1h              # 重复间隔
  receiver: '接收器名称'           # 默认接收器
  
  routes:                          # 子路由
    - match:
        severity: 'critical'
      receiver: '紧急接收器'
      group_wait: 5s
      repeat_interval: 30m
```

### 3.4 接收器配置

**Webhook 接收器**：
```yaml
receivers:
  - name: 'webhook-receiver'
    webhook_configs:
      - url: 'http://example.com/webhook'
        send_resolved: true
        http_config:
          follow_redirects: true
          enable_http2: true
```

**邮件接收器**：
```yaml
receivers:
  - name: 'email-receiver'
    email_configs:
      - to: 'receiver@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alertmanager@example.com'
        auth_password: 'password'
```

### 3.5 告警模板

**文件路径**：`/opt/monitoring/alertmanager/templates/dingtalk.tmpl`

```go
{{ define "dingtalk.default.message" }}
{{- if eq .Status "firing" }}
**[告警触发] {{ .GroupLabels.alertname }}**
**告警级别：** {{ .GroupLabels.severity }}
**告警实例：** {{ .GroupLabels.instance }}
**告警时间：** {{ .StartsAt.Format "2006-01-02 15:04:05" }}
**告警详情：**
{{ range .Alerts }}
- {{ .Annotations.summary }}
{{- if .Annotations.description }}
  详情：{{ .Annotations.description }}
{{- end }}
{{- end }}
{{- else }}
**[告警恢复] {{ .GroupLabels.alertname }}**
**告警级别：** {{ .GroupLabels.severity }}
**告警实例：** {{ .GroupLabels.instance }}
**恢复时间：** {{ .EndsAt.Format "2006-01-02 15:04:05" }}
**告警已恢复**
{{- end }}
{{ end }}
```

### 3.6 抑制规则

**抑制规则配置**：
```yaml
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

**参数说明**：
- source_match：源告警匹配条件
- target_match：目标告警匹配条件
- equal：相等标签列表

## 4. Grafana 配置

### 4.1 数据源配置

**配置文件路径**：`/etc/grafana/provisioning/datasources/prometheus.yml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: '15s'
      httpMethod: POST
```

### 4.2 大盘导入

**导入步骤**：
1. 访问 Grafana（http://服务器IP:3000）
2. 左侧菜单 → Dashboards → Import
3. 输入 Dashboard ID
4. 选择 Prometheus 数据源
5. 点击 Import

**推荐大盘 ID**：
- 主机监控：8919
- MySQL 监控：7362
- Nginx 监控：12708

### 4.3 告警配置

**Grafana 告警规则**：
1. 编辑面板 → Alert 标签
2. 创建告警规则
3. 配置阈值和通知渠道
4. 保存告警规则

### 4.4 用户管理

**用户配置**：
- 默认账号：admin
- 默认密码：admin
- 首次登录需修改密码

**权限管理**：
- 基于角色的访问控制
- 支持 LDAP、OAuth2 认证
- 组织和团队管理

## 5. Exporter 配置

### 5.1 Node Exporter 配置

**配置参数**：
```bash
/opt/monitoring/exporters/node_exporter/node_exporter \
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
```

**常用采集器**：
- cpu：CPU 使用率
- diskstats：磁盘统计
- filesystem：文件系统
- loadavg：系统负载
- meminfo：内存信息
- netdev：网络设备
- stat：系统统计
- time：时间
- uname：系统信息
- vmstat：虚拟内存统计

### 5.2 Nginx Exporter 配置

**配置参数**：
```bash
/opt/monitoring/exporters/nginx_exporter \
  -nginx.scrape-uri=http://127.0.0.1:8080/nginx_status \
  -web.listen-address=:9113
```

**Nginx stub_status 配置**：
```nginx
server {
    listen 8080;
    server_name localhost;
    
    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
```

### 5.3 MySQL Exporter 配置

**配置参数**：
```bash
/opt/monitoring/exporters/mysqld_exporter/mysqld_exporter \
  --config.my-cnf=/opt/monitoring/exporters/mysqld_exporter/.my.cnf \
  --web.listen-address=:9104 \
  --collect.global_status \
  --collect.global_variables \
  --collect.slave_status \
  --collect.info_schema.innodb_metrics \
  --collect.info_schema.processlist \
  --collect.info_schema.query_response_time \
  --collect.engine_innodb_status
```

**MySQL 配置文件**：
```ini
[client]
user=exporter
password=Exporter@123
host=localhost
port=3306
```

**常用采集器**：
- global_status：全局状态
- global_variables：全局变量
- slave_status：主从状态
- info_schema.innodb_metrics：InnoDB 指标
- info_schema.processlist：进程列表
- info_schema.query_response_time：查询响应时间
- engine_innodb_status：InnoDB 引擎状态

## 6. Systemd 服务配置

### 6.1 Prometheus 服务

**文件路径**：`/etc/systemd/system/prometheus.service`

```ini
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
```

### 6.2 Node Exporter 服务

**文件路径**：`/etc/systemd/system/node_exporter.service`

```ini
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
```

### 6.3 Nginx Exporter 服务

**文件路径**：`/etc/systemd/system/nginx_exporter.service`

```ini
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
```

### 6.4 MySQL Exporter 服务

**文件路径**：`/etc/systemd/system/mysql_exporter.service`

```ini
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
```

### 6.5 Alertmanager 服务

**文件路径**：`/etc/systemd/system/alertmanager.service`

```ini
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
```

### 6.6 Grafana 服务

**文件路径**：`/etc/systemd/system/grafana-server.service`

```ini
[Unit]
Description=Grafana instance
Documentation=http://docs.grafana.org
Wants=network-online.target
After=network-online.target
After=postgresql.service mariadb.service mysql.service

[Service]
EnvironmentFile=/etc/default/grafana-server
User=grafana
Group=grafana
Type=simple
WorkingDirectory=/usr/share/grafana
RuntimeDirectory=grafana
RuntimeDirectoryMode=0750
ExecStart=/usr/sbin/grafana-server                                                  \
                            --config=${CONF_FILE}                                   \
                            --pidfile=${PID_FILE_DIR}/grafana-server.pid            \
                            --packaging=deb                                         \
                            cfg:default.paths.logs=${LOG_DIR}                       \
                            cfg:default.paths.data=${DATA_DIR}                      \
                            cfg:default.paths.plugins=${PLUGINS_DIR}                \
                            cfg:default.paths.provisioning=${PROVISIONING_CFG_DIR}
LimitNOFILE=10000
TimeoutStopSec=20
UMask=0027
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## 7. 配置验证

### 7.1 Prometheus 配置验证

```bash
/opt/monitoring/prometheus/prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml --check
```

### 7.2 Alertmanager 配置验证

```bash
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

### 7.3 Grafana 配置验证

```bash
grafana-cli admin data-migration validate
```

### 7.4 重载配置

**Prometheus 配置重载**：
```bash
curl -X POST http://localhost:9090/-/reload
```

**Alertmanager 配置重载**：
```bash
kill -HUP $(pidof alertmanager)
```

**Grafana 配置重载**：
```bash
systemctl restart grafana-server
```

## 8. 配置备份

### 8.1 备份脚本

```bash
#!/bin/bash
# 配置备份脚本

BACKUP_DIR="/opt/monitoring/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

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

echo "配置备份完成：$BACKUP_DIR"
```

### 8.2 恢复配置

```bash
# 恢复 Prometheus 配置
cp /opt/monitoring/backup/20231201_120000/prometheus.yml /opt/monitoring/prometheus/
cp -r /opt/monitoring/backup/20231201_120000/rules /opt/monitoring/prometheus/

# 恢复 Alertmanager 配置
cp /opt/monitoring/backup/20231201_120000/alertmanager.yml /opt/monitoring/alertmanager/
cp -r /opt/monitoring/backup/20231201_120000/templates /opt/monitoring/alertmanager/

# 重启服务
systemctl restart prometheus alertmanager
```