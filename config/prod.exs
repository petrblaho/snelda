import Config

# We leave the global logger level alone here, but we will configure it dynamically
# in the CLI module when we boot up so the CLI stays quiet, but the daemon logs to a file.
config :logger, level: :info
