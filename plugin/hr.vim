" ============================================================
"                          hr.vim
" ============================================================
" A reading-list sidebar backed by the `hr` CLI.
" Works in both Vim 8+ and Neovim (pure Vimscript, no Lua).
"
" Configuration (set before the plugin loads, or any time):
"   g:hr_binary     CLI name/path            (default "hr")
"   g:hr_vault      vault dir; ""/unset      (default reads ~/.hrrc)
"   g:hr_side       "left" | "right"         (default "left")
"   g:hr_width      sidebar columns          (default 60)
"   g:hr_show_read  1 = include read items   (default 1)
"   g:hr_filter     extra `hr list` flags    (default [])
"
" Commands:
"   :Hr / :HrToggle   toggle the sidebar
"   :HrOpen :HrClose  open / close it
"   :HrStart          open panel only (entry point for the `hr` CLI)
"   :HrRefresh        re-fetch the list
"   :HrSync           sync feeds + refresh
"   :HrFilter         set/report the flags scoping the panel
"
" :Hr, :HrToggle, :HrOpen and :HrStart take optional `hr list` flags that
" scope the panel, e.g. `:Hr --group books` or `:HrStart --feed matklad
" --unread`. hr owns the vocabulary; the plugin only forwards, so any flag
" `hr list` accepts works. `:HrFilter -` clears the scope.

if exists('g:loaded_hr')
  finish
endif
let g:loaded_hr = 1

let g:hr_binary       = get(g:, 'hr_binary', 'hr')
let g:hr_vault        = get(g:, 'hr_vault', '')
let g:hr_side         = get(g:, 'hr_side', 'left')
let g:hr_width        = get(g:, 'hr_width', 60)
let g:hr_show_read    = get(g:, 'hr_show_read', 1)
" Extra `hr list` flags scoping the panel: a list (['--group','books']) or a
" whitespace-separated string ('--group books').
let g:hr_filter       = get(g:, 'hr_filter', [])
" Corruption marking inside opened articles:
"   g:hr_corrupt_maps    1 = install buffer-local maps (default 1)
"   g:hr_corrupt_prefix  key prefix for those maps    (default "<leader>n")
let g:hr_corrupt_maps   = get(g:, 'hr_corrupt_maps', 1)
let g:hr_corrupt_prefix = get(g:, 'hr_corrupt_prefix', '<leader>n')

" The four openers take optional `hr list` flags; passing none leaves the
" current filter alone, so <leader>Hr keeps toggling the view you set up.
command! -bar -nargs=* Hr        call hr#toggle(<q-args>)
command! -bar -nargs=* HrToggle  call hr#toggle(<q-args>)
command! -bar -nargs=* HrOpen    call hr#open(<q-args>)
command! -bar -nargs=0 HrClose   call hr#close()
command! -bar -nargs=* HrStart   call hr#start(<q-args>)
command! -bar -nargs=0 HrRefresh call hr#refresh()
command! -bar -nargs=0 HrSync    call hr#sync()
command! -bar -nargs=* HrFilter  call hr#filter(<q-args>)

" Corruption marking — usable in any saved article buffer. :HrCorrupt is
" range-aware, so it works straight from a visual selection (:'<,'>HrCorrupt)
" and takes an optional note; :HrCorruptUndo drops the most recent mark.
command! -bar -range -nargs=? HrCorrupt     call hr#corrupt(<q-args>)
command! -bar          -nargs=0 HrCorruptUndo call hr#corrupt_undo()

" Jump from an opened article to its row in the feed panel.
command! -bar -nargs=0 HrLocate call hr#locate()

" <Plug> targets so a config can bind its own keys (the buffer-local
" defaults installed on opened articles point at these).
xnoremap <silent> <Plug>(HrCorrupt)     :<C-u>call hr#corrupt('')<CR>
xnoremap <silent> <Plug>(HrCorruptNote) :<C-u>call hr#corrupt(input('corruption note: '))<CR>
nnoremap <silent> <Plug>(HrCorruptUndo) :<C-u>call hr#corrupt_undo()<CR>
nnoremap <silent> <Plug>(HrLocate)      :<C-u>call hr#locate()<CR>
