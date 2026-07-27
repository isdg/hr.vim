# hr.vim

A thin reading-list sidebar over the [`hr`](https://github.com/) CLI, for
**Vim 8.1+ and Neovim**. Lists articles, opens them in the main window, and
maps a handful of keys to mark read/unread, favorite, alias, sync, and refresh.

Pure Vimscript — no Lua, no dependencies beyond the `hr` binary.

```
[ F] 2026-06-04  matklad   CSS: unavoidable bad parts
[R ] 2021-04-26  mcyoung   Move constructors in Rust: is it possible?
```

## Install

**lazy.nvim**

```lua
{ "isdg/hr.vim", cmd = { "Hr", "HrToggle", "HrStart" },
  keys = { { "<leader>r", "<Cmd>HrToggle<CR>", desc = "hr reading list" } } }
```

Local checkout while developing:

```lua
{ dir = "~/hr.vim", cmd = { "Hr", "HrStart" } }
```

**vim-plug**

```vim
Plug 'isdg/hr.vim'
```

**Built-in package (no manager)** — Vim or Neovim:

```sh
git clone https://github.com/isdg/hr.vim \
  ~/.vim/pack/plugins/start/hr.vim          # Vim
git clone https://github.com/isdg/hr.vim \
  ~/.config/nvim/pack/plugins/start/hr.vim  # Neovim
```

Then `:helptags ALL` (or `:Helptags`) once to index the docs.

## Usage

| Command | Action |
| --- | --- |
| `:Hr` / `:HrToggle` | toggle the sidebar (on open, closes other windows — feed only) |
| `:HrOpen` / `:HrClose` | open / close (leaves other windows untouched) |
| `:HrStart` | panel only — entry point for the `hr` CLI |
| `:HrRefresh` | re-fetch the list |
| `:HrSync` | `hr sync` then refresh |
| `:HrFilter [flags]` | scope the panel; no args reports, `-` clears |

`:Hr`, `:HrToggle`, `:HrOpen` and `:HrStart` also take optional `hr list`
flags that scope the panel:

```vim
:Hr --group books                  " one shelf
:HrStart --feed matklad,danluu     " one or more authors
:HrFilter --group sites --unread   " flags compose
:HrFilter -                        " drop the scope
```

The plugin doesn't interpret them — it appends them to `hr list --json`, so
the CLI stays the only authority on what a flag means and nothing here needs
changing when `hr` grows a new one. A scoped panel shows the filter in its
buffer name (`hr://reading-list --group books`) so a narrow view can't be
mistaken for an empty vault.

From the shell, the `hrv` function (in isg's dotfiles, `zsh/fzf.zsh`) is a
thin wrapper over this: `hrv --group books` validates the flags against the
CLI, then launches `nvim -c "HrStart --group books"`.

Keys inside the sidebar:

| Key | Action |
| --- | --- |
| `<CR>`, `o` | open article |
| `r` | toggle read / unread |
| `u` | mark unread |
| `f` | toggle favorite |
| `a` | set alias (rename label) |
| `R` / `s` | refresh / sync + refresh |
| `q` | close |
| `?` | help |

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `g:hr_binary` | `"hr"` | CLI name or path |
| `g:hr_vault` | `""` | vault dir; empty → read from `~/.hrrc` and `:cd` into it |
| `g:hr_side` | `"left"` | sidebar side (`left`/`right`) |
| `g:hr_width` | `60` | sidebar width in columns |
| `g:hr_show_read` | `1` | `1` = include read items, `0` = unread only |
| `g:hr_filter` | `[]` | extra `hr list` flags scoping the panel |

```lua
-- Neovim
vim.g.hr_width = 50
```

```vim
" Vim
let g:hr_width = 50
```

See `:help hr` for full documentation.
