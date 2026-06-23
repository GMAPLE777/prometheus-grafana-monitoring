# Prometheus + Grafana 全栈监控告警体系

## 项目简介

本项目构建了一个完整的生产级监控告警体系，采用 Prometheus + Grafana 技术栈，覆盖服务器基础资源、Web 服务、数据库三类核心监控对象，实现分级告警和可视化大盘展示。

## 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    可视化层 (Grafana)                        │
├─────────────────────────────────────────────────────────────┤
│                    告警层 (Alertmanager)                     │
├─────────────────────────────────────────────────────────────┤
│                    存储层 (Prometheus)                       │
├─────────────────────────────────────────────────────────────┤
│  采集层 (Node Exporter + Nginx Exporter + MySQL Exporter)   │
└─────────────────────────────────────────────────────────────┘
```

## 核心组件

| 组件 | 版本 | 用途 |
|------|------|------|
| Prometheus | v2.45.0 | 时序数据库，指标存储与查询 |
| Grafana | v10.0.3 | 可视化平台，大盘展示 |
| Alertmanager | v0.26.0 | 告警管理器，通知推送 |
| Node Exporter | v1.6.1 | 主机指标采集 |
| Nginx Exporter | v0.11.0 | Nginx 指标采集 |
| MySQL Exporter | v0.15.0 | MySQL 指标采集 |

## 功能特性

### 监控覆盖
- **主机资源监控**：CPU、内存、磁盘、网络
- **Web 服务监控**：Nginx 连接数、请求数、状态码分布
- **数据库监控**：MySQL 连接数、查询数、慢查询、InnoDB 指标

### 告警能力
- **分级告警**：critical（紧急）和 warning（警告）两级
- **告警规则**：主机宕机、CPU 过高、内存过高、磁盘空间不足
- **通知方式**：钉钉机器人 Webhook 推送
- **告警聚合**：自动分组、抑制、静默

### 可视化展示
- **预置大盘**：Node Exporter Full、MySQL Overview、Nginx
- **自定义大盘**：支持创建告警概览、趋势分析等
- **实时刷新**：支持自动刷新和手动刷新

## 快速开始

### 环境要求
- 操作系统：Ubuntu 22.04 LTS
- 硬件配置：2核4G+，磁盘 20G+
- 开放端口：9090, 3000, 9100, 9093, 9113, 9104

### 一键部署
```bash
# 克隆项目
git clone <repository-url>
cd prometheus-grafana-monitoring

# 执行部署脚本
chmod +x scripts/deploy.sh
sudo ./scripts/deploy.sh
```

### 手动部署
详细部署步骤请参考 [部署指南](docs/deployment.md)

## 访问地址

部署完成后，可通过以下地址访问：

| 服务 | 地址 | 默认账号密码 |
|------|------|--------------|
| Prometheus | http://服务器IP:9090 | 无需认证 |
| Grafana | http://服务器IP:3000 | admin/admin |
| Alertmanager | http://服务器IP:9093 | 无需认证 |

## 目录结构

```
prometheus-grafana-monitoring/
├── README.md                    # 项目说明文档
├── docs/                        # 运维文档目录
│   ├── architecture.md         # 架构设计文档
│   ├── deployment.md           # 部署指南
│   ├── configuration.md        # 配置说明
│   ├── troubleshooting.md      # 故障排查指南
│   └── maintenance.md          # 日常维护手册
├── scripts/                     # 自动化脚本
│   ├── deploy.sh               # 一键部署脚本
│   ├── monitor.sh              # 监控检查脚本
│   └── backup.sh               # 数据备份脚本
├── config/                      # 配置文件目录
│   ├── prometheus/             # Prometheus 配置
│   │   ├── prometheus.yml      # 主配置文件
│   │   └── rules/              # 告警规则
│   │       ├── host_rules.yml  # 主机告警规则
│   │       ├── nginx_rules.yml # Nginx 告警规则
│   │       └── mysql_rules.yml # MySQL 告警规则
│   ├── alertmanager/           # Alertmanager 配置
│   │   ├── alertmanager.yml    # 主配置文件
│   │   └── templates/          # 告警模板
│   │       └── dingtalk.tmpl   # 钉钉告警模板
│   └── grafana/                # Grafana 配置
│       └── provisioning/       # 自动化配置
│           └── datasources/    # 数据源配置
│               └── prometheus.yml
└── docker-compose.yml          # Docker 部署方案（可选）
```

## 常用命令

### 服务管理
```bash
# 启动所有服务
systemctl start prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 停止所有服务
systemctl stop prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 重启所有服务
systemctl restart prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server

# 查看服务状态
systemctl status prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server
```

### 监控检查
```bash
# 执行健康检查
./scripts/monitor.sh

# 检查 Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'

# 检查告警状态
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {alertname: .labels.alertname, state: .state}'
```

### 配置验证
```bash
# 验证 Prometheus 配置
/opt/monitoring/prometheus/prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml --check

# 验证 Alertmanager 配置
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

## 告警规则说明

### 主机告警规则
- **InstanceDown**：实例宕机超过 1 分钟（critical）
- **CPUHighUsage**：CPU 使用率超过 85% 持续 5 分钟（warning）
- **MemoryHighUsage**：内存使用率超过 85% 持续 5 分钟（warning）
- **DiskHighUsage**：磁盘使用率超过 85% 持续 5 分钟（warning）

### Nginx 告警规则
- **NginxDown**：Nginx 服务宕机（critical）
- **NginxHighConnections**：活跃连接数过高（warning）
- **NginxHighErrorRate**：5xx 错误率过高（warning）

### MySQL 告警规则
- **MySQLDown**：MySQL 服务宕机（critical）
- **MySQLHighConnections**：连接数过高（warning）
- **MySQLSlowQueries**：慢查询过多（warning）
- **MySQLReplicationLag**：主从复制延迟过高（warning）

## Grafana 大盘

### 预置大盘 ID
- **主机监控**：8919（Node Exporter Full）
- **MySQL 监控**：7362（MySQL Overview）
- **Nginx 监控**：12708（Nginx）

### 导入大盘
1. 访问 Grafana（http://服务器IP:3000）
2. 左侧菜单 → Dashboards → Import
3. 输入 Dashboard ID
4. 选择 Prometheus 数据源
5. 点击 Import

## 故障排查

常见问题及解决方案请参考 [故障排查指南](docs/troubleshooting.md)

## 日常维护

日常维护操作请参考 [维护手册](docs/maintenance.md)

## 贡献指南

欢迎提交 Issue 和 Pull Request

## 许可证

MIT License

## 联系方式

如有问题，请提交 Issue 或联系项目维护者