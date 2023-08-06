:set number
:set ruler
:syntax on
:set bs=2
":set expandtab
":set tabstop=4
":set shiftwidth=4
:set noautoindent

"prevent exploit CVE-2019-12735
:set nomodeline

autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o


autocmd! BufNewFile,BufRead *.pde setlocal ft=arduino
autocmd! BufNewFile,BufRead *.rs setlocal ft=rust
autocmd! BufNewFile,BufRead *.nl setlocal ft=neulang

" highlight all hard tabs
":highlight HardTabs ctermbg=green guibg=green
":syntax match HardTabs /\t/ containedin=ALL

" highlight only trailing tabs (including blank lines)
":highlight TrailingTabs ctermbg=green guibg=green
":syntax match TrailingTabs /\t\+$/ containedin=ALL

" highlight trailing spaces
":highlight TrailingSpaces ctermbg=blue guibg=blue
" including blank lines
":syntax match TrailingSpaces /\s\+$/ containedin=ALL
" not including blank lines
":syntax match TrailingSpaces /\S\zs\s\+$/ containedin=ALL

":highlight ExtraWhitespace ctermbg=red guibg=red
" any tab character
":syntax match ExtraWhitespace /\t/
" tab or any trailing spaces (including blank lines)
":syntax match ExtraWhitespace /\t\|\s\+$/
" tab or any trailing spaces (not including blank lines)
":syntax match ExtraWhitespace /\t\|\S\zs\s\+$/


":highlight TODOs ctermbg=yellow guibg=yellow
":syntax match TODOs /TODO\|NOTE/

:autocmd BufRead,BufNewFile *.todo,todo.txt set filetype=todo
:autocmd BufRead,BufNewFile .guile set filetype=scheme

"enable indent-based code folding in vim
set foldmethod=indent   
set foldnestmax=10
set nofoldenable
set foldlevel=4

:function! Space_Indent(count)
"	:echo 'Switching to space indenting with '.a:count.' spaces per tab'
	
	" toggle syntax off and on to re-set any existing whitespace highlighting
	:syntax off
	:syntax on
	
	:set expandtab
	:let &tabstop=a:count
	:let &shiftwidth=a:count
"	:set tabstop=4
"	:set shiftwidth=4
	
	" highlight all hard tabs
	:highlight HardTabs ctermbg=green guibg=green
	:syntax match HardTabs /\t/ containedin=ALL
	
	" highlight trailing spaces
	:highlight TrailingSpaces ctermbg=blue guibg=blue
	" including blank lines
	:syntax match TrailingSpaces /\s\+$/ containedin=ALL
	
	" not including blank lines
	" :syntax match TrailingSpaces /\S\zs\s\+$/ containedin=ALL
	
:endfunction

:function! Tab_Indent()
	" toggle syntax off and on to re-set any existing whitespace highlighting
	:syntax off
	:syntax on
	
	:set noexpandtab
	:set tabstop=8
	:set shiftwidth=8
	
	" highlight trailing spaces
	:highlight TrailingSpaces ctermbg=blue guibg=blue
	" including blank lines
	:syntax match TrailingSpaces / \+$/ containedin=ALL
	" :syntax match TrailingSpaces / \+$\|  \+/ containedin=ALL
	
	" highlight only trailing tabs (including blank lines)
	:highlight TrailingTabs ctermbg=green guibg=green
	:syntax match TrailingTabs /\t\+$/ containedin=ALL
:endfunction

" User proper tab indenting
":call Tab_Indent()

" Use space indenting instead of (the correct and proper) tab indenting
":call Space_Indent(4)

"automatically scroll down every so often based on the provided delay
:function! Autoscroll(delay_ms)
	" NOTE: vimscript does NOT tailcall optimize
	" so this recursive solution has limited value
	" but is left for reference
"	:exe "normal \<C-e>"
"	:let delay_ms=a:delay_ms.'m'
"	:exe 'sleep '.delay_ms
"	:normal j
"	:redraw
"	:exe 'call Autoscroll('.a:delay_ms.')'
	
	" this iterative solution works better
	:let current_line=line(".")
	:let last_line=line("$")
	:while current_line<=last_line
		:exe "normal \<C-e>"
		:let delay_ms=a:delay_ms.'m'
		:exe 'sleep '.delay_ms
		:normal j
		:redraw
		
		:let current_line+=1
	:endwhile
:endfunction


" re-bind vim shortcuts which conflict with gnu screen (for example ctrl+a can't increment under screen, so I use ctrl+pgup and ctrl+pgdn for inc/dec)
":noremap <C-PageUp> <C-A>
":noremap <C-PageDown> <C-X>
":nnoremap <M-PageUp> <C-A>
":nnoremap <M-PageDown> <C-X>

"okay nvm, so, ctrl+i is increment, ctrl+x is decrement
"this allows me to have that functionality in screen and only modify a single vim keybinding
":noremap <C-I> <C-A>

"next and prev? (previously these went a line up or a line down, but I use the arrows for that anyway)
:noremap <C-N> <C-A>
:noremap <C-P> <C-X>

"fast re-search (research? get it?)
"this just avoids having to type / a bunch of times to search for terms that have more than one hit
:noremap <F3> <Esc>/<Return>
":noremap <S-F3> <Esc>?<Return>

"when running under tmux (and ONLY when running under tmux), rename the tmux pane to the name of the file
autocmd BufEnter * call system("if [ \"$(pstree -s -p $PPID | fgrep -o 'tmux')\" == 'tmux' ] ; then tmux rename-window \"".expand("%:t")."\" ; fi")
autocmd VimLeave * call system("if [ \"$(pstree -s -p $PPID | fgrep -o 'tmux')\" == 'tmux' ] ; then tmux rename-window bash; tmux set-option automatic-rename on ; fi")
autocmd BufEnter * let &titlestring=' '.expand("%:t")
set title

" this is a super nasty hack but I'm pretty proud of it; it's effective, portable, and will slap you
" be sure this vimrc takes precedence over anything else (everything else)
:autocmd BufRead,BufNewFile * so $MYVIMRC

