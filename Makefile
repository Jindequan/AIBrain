.PHONY: setup dev test test-web clean

# ── Setup ────────────────────────────────────────────────
setup:
	cd server && mix deps.get
	cd server && MIX_ENV=dev mix ecto.migrate -r AIBrain.Repo
	cd web && npm install

# ── Development ──────────────────────────────────────────
dev:
	@echo "Starting server on :4100 and web on :5200..."
	cd server && mix run --no-halt &
	cd web && npm run dev &
	@echo "Open http://localhost:5200"
	@wait

# ── Testing ───────────────────────────────────────────────
test:
	cd server && mix test --exclude integration_smoke

test-full:
	cd server && mix test

test-web:
	cd web && npm run test

# ── Formatting ────────────────────────────────────────────
format:
	cd server && mix format
	cd web && npx prettier --write src/

# ── Cleanup ───────────────────────────────────────────────
clean:
	cd server && rm -rf _build deps
	cd web && rm -rf node_modules dist
