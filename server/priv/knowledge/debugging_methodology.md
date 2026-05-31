---
id: "debugging_methodology"
category: "methodology"
domain: "software"
title: "调试方法论：5 Whys 定位根因"
tags: ["debugging", "troubleshooting", "problem_solving"]
applicable_intents: ["debugging", "error_analysis", "all"]
version: "1.0"
principles:
  - "不要猜测，用证据说话"
  - "5 Whys：连续问 5 次为什么找到根因"
  - "最小化复现：创建最小的复现用例"
  - "二分法：不断缩小问题范围"
  - "对比法：对比工作和不工作的环境"
examples: |
  **场景**: "网站响应慢"

  ❌ 浅层方法：
  - "加缓存吧"
  - "升级服务器"

  ✅ 5 Whys 方法：
  1. 为什么慢？→ 数据库查询慢（2.5秒）
  2. 为什么查询慢？→ 没有索引
  3. 为什么没有索引？→ 这是一个新字段
  4. 为什么新字段没有索引？→ 没有索引审查流程
  5. 为什么没有审查流程？→ 缺乏数据库设计规范

  **根本解决方案**：建立数据库设计规范，而不是简单加索引。
---

## 5 Whys 方法

### 什么是 5 Whys？

连续问 5 次"为什么"，深入挖掘问题的根本原因，而不是停留在表面症状。

### 实施步骤

#### 第一步：定义问题
```
问题：用户登录失败
```

#### 第二步：连续问为什么

**Why 1**: 为什么登录失败？
→ 返回 401 Unauthorized

**Why 2**: 为什么返回 401？
→ JWT token 验证失败

**Why 3**: 为什么验证失败？
→ token 中的签名与 secret 不匹配

**Why 4**: 为什么 secret 不匹配？
→ 配置文件中的 secret 和代码中硬编码的不一样

**Why 5**: 为什么会有两个 secret？
→ 开发时临时改了配置，忘记改回去

**根本原因**：缺乏配置管理流程，允许硬编码

#### 第三步：解决根本原因
```
❌ 治标：统一 secret 值
✅ 治本：
  1. 移除所有硬编码的 secret
  2. 建立配置管理流程
  3. 添加 CI 检查防止硬编码
```

### 关键原则

1. **基于证据，不是猜测**
   - ❌ "可能是缓存问题"
   - ✅ "日志显示 token 验证失败"

2. **直到可行动的原因才停止**
   - ❌ 停在"配置错了"
   - ✅ 继续"为什么配置会错？"

3. **每次回答都要可验证**
   - ❌ "应该是这样"
   - ✅ "查看日志，确认是..."

## 最小化复现

### 为什么需要最小复现？

- 大型系统复杂，难以调试
- 小用例容易定位问题
- 可以快速验证修复

### 如何创建最小复现

#### 1. 剥离无关代码
```python
# ❌ 复杂场景（1000 行代码）
class UserAuth:
    # ... 大量代码 ...
    def login(self):
        # ... 复杂逻辑 ...
        return result

# ✅ 最小复现（10 行代码）
def test_jwt_verify():
    token = "eyJ..."  # 失败的 token
    secret = "my_secret"
    result = jwt.verify(token, secret)
    assert result == True  # 失败
```

#### 2. 固定输入
```python
# ❌ 变量输入
user_input = input()

# ✅ 固定输入
user_input = "test@example.com"  # 总是相同的输入
```

#### 3. 独立运行
```bash
# ❌ 需要完整系统
curl http://localhost:8080/api/login

# ✅ 独立脚本
python test_jwt_verify.py  # 只需要 Python 和 JWT 库
```

## 二分法

### 原理

不断将问题范围缩小一半，直到定位问题。

### 实施示例

#### 场景：页面加载慢

```
1. 哪一部分慢？
   - 测量：网络传输 0.5s，服务器处理 2.5s
   → 服务器慢

2. 服务器哪一部分慢？
   - 测量：数据库 2.3s，其他 0.2s
   → 数据库慢

3. 数据库哪个查询慢？
   - 测量：用户查询 2.1s，其他 0.2s
   → 用户查询慢

4. 查询哪一部分慢？
   - EXPLAIN：扫描 100 万行
   → 缺少索引

5. 定位问题：缺少索引
```

### 代码层面的二分法

```python
# ❌ 不知道问题在哪
def complex_function():
    # 100 行代码
    pass

# ✅ 逐步注释缩小范围
def debug_complex_function():
    # 注释前 50 行 → 还是慢？
    # 是 → 问题在后 50 行
    # 否 → 问题在前 50 行

    # 重复直到定位问题
```

## 对比法

### 原理

对比工作和不工作的环境，找出差异。

### 实施示例

#### 场景：测试环境正常，生产环境失败

| 维度 | 测试环境 | 生产环境 |
|------|---------|---------|
| 数据 | 测试数据（100 条） | 生产数据（100 万条） |
| 配置 | DEBUG=False | DEBUG=False |
| 版本 | v1.2.3 | v1.2.3 |
| 服务器 | 4 核 8G | 2 核 4G |
| **差异** | 数据量小 | **数据量大** |

**结论**：可能是数据量导致的问题

#### 验证假设
```bash
# 在测试环境模拟大数据量
# 导入 100 万条测试数据
python import_large_data.py

# 再次测试
python test.py

# 问题复现！→ 确认是数据量问题
```

## 调试工具箱

### 日志
```bash
# 查看实时日志
tail -f /var/log/app/error.log

# 搜索错误
grep "ERROR" /var/log/app/error.log

# 查看上下文
grep -A 5 -B 5 "ERROR" /var/log/app/error.log
```

### 堆栈跟踪
```python
# Python
import traceback
traceback.print_exc()

# Elixir
Process.info(self(), :current_stacktrace)
```

### 性能分析
```bash
# Python
cProfile -s cumulative script.py

# Elixir
:fprof.apply(fn -> work() end)
```

### 网络抓包
```bash
# 查看请求
tcpdump -i any port 80

# HTTP 流量
ngrep -W byline port 80
```

## 常见陷阱

### ❌ 猜测而非验证
```
"可能是网络问题"（没有检查）
→ 应该先 ping，检查网络延迟
```

### ❌ 治标不治本
```
"重启就好了"（问题会再次出现）
→ 应该找到为什么崩溃
```

### ❌ 复杂化问题
```
"可能是多个因素综合作用"（放弃分析）
→ 应该用二分法逐步缩小
```

### ❌ 依赖运气
```
"试试这个配置"（盲目尝试）
→ 应该基于证据假设
```

## 正确流程

```
1. 观察症状
   ↓
2. 收集证据（日志、指标、堆栈）
   ↓
3. 提出假设（基于证据）
   ↓
4. 设计实验验证假设
   ↓
5. 如果假设错误，回到 3
   ↓
6. 如果假设正确，找到根因（5 Whys）
   ↓
7. 修复根因
   ↓
8. 验证修复（测试、监控）
   ↓
9. 总结教训（文档化）
```

记住：**调试是科学，不是魔法**。
