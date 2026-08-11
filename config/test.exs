import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :snelda, os_adapter: Snelda.OS.Mock
