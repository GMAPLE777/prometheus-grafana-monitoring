# 故障排查指南

## 1. 服务启动故障

### 1.1 Prometheus 启动失败

**症状**：
- 服务无法启动
- 启动后立即退出
- 日志显示配置错误

**排查步骤**：

1. **检查服务状态**
```bash
systemctl status prometheus
journalctl -u prometheus -f
```

2. **检查配置文件语法**
```bash
/opt/monitoring/prometheus/prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml --check
```

3. **检查端口占用**
```bash
ss -tlnp | grep :9090
```

4. **检查文件权限**
```bash
ls -la /opt/monitoring/prometheus/
ls -la /opt/monitoring/prometheus/data/
```

5. **检查磁盘空间**
```bash
df -h /opt/monitoring/
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 配置文件语法错误 | 使用 --check 验证配置，修复语法错误 |
| 端口被占用 | 杀死占用进程或修改监听端口 |
| 权限不足 | 修改文件权限或使用 root 用户 |
| 磁盘空间不足 | 清理磁盘空间或扩展磁盘 |
| 数据目录损坏 | 删除数据目录重新创建 |

### 1.2 Node Exporter 启动失败

**症状**：
- 服务无法启动
- 指标无法采集

**排查步骤**：

1. **检查服务状态**
```bash
systemctl status node_exporter
journalctl -u node_exporter -f
```

2. **检查端口占用**
```bash
ss -tlnp | grep :9100
```

3. **测试指标采集**
```bash
curl http://localhost:9100/metrics
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 端口被占用 | 杀死占用进程或修改监听端口 |
| 二进制文件损坏 | 重新下载安装 |
| 权限不足 | 使用 root 用户启动 |

### 1.3 Nginx Exporter 启动失败

**症状**：
- 服务无法启动
- Nginx 指标无法采集

**排查步骤**：

1. **检查服务状态**
```bash
systemctl status nginx_exporter
journalctl -u nginx_exporter -f
```

2. **检查 Nginx stub_status**
```bash
curl http://localhost:8080/nginx_status
```

3. **检查 Nginx 配置**
```bash
nginx -t
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| Nginx 未启用 stub_status | 配置 stub_status 端点 |
| Nginx 服务未启动 | 启动 Nginx 服务 |
| 端口配置错误 | 检查 Nginx 和 Exporter 端口配置 |

### 1.4 MySQL Exporter 启动失败

**症状**：
- 服务无法启动
- MySQL 指标无法采集

**排查步骤**：

1. **检查服务状态**
```bash
systemctl status mysql_exporter
journalctl -u mysql_exporter -f
```

2. **检查 MySQL 连接**
```bash
mysql -u exporter -p'Exporter@123' -h localhost -e "SELECT 1"
```

3. **检查配置文件**
```bash
cat /opt/monitoring/exporters/mysqld_exporter/.my.cnf
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| MySQL 服务未启动 | 启动 MySQL 服务 |
| 监控账号不存在 | 创建监控账号并授权 |
| 密码错误 | 检查配置文件中的密码 |
| 权限不足 | 授予必要权限 |

### 1.5 Alertmanager 启动失败

**症状**：
- 服务无法启动
- 告警无法发送

**排查步骤**：

1. **检查服务状态**
```bash
systemctl status alertmanager
journalctl -u alertmanager -f
```

2. **检查配置文件语法**
```bash
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

3. **检查端口占用**
```bash
ss -tlnp | grep :9093
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 配置文件语法错误 | 使用 amtool 验证配置，修复语法错误 |
| 端口被占用 | 杀死占用进程或修改监听端口 |
| 钉钉 Webhook 配置错误 | 检查 Webhook 地址和 token |

### 1.6 Grafana 启动失败

**症状**：
- 服务无法启动
- Web UI 无法访问

**排查步骤**：

1. **检查服务状态**
```bash
systemctl status grafana-server
journalctl -u grafana-server -f
```

2. **检查端口占用**
```bash
ss -tlnp | grep :3000
```

3. **检查日志**
```bash
tail -f /var/log/grafana/grafana.log
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 端口被占用 | 杀死占用进程或修改监听端口 |
| 数据库连接失败 | 检查数据库配置 |
| 权限不足 | 修改文件权限 |

## 2. 采集故障

### 2.1 Prometheus Target 状态为 DOWN

**症状**：
- Prometheus Web UI 中 Target 状态显示 DOWN
- 指标无法采集

**排查步骤**：

1. **检查 Target 状态**
```bash
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health, lastError: .lastError}'
```

2. **检查 Exporter 服务状态**
```bash
systemctl status node_exporter nginx_exporter mysql_exporter
```

3. **测试 Exporter 端点**
```bash
curl http://localhost:9100/metrics
curl http://localhost:9113/metrics
curl http://localhost:9104/metrics
```

4. **检查网络连通性**
```bash
telnet localhost 9100
telnet localhost 9113
telnet localhost 9104
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| Exporter 服务未启动 | 启动 Exporter 服务 |
| 端口监听异常 | 检查端口配置和防火墙规则 |
| 网络不通 | 检查网络配置和防火墙规则 |
| 配置文件错误 | 检查 Prometheus 配置文件中的 Target 地址 |

