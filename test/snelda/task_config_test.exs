defmodule Snelda.TaskConfigTest do
  use ExUnit.Case, async: true
  alias Snelda.TaskConfig

  test "replaces variables in template" do
    template = "Message: {{message}}\nDiff: {{diff}}"
    vars = %{"message" => "fix stuff", "diff" => "+ code"}
    assert TaskConfig.render_prompt(template, vars) == "Message: fix stuff\nDiff: + code"
  end
end
