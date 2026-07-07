" ============================================================
"                          hr.vim — autoload
" ============================================================
" Implementation of the reading-list sidebar. Portable Vimscript:
" relies only on functions present in both Vim 8.1+ and Neovim
" (win_getid, win_id2win, getwininfo, json_decode, setbufline, ...).
"
" Buffer-local keys (active only in the sidebar):
"   <CR>/o open   r read   u unread   f fav   a alias
"   R refresh   s sync   q close   ? help

let s:state = {'winid': -1, 'bufnr': -1, 'prev_winid': -1, 'items': []}

" ── helpers ────────────────────────────────────────────────

function! s:is_open() abort
  return s:state.winid > 0 && win_id2win(s:state.winid) != 0
endfunction

function! s:truthy(v) abort
  " json_decode yields v:true/v:false; treat both those and 1/0 uniformly.
  return type(a:v) == v:t_bool ? a:v is v:true : (!empty(a:v) && a:v != 0)
endfunction

function! s:vault_from_rc() abort
  let l:path = expand('~/.hrrc')
  if !filereadable(l:path)
    return ''
  endif
  for l:line in readfile(l:path)
    let l:m = matchlist(l:line, 'vault\s*=\s*"\([^"]*\)"')
    if !empty(l:m)
      return l:m[1]
    endif
  endfor
  return ''
endfunction

function! s:resolve_vault() abort
  return !empty(g:hr_vault) ? g:hr_vault : s:vault_from_rc()
endfunction

" Only pass -C when the vault is configured explicitly; when it comes from
" ~/.hrrc we cd into it instead (see hr#open), so the CLI finds it itself.
function! s:base_cmd() abort
  let l:cmd = [g:hr_binary]
  if !empty(g:hr_vault)
    call extend(l:cmd, ['-C', g:hr_vault])
  endif
  return l:cmd
endfunction

" Returns [ok, output]. Shows an error and returns [0, ''] on non-zero exit.
" When a:input is given (non-empty string), it is fed to the CLI on stdin.
function! s:run(args, ...) abort
  let l:cmd = join(map(s:base_cmd() + a:args, 'shellescape(v:val)'), ' ')
  let l:out = (a:0 >= 1) ? system(l:cmd, a:1) : system(l:cmd)
  if v:shell_error != 0
    echohl ErrorMsg
    echomsg 'hr: ' . substitute(l:out, '\n', ' ', 'g')
    echohl NONE
    return [0, '']
  endif
  return [1, l:out]
endfunction

" With a:1 truthy, ignore g:hr_show_read and return every article — used by
" locate, so a read item hidden by an unread-only view is still findable.
function! s:fetch_items(...) abort
  let l:all = a:0 >= 1 && a:1
  let l:args = ['list', '--json']
  if !l:all && !s:truthy(g:hr_show_read)
    call add(l:args, '--unread')
  endif
  let [l:ok, l:out] = s:run(l:args)
  if !l:ok || empty(l:out)
    return []
  endif
  try
    let l:decoded = json_decode(l:out)
  catch
    return []
  endtry
  return type(l:decoded) == v:t_list ? l:decoded : []
endfunction

