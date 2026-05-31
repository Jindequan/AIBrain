defmodule AIBrain.Data.ChannelConfig do
  use Ecto.Schema
  import Ecto.Changeset
  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :channel_type,
             :credentials,
             :extra,
             :enabled,
             :inserted_at,
             :updated_at
           ]}

  schema "channel_configs" do
    field(:name, :string)
    field(:channel_type, :string)
    field(:credentials, :string, default: "{}")
    field(:extra, :string, default: "{}")
    field(:enabled, :boolean, default: false)
    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:id, :name, :channel_type, :credentials, :extra, :enabled])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:channel_type])
    |> validate_inclusion(:channel_type, ["telegram", "discord", "feishu", "wechat", "whatsapp"])
    |> validate_length(:name, max: 100)
    |> normalize_credentials()
  end

  defp normalize_credentials(changeset) do
    case get_field(changeset, :credentials) do
      creds when is_map(creds) ->
        put_change(changeset, :credentials, Jason.encode!(creds))

      _ ->
        changeset
    end
  end
end
