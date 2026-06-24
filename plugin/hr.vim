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
"
" Commands:
"   :Hr / :HrToggle   toggle the sidebar
"   :HrOpen :HrClose  open / close it
"   :HrStart          open panel only (entry point for the `hr` CLI)
"   :HrRefresh        re-fetch the list
"   :HrSync           sync feeds + refresh

if exists('g:loaded_hr')
  finish
endif
let g:loaded_hr = 1

let g:hr_binary       = get(g:, 'hr_binary', 'hr')
let g:hr_vault        = get(g:, 'hr_vault', '')
let g:hr_side         = get(g:, 'hr_side', 'left')
let g:hr_width        = get(g:, 'hr_width', 60)
let g:hr_show_read    = get(g:, 'hr_show_read', 1)
" Corruption marking inside opened articles:
"   g:hr_corrupt_maps    1 = install buffer-local maps (default 1)
"   g:hr_corrupt_prefix  key prefix for those maps    (default "<leader>n")
let g:hr_corrupt_maps   = get(g:, 'hr_corrupt_maps', 1)
let g:hr_corrupt_prefix = get(g:, 'hr_corrupt_prefix', '<leader>n')

command! -bar -nargs=0 Hr        call hr#toggle()
command! -bar -nargs=0 HrToggle  call hr#toggle()
command! -bar -nargs=0 HrOpen    call hr#open()
command! -bar -nargs=0 HrClose   call hr#close()
command! -bar -nargs=0 HrStart   call hr#start()
command! -bar -nargs=0 HrRefresh call hr#refresh()
command! -bar -nargs=0 HrSync    call hr#sync()

" Corruption marking — usable in any saved article buffer. :HrCorrupt is
" range-aware, so it works straight from a visual selection (:'<,'>HrCorrupt)
" and takes an optional note; :HrCorruptUndo drops the most recent mark.
command! -bar -range -nargs=? HrCorrupt     call hr#corrupt(<q-args>)
command! -bar          -nargs=0 HrCorruptUndo call hr#corrupt_undo()

" <Plug> targets so a config can bind its own keys (the buffer-local
" defaults installed on opened articles point at these).
xnoremap <silent> <Plug>(HrCorrupt)     :<C-u>call hr#corrupt('')<CR>
xnoremap <silent> <Plug>(HrCorruptNote) :<C-u>call hr#corrupt(input('corruption note: '))<CR>
nnoremap <silent> <Plug>(HrCorruptUndo) :<C-u>call hr#corrupt_undo()<CR>