function! s:render(items) abort
  let l:feed_w = 4
  for l:it in a:items
    let l:f = get(l:it, 'feed', '')
    if strlen(l:f) > l:feed_w
      let l:feed_w = strlen(l:f)
    endif
  endfor
  if l:feed_w > 20
    let l:feed_w = 20
  endif

  let l:lines = []
  for l:it in a:items
    let l:r     = s:truthy(get(l:it, 'read', 0))     ? 'R' : ' '
    let l:fav   = s:truthy(get(l:it, 'favorite', 0)) ? 'F' : ' '
    let l:date  = strpart(get(l:it, 'published', ''), 0, 10)
    let l:feed  = strpart(get(l:it, 'feed', ''), 0, l:feed_w)
    let l:alias = get(l:it, 'alias', '')
    let l:label = (type(l:alias) == v:t_string && l:alias !=# '')
          \ ? l:alias : get(l:it, 'title', '')
    call add(l:lines, printf('[%s%s] %s  %-' . l:feed_w . 's  %s',
          \ l:r, l:fav, l:date, l:feed, l:label))
  endfor
  return l:lines
endfunction

function! s:redraw() abort
  if !s:is_open()
    return
  endif
  " Rebuilding the buffer (delete-all + re-add) snaps the cursor back to
  " line 1, which reads as the item you just acted on jumping to the top
  " of the feed. Preserve the panel's view across the rewrite.
  let l:onpanel = win_getid() == s:state.winid
  let l:view = l:onpanel ? winsaveview() : {}

  let s:state.items = s:fetch_items()
  let l:lines = s:render(s:state.items)
  if empty(l:lines)
    let l:lines = ['(no articles)']
  endif
  call setbufvar(s:state.bufnr, '&modifiable', 1)
  silent call deletebufline(s:state.bufnr, 1, '$')
  call setbufline(s:state.bufnr, 1, l:lines)
  call setbufvar(s:state.bufnr, '&modifiable', 0)

  if l:onpanel
    call winrestview(l:view)
  endif
endfunction

" The item under the cursor. Mappings run with the panel as the current
" window, so line('.') is the panel row.
function! s:current_item() abort
  if !s:is_open()
    return {}
  endif
  let l:row = line('.')
  if l:row < 1 || l:row > len(s:state.items)
    return {}
  endif
  return s:state.items[l:row - 1]
endfunction

" ── actions (script-local; invoked from buffer mappings) ────

function! s:open_current() abort
  let l:it = s:current_item()
  if empty(l:it)
    return
  endif

  let l:target = s:state.prev_winid
  if !(l:target > 0 && win_id2win(l:target) != 0 && l:target != s:state.winid)
    let l:target = 0
  endif

  if l:target
    call win_gotoid(l:target)
  else
    wincmd l
    if win_getid() == s:state.winid
      rightbelow vsplit
    endif
  endif

  execute 'edit ' . fnameescape(get(l:it, 'path', ''))
  " A split spawned from the panel inherits its window-local options
  " (signcolumn=no, winfixwidth, cursorline); restore normal-file defaults so
  " the git gutter shows and the article window can be resized.
  setlocal signcolumn=yes nowinfixwidth nocursorline
  call s:setup_article_keymaps()
  let s:state.prev_winid = win_getid()
endfunction

function! s:act(cmd) abort
  let l:it = s:current_item()
  if empty(l:it)
    return
  endif
  call s:run([a:cmd, get(l:it, 'path', '')])
  call s:redraw()
endfunction

" Flip the read state of the item under the cursor (read if unread, and
" vice versa), driven by the state already in s:state.items.
function! s:toggle_read() abort
  let l:it = s:current_item()
  if empty(l:it)
    return
  endif
  let l:cmd = s:truthy(get(l:it, 'read', 0)) ? 'unread' : 'read'
  call s:run([l:cmd, get(l:it, 'path', '')])
  call s:redraw()
endfunction

function! s:rename_current() abort
  let l:it = s:current_item()
  if empty(l:it)
    return
  endif
  let l:alias = get(l:it, 'alias', '')
  let l:default = (type(l:alias) == v:t_string && l:alias !=# '')
        \ ? l:alias : get(l:it, 'title', '')
  let l:new = input('Alias (empty to clear): ', l:default)
  call s:run(['alias', get(l:it, 'path', ''), l:new])
  call s:redraw()
  redraw
endfunction

function! s:sync_then_redraw() abort
  call s:run(['sync'])
  call s:redraw()
endfunction

function! s:show_help() abort
  echo join([
        \ 'hr keys:',
        \ '  <CR>/o  open article',
        \ '  r       toggle read',
        \ '  u       mark unread',
        \ '  f       toggle favorite',
        \ '  a       set alias (rename label)',
        \ '  R       refresh',
        \ '  s       sync + refresh',
        \ '  q       close panel',
        \ '  ?       this help',
        \ ], "\n")
endfunction

function! s:setup_keymaps() abort
  nnoremap <buffer><silent><nowait> <CR> :call <SID>open_current()<CR>
  nnoremap <buffer><silent><nowait> o    :call <SID>open_current()<CR>
  nnoremap <buffer><silent><nowait> r    :call <SID>toggle_read()<CR>
  nnoremap <buffer><silent><nowait> u    :call <SID>act('unread')<CR>
  nnoremap <buffer><silent><nowait> f    :call <SID>act('fav')<CR>
  nnoremap <buffer><silent><nowait> a    :call <SID>rename_current()<CR>
  nnoremap <buffer><silent><nowait> R    :call <SID>redraw()<CR>
  nnoremap <buffer><silent><nowait> s    :call <SID>sync_then_redraw()<CR>
  nnoremap <buffer><silent><nowait> q    :call hr#close()<CR>
  nnoremap <buffer><silent><nowait> ?    :call <SID>show_help()<CR>
endfunction

" ── corruption marking (used inside an opened article) ──────
"
" These operate on the article in the *current* window, not the panel:
" the user selects the garbled text and marks it, so an LLM can repair it
" later via `hr corrupt list --all --json` / `hr corrupt restore`.

" The exclusive 0-based end byte column for a selection ending at the
" 1-based byte column a:col on line a:lnum. With the default inclusive
" 'selection', '> points at the last selected char, so we step past it
" (rune-aware); 'exclusive' already points one past, so col-1 is the end.
function! s:excl_endcol(lnum, col) abort
  if &selection ==# 'exclusive'
    return a:col - 1
  endif
  let l:line = getline(a:lnum)
  if a:col - 1 >= strlen(l:line)
    return strlen(l:line)
  endif
  let l:ch = matchstr(l:line, '.', a:col - 1)
  return (a:col - 1) + max([1, strlen(l:ch)])
endfunction

" The text of the last visual selection, leaving registers and cursor
" untouched. This is the source of truth the binary cross-checks the
" --range against (mismatched ranges are rejected, not silently stored).
function! s:visual_text() abort
  let l:save_reg  = getreg('"')
  let l:save_type = getregtype('"')
  let l:save_pos  = getcurpos()
  silent normal! gvy
  let l:text = getreg('"')
  call setreg('"', l:save_reg, l:save_type)
  call setpos('.', l:save_pos)
  return l:text
endfunction

function! s:article_path() abort
  if &buftype !=# '' || empty(expand('%'))
    echohl WarningMsg
    echomsg 'hr: not a saved article buffer'
    echohl NONE
    return ''
  endif
  return expand('%:p')
endfunction

" Mark the current visual selection corrupted. Optional argument is a note.
function! hr#corrupt(...) abort
  let l:path = s:article_path()
  if empty(l:path)
    return
  endif

  let [l:_b1, l:l1, l:c1, l:_o1] = getpos("'<")
  let [l:_b2, l:l2, l:c2, l:_o2] = getpos("'>")
  if l:l1 == 0 || l:l2 == 0
    echohl WarningMsg | echomsg 'hr: no visual selection' | echohl NONE
    return
  endif

  " 1-based lines, 0-based byte columns, end exclusive — the hr contract.
  let l:range = printf('%d:%d-%d:%d',
        \ l:l1, l:c1 - 1, l:l2, s:excl_endcol(l:l2, l:c2))

  let l:args = ['corrupt', l:path, '--range', l:range]
  let l:note = (a:0 >= 1) ? a:1 : ''
  if !empty(l:note)
    call extend(l:args, ['--note', l:note])
  endif

  let [l:ok, l:out] = s:run(l:args, s:visual_text())
  if l:ok
    echo substitute(l:out, '\n\+$', '', '')
  endif
endfunction

" Undo the most recent corruption mark on the current article.
function! hr#corrupt_undo() abort
  let l:path = s:article_path()
  if empty(l:path)
    return
  endif
  let [l:ok, l:out] = s:run(['corrupt', 'undo', l:path])
  if l:ok
    echo substitute(l:out, '\n\+$', '', '')
  endif
endfunction

" 1-based row of the item whose path matches a:target (a canonical absolute
" path), or 0 when none does. Paths are compared canonically so symlinks and
" relative CLI paths still match a buffer's absolute path.
function! s:row_of(items, target) abort
  let l:i = 0
  for l:it in a:items
    let l:i += 1
    if resolve(fnamemodify(get(l:it, 'path', ''), ':p')) ==# a:target
      return l:i
    endif
  endfor
  return 0
endfunction

" Locate the current article in the feed. Run from any saved article buffer:
" if the file belongs to the feed, close the article window, open the panel
" (when closed) and put the cursor on its row so you can manage it there; if
" it does not, do nothing.
function! hr#locate() abort
  let l:src = win_getid()
  let l:path = s:article_path()
  if empty(l:path)
    return
  endif
  let l:target = resolve(fnamemodify(l:path, ':p'))

  " Membership is checked before touching windows (so a non-feed file never
  " spawns a panel) and against the *unfiltered* list, so a read article is
  " found even under an unread-only view.
  let l:all = s:fetch_items(1)
  let l:idx = s:row_of(l:all, l:target)
  if l:idx == 0
    echohl WarningMsg
    echomsg 'hr: article not in the feed'
    echohl NONE
    return
  endif

  " The cursor can only land on a rendered row, so if this article is read
  " and the panel is unread-only, switch to showing read items — otherwise
  " its row would not exist. This changes g:hr_show_read for the session.
  if !s:truthy(g:hr_show_read) && s:truthy(get(l:all[l:idx - 1], 'read', 0))
    let g:hr_show_read = 1
  endif

  if !s:is_open()
    call hr#open()
  else
    call s:redraw()
  endif
  if !s:is_open()
    return
  endif

  " Recompute against what the panel actually rendered.
  let l:row = s:row_of(s:state.items, l:target)
  if l:row == 0
    return
  endif
  call win_gotoid(s:state.winid)
  call cursor(l:row, 1)

  " Close the window the article was in, leaving the feed. Skip it when that
  " window is the panel itself or has already gone (e.g. hr#open reused it).
  if l:src != s:state.winid && win_id2win(l:src) != 0 && winnr('$') > 1
    call win_gotoid(l:src)
    close
    call win_gotoid(s:state.winid)
  endif
endfunction

" Install the buffer-local corruption mappings on an article opened from
" the panel (no-op when the user has turned defaults off). The <Plug>
" targets exist regardless, so a custom config can map them anywhere.
function! s:setup_article_keymaps() abort
  if !get(g:, 'hr_corrupt_maps', 1)
    return
  endif
  let l:p = get(g:, 'hr_corrupt_prefix', '<leader>c')
  execute 'xnoremap <buffer><silent> ' . l:p . 'c <Plug>(HrCorrupt)'
  execute 'xnoremap <buffer><silent> ' . l:p . 'n <Plug>(HrCorruptNote)'
  execute 'nnoremap <buffer><silent> ' . l:p . 'u <Plug>(HrCorruptUndo)'
endfunction

" ── public API ─────────────────────────────────────────────

function! hr#open() abort
  if s:is_open()
    call win_gotoid(s:state.winid)
    return
  endif

  let l:vault = s:resolve_vault()
  if !empty(l:vault)
    execute 'silent! cd ' . fnameescape(l:vault)
  endif
  let s:state.prev_winid = win_getid()

  let l:prefix = (g:hr_side ==# 'left') ? 'topleft' : 'botright'
  execute l:prefix . ' ' . g:hr_width . 'vnew'
  let s:state.winid = win_getid()
  let s:state.bufnr = bufnr('%')

  setlocal buftype=nofile bufhidden=wipe noswapfile
  setlocal filetype=hr
  silent! keepalt file hr://reading-list
  setlocal number norelativenumber nowrap signcolumn=no cursorline winfixwidth

  call s:setup_keymaps()
  call s:redraw()
endfunction

function! hr#close() abort
  if s:is_open()
    let l:cur = win_getid()
    call win_gotoid(s:state.winid)
    close!
    if l:cur != s:state.winid && win_id2win(l:cur) != 0
      call win_gotoid(l:cur)
    endif
  endif
  let s:state.winid = -1
  let s:state.bufnr = -1
  let s:state.items = []
endfunction

function! hr#toggle() abort
  if s:is_open()
    call hr#close()
  else
    call hr#open()
    " Close every other window, leaving the feed as the only one. The bang
    " hides modified buffers instead of refusing (no buffer content is lost).
    if s:is_open()
      call win_gotoid(s:state.winid)
      silent! only!
      " Now the sole window, the panel no longer has a sibling to open
      " articles into; clear the stale target so s:open_current() makes one.
      let s:state.prev_winid = -1
    endif
  endif
endfunction

function! hr#refresh() abort
  call s:redraw()
endfunction

function! hr#sync() abort
  call s:sync_then_redraw()
endfunction

" Open the panel only, closing the initial empty [No Name] window if there
" is one. Entry point for the `hr` CLI: panel, no placeholder, no auto-open.
function! hr#start() abort
  call hr#open()

  let l:prev = s:state.prev_winid
  if !(l:prev > 0 && l:prev != s:state.winid && win_id2win(l:prev) != 0)
    return
  endif

  let l:info = getwininfo(l:prev)
  if empty(l:info)
    return
  endif
  let l:buf = l:info[0].bufnr
  if bufname(l:buf) ==# '' && !getbufvar(l:buf, '&modified')
        \ && len(getbufline(l:buf, 1, '$')) <= 1 && winnr('$') > 1
    let l:cur = win_getid()
    call win_gotoid(l:prev)
    close
    if win_id2win(l:cur) != 0
      call win_gotoid(l:cur)
    endif
  endif
endfunction
