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

let g:hr_binary    = get(g:, 'hr_binary', 'hr')
let g:hr_vault     = get(g:, 'hr_vault', '')
let g:hr_side      = get(g:, 'hr_side', 'left')
let g:hr_width     = get(g:, 'hr_width', 60)
let g:hr_show_read = get(g:, 'hr_show_read', 1)

command! -bar -nargs=0 Hr        call hr#toggle()
command! -bar -nargs=0 HrToggle  call hr#toggle()
command! -bar -nargs=0 HrOpen    call hr#open()
command! -bar -nargs=0 HrClose   call hr#close()
command! -bar -nargs=0 HrStart   call hr#start()
command! -bar -nargs=0 HrRefresh call hr#refresh()
command! -bar -nargs=0 HrSync    call hr#sync()
