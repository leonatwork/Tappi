## Motivation

Why is this change needed? Link the related issue and summarize the change.

## Testing

How did you test the change? Include automated checks and relevant manual scenarios
(for example, multiple Spaces, minimized windows, multiple monitors or missing
permissions). Mark checks you could not run and explain why.

- [ ] `swift build -c release` completes without warnings.
- [ ] `swift test -c release` passes.

## Hotkey-path measurements

If this change touches the hotkey path, record keypress-to-visible-panel latency
in ms **before** and **after**, with macOS version, hardware, window count and
preview settings. Otherwise, mark this section as not applicable.

Use `TAPPI_DEBUG=1 /Applications/Tappi.app/Contents/MacOS/Tappi` and the
`visible after … ms` output, as described in
[CONTRIBUTING.md](https://github.com/leonatwork/Tappi/blob/master/CONTRIBUTING.md).

| Setup | before (ms) | after (ms) |
|---|---|---|
| | | |
