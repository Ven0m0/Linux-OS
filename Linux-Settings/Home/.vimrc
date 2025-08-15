" ------------------------
" some settings
" ------------------------
filetype plugin indent on
syntax on
set background=dark
set termguicolors
set number
set relativenumber
set smartcase           " Enable smart-case search
set ignorecase          " Always case-insensitive
set incsearch           " Searches for strings incrementally
set autoindent          " Auto-indent new lines
set expandtab           " Use spaces instead of tabs
set shiftwidth=2        " Number of auto-indent spaces
set smartindent         " Enable smart-indent
set smarttab            " Enable smart-tabs
set softtabstop=2       " Number of spaces per Tab
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
