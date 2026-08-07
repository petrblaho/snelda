defmodule Snelda.Event do
  @moduledoc false

  @enforce_keys [:session_id, :type, :payload]
  defstruct [:session_id, :type, :payload, :index]
end
