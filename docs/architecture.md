# 架构设计文档

## 1. 整体架构

### 1.1 架构概览

本监控体系采用分层设计，从下到上分为四层：

```
┌─────────────────────────────────────────────────────────────┐
│                    可视化层 (Grafana)                        │
│    - 大盘展示                                                │
│    - 告警状态可视化                                          │
│    - 自定义 Dashboard                                        │
├─────────────────────────────────────────────────────────────┤
│                    告警层 (Alertmanager)                     │
│    - 告警规则处理                                            │
│    - 告警聚合与降噪                                          │
│    - 通知推送（钉钉/邮件/Webhook）                           │
├─────────────────────────────────────────────────────────────┤
│                    存储层 (Prometheus)                       │
│    - 指标采集（Pull 模式）                                   │
│    - 时序数据存储                                            │
│    - PromQL 查询引擎                                         │
├─────────────────────────────────────────────────────────────┤
│                    采集层 (Exporters)                        │
│    - Node Exporter（主机指标）                               │
│    - Nginx Exporter（Web 服务指标）                          │
│    - MySQL Exporter（数据库指标）                            │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 数据流

```
Exporters → Prometheus → Alertmanager → 通知渠道（钉钉）
    ↓           ↓
    ↓       Grafana ← 数据源查询
    ↓
  指标暴露    指标采集存储      告警触发      通知推送
```

### 1.3 组件关系

| 组件 | 角色 | 通信方式 | 端口 |
|------|------|----------|------|
| Node Exporter | 指标暴露 | HTTP | 9100 |
| Nginx Exporter | 指标暴露 | HTTP | 9113 |
| MySQL Exporter | 指标暴露 | HTTP | 9104 |
| Prometheus | 指标采集存储 | HTTP Pull | 9090 |
| Alertmanager | 告警处理 | HTTP | 9093 |
| Grafana | 可视化展示 | HTTP | 3000 |

## 2. 采集层设计

### 2.1 Node Exporter

**功能**：采集主机级别指标

**采集指标**：
- CPU 使用率（node_cpu_seconds_total）
- 内存使用（node_memory_*）
- 磁盘使用（node_filesystem_*）
- 网络流量（node_network_*）
- 系统负载（node_load*）
- 系统启动时间（node_boot_time）

**配置要点**：
- 监听地址：:9100
- 采集器：cpu, diskstats, filesystem, loadavg, meminfo, netdev, stat, time, uname, vmstat

### 2.2 Nginx Exporter

**功能**：采集 Nginx Web 服务指标

**采集指标**：
- 活跃连接数（nginx_connections_active）
- 接受连接数（nginx_connections_accepted）
- 处理连接数（nginx_connections_handled）
- 请求数（nginx_http_requests_total）
- 读/写/等待连接数

**前置条件**：
- 启用 Nginx stub_status 模块
- 配置状态端点：/nginx_status

### 2.3 MySQL Exporter

**功能**：采集 MySQL 数据库指标

**采集指标**：
- 全局状态（global_status）
- 全局变量（global_variables）
- 主从状态（slave_status）
- InnoDB 指标（innodb_metrics）
- 进程列表（processlist）
- 查询响应时间（query_response_time）
- InnoDB 引擎状态（engine_innodb_status）

**前置条件**：
- 创建监控专用账号
- 授予必要权限：PROCESS, REPLICATION CLIENT, SELECT

## 3. 存储层设计

### 3.1 Prometheus 配置

**核心参数**：
- 采集间隔：15s
- 评估间隔：15s
- 数据保留时间：15d
- 数据保留大小：5GB

**存储路径**：
- 配置文件：/opt/monitoring/prometheus/prometheus.yml
- 数据目录：/opt/monitoring/prometheus/data
- 规则目录：/opt/monitoring/prometheus/rules

### 3.2 采集任务配置

```yaml
scrape_configs:
  # Prometheus 自身监控
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # 主机监控
  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]

  # Nginx 监控
  - job_name: "nginx_exporter"
    static_configs:
      - targets: ["localhost:9113"]

  # MySQL 监控
  - job_name: "mysql_exporter"
    static_configs:
      - targets: ["localhost:9104"]
