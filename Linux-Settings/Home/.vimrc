" ------------------------
" some settings
" ------------------------
set nocompatible
filetype plugin indent on
syntax on
set encoding=utf-8
set background=dark
set t_Co=256
set termguicolors
set number
set relativenumber
set smartcase           " Enable smart-case search
set ignorecase          " Always case-insensitive
set incsearch           " Searches for strings incrementally
set hlsearch
set autoindent          " Auto-indent new lines
set expandtab           " Use spaces instead of tabs
set shiftwidth=2        " Number of auto-indent spaces
set smartindent         " Enable smart-indent
set smarttab            " Enable smart-tabs
set softtabstop=2       " Number of spaces per Tab
set showcmd                     "Show incomplete cmds down the bottom
set showmode                    "Show current mode down the bottom
set gcr=a:blinkon0              "Disable cursor blink
set visualbell                  "No sounds
set autoread                    "Reload files changed outside vim
set ruler                       "Add the current line and column"
" This makes vim act like all other editors, buffers can
" exist in the background without being in a window.
" http://items.sjbach.com/319/configuring-vim-right
set hidden
set scrolloff=8         "Start scrolling when we're 8 lines away from margins
set sidescrolloff=15
set sidescroll=1
set lazyredraw          " Don't redraw while executing macros (good performance config)
" Use system clipboard for yanking and pasting
set clipboard=unnamed
" ================ Turn Off Swap Files ==============
set noswapfile
set nobackup
set nowb
" Auto indent pasted text
nnoremap p p=`]<C-o>
nnoremap P P=`]<C-o>

filetype plugin on
filetype indent on

set nowrap       "Don't wrap lines
set linebreak    "Wrap lines at convenient points
" ================ Folds ============================

set foldmethod=indent   "fold based on indent
set foldnestmax=3       "deepest fold is 3 levels
set nofoldenable        "dont fold by default
" ================ Completion =======================

set wildmode=list:longest
set wildmenu                "enable ctrl-n and ctrl-p to scroll thru matches
set wildignore=*.o,*.obj,*~ "stuff to ignore when tab completing
set wildignore+=*vim/backups*
set wildignore+=*sass-cache*
set wildignore+=*DS_Store*
set wildignore+=vendor/cache/**
set wildignore+=*.gem
set wildignore+=log/**
set wildignore+=tmp/**
set wildignore+=*.png,*.jpg,*.gif
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

" Don't expand tabs for Makefile
autocmd FileType make setlocal noexpandtab