### 2.2 指标数据缺失

**症状**：
- Grafana 大盘显示 No data
- PromQL 查询无结果

**排查步骤**：

1. **检查指标是否存在**
```bash
curl http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep node_cpu
```

2. **执行 PromQL 查询**
```bash
curl 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total'
```

3. **检查采集时间**
```bash
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, lastScrape: .lastScrape}'
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| Exporter 未正确暴露指标 | 检查 Exporter 配置和采集器 |
| 采集间隔过长 | 调整 scrape_interval 配置 |
| 指标名称错误 | 检查 PromQL 查询中的指标名称 |
| 标签不匹配 | 检查标签过滤条件 |

### 2.3 采集延迟

**症状**：
- 指标数据更新延迟
- 告警触发不及时

**排查步骤**：

1. **检查采集时间戳**
```bash
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, lastScrape: .lastScrape, scrapeDuration: .scrapeDuration}'
```

2. **检查 Prometheus 负载**
```bash
curl 'http://localhost:9090/api/v1/query?query=prometheus_engine_query_duration_seconds'
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 采集间隔过短 | 增加 scrape_interval |
| Exporter 响应慢 | 优化 Exporter 性能 |
| Prometheus 负载高 | 优化查询或增加资源 |

## 3. 告警故障

### 3.1 告警不触发

**症状**：
- 满足条件但告警未触发
- Prometheus 告警页面无告警

**排查步骤**：

1. **检查告警规则状态**
```bash
curl http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name: .name, state: .state, lastEvaluation: .lastEvaluation}'
```

2. **检查告警规则语法**
```bash
/opt/monitoring/prometheus/prometheus --config.file=/opt/monitoring/prometheus/prometheus.yml --check
```

3. **测试 PromQL 表达式**
```bash
curl 'http://localhost:9090/api/v1/query?query=up == 0'
```

4. **检查评估间隔**
```bash
curl http://localhost:9090/api/v1/status/config | jq '.data.yaml' | grep evaluation_interval
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| PromQL 表达式错误 | 验证 PromQL 语法和逻辑 |
| 持续时间不足 | 调整 for 参数 |
| 评估间隔过长 | 调整 evaluation_interval |
| 标签不匹配 | 检查标签过滤条件 |

### 3.2 告警通知失败

**症状**：
- 告警触发但未收到通知
- Alertmanager 显示告警但未发送

**排查步骤**：

1. **检查 Alertmanager 告警状态**
```bash
curl http://localhost:9093/api/v2/alerts
```

2. **检查 Alertmanager 日志**
```bash
journalctl -u alertmanager -f
```

3. **检查配置文件**
```bash
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

4. **测试 Webhook 连通性**
```bash
curl -X POST "https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msgtype":"text","text":{"content":"测试消息"}}'
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| Webhook 地址错误 | 检查 Webhook URL 和 token |
| 网络不通 | 检查网络连通性和防火墙规则 |
| 消息格式错误 | 检查告警模板配置 |
| 钉钉安全设置 | 检查钉钉机器人安全设置 |

### 3.3 告警风暴

**症状**：
- 收到大量重复告警
- 通知频率过高

**排查步骤**：

1. **检查活跃告警数量**
```bash
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts | length'
```

2. **检查告警分组配置**
```bash
cat /opt/monitoring/alertmanager/alertmanager.yml | grep -A 10 "group_by"
```

3. **检查抑制规则**
```bash
cat /opt/monitoring/alertmanager/alertmanager.yml | grep -A 10 "inhibit_rules"
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 告警规则过于敏感 | 调整告警阈值和持续时间 |
| 分组配置不当 | 优化 group_by 配置 |
| 缺少抑制规则 | 配置 inhibit_rules |
| 重复间隔过短 | 增加 repeat_interval |

### 3.4 告警恢复通知失败

**症状**：
- 问题解决后未收到恢复通知
- 告警状态未更新

**排查步骤**：

1. **检查告警状态**
```bash
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state: .state}'
```

