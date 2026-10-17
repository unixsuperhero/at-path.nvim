# Project brief and domain

## Brief

Build a Neovim Lua plugin that inserts a chosen file or directory path from a
native popup when a word starts with `@`. The first usable outcome is selecting
a real filesystem entry in a Markdown buffer and replacing the trigger token
with its path. The repository is `/Users/unixsuperhero/proj/at-path.nvim`.

The acceptance criterion is an input-driven Neovim session where typing a path
prefix shows matching entries, choosing one inserts the expected path, and
choosing a directory permits continued navigation without another `@`.

Use Neovim's Lua API, libuv filesystem calls, and `vim.fn.complete()`. Keep the
plugin dependency-free, without timers, background indexing, repository-only
search, or changes to global keys and completion options. Default to Markdown
and provide an inline configuration instruction for all buffers.

Verification runs actual Insert-mode input in an isolated Neovim with a UI
attached. The retained command is `nvim --headless -u NONE -l tests/smoke.lua`.
It checks popup visibility and literal buffer results, not private functions.

## Domain concepts

- A **buffer** supplies its filetype and filename. The filetype controls whether
  the plugin is enabled; the filename supplies the relative path base. An
  unnamed buffer uses the current working directory.
- A **trigger** is `@` at the start of a word, including after punctuation. An
  email's embedded `@` is not a trigger.
- A **path query** follows the trigger. Its prefix chooses a directory relative
  to the buffer, relative to a parent, absolute from `/`, or relative to `~/`.
  The last component filters that directory's entries by filename prefix.
- An **entry** is a file or directory, including a symlink whose target is one
  of those kinds. Directory entries end in `/` so users can distinguish them
  and navigate into them.
- A **completion session** anchors a query to a buffer, line, and text prefix.
  It owns a native popup list. Candidate selection does not reset the session.
  Acceptance removes only the trigger marker, preserving literal `@` in names.
- **Directory navigation** continues a session after the marker is removed.
  Its anchor survives spaces and `@` in accepted paths. Each accepted directory
  opens its children. File acceptance ends the session.

The session's anchor and relative base belong together. Buffer or Insert-mode
leave invalidates the session and pending callbacks. Deferred refreshes compare
their captured buffer, cursor, line, and generation before touching completion.

## User goals

- Insert a real path without manually transcribing it.
- Choose relative or absolute paths anywhere on the readable local filesystem.
- Browse files and directories, including hidden entries and names with spaces
  or Unicode characters.
- Continue down directories without retyping the trigger.
- Keep Markdown as the default scope, with an explicit all-buffer option.
- Use Neovim's existing completion keys rather than learn another picker.

The [README](../README.md) documents installation, keys, scope configuration,
and filesystem limitations. The [prompt log](prompts/index.md) holds the exact
original request once, separately from this implementation brief.
