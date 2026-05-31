defmodule AIBrain.Skill.Installer do
  @moduledoc """
  Thin URL installer facade for the single Codex-style skill manager.
  """

  alias AIBrain.Skill.Manager

  def install(url) when is_binary(url), do: Manager.install_url(url)
  def update(name) when is_binary(name), do: Manager.update_from_source(name)
  def uninstall(name) when is_binary(name), do: Manager.delete(name)
end