```

### 3.3 告警规则

**规则文件**：/opt/monitoring/prometheus/rules/*.yml

**规则分组**：
- host_alerts：主机相关告警
- nginx_alerts：Nginx 相关告警
- mysql_alerts：MySQL 相关告警

## 4. 告警层设计

### 4.1 Alertmanager 配置

**全局配置**：
- 解析超时：5m
- 钉钉 API 地址

**路由配置**：
- 分组依据：alertname, cluster, service
- 分组等待：10s
- 分组间隔：10s
- 重复间隔：1h

**接收器配置**：
- 钉钉机器人 Webhook
- 支持告警恢复通知

### 4.2 告警分级

| 级别 | 通知策略 | 重复间隔 | 示例 |
|------|----------|----------|------|
| critical | 立即通知 | 30m | 实例宕机、服务不可用 |
| warning | 延迟通知 | 2h | CPU/内存/磁盘使用率过高 |

### 4.3 告警抑制

```yaml
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

当 critical 告警触发时，自动抑制同一实例的 warning 告警。

## 5. 可视化层设计

### 5.1 Grafana 配置

**数据源**：
- 名称：Prometheus
- 类型：Prometheus
- 地址：http://localhost:9090
- 访问模式：Server (default)

**大盘设计**：
- 预置大盘：Node Exporter Full (8919)、MySQL Overview (7362)、Nginx (12708)
- 自定义大盘：告警概览、趋势分析

### 5.2 大盘分类

**主机监控大盘**：
- CPU 使用率趋势
- 内存使用率趋势
- 磁盘使用率
- 网络流量
- 系统负载

**Nginx 监控大盘**：
- 活跃连接数
- 请求速率
- 状态码分布
- 响应时间

**MySQL 监控大盘**：
- 连接数
- 查询速率
- 慢查询
- InnoDB 缓冲池
- 复制状态

## 6. 安全设计

### 6.1 访问控制

**Prometheus**：
- 默认无认证
- 可配置 Basic Auth 或 OAuth2

**Grafana**：
- 默认账号：admin/admin
- 支持 LDAP、OAuth2 认证
- 基于角色的访问控制

**Alertmanager**：
- 默认无认证
- 可配置 Basic Auth

### 6.2 网络安全

**端口规划**：
- 9090：Prometheus（内部访问）
- 3000：Grafana（可对外暴露）
- 9100：Node Exporter（内部访问）
- 9093：Alertmanager（内部访问）
- 9113：Nginx Exporter（内部访问）
- 9104：MySQL Exporter（内部访问）

**防火墙规则**：
- 仅允许必要端口
- 限制访问源 IP
- 使用 VPN 或跳板机访问

### 6.3 数据安全

**传输加密**：
- 配置 TLS/SSL
- 使用 HTTPS 访问

**存储加密**：
- 敏感配置加密存储
- 定期轮换密钥

## 7. 高可用设计

### 7.1 Prometheus 高可用

**方案一：联邦集群**
- 多个 Prometheus 实例
- 聚合查询

**方案二：远程存储**
- Thanos
- Cortex
- VictoriaMetrics

### 7.2 Alertmanager 高可用

**集群部署**：
- 多个 Alertmanager 实例
- 自动故障转移
- 告警去重

### 7.3 Grafana 高可用

**数据库共享**：
- 使用外部数据库（MySQL/PostgreSQL）
- 共享会话存储

## 8. 扩展性设计

### 8.1 新增监控目标

**添加 Exporter**：
1. 部署新的 Exporter
2. 在 prometheus.yml 中添加采集任务
3. 创建对应的告警规则
4. 导入或创建 Grafana 大盘

### 8.2 自定义告警规则

**规则语法**：
```yaml
groups:
  - name: custom_alerts
    rules:
      - alert: CustomAlert
        expr: <PromQL 表达式>
        for: <持续时间>
        labels:
          severity: <级别>
        annotations:
          summary: "<摘要>"
          description: "<描述>"
```

### 8.3 自定义 Dashboard

**创建步骤**：
1. 设计面板布局
2. 编写 PromQL 查询
3. 配置可视化选项
4. 设置告警规则（可选）

