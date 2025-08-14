" ------------------------
" some settings
" ------------------------
filetype plugin indent on
syntax on
set background=dark
set termguicolors
set number
set relativenumber
" ------------------------
" keys
" ------------------------
" File ops
nnoremap <leader>f :FZF<CR>
nnoremap <leader>s :w<CR>
nnoremap <leader>wq :wq<CR>
" buffers
nnoremap <leader>n :bnext<CR>
nnoremap <leader>p :bprev<CR>
" quit
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa!<CR>
"  numbers
nnoremap <leader>l :set number!<CR>
nnoremap <leader>r :set relativenumber!<CR>
" window nav
nnoremap <leader>h <C-w>h
nnoremap <leader>j <C-w>j
nnoremap <leader>k <C-w>k
nnoremap <leader>l <C-w>l
