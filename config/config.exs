import Config

config :mix_test_watch,
  clear: true,
  tasks: [
    "coveralls",
    "format --check-formatted",
    "credo --strict",
    "dialyzer"
  ]

import_config "#{config_env()}.exs"
