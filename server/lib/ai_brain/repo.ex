defmodule AIBrain.Repo do
  use Ecto.Repo,
    otp_app: :ai_brain,
    adapter: Ecto.Adapters.SQLite3
end
