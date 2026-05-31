defmodule AIBrain.Web.Handlers.DocsHandler do
  @moduledoc """
  API 文档处理器
  """

  import Plug.Conn

  def handle_docs(conn) do
    html = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>AIBrain API Documentation</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 1.1em; }
        .section {
            background: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .section h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.8em;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        .endpoint {
            background: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .method {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 4px;
            font-weight: bold;
            margin-right: 10px;
            font-size: 0.9em;
        }
        .method.get { background: #61affe; color: white; }
        .method.post { background: #49cc90; color: white; }
        .method.delete { background: #f93e3e; color: white; }
        .path {
            font-family: 'Courier New', monospace;
            font-weight: bold;
            color: #333;
        }
        .description { margin: 10px 0; color: #666; }
        code {
            background: #2d2d2d;
            color: #f8f8f2;
            padding: 15px;
            border-radius: 5px;
            display: block;
            margin: 15px 0;
            overflow-x: auto;
            font-family: 'Courier New', monospace;
        }
        .param {
            margin: 10px 0;
            padding-left: 20px;
        }
        .param strong { color: #667eea; }
        .response {
            background: #e8f5e9;
            padding: 15px;
            border-radius: 5px;
            margin: 15px 0;
        }
        .warning {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
        }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>AIBrain API</h1>
            <p>自主 AI Agent 系统 - 无需鉴权的本地开发 API</p>
        </div>

        <div class="section">
            <h2>快速开始</h2>
            <div class="warning">
                <strong>开发模式说明：</strong>当前无需鉴权，适合本地开发测试。生产环境请配置认证！
            </div>

            <h3>基础请求示例</h3>
            <code>curl -X POST http://localhost:4000/api/v1/query \
              -H "Content-Type: application/json" \
              -d '{"message": "你好，请介绍一下你自己"}'</code>

            <h3>流式响应示例 (SSE)</h3>
            <code>curl -X POST http://localhost:4000/api/v1/query/stream \
              -H "Accept: text/event-stream" \
              -H "Content-Type: application/json" \
              -d '{"message": "写一首关于编程的诗"}'</code>
        </div>

        <div class="section">
            <h2>API 端点</h2>

            <div class="endpoint">
                <span class="method get">GET</span>
                <span class="path">/health</span>
                <p class="description">健康检查</p>
                <code>curl http://localhost:4000/health</code>
            </div>

            <div class="endpoint">
                <span class="method post">POST</span>
                <span class="path">/api/v1/query</span>
                <p class="description">执行单次查询</p>

                <h4>请求参数：</h4>
                <div class="param"><strong>message</strong> (string) - 用户消息内容</div>
                <div class="param"><strong>messages</strong> (array) - 多轮对话消息数组</div>
                <div class="param"><strong>model</strong> (string, 可选) - 模型名称，默认 claude-3-5-sonnet-20241022</div>
                <div class="param"><strong>session_id</strong> (string, 可选) - 关联的会话 ID</div>
                <div class="param"><strong>mode</strong> (string, 可选) - 权限模式：default, plan, approval_required</div>

                <h4>请求示例：</h4>
                <code>{
    "message": "分析这个项目的架构",
    "model": "claude-3-5-sonnet-20241022",
    "mode": "default"
                }</code>

                <h4>响应示例：</h4>
                <div class="response">{
    "success": true,
    "response": "这是一个基于 Elixir 的 AI Agent 系统...",
    "timestamp": "2026-04-25T10:30:00Z"
                }</div>
            </div>

            <div class="endpoint">
                <span class="method post">POST</span>
                <span class="path">/api/v1/query/stream</span>
                <p class="description">流式查询 (Server-Sent Events)</p>

                <h4>事件类型：</h4>
                <div class="param"><strong>start</strong> - 查询开始</div>
                <div class="param"><strong>message</strong> - 中间事件（工具执行等）</div>
                <div class="param"><strong>complete</strong> - 查询完成</div>
                <div class="param"><strong>error</strong> - 查询错误</div>
            </div>

            <div class="endpoint">
                <span class="method get">GET</span>
                <span class="path">/api/v1/sessions/:id</span>
                <p class="description">获取会话详情</p>
                <code>curl http://localhost:4000/api/v1/sessions/session-123</code>
            </div>

            <div class="endpoint">
                <span class="method post">POST</span>
                <span class="path">/api/v1/sessions</span>
                <p class="description">创建新会话</p>
                <code>{
    "messages": [
        {"role": "user", "content": "开始新对话"}
    ],
    "model": "claude-3-5-sonnet-20241022"
                }</code>
            </div>

            <div class="endpoint">
                <span class="method post">POST</span>
                <span class="path">/api/v1/sessions/:id/resume</span>
                <p class="description">恢复会话继续对话</p>
            </div>

            <div class="endpoint">
                <span class="method delete">DELETE</span>
                <span class="path">/api/v1/sessions/:id</span>
                <p class="description">删除会话</p>
            </div>

            <div class="endpoint">
                <span class="method get">GET</span>
                <span class="path">/api/v1/ws</span>
                <p class="description">WebSocket 连接（实时双向通信）</p>
            </div>
        </div>

        <div class="section">
            <h2>配置说明</h2>

            <h3>Provider 配置</h3>
            <p>Provider 配置保存在数据库中，可通过 API 进行管理：</p>
            <code>GET /api/v1/providers  - 查看 Provider 列表
            POST /api/v1/providers - 添加 Provider
            PUT /api/v1/providers/:name - 更新 Provider
            DELETE /api/v1/providers/:name - 删除 Provider</code>

            <h3>环境变量</h3>
            <div class="param"><strong>PORT</strong> - 服务端口，默认 4000</div>
            <div class="param"><strong>MIX_ENV</strong> - 运行环境：dev, prod</div>
        </div>

        <div class="section">
            <h2>系统架构</h2>
            <ul style="list-style: none; padding: 0;">
                <li style="margin: 10px 0;"><strong>Agent Loop</strong> - 核心推理引擎</li>
                <li style="margin: 10px 0;"><strong>Tool System</strong> - 可扩展工具集</li>
                <li style="margin: 10px 0;"><strong>Provider Router</strong> - 多模型路由</li>
                <li style="margin: 10px 0;"><strong>Session Store</strong> - 会话管理</li>
                <li style="margin: 10px 0;"><strong>Permission System</strong> - 权限控制</li>
            </ul>
        </div>

        <div class="section">
            <h2>测试</h2>
            <code>mix test</code>
        </div>

        <div class="section">
            <h2>更多信息</h2>
            <p>GitHub: <a href="https://github.com/your-org/aibrain">github.com/your-org/aibrain</a></p>
            <p>文档: <a href="https://docs.aibrain.dev">docs.aibrain.dev</a></p>
        </div>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