2. **检查 Alertmanager 配置**
```bash
cat /opt/monitoring/alertmanager/alertmanager.yml | grep "send_resolved"
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| send_resolved 未配置 | 设置 send_resolved: true |
| 恢复条件未满足 | 检查告警规则的恢复逻辑 |

## 4. Grafana 故障

### 4.1 数据源连接失败

**症状**：
- 数据源测试失败
- 大盘显示 No data

**排查步骤**：

1. **检查 Prometheus 服务状态**
```bash
systemctl status prometheus
curl http://localhost:9090/-/healthy
```

2. **检查数据源配置**
- 访问 Grafana → Connections → Data sources
- 检查 URL 配置是否正确

3. **测试网络连通性**
```bash
curl http://localhost:9090/api/v1/status/config
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| Prometheus 服务未启动 | 启动 Prometheus 服务 |
| URL 配置错误 | 检查数据源 URL 配置 |
| 网络不通 | 检查网络连通性 |
| 认证失败 | 检查认证配置 |

### 4.2 大盘无数据

**症状**：
- 大盘图表显示 No data
- 查询无结果

**排查步骤**：

1. **检查数据源连接**
- 访问 Grafana → Connections → Data sources
- 测试数据源连接

2. **检查查询语句**
- 编辑面板 → Query 标签
- 检查 PromQL 语法

3. **检查时间范围**
- 检查右上角时间范围设置
- 确认数据时间范围

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 数据源连接失败 | 修复数据源连接 |
| PromQL 语法错误 | 修正查询语句 |
| 时间范围不匹配 | 调整时间范围 |
| 指标不存在 | 检查指标名称和标签 |

### 4.3 大盘加载缓慢

**症状**：
- 大盘加载时间过长
- 页面响应缓慢

**排查步骤**：

1. **检查浏览器控制台**
- 按 F12 打开开发者工具
- 查看 Console 和 Network 标签

2. **检查查询性能**
- 简化查询语句
- 减少查询时间范围

3. **检查 Prometheus 负载**
```bash
curl 'http://localhost:9090/api/v1/query?query=prometheus_engine_query_duration_seconds'
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 查询语句复杂 | 优化 PromQL 查询 |
| 数据量过大 | 缩小时间范围或使用 Recording Rules |
| 网络延迟 | 优化网络配置 |
| 浏览器缓存 | 清除浏览器缓存 |

## 5. 性能故障

### 5.1 Prometheus 内存占用过高

**症状**：
- Prometheus 内存使用率持续增长
- 系统响应缓慢

**排查步骤**：

1. **检查内存使用情况**
```bash
free -h
ps aux | grep prometheus
```

2. **检查数据保留配置**
```bash
curl http://localhost:9090/api/v1/status/config | jq '.data.yaml' | grep retention
```

3. **检查存储使用情况**
```bash
du -sh /opt/monitoring/prometheus/data/
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 数据保留时间过长 | 调整 storage.tsdb.retention.time |
| 数据量过大 | 减少采集指标或增加采集间隔 |
| 内存泄漏 | 升级 Prometheus 版本 |

### 5.2 Prometheus 查询超时

**症状**：
- 查询响应缓慢
- 查询超时

**排查步骤**：

1. **检查查询语句**
- 简化 PromQL 查询
- 减少时间范围