## 9. 性能优化

### 9.1 采集优化

**采集间隔**：
- 默认：15s
- 高频指标：5s
- 低频指标：60s

**指标过滤**：
- 使用 metric_relabel_configs
- 过滤不需要的指标

### 9.2 存储优化

**数据保留**：
- 时间保留：15d
- 大小保留：5GB
- 压缩策略：2h 块

**分片策略**：
- 按时间分片
- 按指标分片

### 9.3 查询优化

**Recording Rules**：
- 预计算常用查询
- 减少实时计算负载

**查询缓存**：
- 启用查询缓存
- 配置缓存大小

## 10. 监控指标说明

### 10.1 主机指标

| 指标名称 | 说明 | 单位 |
|----------|------|------|
| node_cpu_seconds_total | CPU 使用时间 | 秒 |
| node_memory_MemTotal_bytes | 总内存 | 字节 |
| node_memory_MemAvailable_bytes | 可用内存 | 字节 |
| node_filesystem_size_bytes | 文件系统总大小 | 字节 |
| node_filesystem_avail_bytes | 文件系统可用大小 | 字节 |
| node_network_receive_bytes_total | 网络接收字节数 | 字节 |
| node_network_transmit_bytes_total | 网络发送字节数 | 字节 |

### 10.2 Nginx 指标

| 指标名称 | 说明 | 单位 |
|----------|------|------|
| nginx_connections_active | 活跃连接数 | 个 |
| nginx_connections_accepted | 接受连接数 | 个 |
| nginx_connections_handled | 处理连接数 | 个 |
| nginx_http_requests_total | HTTP 请求总数 | 个 |

### 10.3 MySQL 指标

| 指标名称 | 说明 | 单位 |
|----------|------|------|
| mysql_global_status_threads_connected | 当前连接数 | 个 |
| mysql_global_status_threads_running | 运行线程数 | 个 |
| mysql_global_status_queries | 查询总数 | 个 |
| mysql_global_status_slow_queries | 慢查询数 | 个 |
| mysql_global_status_questions | 问题总数 | 个 |

## 11. 故障处理

### 11.1 常见故障

**Exporter 不可用**：
- 检查服务状态
- 检查端口监听
- 检查防火墙规则

**Prometheus 采集失败**：
- 检查 Target 状态
- 检查网络连通性
- 检查配置文件语法

**告警不触发**：
- 检查告警规则语法
- 检查评估间隔
- 检查 Alertmanager 配置

### 11.2 故障恢复

**服务重启**：
```bash
systemctl restart <service-name>
```

**配置重载**：
```bash
# Prometheus
curl -X POST http://localhost:9090/-/reload

# Alertmanager
kill -HUP $(pidof alertmanager)
```

**数据恢复**：
- 从备份恢复数据目录
- 重新创建数据目录

## 12. 性能基准

### 12.1 资源占用

| 组件 | CPU | 内存 | 磁盘 |
|------|-----|------|------|
| Prometheus | < 1 核 | < 2GB | < 10GB |
| Grafana | < 0.5 核 | < 1GB | < 1GB |
| Alertmanager | < 0.5 核 | < 512MB | < 1GB |
| Exporters | < 0.5 核 | < 512MB | < 100MB |

### 12.2 性能指标

| 指标 | 目标值 |
|------|--------|
| Prometheus 查询延迟 | < 1s |
| Grafana 大盘加载 | < 3s |
| 告警触发延迟 | < 1m |
| 数据采集成功率 | > 99.99% |
| 告警通知成功率 | > 99.9% |

## 13. 版本规划

### 13.1 当前版本

- Prometheus: v2.45.0
- Grafana: v10.0.3
- Alertmanager: v0.26.0
- Node Exporter: v1.6.1
- Nginx Exporter: v0.11.0
- MySQL Exporter: v0.15.0

### 13.2 升级策略

**滚动升级**：
1. 升级 Exporter
2. 升级 Prometheus
3. 升级 Alertmanager
4. 升级 Grafana

**回滚方案**：
- 保留旧版本二进制文件
- 备份配置文件
- 快速回滚脚本