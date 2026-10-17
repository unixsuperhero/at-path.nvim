# at-path.nvim

A dependency-free Neovim Lua plugin that opens the native completion popup when
an Insert-mode word starts with `@`. Choose a file or directory to insert its
path. Markdown buffers are enabled by default.

## Install locally

Requires Neovim 0.12.3 on macOS or Linux. Earlier versions have not been verified.
No completion framework, external executable, or package installation is needed.

Add this to your `init.lua` for the checkout created here:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/proj/at-path.nvim'))
require('at_path').setup()
```

For a different checkout location, change the runtime path. The Lua module lives
in [`lua/at_path/init.lua`](lua/at_path/init.lua). Nothing loads automatically
until you call `setup()`.

## Use

In a Markdown buffer, enter Insert mode and type `@`, optionally followed by a
path prefix. A trigger after whitespace or punctuation works, including `(@`.
An `@` immediately after a keyword character, as in `name@example.com`, does not
start completion. If an earlier query has no matches, a new word-start `@` starts
a fresh query. An existing matching path keeps its anchor, including spaces and
literal `@` characters in names.

- `<C-n>` and `<C-p>` select the next or previous item.
- `<C-y>` accepts the selected item and removes the trigger `@`.
- `<C-e>` cancels the popup and restores the original text, including `@`.
- `<Esc>` leaves Insert mode and ends path navigation.

Directories have a trailing `/` and a `[dir]` label. Accept one to insert its
path and open its children immediately. Type the child's prefix to narrow the
list, or select another item. Navigation continues without typing `@` again,
including through directories containing spaces or `@`. An empty directory has
no child popup. File acceptance ends navigation.

Paths are inserted as plain text. Spaces, Unicode, and literal `@` characters
in names are preserved. The marker stays in the buffer while a suggestion is
selected and disappears only when that suggestion is accepted. Other text on
the line is preserved.

## Path bases

| Typed prefix | Search location | Example inserted path |
| --- | --- | --- |
| `@` or `@rep` | Current file's directory | `report.md` |
| `@./` | Current file's directory | `./report.md` |
| `@../` | Parent of the current file's directory | `../report.md` |
| `@/` | Filesystem root, not repository root | `/tmp/report.md` |
| `@~/` | Your home directory | `~/notes/report.md` |

An unnamed buffer uses Neovim's current working directory. The base is captured
when navigation starts. Relative paths stay relative, absolute paths stay
absolute, and `~/` stays abbreviated. Hidden entries and symlinks to files or
directories are included. Matching is a case-sensitive filename prefix search;
there is no recursive index or repository restriction.

## Buffer scope

```lua
-- Default: Markdown only.
require('at_path').setup()

-- All buffers. The same instruction appears beside the default in the code.
require('at_path').setup({ filetypes = {} })

-- An explicit set of filetypes.
require('at_path').setup({ filetypes = { 'markdown', 'text' } })
```

Calling `setup()` again replaces this plugin's autocommands and resets navigation.
There are no key mappings or global completion option changes. Each popup call
briefly uses a buffer-local `completeopt` value with `menuone,noselect`, then
restores the original local value.

## Limits

- Directory enumeration is synchronous and limited to the current directory.
  Large or slow network directories can pause input. There are no timers or
  background indexers.
- Paths use Unix `/` separators. Windows paths are not supported.
- Names containing newlines or carriage returns are omitted. Dangling symlinks
  and special entries such as sockets or FIFOs are omitted.
- Unreadable or nonexistent directories produce no suggestions.
- Inserted text is not a Markdown link or URL and is not escaped for Markdown
  syntax or a shell. Apply any formatting required by its destination.
- Path sessions end on leaving the buffer or Insert mode, cancelling completion,
  or moving the cursor away. Start a new session with `@` after that.
- Other completion plugins share Neovim's native popup and can replace this list.
  This plugin does not override their mappings or configuration.

## Verify

From this repository, run:

```sh
nvim --headless -u NONE -l tests/smoke.lua
```

The regression check starts an isolated embedded Neovim with an attached UI,
creates temporary files, sends actual Insert-mode keys, and checks
`pumvisible()`, completion entries, selection, and accepted buffer text. It
covers relative, absolute, home, and unnamed-buffer paths; directory navigation
with spaces and `@`; hidden/Unicode/symlink entries; cancellation; email
suppression; scope options; and preservation of global completion options and
keys. It deletes its temporary files afterward.

## Context

- [Documentation index](docs/index.md)
- [Project brief, domain concepts, and goals](docs/project.md)
- [Authoritative prompt log](docs/prompts/index.md)
- [Agent instructions](AGENTS.md)

Thinktank registry name `at-path-nvim` points to this independent repository.
Durable notes live in `~/notes/proj/at-path-nvim/`; shared notes live in
`~/notes/proj/all/`. The generated agent instructions link to the local
Thinktank conventions, but installation does not depend on that checkout.
