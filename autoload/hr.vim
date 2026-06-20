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
function! s:run(args) abort
  let l:cmd = join(map(s:base_cmd() + a:args, 'shellescape(v:val)'), ' ')
  let l:out = system(l:cmd)
  if v:shell_error != 0
    echohl ErrorMsg
    echomsg 'hr: ' . substitute(l:out, '\n', ' ', 'g')
    echohl NONE
    return [0, '']
  endif
  return [1, l:out]
endfunction

function! s:fetch_items() abort
  let l:args = ['list', '--json']
  if !s:truthy(g:hr_show_read)
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
  let s:state.items = s:fetch_items()
  let l:lines = s:render(s:state.items)
  if empty(l:lines)
    let l:lines = ['(no articles)']
  endif
  call setbufvar(s:state.bufnr, '&modifiable', 1)
  silent call deletebufline(s:state.bufnr, 1, '$')
  call setbufline(s:state.bufnr, 1, l:lines)
  call setbufvar(s:state.bufnr, '&modifiable', 0)
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
        \ '  r       mark read',
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
  nnoremap <buffer><silent><nowait> r    :call <SID>act('read')<CR>
  nnoremap <buffer><silent><nowait> u    :call <SID>act('unread')<CR>
  nnoremap <buffer><silent><nowait> f    :call <SID>act('fav')<CR>
  nnoremap <buffer><silent><nowait> a    :call <SID>rename_current()<CR>
  nnoremap <buffer><silent><nowait> R    :call <SID>redraw()<CR>
  nnoremap <buffer><silent><nowait> s    :call <SID>sync_then_redraw()<CR>
  nnoremap <buffer><silent><nowait> q    :call hr#close()<CR>
  nnoremap <buffer><silent><nowait> ?    :call <SID>show_help()<CR>
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
