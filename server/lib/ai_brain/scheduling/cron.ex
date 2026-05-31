defmodule AIBrain.Scheduling.Cron do
  @moduledoc """
  Minimal cron expression parser.

  Supports 5-field cron: minute hour day-of-month month day-of-week.
  Accepted field formats: `*`, `*/N`, specific integers, ranges, and
  comma-separated lists.
  """

  defstruct minute: :any, hour: :any, dom: :any, month: :any, dow: :any

  @type field_spec :: :any | {:step, pos_integer()} | MapSet.t(integer())
  @type t :: %__MODULE__{
          minute: field_spec(),
          hour: field_spec(),
          dom: field_spec(),
          month: field_spec(),
          dow: field_spec()
        }

  @minute_range 0..59
  @hour_range 0..23
  @dom_range 1..31
  @month_range 1..12
  @dow_range 0..6

  def parse(expression) when is_binary(expression) do
    case String.split(expression, ~r/\s+/, trim: true) do
      [minute, hour, dom, month, dow] ->
        with {:ok, m} <- parse_field(minute, @minute_range),
             {:ok, h} <- parse_field(hour, @hour_range),
             {:ok, d} <- parse_field(dom, @dom_range),
             {:ok, mo} <- parse_field(month, @month_range),
             {:ok, dw} <- parse_field(dow, @dow_range) do
          {:ok, %__MODULE__{minute: m, hour: h, dom: d, month: mo, dow: dw}}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  def parse(_), do: {:error, :invalid_format}

  def next_fire(%__MODULE__{} = expr, %DateTime{} = from) do
    start = DateTime.add(from, 60, :second)
    search(expr, start, 525_960)
  end

  defp search(_expr, _dt, 0), do: {:error, :no_match}
  defp search(_expr, %{year: year}, _remaining) when year > 2028, do: {:error, :no_match}

  defp search(expr, dt, remaining) do
    if matches?(expr, dt) do
      {:ok, dt}
    else
      search(expr, DateTime.add(dt, 60, :second), remaining - 1)
    end
  end

  @doc """
  Returns true if the given DateTime matches this cron expression.
  """
  def matches?(expr, dt) do
    dow = rem(Date.day_of_week(dt), 7)

    field_matches?(expr.minute, dt.minute) and
      field_matches?(expr.hour, dt.hour) and
      field_matches?(expr.dom, dt.day) and
      field_matches?(expr.month, dt.month) and
      field_matches?(expr.dow, dow)
  end

  defp field_matches?(:any, _value), do: true
  defp field_matches?({:step, step}, value), do: rem(value, step) == 0
  defp field_matches?(%MapSet{} = set, value), do: MapSet.member?(set, value)

  defp parse_field("*", _range), do: {:ok, :any}

  defp parse_field("*/" <> n, _range) do
    case Integer.parse(n) do
      {step, ""} when step > 0 -> {:ok, {:step, step}}
      _ -> {:error, {:invalid_step, n}}
    end
  end

  defp parse_field(field, range) do
    values =
      field
      |> String.split(",")
      |> Enum.flat_map(&expand_part(&1))
      |> Enum.uniq()

    if values != [] and Enum.all?(values, &(&1 in range)) do
      {:ok, MapSet.new(values)}
    else
      {:error, {:invalid_field, field}}
    end
  end

  defp expand_part(part) do
    if String.contains?(part, "-") do
      case String.split(part, "-") do
        [a, b] ->
          with {start, ""} <- Integer.parse(a),
               {stop, ""} <- Integer.parse(b) do
            Enum.to_list(start..stop)
          else
            _ -> []
          end

        _ ->
          []
      end
    else
      case Integer.parse(part) do
        {n, ""} -> [n]
        _ -> []
      end
    end
  end
end
