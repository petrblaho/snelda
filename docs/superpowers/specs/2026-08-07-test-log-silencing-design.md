# Test Log Silencing

**Goal:** Clean up the `mix test` output by redirecting and silencing `Logger` output for passing tests, while preserving logs for failing tests and explicit assertions.

## Architecture

*   **Mechanism:** `ExUnit` built-in log capturing.
*   **Behavior:** 
    *   Global capture intercepts all `Logger` output.
    *   Passing tests emit no log output to the console.
    *   Failing tests automatically print the captured logs alongside the failure reason.
    *   Tests that need to assert on log output can do so using `ExUnit.CaptureLog.capture_log/1`.

## Changes Required

1.  **Modify `test/test_helper.exs`:** Update `ExUnit.start()` to `ExUnit.start(capture_log: true)`.


