---
id: "engineering_verification"
category: "engineering"
domain: "software"
title: "工程验证协议：确认优于假设"
tags: ["development", "testing", "quality", "code"]
applicable_intents: ["code_change", "refactoring", "implementation", "all"]
version: "1.0"
principles:
  - "验证优于猜测：读取文件确认，而不是假设修改成功"
  - "测试优于假设：运行测试验证，而不是假设代码正确"
  - "测量优于猜测：性能优化前先测量"
  - "小步提交：频繁提交，每个变更都经过验证"
  - "可逆性优先：默认不执行破坏性操作"
examples: |
  **场景**: "修复用户登录 Bug"

  ❌ 错误方法：
  ```
  "我改了代码，应该修复了"
  ```

  ✅ 工程验证：
  1. 修改代码
  2. **读取文件确认修改** (Read tool)
  3. **编译检查** (mix compile)
  4. **运行相关测试** (mix test test/auth_test.exs)
  5. **本地验证** (手动测试登录流程)
  6. **才声称完成**
---

## 强制验证协议

### 代码修改后

每个代码修改后**必须**执行以下步骤：

#### 1. 读取文件确认
```bash
# 验证修改确实写入
Read: /path/to/file

# 检查特定行
Line: 100-120
```

#### 2. 编译检查
```bash
# Elixir
mix compile

# Python
python -m py_compile file.py

# Node
npm run build
```

#### 3. 运行测试
```bash
# 运行所有测试
mix test

# 运行特定测试
mix test test/auth_test.exs

# 运行相关的测试文件
mix test test/models/ test/controllers/
```

#### 4. 检查错误
```bash
# 检查是否有编译警告
mix compile 2>&1 | grep -i warning

# 检查是否有测试失败
mix test | grep -i "failure\|error"
```

#### 5. 只有全部通过才声称完成
```
✅ 编译通过（0 warnings）
✅ 测试通过（10/10 passed）
✅ 文件已确认修改
✅ 本地验证成功
→ 可以声称完成
```

### Shell 命令后

每个 shell 命令执行后**必须**验证：

#### 1. 检查退出码
```bash
# 应该是 0
echo $?
```

#### 2. 检查输出中无错误
```bash
# 检查错误关键词
command 2>&1 | grep -i "error\|failed"

# 如果有输出，说明有问题
```

#### 3. 验证预期结果
```bash
# 检查文件是否存在
ls -la expected_output

# 检查进程是否运行
ps aux | grep process_name

# 检查服务是否启动
systemctl status service_name
```

#### 4. 记录结果
```
✅ 退出码: 0
✅ 无错误输出
✅ 文件已创建
✅ 服务已启动
→ 命令执行成功
```

### 数据库操作后

#### 1. 验证记录
```sql
-- 检查记录是否插入
SELECT * FROM users WHERE id = 123;

-- 检查记录是否更新
SELECT updated_at FROM users WHERE id = 123;

-- 检查记录是否删除
SELECT COUNT(*) FROM users WHERE id = 123;
```

#### 2. 检查约束
```sql
-- 检查外键约束
SELECT * FROM orders WHERE user_id NOT IN (SELECT id FROM users);

-- 检查唯一性约束
SELECT email, COUNT(*) FROM users GROUP BY email HAVING COUNT(*) > 1;
```

#### 3. 回滚测试
```sql
-- 如果操作失败，验证可以回滚
ROLLBACK;
-- 检查数据是否恢复
```

## 验证检查清单

### 代码变更
- [ ] 文件已确认修改（Read 工具）
- [ ] 编译通过（0 warnings）
- [ ] 测试通过（100% pass rate）
- [ ] 代码审查通过
- [ ] 文档已更新

### 配置变更
- [ ] 配置文件已验证
- [ ] 服务已重启
- [ ] 功能已测试
- [ ] 监控正常

### 数据库变更
- [ ] Migration 已执行
- [ ] 数据已验证
- [ ] 回滚脚本已准备
- [ ] 性能已测试

### 部署变更
- [ ] 测试环境验证
- [ ] 监控指标正常
- [ ] 回滚方案已准备
- [ ] 用户已通知

## 常见错误

### ❌ 跳过验证
```
"我改了配置，应该没问题"
→ 必须验证配置已生效
```

### ❌ 部分验证
```
"编译通过了，应该没问题"
→ 还需要运行测试
```

### ❌ 延迟验证
```
"先部署，有问题再回滚"
→ 必须在测试环境完整验证
```

### ❌ 主观验证
```
"看起来是对的"
→ 必须用工具客观验证
```

## 正确示例

### ✅ 完整验证流程
```
1. 修改代码
   ↓
2. Read tool 确认修改
   "文件 /path/to/file 已修改，第 42 行已更新"
   ↓
3. 编译检查
   "Compilation successful, 0 warnings"
   ↓
4. 运行测试
   "10 tests, 0 failures"
   ↓
5. 本地验证
   "手动测试登录功能，成功登录"
   ↓
6. 声称完成
   "修改已完成并通过所有验证"
```

记住：**没有验证的修改等于没做**。
