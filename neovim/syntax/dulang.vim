if exists("b:current_syntax")
  finish
endif

set tabstop=2
set softtabstop=2
set shiftwidth=2
set expandtab

" Variable Names / Identifiers
" Matches lowercase words, parameters like (name), or standard identifiers
syntax match variable /[a-z_][a-zA-Z0-9_]*/
syntax match atom /@[a-z_][a-zA-Z0-9_]*/

" Keywords
syntax keyword keywords mod pub fn false if match
syntax keyword boolean true false

syntax match function "\v<\w+>(\s*\()@="
syntax match module "\<\h\w*\>\ze:"

" Comments (Starts with $ up to the end of the line)
syntax match comment "\$.*$"

" Numbers (Integers and Decimals like 1000 and 1.0)
syntax match number "\<\d\+\(\.\d\+\)\?\>"

" Strings
syntax region string start=/"/ skip=/\\"/ end=/"/


" 2. CUSTOM COLOR DEFINITIONS (No linking!)
hi keywords ctermfg=203 guifg=#ff5f5f gui=bold
hi boolean ctermfg=180 guifg=#4ffba8
hi function ctermfg=190 guifg=#4e85de gui=bold
hi module ctermfg=190 guifg=#4e85de gui=bold
hi comment ctermfg=242 guifg=#6c6c6c gui=italic
hi number ctermfg=141 guifg=#afa7ff
hi string ctermfg=114 guifg=#bbfbbb
hi variable ctermfg=253 guifg=#fadada
hi atom ctermfg=253 guifg=#f7f77c

let b:current_syntax = "mylang"
