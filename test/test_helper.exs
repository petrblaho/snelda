# test_helper.exs
ExUnit.start()

# By default, Snelda.Application starts Acceptor on /tmp/snelda.sock
# and starts the global Registry and PubSub.
# That is fine for tests that use isolated paths or dynamic names,
# but can conflict if we try to start the same named processes again.
