---
id: "scientific_method"
category: "scientific"
domain: "general"
title: "科学方法：观察→假设→验证→结论"
tags: ["debugging", "research", "analysis", "all"]
applicable_intents: ["debugging", "investigation", "research", "all"]
version: "1.0"
principles:
  - "观察：收集客观数据和事实"
  - "假设：提出解释所有观察的理论"
  - "预测：如果假设正确，应该看到什么？"
  - "测试：使用工具验证预测"
  - "验证：通过独立方法确认结果"
  - "结论：基于证据陈述发现"
examples: |
  **场景**: "用户报告登录失败"

  ❌ 错误方法：
  - "可能是 token 过期了，刷新试试"
  - "可能是数据库问题，重启一下"

  ✅ 科学方法：
  1. **观察**: 收集日志、错误码、复现步骤
  2. **假设**: "可能是 JWT 验证失败，因为 secret 不匹配"
  3. **预测**: "如果检查日志，应该看到 'signature verification failed'"
  4. **测试**: 查看日志，确认预测
  5. **验证**: 检查配置文件中的 secret
  6. **结论**: "确认是 JWT secret 不匹配，修复方法：..."
---

## 核心方法

### 1. 观察（Observe）

收集客观数据，不带偏见：
- 错误日志
- 堆栈跟踪
- 用户报告的复现步骤
- 系统状态（CPU、内存、网络）
- 时间线（什么时候发生的？）

### 2. 假设（Hypothesize）

提出一个**能解释所有观察**的理论：
- ❌ "可能是缓存问题"（太模糊）
- ✅ "Redis 连接池耗尽，导致新请求超时"（具体、可验证）

### 3. 预测（Predict）

如果假设正确，**应该看到什么**？
- 如果是 Redis 连接池耗尽 → 应该看到 "connection timeout" 错误
- 如果检查 Redis 指标 → 应该看到 `used_connections > max_connections`

### 4. 测试（Test）

使用工具验证预测：
```bash
# 检查 Redis 连接数
redis-cli info clients | grep connected_clients

# 查看应用日志
grep "connection timeout" /var/log/app/error.log

# 测试连接
redis-cli ping
```

### 5. 验证（Verify）

通过**独立方法**确认：
- 如果预测 A 正确，那么 B 也应该正确
- 交叉验证：用不同工具得到相同结论
- 修复后验证：问题真的解决了吗？

### 6. 结论（Conclude）

基于证据陈述发现：
- ✅ "确认是 Redis 连接池配置过低。证据：日志显示超时、Redis 指标显示连接数满、调整配置后问题消失。"
- ❌ "可能是配置问题，我调高了就好了"（没有验证）

## 关键原则

**在得出结论之前，主动尝试推翻你自己的假设。**

如果找不到推翻假设的证据，才接受假设为真。

## 应用场景

- **Bug 调试**: 从错误症状出发，反向追踪根因
- **性能分析**: 测量→假设→优化→验证
- **架构决策**: 评估选项→原型→验证→选择
- **安全审计**: 寻找漏洞→验证利用→确认风险
