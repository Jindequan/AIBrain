#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_DIR="$PROJECT_DIR/.pids"
LOG_DIR="$PROJECT_DIR/.logs"

SERVER_PORT=4100
WEB_PORT=5200

mkdir -p "$PID_DIR" "$LOG_DIR"

_kill_port() {
  local port="$1" name="$2"
  local pid
  pid=$(lsof -ti ":$port" 2>/dev/null | head -1)
  if [ -n "$pid" ]; then
    echo "[$name] Killing stale process on port $port (pid $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$pid" 2>/dev/null || true
  fi
}

# ── Server ──────────────────────────────────────────────
if [ -f "$PID_DIR/server.pid" ] && kill -0 "$(cat "$PID_DIR/server.pid")" 2>/dev/null; then
  echo "[server] Already running (pid $(cat "$PID_DIR/server.pid"))"
else
  _kill_port $SERVER_PORT "server"
  rm -f "$PID_DIR/server.pid"
  echo "[server] Starting..."
  cd "$PROJECT_DIR/server"
  mix run --no-halt > "$LOG_DIR/server.log" 2>&1 &
  echo $! > "$PID_DIR/server.pid"
  echo "[server] Started (pid $(cat "$PID_DIR/server.pid"))"
fi

# ── Web ─────────────────────────────────────────────────
if [ -f "$PID_DIR/web.pid" ] && kill -0 "$(cat "$PID_DIR/web.pid")" 2>/dev/null; then
  echo "[web] Already running (pid $(cat "$PID_DIR/web.pid"))"
else
  _kill_port $WEB_PORT "web"
  rm -f "$PID_DIR/web.pid"
  echo "[web] Starting..."
  cd "$PROJECT_DIR/web"
  npm run dev > "$LOG_DIR/web.log" 2>&1 &
  echo $! > "$PID_DIR/web.pid"
  echo "[web] Started (pid $(cat "$PID_DIR/web.pid"))"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Server → http://localhost:$SERVER_PORT"
echo "  Web    → http://localhost:$WEB_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
