defmodule Snelda.TaskConfig do
  @moduledoc false

  def render_prompt(template, vars) do
    Enum.reduce(vars, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", value)
    end)
  end
end
