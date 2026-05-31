defmodule AIBrain.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  @doc """
  Consolidated initial schema — all current tables in one migration.
  Aligned with the unified runs architecture.

  Non-Ecto tables (sessions, knowledge_entries, rag_chunks, telemetry_spans,
  audit_log) are managed by their
  respective modules and NOT included here.
  """

  def up do
    # ── Core Identity ──────────────────────────────────────────

    create table(:users, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :bio, :string
      add :role, :string, default: "user"
      add :active, :boolean, default: false
      add :profile, :text
      add :preferences, :text, default: "{}"
      timestamps()
    end

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    execute """
    INSERT OR IGNORE INTO users (id, name, role, active, preferences, inserted_at, updated_at)
    VALUES ('user-default', 'Me', 'user', true, '{}', '#{now}', '#{now}')
    """

    execute """
    INSERT OR IGNORE INTO users (id, name, role, active, preferences, inserted_at, updated_at)
    VALUES ('proxy-default', 'Proxy', 'proxy', false, '{}', '#{now}', '#{now}')
    """

    # ── Goals / Tasks ──────────────────────────────────────────

    create table(:goals, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :status, :string, default: "active"
      add :priority, :integer, default: 3
      add :workspace_path, :string
      add :parent_id, :string
      add :metadata, :map, default: %{}
      timestamps()
    end
    create index(:goals, [:parent_id])
    create index(:goals, [:status])

    create table(:tasks, primary_key: false) do
      add :id, :string, primary_key: true
      add :goal_id, :string
      add :title, :string, null: false
      add :description, :text
      add :status, :string, default: "pending"
      add :priority, :integer, default: 3
      add :parent_id, :string
      add :depends_on, {:array, :string}, default: []
      add :required_skills, {:array, :string}, default: []
      add :output, :text
      add :run_id, :string
      add :metadata, :map, default: %{}
      timestamps()
    end
    create index(:tasks, [:goal_id])
    create index(:tasks, [:status])

    # ── Runs (unified) ─────────────────────────────────────────

    create table(:runs, primary_key: false) do
      add :id, :string, primary_key: true
      add :source_type, :string, null: false
      add :source_id, :string
      add :status, :string, default: "pending"
      add :input, :map, default: %{}
      add :output, :text
      add :output_summary, :text
      add :error, :text
      add :model, :string
      add :mode, :string
      add :phase, :string
      add :objective, :text
      add :autonomy_level, :integer, default: 0
      add :workspace_path, :string
      add :messages_path, :string
      add :output_path, :string
      add :parent_run_id, :string
      add :title, :string
      add :metadata, :map, default: %{}
      add :deliverables, {:array, :map}, default: []
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps()
    end
    create index(:runs, [:source_type])
    create index(:runs, [:source_id])
    create index(:runs, [:status])
    create index(:runs, [:mode])
    create index(:runs, [:phase])
    create index(:runs, [:parent_run_id])

    create table(:run_context_refs, primary_key: false) do
      add :id, :string, primary_key: true
      add :run_id, :string, null: false
      add :ref_type, :string, null: false
      add :ref_id, :string, null: false
      add :role, :string, null: false, default: "related"
      add :metadata, :map, default: %{}
      timestamps()
    end
    create index(:run_context_refs, [:run_id])
    create index(:run_context_refs, [:ref_type, :ref_id])
    create unique_index(:run_context_refs, [:run_id, :ref_type, :ref_id, :role])

    create table(:run_steps, primary_key: false) do
      add :id, :string, primary_key: true
      add :run_id, :string, null: false
      add :step_index, :integer, null: false
      add :phase, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :kind, :string
      add :title, :string
      add :summary, :text
      add :input_path, :string
      add :output_path, :string
      add :error, :text
      add :metadata, :map, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps()
    end
    create index(:run_steps, [:run_id])
    create index(:run_steps, [:run_id, :step_index])
    create index(:run_steps, [:phase])
    create index(:run_steps, [:status])

    # ── Schedules (unified) ────────────────────────────────────

    create table(:schedules, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :trigger_type, :string, null: false
      add :trigger_config, :map, default: %{}
      add :action_type, :string, null: false
      add :action_config, :map, default: %{}
      add :status, :string, default: "active"
      add :priority, :integer, default: 3
      add :next_fire_at, :utc_datetime
      add :last_fired_at, :utc_datetime
      add :last_result, :text
      timestamps()
    end
    create index(:schedules, [:trigger_type])
    create index(:schedules, [:status])
    create index(:schedules, [:next_fire_at])

    # ── Memory ─────────────────────────────────────────────────

    create table(:episodic_memories, primary_key: false) do
      add :id, :string, primary_key: true
      add :goal_id, :string
      add :task_id, :string
      add :run_id, :string
      add :event_start_id, :string
      add :event_end_id, :string
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime
      add :narrative, :text, null: false
      add :objective, :string
      add :approach, :string
      add :key_decisions, :map, default: %{}
      add :success_score, :float, default: 0.0
      add :lessons, {:array, :string}, default: []
      add :difficulties, :map, default: %{}
      add :tool_usage_summary, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :importance_score, :float, default: 0.0
      timestamps()
    end
    create index(:episodic_memories, [:goal_id])

    create table(:events, primary_key: false) do
      add :id, :string, primary_key: true
      add :correlation_id, :string
      add :event_type, :string, null: false
      add :source, :string
      add :channel_type, :string
      add :payload, :map, default: %{}
      add :metadata, :map, default: %{}
      add :session_id, :string
      add :goal_id, :string
      add :task_id, :string
      add :run_id, :string
      add :importance, :float, default: 0.5
      add :token_count, :integer, default: 0
      add :snapshot_id, :string
      timestamps()
    end
    create index(:events, [:session_id])
    create index(:events, [:goal_id])
    create index(:events, [:task_id])
    create index(:events, [:correlation_id])
    create index(:events, [:snapshot_id])

    # ── Channels ───────────────────────────────────────────────

    create table(:channel_configs, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string
      add :channel_type, :string, null: false
      add :credentials, :text
      add :extra, :text
      add :enabled, :boolean, default: false
      timestamps()
    end

    # ── Artifacts ──────────────────────────────────────────────

    create table(:artifacts, primary_key: false) do
      add :id, :string, primary_key: true
      add :run_id, :string
      add :title, :string
      add :description, :text
      add :kind, :string
      add :uri, :string
      add :content, :string
      add :size, :integer
      add :mime_type, :string
      add :metadata, :map, default: %{}
      timestamps()
    end
    create index(:artifacts, [:run_id])
    create index(:artifacts, [:kind])

    # ── User Prompts ───────────────────────────────────────────

    create table(:user_prompts, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :category, :string
      add :template, :text, null: false
      add :variables, :text
      add :is_active, :boolean, default: true
      add :description, :string
      timestamps()
    end
    create index(:user_prompts, [:category])
    create index(:user_prompts, [:is_active])

    # ── Workspaces ─────────────────────────────────────────────

    create table(:workspaces, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :path, :string, null: false
      add :metadata, :map, default: %{}
      timestamps()
    end
    create unique_index(:workspaces, [:path])

    # ── Context Links ──────────────────────────────────────────

    create table(:context_links, primary_key: false) do
      add :id, :string, primary_key: true
      add :owner_type, :string, null: false
      add :owner_id, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :string, null: false
      add :context_type, :string
      add :uri, :string
      add :title, :string
      add :summary, :string
      add :relevance, :float, default: 0.5
      add :metadata, :map, default: %{}
      timestamps()
    end
    create index(:context_links, [:owner_type, :owner_id])
    create index(:context_links, [:target_type, :target_id])

    # ── Evidence Ledger ────────────────────────────────────────

    create table(:evidence_items, primary_key: false) do
      add :id, :string, primary_key: true
      add :run_id, :string, null: false
      add :step_id, :string
      add :claim, :text, null: false
      add :source_type, :string, null: false
      add :source_uri, :string
      add :source_title, :string
      add :source_excerpt_path, :string
      add :tool_name, :string
      add :confidence, :float, default: 0.5
      add :status, :string, default: "active"
      add :metadata, :map, default: %{}
      timestamps()
    end
    create index(:evidence_items, [:run_id, :status])
    create index(:evidence_items, [:source_type])

    # ── Intent / Interaction / Feedback ────────────────────────

    create table(:intent_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :session_id, :string, null: false
      add :parent_intent_id, :string
      add :run_id, :string
      add :status, :string, null: false, default: "classifying"
      add :intent_type, :string
      add :intent_subtype, :string
      add :parameters, :map, default: %{}
      add :constraints, :map, default: %{}
      add :confidence, :float, default: 0.0
      add :reasoning, :text
      add :skill_id, :string
      add :pending_questions, {:array, :map}, default: []
      add :user_responses, {:array, :map}, default: []
      add :resolved_at, :utc_datetime
      timestamps()
    end
    create index(:intent_sessions, [:session_id])
    create index(:intent_sessions, [:status])
    create index(:intent_sessions, [:session_id, :status])
    create index(:intent_sessions, [:run_id])

    create table(:interactions, primary_key: false) do
      add :id, :string, primary_key: true
      add :type, :string, null: false
      add :status, :string, default: "pending"
      add :schema_data, :text
      add :context, :text
      add :result, :text
      add :proxy_trail, :text
      add :resolved_by, :string
      add :expires_at, :string
      add :resolved_at, :string
      add :resume_token, :string
      add :prompt_versions, :text
      timestamps()
    end
    create index(:interactions, [:status])
    create index(:interactions, [:type])
    create index(:interactions, [:resume_token])
    create index(:interactions, [:expires_at])

    create table(:feedback, primary_key: false) do
      add :id, :string, primary_key: true
      add :interaction_id, :string
      add :target_type, :string, null: false
      add :original_action, :text
      add :original_reasoning, :text
      add :user_correction, :text
      add :expected_action, :text
      add :context_snapshot, :text
      add :severity, :string, default: "minor"
      add :status, :string, default: "pending"
      add :source, :string, default: "user"
      timestamps()
    end
    create index(:feedback, [:target_type])
    create index(:feedback, [:status])
    create index(:feedback, [:interaction_id])

    create table(:system_lessons, primary_key: false) do
      add :id, :string, primary_key: true
      add :target_type, :string, null: false
      add :lesson, :text, null: false
      add :source_count, :integer, default: 1
      add :version, :integer, default: 1
      add :active, :boolean, default: true
      add :changelog, :text
      timestamps()
    end
    create index(:system_lessons, [:target_type])
    create index(:system_lessons, [:active])

    # ── System Settings ────────────────────────────────────────

    create table(:system_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text
      timestamps(updated_at: false)
    end

    # ── Notifications ──────────────────────────────────────────

    create table(:notification_queue, primary_key: false) do
      add :id, :string, primary_key: true
      add :event_id, :string, null: false
      add :channel, :string, null: false
      add :status, :string, default: "pending"
      add :payload, :map, default: %{}
      add :retry_count, :integer, default: 0
      add :max_retries, :integer, default: 5
      add :last_error, :string
      add :scheduled_at, :utc_datetime
      add :delivered_at, :utc_datetime
      timestamps()
    end
    create index(:notification_queue, [:status])
    create index(:notification_queue, [:channel])

    # ── Sessions (SQLite store, not Ecto-managed) ──────────────

    execute """
    CREATE TABLE IF NOT EXISTS sessions (
      id                   TEXT PRIMARY KEY,
      session_type         TEXT NOT NULL DEFAULT 'web_chat',
      title                TEXT,
      channel_adapter      TEXT,
      channel_id           TEXT,
      turn_count           INTEGER DEFAULT 0,
      started_at           TEXT,
      workspace_path       TEXT,
      status               TEXT DEFAULT 'active',
      notes                TEXT,
      inserted_at          TEXT,
      created_at           TEXT NOT NULL,
      updated_at           TEXT NOT NULL
    )
    """

    # ── Knowledge Wiki ──────────────────────────────────────────

    execute """
    CREATE TABLE IF NOT EXISTS knowledge_entries (
      id                      TEXT PRIMARY KEY,
      type                    TEXT NOT NULL,
      content                 TEXT NOT NULL,
      content_hash            TEXT NOT NULL,
      source_type             TEXT NOT NULL DEFAULT 'session',
      confidence              REAL DEFAULT 0.0,
      decay_score             REAL DEFAULT 1.0,
      tags                    TEXT DEFAULT '[]',
      first_source_session_id TEXT REFERENCES sessions(id),
      source_session_id       TEXT REFERENCES sessions(id),
      source_detail           TEXT,
      usable_for_auto_decision INTEGER DEFAULT 0,
      embedding               BLOB,
      last_confirmed_at       TEXT,
      created_at              TEXT NOT NULL,
      updated_at              TEXT NOT NULL
    )
    """
    execute "CREATE UNIQUE INDEX IF NOT EXISTS idx_knowledge_content_hash ON knowledge_entries(content_hash)"
    execute "CREATE INDEX IF NOT EXISTS idx_knowledge_type ON knowledge_entries(type)"
    execute "CREATE INDEX IF NOT EXISTS idx_knowledge_confidence ON knowledge_entries(confidence DESC)"

    # ── RAG Chunks ──────────────────────────────────────────────

    execute """
    CREATE TABLE IF NOT EXISTS rag_chunks (
      id          TEXT PRIMARY KEY,
      source      TEXT NOT NULL,
      source_type TEXT NOT NULL DEFAULT 'file',
      chunk_index INTEGER DEFAULT 0,
      content     TEXT NOT NULL,
      embedding   BLOB,
      metadata    TEXT DEFAULT '{}',
      created_at  TEXT NOT NULL
    )
    """
    execute "CREATE INDEX IF NOT EXISTS idx_rag_source ON rag_chunks(source)"
    execute "CREATE INDEX IF NOT EXISTS idx_rag_source_type ON rag_chunks(source_type)"

    # ── Telemetry ───────────────────────────────────────────────

    create table(:telemetry_spans) do
      add :event, :string, null: false
      add :measurements, :map
      add :metadata, :map
      timestamps(updated_at: false)
    end
    create index(:telemetry_spans, [:event])
    create index(:telemetry_spans, [:inserted_at])

    # ── Distillation Log ───────────────────────────────────────

    create table(:distillation_log, primary_key: false) do
      add :session_id, :string, primary_key: true
      add :distilled_at, :string
      add :entry_count, :integer
      add :status, :string
    end
    create index(:distillation_log, [:session_id], unique: true)

    # ── Monitor Logs ───────────────────────────────────────────

    execute """
    CREATE TABLE IF NOT EXISTS monitor_logs (
      id           TEXT PRIMARY KEY,
      monitor_id   TEXT NOT NULL,
      status       TEXT NOT NULL DEFAULT 'running',
      result       TEXT,
      result_path  TEXT,
      summary      TEXT,
      triggered_at TEXT NOT NULL,
      completed_at TEXT
    )
    """
    execute "CREATE INDEX IF NOT EXISTS idx_monitor_logs_monitor ON monitor_logs(monitor_id)"
    execute "CREATE INDEX IF NOT EXISTS idx_monitor_logs_triggered ON monitor_logs(triggered_at)"

  end

  def down do
    for table <- ~w(
      notification_queue system_settings system_lessons evidence_items feedback interactions
      intent_sessions context_links workspaces
      user_prompts artifacts channel_configs events episodic_memories
      schedules run_steps run_context_refs runs tasks goals users
    )a do
      drop table(table)
    end

    execute "DROP TABLE IF EXISTS monitor_logs"
    execute "DROP TABLE IF EXISTS distillation_log"
    execute "DROP TABLE IF EXISTS telemetry_spans"
    execute "DROP TABLE IF EXISTS rag_chunks"
    execute "DROP TABLE IF EXISTS knowledge_entries"
    execute "DROP TABLE IF EXISTS sessions"
  end
end