2. **检查 Recording Rules**
```bash
curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | contains("recording"))'
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 查询语句复杂 | 优化 PromQL 查询 |
| 数据量过大 | 使用 Recording Rules 预计算 |
| 资源不足 | 增加 CPU 和内存资源 |

### 5.3 磁盘空间不足

**症状**：
- 磁盘使用率过高
- 服务无法写入数据

**排查步骤**：

1. **检查磁盘使用情况**
```bash
df -h
du -sh /opt/monitoring/*
```

2. **检查数据保留策略**
```bash
curl http://localhost:9090/api/v1/status/config | jq '.data.yaml' | grep retention
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 数据保留时间过长 | 调整 storage.tsdb.retention.time |
| 数据量过大 | 减少采集指标或增加采集间隔 |
| 日志文件过大 | 清理或轮转日志文件 |

## 6. 网络故障

### 6.1 端口不通

**症状**：
- 无法访问服务端口
- 连接超时

**排查步骤**：

1. **检查端口监听状态**
```bash
ss -tlnp | grep :9090
ss -tlnp | grep :3000
ss -tlnp | grep :9100
```

2. **检查防火墙规则**
```bash
iptables -L -n
ufw status
```

3. **测试端口连通性**
```bash
telnet localhost 9090
curl http://localhost:9090/-/healthy
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| 服务未启动 | 启动对应服务 |
| 端口配置错误 | 检查服务端口配置 |
| 防火墙阻止 | 配置防火墙规则允许端口 |

### 6.2 DNS 解析失败

**症状**：
- 无法解析主机名
- 连接超时

**排查步骤**：

1. **检查 DNS 配置**
```bash
cat /etc/resolv.conf
nslookup localhost
```

2. **测试 DNS 解析**
```bash
ping localhost
```

**常见原因及解决方案**：

| 原因 | 解决方案 |
|------|----------|
| DNS 配置错误 | 检查 /etc/resolv.conf 配置 |
| DNS 服务器不可用 | 更换 DNS 服务器 |

## 7. 日志分析

### 7.1 Prometheus 日志

**日志位置**：
```bash
journalctl -u prometheus -f
```

**关键日志信息**：
- 配置加载信息
- 采集错误信息
- 规则评估信息

**日志分析示例**：
```bash
# 查看错误日志
journalctl -u prometheus | grep -i error

# 查看告警日志
journalctl -u prometheus | grep -i alert

# 查看采集日志
journalctl -u prometheus | grep -i scrape
```

### 7.2 Alertmanager 日志

**日志位置**：
```bash
journalctl -u alertmanager -f
```

**关键日志信息**：
- 告警接收信息
- 通知发送信息
- 配置加载信息

**日志分析示例**：
```bash
# 查看告警日志
journalctl -u alertmanager | grep -i alert

# 查看通知日志
journalctl -u alertmanager | grep -i notify

# 查看错误日志
journalctl -u alertmanager | grep -i error
```

### 7.3 Grafana 日志

**日志位置**：
```bash
tail -f /var/log/grafana/grafana.log
journalctl -u grafana-server -f
```

**关键日志信息**：
- 请求日志
- 错误日志
- 认证日志

**日志分析示例**：
```bash
# 查看错误日志
tail -f /var/log/grafana/grafana.log | grep -i error

# 查看请求日志
tail -f /var/log/grafana/grafana.log | grep -i request

# 查看认证日志
tail -f /var/log/grafana/grafana.log | grep -i auth
```

## 8. 故障恢复

### 8.1 服务重启

**重启所有服务**：
```bash
systemctl restart prometheus node_exporter nginx_exporter mysql_exporter alertmanager grafana-server
```

**重启单个服务**：
```bash
systemctl restart prometheus
systemctl restart node_exporter
systemctl restart nginx_exporter
systemctl restart mysql_exporter
systemctl restart alertmanager
systemctl restart grafana-server
```

### 8.2 配置重载

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

### 8.3 数据恢复

**从备份恢复数据**：
```bash
# 停止服务
systemctl stop prometheus

# 恢复数据
cp -r /opt/monitoring/backup/20231201_120000/data/* /opt/monitoring/prometheus/data/

# 启动服务
systemctl start prometheus
```

**重新创建数据目录**：
```bash
# 停止服务
systemctl stop prometheus

# 删除数据目录
rm -rf /opt/monitoring/prometheus/data/*

# 启动服务
systemctl start prometheus
```

## 9. 预防措施

### 9.1 定期检查

**每日检查**：
- 服务状态检查
- 磁盘空间检查
- 告警状态检查

**每周检查**：
- 性能指标分析
- 日志分析
- 配置备份

**每月检查**：
- 安全更新
- 性能优化
- 容量规划

### 9.2 监控告警

**系统监控**：
- CPU、内存、磁盘使用率
- 网络流量
- 服务状态

**应用监控**：
- Prometheus 采集延迟
- Grafana 响应时间
- 告警通知成功率

### 9.3 备份策略

**配置备份**：
- 每日备份配置文件
- 定期备份 Grafana 大盘

**数据备份**：
- 定期备份 Prometheus 数据
- 备份 Alertmanager 数据

## 10. 故障报告模板

### 10.1 故障描述

```
故障标题：[服务名称] [故障现象]
故障时间：YYYY-MM-DD HH:MM:SS
影响范围：[受影响的服务和用户]
故障等级：[P0/P1/P2/P3]
```

### 10.2 故障排查

```
排查步骤：
1. 检查服务状态
2. 检查日志信息
3. 检查配置文件
4. 检查网络连通性
5. 检查资源使用情况

排查结果：
[详细描述排查过程和发现]
```

### 10.3 故障原因

```
根本原因：
[详细描述故障的根本原因]

触发条件：
[描述触发故障的条件]
```

### 10.4 解决方案

```
临时解决方案：
[描述临时解决方案]

永久解决方案：
[描述永久解决方案]

预防措施：
[描述预防类似故障的措施]
```

### 10.5 经验总结

```
经验教训：
[总结故障处理的经验教训]

改进建议：
[提出改进建议]
```