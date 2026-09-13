# Semantic search validation

Run the isolated tests from the repository root:

```sh
cmake -S tests -B build-semantic-tests
cmake --build build-semantic-tests
ctest --test-dir build-semantic-tests --output-on-failure
```

The color test runs on any C++17 platform. On macOS, the index test also runs
against Foundation with a deterministic test scoring engine. It checks the
16 MiB spill boundary, sentence IDs, top-k ranking, scoring failure, and reset.
It does not validate Metal or Apple's embedding models.

Before submitting the PR, build the full app on macOS using the main README's
build instructions and check the following on a Mac with model assets:

- Type a query, edit its document during indexing, and switch to another tab
  or split pane. Only the active document's current results should appear.
- Switch between documents in different supported languages. Verify the model
  changes and sentences are indexed. Unsupported languages should produce an
  availability error rather than silently using an English model.
- Test empty text, emoji, CJK text, and non-ASCII punctuation. Sentence colors
  should align with UTF-8 byte ranges; failed embeddings should remain uncolored.
- Test exactly 4,096 sentences, then 4,097, and a file larger than 2 MiB. Limits
  should report an error, clear previous colors, and stop the spinner.
- Close during indexing, immediately reopen, and close again. No delayed result
  should recolor a detached editor or hide a newly reopened bar. Reopening must
  use the visible query, including text entered just before closing.
- Change Strict/Standard/Broad with results visible. Colors should update
  immediately; scores and sentence coverage should remain unchanged. Reopen
  the app and verify the selection persists.
- Resize to 480 pixels wide in light and dark appearances. Check query field,
  popup, close button, truncated status tooltip, keyboard access, and VoiceOver
  labels. Check that collapsed bars do not draw over adjacent content.
- Exercise missing model assets and unavailable Metal/MPS. These must show an
  error or documented model fallback, not apparent successful search results.

Mean pooling combines contextual token vectors, but color thresholds have not
been calibrated against labeled relevance examples. Evaluate representative
queries on each backend before making claims about retrieval accuracy or
comparing scores between languages/models.
