" Copyright (c) 2017 Junegunn Choi
"
" MIT License
"
" Permission is hereby granted, free of charge, to any person obtaining
" a copy of this software and associated documentation files (the
" "Software"), to deal in the Software without restriction, including
" without limitation the rights to use, copy, modify, merge, publish,
" distribute, sublicense, and/or sell copies of the Software, and to
" permit persons to whom the Software is furnished to do so, subject to
" the following conditions:
"
" The above copyright notice and this permission notice shall be
" included in all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
" EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
" MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
" NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
" LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
" OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
" WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

let s:cpo_save = &cpo
set cpo&vim

" ------------------------------------------------------------------
" Common
" ------------------------------------------------------------------

let s:is_win = has('win32') || has('win64')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:h:h:h').'/bin/'
let s:bin = {
\ 'preview': s:bin_dir.'preview.sh',
\ 'tags':    s:bin_dir.'tags.pl' }
let s:TYPE = {'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}
if s:is_win
  if has('nvim')
    let s:bin.preview = split(system('for %A in ("'.s:bin.preview.'") do @echo %~sA'), "\n")[0]
  else
    let s:bin.preview = fnamemodify(s:bin.preview, ':8')
  endif
  let s:bin.preview = 'bash '.escape(s:bin.preview, '\')
endif

let s:wide = 120

function! s:extend_opts(dict, eopts, prepend)
  if empty(a:eopts)
    return
  endif
  if has_key(a:dict, 'options')
    if type(a:dict.options) == s:TYPE.list && type(a:eopts) == s:TYPE.list
      if a:prepend
        let a:dict.options = extend(copy(a:eopts), a:dict.options)
      else
        call extend(a:dict.options, a:eopts)
      endif
    else
      let all_opts = a:prepend ? [a:eopts, a:dict.options] : [a:dict.options, a:eopts]
      let a:dict.options = join(map(all_opts, 'type(v:val) == s:TYPE.list ? join(map(copy(v:val), "fzf#shellescape(v:val)")) : v:val'))
    endif
  else
    let a:dict.options = a:eopts
  endif
endfunction

function! s:merge_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 0)
endfunction

function! s:prepend_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 1)
endfunction

" [[options to wrap], [preview window expression], [toggle-preview keys...]]
function! fzf#vim#with_preview(...)
  " Default options
  let options = {}
  let window = 'right'

  let args = copy(a:000)

  " Options to wrap
  if len(args) && type(args[0]) == s:TYPE.dict
    let options = copy(args[0])
    call remove(args, 0)
  endif

  " Preview window
  if len(args) && type(args[0]) == s:TYPE.string
    if args[0] !~# '^\(up\|down\|left\|right\)'
      throw 'invalid preview window: '.args[0]
    endif
    let window = args[0]
    call remove(args, 0)
  endif

  let preview = ['--preview-window', window, '--preview', (s:is_win ? s:bin.preview : fzf#shellescape(s:bin.preview)).' {}']

  if len(args)
    call extend(preview, ['--bind', join(map(args, 'v:val.":toggle-preview"'), ',')])
  endif
  call s:merge_opts(options, preview)
  return options
endfunction

function! s:remove_layout(opts)
  for key in s:layout_keys
    if has_key(a:opts, key)
      call remove(a:opts, key)
    endif
  endfor
  return a:opts
endfunction

function! s:wrap(name, opts, bang)
  " fzf#wrap does not append --expect if sink or sink* is found
  let opts = copy(a:opts)
  let options = ''
  if has_key(opts, 'options')
    let options = type(opts.options) == s:TYPE.list ? join(opts.options) : opts.options
  endif
  if options !~ '--expect' && has_key(opts, 'sink*')
    let Sink = remove(opts, 'sink*')
    let wrapped = fzf#wrap(a:name, opts, a:bang)
    let wrapped['sink*'] = Sink
  else
    let wrapped = fzf#wrap(a:name, opts, a:bang)
  endif
  return wrapped
endfunction

function! s:strip(str)
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! s:chomp(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:escape(path)
  let path = fnameescape(a:path)
  return s:is_win ? escape(path, '$') : path
endfunction

if v:version >= 704
  function! s:function(name)
    return function(a:name)
  endfunction
else
  function! s:function(name)
    " By Ingo Karkat
    return function(substitute(a:name, '^s:', matchstr(expand('<sfile>'), '<SNR>\d\+_\zefunction$'), ''))
  endfunction
endif

function! s:get_color(attr, ...)
  let gui = has('termguicolors') && &termguicolors
  let fam = gui ? 'gui' : 'cterm'
  let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
  for group in a:000
    let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
    if code =~? pat
      return code
    endif
  endfor
  return ''
endfunction

let s:ansi = {'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36}

function! s:csi(color, fg)
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] == '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...)
  let fg = s:get_color('fg', a:group)
  let bg = s:get_color('bg', a:group)
  let color = (empty(fg) ? s:ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.s:csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
  execute "function! s:".s:color_name."(str, ...)\n"
        \ "  return s:ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
        \ "endfunction"
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") != "qf"')
endfunction

function! s:fzf(name, opts, extra)
  let [extra, bang] = [{}, 0]
  if len(a:extra) <= 1
    let first = get(a:extra, 0, 0)
    if type(first) == s:TYPE.dict
      let extra = first
    else
      let bang = first
    endif
  elseif len(a:extra) == 2
    let [extra, bang] = a:extra
  else
    throw 'invalid number of arguments'
  endif

  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  call s:merge_opts(merged, eopts)
  return fzf#run(s:wrap(a:name, merged, bang))
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:action_for(key, ...)
  let default = a:0 ? a:1 : ''
  let Cmd = get(get(g:, 'fzf_action', s:default_action), a:key, default)
  return type(Cmd) == s:TYPE.string ? Cmd : default
endfunction

function! s:open(cmd, target)
  if stridx('edit', a:cmd) == 0 && fnamemodify(a:target, ':p') ==# expand('%:p')
    return
  endif
  execute a:cmd s:escape(a:target)
endfunction

function! s:align_lists(lists)
  let maxes = {}
  for list in a:lists
    let i = 0
    while i < len(list)
      let maxes[i] = max([get(maxes, i, 0), len(list[i])])
      let i += 1
    endwhile
  endfor
  for list in a:lists
    call map(list, "printf('%-'.maxes[v:key].'s', v:val)")
  endfor
  return a:lists
endfunction

function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function! s:fill_quickfix(list, ...)
  if len(a:list) > 1
    call setqflist(a:list)
    copen
    wincmd p
    if a:0
      execute a:1
    endif
  endif
endfunction

function! fzf#vim#_uniq(list)
  let visited = {}
  let ret = []
  for l in a:list
    if !empty(l) && !has_key(visited, l)
      call add(ret, l)
      let visited[l] = 1
    endif
  endfor
  return ret
endfunction

" ------------------------------------------------------------------
" Files
" ------------------------------------------------------------------
function! s:shortpath()
  let short = fnamemodify(getcwd(), ':~:.')
  if !has('win32unix')
    let short = pathshorten(short)
  endif
  let slash = (s:is_win && !&shellslash) ? '\' : '/'
  return empty(short) ? '~'.slash : short . (short =~ escape(slash, '\').'$' ? '' : slash)
endfunction

function! fzf#vim#files(dir, ...)
  let args = {}
  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      return s:warn('Invalid directory')
    endif
    let slash = (s:is_win && !&shellslash) ? '\\' : '/'
    let dir = substitute(a:dir, '[/\\]*$', slash, '')
    let args.dir = dir
  else
    let dir = s:shortpath()
  endif

  let args.options = ['-m', '--prompt', strwidth(dir) < &columns / 2 - 20 ? dir : '> ']
  call s:merge_opts(args, get(g:, 'fzf_files_options', []))
  return s:fzf('files', args, a:000)
endfunction

" ------------------------------------------------------------------
" Lines
" ------------------------------------------------------------------
function! s:line_handler(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let cmd = s:action_for(a:lines[0])
  if !empty(cmd) && stridx('edit', cmd) < 0
    execute 'silent' cmd
  endif

  let keys = split(a:lines[1], '\t')
  execute 'buffer' keys[0]
  execute keys[2]
  normal! ^zvzz
endfunction

function! fzf#vim#_lines(all)
  let cur = []
  let rest = []
  let buf = bufnr('')
  let longest_name = 0
  let display_bufnames = &columns > s:wide
  if display_bufnames
    let bufnames = {}
    for b in s:buflisted()
      let bufnames[b] = pathshorten(fnamemodify(bufname(b), ":~:."))
      let longest_name = max([longest_name, len(bufnames[b])])
    endfor
  endif
  let len_bufnames = min([15, longest_name])
  for b in s:buflisted()
    let lines = getbufline(b, 1, "$")
    if empty(lines)
      let path = fnamemodify(bufname(b), ':p')
      let lines = filereadable(path) ? readfile(path) : []
    endif
    if display_bufnames
      let bufname = bufnames[b]
      if len(bufname) > len_bufnames + 1
        let bufname = '…' . bufname[-len_bufnames+1:]
      endif
      let bufname = printf(s:green("%".len_bufnames."s", "Directory"), bufname)
    else
      let bufname = ''
    endif
    let linefmt = s:blue("%2d\t", "TabLine")."%s".s:yellow("\t%4d ", "LineNr")."\t%s"
    call extend(b == buf ? cur : rest,
    \ filter(
    \   map(lines,
    \       '(!a:all && empty(v:val)) ? "" : printf(linefmt, b, bufname, v:key + 1, v:val)'),
    \   'a:all || !empty(v:val)'))
  endfor
  return [display_bufnames, extend(cur, rest)]
endfunction

function! fzf#vim#lines(...)
  let [display_bufnames, lines] = fzf#vim#_lines(1)
  let nth = display_bufnames ? 3 : 2
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('lines', {
  \ 'source':  lines,
  \ 'sink*':   s:function('s:line_handler'),
  \ 'options': ['+m', '--tiebreak=index', '--prompt', 'Lines> ', '--ansi', '--extended', '--nth='.nth.'..', '--layout=reverse-list', '--tabstop=1', '--query', query]
  \}, args)
endfunction

" ------------------------------------------------------------------
" BLines
" ------------------------------------------------------------------
function! s:buffer_line_handler(lines)
  if len(a:lines) < 2
    return
  endif
  let qfl = []
  for line in a:lines[1:]
    let chunks = split(line, "\t", 1)
    let ln = chunks[0]
    let ltxt = join(chunks[1:], "\t")
    call add(qfl, {'filename': expand('%'), 'lnum': str2nr(ln), 'text': ltxt})
  endfor
  call s:fill_quickfix(qfl, 'cfirst')
  normal! m'
  let cmd = s:action_for(a:lines[0])
  if !empty(cmd)
    execute 'silent' cmd
  endif

  execute split(a:lines[1], '\t')[0]
  normal! ^zvzz
endfunction

function! s:buffer_lines(query)
  let linefmt = s:yellow(" %4d ", "LineNr")."\t%s"
  let fmtexpr = 'printf(linefmt, v:key + 1, v:val)'
  let lines = getline(1, '$')
  if empty(a:query)
    return map(lines, fmtexpr)
  end
  return filter(map(lines, 'v:val =~ a:query ? '.fmtexpr.' : ""'), 'len(v:val)')
endfunction

function! fzf#vim#buffer_lines(...)
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('blines', {
  \ 'source':  s:buffer_lines(query),
  \ 'sink*':   s:function('s:buffer_line_handler'),
  \ 'options': ['+m', '--tiebreak=index', '--multi', '--prompt', 'BLines> ', '--ansi', '--extended', '--nth=2..', '--layout=reverse-list', '--tabstop=1']
  \}, args)
endfunction

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------
function! fzf#vim#colors(...)
  let colors = split(globpath(&rtp, "colors/*.vim"), "\n")
  if has('packages')
    let colors += split(globpath(&packpath, "pack/*/opt/*/colors/*.vim"), "\n")
  endif
  return s:fzf('colors', {
  \ 'source':  fzf#vim#_uniq(map(colors, "substitute(fnamemodify(v:val, ':t'), '\\..\\{-}$', '', '')")),
  \ 'sink':    'colo',
  \ 'options': '+m --prompt="Colors> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" Locate
" ------------------------------------------------------------------
function! fzf#vim#locate(query, ...)
  return s:fzf('locate', {
  \ 'source':  'locate '.a:query,
  \ 'options': '-m --prompt "Locate> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" History[:/]
" ------------------------------------------------------------------
function! s:all_files()
  return fzf#vim#_uniq(map(
    \ filter([expand('%')], 'len(v:val)')
    \   + filter(map(s:buflisted_sorted(), 'bufname(v:val)'), 'len(v:val)')
    \   + filter(copy(v:oldfiles), "filereadable(fnamemodify(v:val, ':p'))"),
    \ 'fnamemodify(v:val, ":~:.")'))
endfunction

function! s:history_source(type)
  let max  = histnr(a:type)
  let fmt  = ' %'.len(string(max)).'d '
  let list = filter(map(range(1, max), 'histget(a:type, - v:val)'), '!empty(v:val)')
  return extend([' :: Press '.s:magenta('CTRL-E', 'Special').' to edit'],
    \ map(list, 's:yellow(printf(fmt, len(list) - v:key), "Number")." ".v:val'))
endfunction

nnoremap <plug>(-fzf-vim-do) :execute g:__fzf_command<cr>
nnoremap <plug>(-fzf-/) /
nnoremap <plug>(-fzf-:) :

function! s:history_sink(type, lines)
  if len(a:lines) < 2
    return
  endif

  let prefix = "\<plug>(-fzf-".a:type.')'
  let key  = a:lines[0]
  let item = matchstr(a:lines[1], ' *[0-9]\+ *\zs.*')
  if key == 'ctrl-e'
    call histadd(a:type, item)
    redraw
    call feedkeys(a:type."\<up>", 'n')
  else
    if a:type == ':'
      call histadd(a:type, item)
    endif
    let g:__fzf_command = "normal ".prefix.item."\<cr>"
    call feedkeys("\<plug>(-fzf-vim-do)")
  endif
endfunction

function! s:cmd_history_sink(lines)
  call s:history_sink(':', a:lines)
endfunction

function! fzf#vim#command_history(...)
  return s:fzf('history-command', {
  \ 'source':  s:history_source(':'),
  \ 'sink*':   s:function('s:cmd_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist:> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! s:search_history_sink(lines)
  call s:history_sink('/', a:lines)
endfunction

function! fzf#vim#search_history(...)
  return s:fzf('history-search', {
  \ 'source':  s:history_source('/'),
  \ 'sink*':   s:function('s:search_history_sink'),
  \ 'options': '+m --ansi --prompt="Hist/> " --header-lines=1 --expect=ctrl-e --tiebreak=index'}, a:000)
endfunction

function! fzf#vim#history(...)
  return s:fzf('history-files', {
  \ 'source':  s:all_files(),
  \ 'options': ['-m', '--header-lines', !empty(expand('%')), '--prompt', 'Hist> ']
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" GFiles[?]
" ------------------------------------------------------------------

function! s:get_git_root()
  let root = split(system('git rev-parse --show-toplevel'), '\n')[0]
  return v:shell_error ? '' : root
endfunction

function! fzf#vim#gitfiles(args, ...)
  let root = s:get_git_root()
  if empty(root)
    return s:warn('Not in git repo')
  endif
  if a:args != '?'
    return s:fzf('gfiles', {
    \ 'source':  'git ls-files '.a:args.(s:is_win ? '' : ' | uniq'),
    \ 'dir':     root,
    \ 'options': '-m --prompt "GitFiles> "'
    \}, a:000)
  endif

  " Here be dragons!
  " We're trying to access the common sink function that fzf#wrap injects to
  " the options dictionary.
  let wrapped = fzf#wrap({
  \ 'source':  'git -c color.status=always status --short --untracked-files=all',
  \ 'dir':     root,
  \ 'options': ['--ansi', '--multi', '--nth', '2..,..', '--tiebreak=index', '--prompt', 'GitFiles?> ', '--preview', 'sh -c "(git diff --color=always -- {-1} | sed 1,4d; cat {-1}) | head -500"']
  \})
  call s:remove_layout(wrapped)
  let wrapped.common_sink = remove(wrapped, 'sink*')
  function! wrapped.newsink(lines)
    let lines = extend(a:lines[0:0], map(a:lines[1:], 'substitute(v:val[3:], ".* -> ", "", "")'))
    return self.common_sink(lines)
  endfunction
  let wrapped['sink*'] = remove(wrapped, 'newsink')
  return s:fzf('gfiles-diff', wrapped, a:000)
endfunction

" ------------------------------------------------------------------
" Buffers
" ------------------------------------------------------------------
function! s:find_open_window(b)
  let [tcur, tcnt] = [tabpagenr() - 1, tabpagenr('$')]
  for toff in range(0, tabpagenr('$') - 1)
    let t = (tcur + toff) % tcnt + 1
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      let b = buffers[w - 1]
      if b == a:b
        return [t, w]
      endif
    endfor
  endfor
  return [0, 0]
endfunction

function! s:jump(t, w)
  execute a:t.'tabnext'
  execute a:w.'wincmd w'
endfunction

function! s:bufopen(lines)
  if len(a:lines) < 2
    return
  endif
  let b = matchstr(a:lines[1], '\[\zs[0-9]*\ze\]')
  if empty(a:lines[0]) && get(g:, 'fzf_buffers_jump')
    let [t, w] = s:find_open_window(b)
    if t
      call s:jump(t, w)
      return
    endif
  endif
  let cmd = s:action_for(a:lines[0])
  if !empty(cmd)
    execute 'silent' cmd
  endif
  execute 'buffer' b
endfunction

function! s:format_buffer(b)
  let name = bufname(a:b)
  let name = empty(name) ? '[No Name]' : fnamemodify(name, ":p:~:.")
  let flag = a:b == bufnr('')  ? s:blue('%', 'Conditional') :
          \ (a:b == bufnr('#') ? s:magenta('#', 'Special') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]', 'Exception') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]', 'Constant')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  return s:strip(printf("[%s] %s\t%s\t%s", s:yellow(a:b, 'Number'), flag, name, extra))
endfunction

function! s:sort_buffers(...)
  let [b1, b2] = map(copy(a:000), 'get(g:fzf#vim#buffers, v:val, v:val)')
  " Using minus between a float and a number in a sort function causes an error
  return b1 < b2 ? 1 : -1
endfunction

function! s:buflisted_sorted()
  return sort(s:buflisted(), 's:sort_buffers')
endfunction

function! fzf#vim#buffers(...)
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  return s:fzf('buffers', {
  \ 'source':  map(s:buflisted_sorted(), 's:format_buffer(v:val)'),
  \ 'sink*':   s:function('s:bufopen'),
  \ 'options': ['+m', '-x', '--tiebreak=index', '--header-lines=1', '--ansi', '-d', '\t', '-n', '2,1..2', '--prompt', 'Buf> ', '--query', query]
  \}, args)
endfunction

" ------------------------------------------------------------------
" Ag / Rg
" ------------------------------------------------------------------
function! s:ag_to_qf(line, with_column)
  let parts = split(a:line, ':')
  let text = join(parts[(a:with_column ? 3 : 2):], ':')
  let dict = {'filename': &acd ? fnamemodify(parts[0], ':p') : parts[0], 'lnum': parts[1], 'text': text}
  if a:with_column
    let dict.col = parts[2]
  endif
  return dict
endfunction

function! s:ag_handler(lines, with_column)
  if len(a:lines) < 2
    return
  endif

  let cmd = s:action_for(a:lines[0], 'e')
  let list = map(filter(a:lines[1:], 'len(v:val)'), 's:ag_to_qf(v:val, a:with_column)')
  if empty(list)
    return
  endif

  let first = list[0]
  try
    call s:open(cmd, first.filename)
    execute first.lnum
    if a:with_column
      execute 'normal!' first.col.'|'
    endif
    normal! zz
  catch
  endtry

  call s:fill_quickfix(list)
endfunction

" query, [[ag options], options]
function! fzf#vim#ag(query, ...)
  if type(a:query) != s:TYPE.string
    return s:warn('Invalid query argument')
  endif
  let query = empty(a:query) ? '^(?=.)' : a:query
  let args = copy(a:000)
  let ag_opts = len(args) > 1 && type(args[0]) == s:TYPE.string ? remove(args, 0) : ''
  let command = ag_opts . ' ' . fzf#shellescape(query)
  return call('fzf#vim#ag_raw', insert(args, command, 0))
endfunction

" ag command suffix, [options]
function! fzf#vim#ag_raw(command_suffix, ...)
  if !executable('ag')
    return s:warn('ag is not found')
  endif
  return call('fzf#vim#grep', extend(['ag --nogroup --column --color '.a:command_suffix, 1], a:000))
endfunction

" command, with_column, [options]
function! fzf#vim#grep(grep_command, with_column, ...)
  let words = []
  for word in split(a:grep_command)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words   = empty(words) ? ['grep'] : words
  let name    = join(words, '-')
  let capname = join(map(words, 'toupper(v:val[0]).v:val[1:]'), '')
  let opts = {
  \ 'source':  a:grep_command,
  \ 'column':  a:with_column,
  \ 'options': ['--ansi', '--prompt', capname.'> ',
  \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
  \             '--color', 'hl:4,hl+:12']
  \}
  function! opts.sink(lines)
    return s:ag_handler(a:lines, self.column)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  return s:fzf(name, opts, a:000)
endfunction

" ------------------------------------------------------------------
" BTags
" ------------------------------------------------------------------
function! s:btags_source(tag_cmds)
  if !filereadable(expand('%'))
    throw 'Save the file first'
  endif

  for cmd in a:tag_cmds
    let lines = split(system(cmd), "\n")
    if !v:shell_error && len(lines)
      break
    endif
  endfor
  if v:shell_error
    throw get(lines, 0, 'Failed to extract tags')
  elseif empty(lines)
    throw 'No tags found'
  endif
  return map(s:align_lists(map(lines, 'split(v:val, "\t")')), 'join(v:val, "\t")')
endfunction

function! s:btags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let cmd = s:action_for(a:lines[0])
  if !empty(cmd)
    execute 'silent' cmd '%'
  endif
  let qfl = []
  for line in a:lines[1:]
    execute split(line, "\t")[2]
    call add(qfl, {'filename': expand('%'), 'lnum': line('.'), 'text': getline('.')})
  endfor
  call s:fill_quickfix(qfl, 'cfirst')
  normal! zz
endfunction

" query, [[tag commands], options]
function! fzf#vim#buffer_tags(query, ...)
  let args = copy(a:000)
  let escaped = fzf#shellescape(expand('%'))
  let null = s:is_win ? 'nul' : '/dev/null'
  let sort = has('unix') && !has('win32unix') && executable('sort') ? '| sort -s -k 5' : ''
  let tag_cmds = (len(args) > 1 && type(args[0]) != type({})) ? remove(args, 0) : [
    \ printf('ctags -f - --sort=yes --excmd=number --language-force=%s %s 2> %s %s', &filetype, escaped, null, sort),
    \ printf('ctags -f - --sort=yes --excmd=number %s 2> %s %s', escaped, null, sort)]
  if type(tag_cmds) != type([])
    let tag_cmds = [tag_cmds]
  endif
  try
    return s:fzf('btags', {
    \ 'source':  s:btags_source(tag_cmds),
    \ 'sink*':   s:function('s:btags_sink'),
    \ 'options': ['--layout=reverse-list', '-m', '-d', '\t', '--with-nth', '1,4..', '-n', '1', '--prompt', 'BTags> ', '--query', a:query]}, args)
  catch
    return s:warn(v:exception)
  endtry
endfunction

" ------------------------------------------------------------------
" Tags
" ------------------------------------------------------------------
function! s:tags_sink(lines)
  if len(a:lines) < 2
    return
  endif
  normal! m'
  let qfl = []
  let cmd = s:action_for(a:lines[0], 'e')
  try
    let [magic, &magic, wrapscan, &wrapscan, acd, &acd] = [&magic, 0, &wrapscan, 1, &acd, 0]
    for line in a:lines[1:]
      try
        let parts   = split(line, '\t\zs')
        let excmd   = matchstr(join(parts[2:-2], '')[:-2], '^.\{-}\ze;\?"\t')
        let base    = fnamemodify(parts[-1], ':h')
        let relpath = parts[1][:-2]
        let abspath = relpath =~ (s:is_win ? '^[A-Z]:\' : '^/') ? relpath : join([base, relpath], '/')
        call s:open(cmd, expand(abspath, 1))
        silent execute excmd
        call add(qfl, {'filename': expand('%'), 'lnum': line('.'), 'text': getline('.')})
      catch /^Vim:Interrupt$/
        break
      catch
        call s:warn(v:exception)
      endtry
    endfor
  finally
    let [&magic, &wrapscan, &acd] = [magic, wrapscan, acd]
  endtry
  call s:fill_quickfix(qfl, 'clast')
  normal! zz
endfunction

function! fzf#vim#tags(query, ...)
  if !executable('perl')
    return s:warn('Tags command requires perl')
  endif
  if empty(tagfiles())
    call inputsave()
    echohl WarningMsg
    let gen = input('tags not found. Generate? (y/N) ')
    echohl None
    call inputrestore()
    redraw
    if gen =~? '^y'
      call s:warn('Preparing tags')
      call system(get(g:, 'fzf_tags_command', 'ctags -R'.(s:is_win ? ' --output-format=e-ctags' : '')))
      if empty(tagfiles())
        return s:warn('Failed to create tags')
      endif
    else
      return s:warn('No tags found')
    endif
  endif

  let tagfiles = tagfiles()
  let v2_limit = 1024 * 1024 * 200
  for tagfile in tagfiles
    let v2_limit -= getfsize(tagfile)
    if v2_limit < 0
      break
    endif
  endfor
  let opts = v2_limit < 0 ? ['--algo=v1'] : []

  return s:fzf('tags', {
  \ 'source':  'perl '.fzf#shellescape(s:bin.tags).' '.join(map(tagfiles, 'fzf#shellescape(fnamemodify(v:val, ":p"))')),
  \ 'sink*':   s:function('s:tags_sink'),
  \ 'options': extend(opts, ['--nth', '1..2', '-m', '--tiebreak=begin', '--prompt', 'Tags> ', '--query', a:query])}, a:000)
endfunction

" ------------------------------------------------------------------
" Snippets (UltiSnips)
" ------------------------------------------------------------------
function! s:inject_snippet(line)
  let snip = split(a:line, "\t")[0]
  execute 'normal! a'.s:strip(snip)."\<c-r>=UltiSnips#ExpandSnippet()\<cr>"
endfunction

function! fzf#vim#snippets(...)
  if !exists(':UltiSnipsEdit')
    return s:warn('UltiSnips not found')
  endif
  let list = UltiSnips#SnippetsInCurrentScope()
  if empty(list)
    return s:warn('No snippets available here')
  endif
  let aligned = sort(s:align_lists(items(list)))
  let colored = map(aligned, 's:yellow(v:val[0])."\t".v:val[1]')
  return s:fzf('snippets', {
  \ 'source':  colored,
  \ 'options': '--ansi --tiebreak=index +m -n 1 -d "\t"',
  \ 'sink':    s:function('s:inject_snippet')}, a:000)
endfunction

" ------------------------------------------------------------------
" Commands
" ------------------------------------------------------------------
let s:nbs = nr2char(0x2007)

function! s:format_cmd(line)
  return substitute(a:line, '\C \([A-Z]\S*\) ',
        \ '\=s:nbs.s:yellow(submatch(1), "Function").s:nbs', '')
endfunction

function! s:command_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = matchstr(a:lines[1], s:nbs.'\zs\S*\ze'.s:nbs)
  if empty(a:lines[0])
    call feedkeys(':'.cmd.(a:lines[1][0] == '!' ? '' : ' '), 'n')
  else
    execute cmd
  endif
endfunction

let s:fmt_excmd = '   '.s:blue('%-38s', 'Statement').'%s'

function! s:format_excmd(ex)
  let match = matchlist(a:ex, '^|:\(\S\+\)|\s*\S*\(.*\)')
  return printf(s:fmt_excmd, s:nbs.match[1].s:nbs, s:strip(match[2]))
endfunction

function! s:excmds()
  let help = globpath($VIMRUNTIME, 'doc/index.txt')
  if empty(help)
    return []
  endif

  let commands = []
  let command = ''
  for line in readfile(help)
    if line =~ '^|:[^|]'
      if !empty(command)
        call add(commands, s:format_excmd(command))
      endif
      let command = line
    elseif line =~ '^\s\+\S' && !empty(command)
      let command .= substitute(line, '^\s*', ' ', '')
    elseif !empty(commands) && line =~ '^\s*$'
      break
    endif
  endfor
  if !empty(command)
    call add(commands, s:format_excmd(command))
  endif
  return commands
endfunction

function! fzf#vim#commands(...)
  redir => cout
  silent command
  redir END
  let list = split(cout, "\n")
  return s:fzf('commands', {
  \ 'source':  extend(extend(list[0:0], map(list[1:], 's:format_cmd(v:val)')), s:excmds()),
  \ 'sink*':   s:function('s:command_sink'),
  \ 'options': '--ansi --expect '.get(g:, 'fzf_commands_expect', 'ctrl-x').
  \            ' --tiebreak=index --header-lines 1 -x --prompt "Commands> " -n2,3,2..3 -d'.s:nbs}, a:000)
endfunction

" ------------------------------------------------------------------
" Marks
" ------------------------------------------------------------------
function! s:format_mark(line)
  return substitute(a:line, '\S', '\=s:yellow(submatch(0), "Number")', '')
endfunction

function! s:mark_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = s:action_for(a:lines[0])
  if !empty(cmd)
    execute 'silent' cmd
  endif
  execute 'normal! `'.matchstr(a:lines[1], '\S').'zz'
endfunction

function! fzf#vim#marks(...)
  redir => cout
  silent marks
  redir END
  let list = split(cout, "\n")
  return s:fzf('marks', {
  \ 'source':  extend(list[0:0], map(list[1:], 's:format_mark(v:val)')),
  \ 'sink*':   s:function('s:mark_sink'),
  \ 'options': '+m -x --ansi --tiebreak=index --header-lines 1 --tiebreak=begin --prompt "Marks> "'}, a:000)
endfunction

" ------------------------------------------------------------------
" Help tags
" ------------------------------------------------------------------
function! s:helptag_sink(line)
  let [tag, file, path] = split(a:line, "\t")[0:2]
  let rtp = fnamemodify(path, ':p:h:h')
  if stridx(&rtp, rtp) < 0
    execute 'set rtp+='.s:escape(rtp)
  endif
  execute 'help' tag
endfunction

function! fzf#vim#helptags(...)
  if !executable('grep') || !executable('perl')
    return s:warn('Helptags command requires grep and perl')
  endif
  let sorted = sort(split(globpath(&runtimepath, 'doc/tags', 1), '\n'))
  let tags = exists('*uniq') ? uniq(sorted) : fzf#vim#_uniq(sorted)

  if exists('s:helptags_script')
    silent! call delete(s:helptags_script)
  endif
  let s:helptags_script = tempname()
  call writefile(['/('.(s:is_win ? '^[A-Z]:\/.*?[^:]' : '.*?').'):(.*?)\t(.*?)\t/; printf(qq('.s:green('%-40s', 'Label').'\t%s\t%s\n), $2, $3, $1)'], s:helptags_script)
  return s:fzf('helptags', {
  \ 'source':  'grep -H ".*" '.join(map(tags, 'fzf#shellescape(v:val)')).
    \ ' | perl -n '.fzf#shellescape(s:helptags_script).' | sort',
  \ 'sink':    s:function('s:helptag_sink'),
  \ 'options': ['--ansi', '+m', '--tiebreak=begin', '--with-nth', '..-2']}, a:000)
endfunction

" ------------------------------------------------------------------
" File types
" ------------------------------------------------------------------
function! fzf#vim#filetypes(...)
  return s:fzf('filetypes', {
  \ 'source':  fzf#vim#_uniq(sort(map(split(globpath(&rtp, 'syntax/*.vim'), '\n'),
  \            'fnamemodify(v:val, ":t:r")'))),
  \ 'sink':    'setf',
  \ 'options': '+m --prompt="File types> "'
  \}, a:000)
endfunction

" ------------------------------------------------------------------
" Windows
" ------------------------------------------------------------------
function! s:format_win(tab, win, buf)
  let modified = getbufvar(a:buf, '&modified')
  let name = bufname(a:buf)
  let name = empty(name) ? '[No Name]' : name
  let active = tabpagewinnr(a:tab) == a:win
  return (active? s:blue('> ', 'Operator') : '  ') . name . (modified? s:red(' [+]', 'Exception') : '')
endfunction

function! s:windows_sink(line)
  let list = matchlist(a:line, '^ *\([0-9]\+\) *\([0-9]\+\)')
  call s:jump(list[1], list[2])
endfunction

function! fzf#vim#windows(...)
  let lines = []
  for t in range(1, tabpagenr('$'))
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      call add(lines,
        \ printf('%s %s  %s',
            \ s:yellow(printf('%3d', t), 'Number'),
            \ s:cyan(printf('%3d', w), 'String'),
            \ s:format_win(t, w, buffers[w-1])))
    endfor
  endfor
  return s:fzf('windows', {
  \ 'source':  extend(['Tab Win    Name'], lines),
  \ 'sink':    s:function('s:windows_sink'),
  \ 'options': '+m --ansi --tiebreak=begin --header-lines=1'}, a:000)
endfunction

" ------------------------------------------------------------------
" Commits / BCommits
" ------------------------------------------------------------------
function! s:yank_to_register(data)
  let @" = a:data
  silent! let @* = a:data
  silent! let @+ = a:data
endfunction

function! s:commits_sink(lines)
  if len(a:lines) < 2
    return
  endif

  let pat = '[0-9a-f]\{7,9}'

  if a:lines[0] == 'ctrl-y'
    let hashes = join(filter(map(a:lines[1:], 'matchstr(v:val, pat)'), 'len(v:val)'))
    return s:yank_to_register(hashes)
  end

  let diff = a:lines[0] == 'ctrl-d'
  let cmd = s:action_for(a:lines[0], 'e')
  let buf = bufnr('')
  for idx in range(1, len(a:lines) - 1)
    let sha = matchstr(a:lines[idx], pat)
    if !empty(sha)
      if diff
        if idx > 1
          execute 'tab sb' buf
        endif
        execute 'Gdiff' sha
      else
        " Since fugitive buffers are unlisted, we can't keep using 'e'
        let c = (cmd == 'e' && idx > 1) ? 'tab split' : cmd
        execute c FugitiveFind(sha)
      endif
    endif
  endfor
endfunction

function! s:commits(buffer_local, args)
  let s:git_root = s:get_git_root()
  if empty(s:git_root)
    return s:warn('Not in git repository')
  endif

  let source = 'git log '.get(g:, 'fzf_commits_log_options', '--color=always '.fzf#shellescape('--format=%C(auto)%h%d %s %C(green)%cr'))
  let current = expand('%')
  let managed = 0
  if !empty(current)
    call system('git show '.fzf#shellescape(current).' 2> '.(s:is_win ? 'nul' : '/dev/null'))
    let managed = !v:shell_error
  endif

  if a:buffer_local
    if !managed
      return s:warn('The current buffer is not in the working tree')
    endif
    let source .= ' --follow '.fzf#shellescape(current)
  else
    let source .= ' --graph'
  endif

  let command = a:buffer_local ? 'BCommits' : 'Commits'
  let expect_keys = join(keys(get(g:, 'fzf_action', s:default_action)), ',')
  let options = {
  \ 'source':  source,
  \ 'sink*':   s:function('s:commits_sink'),
  \ 'options': ['--ansi', '--multi', '--tiebreak=index', '--layout=reverse-list',
  \   '--inline-info', '--prompt', command.'> ', '--bind=ctrl-s:toggle-sort',
  \   '--header', ':: Press '.s:magenta('CTRL-S', 'Special').' to toggle sort, '.s:magenta('CTRL-Y', 'Special').' to yank commit hashes',
  \   '--expect=ctrl-y,'.expect_keys]
  \ }

  if a:buffer_local
    let options.options[-2] .= ', '.s:magenta('CTRL-D', 'Special').' to diff'
    let options.options[-1] .= ',ctrl-d'
  endif

  if !s:is_win && &columns > s:wide
    call extend(options.options,
    \ ['--preview', 'echo {} | grep -o "[a-f0-9]\{7,\}" | head -1 | xargs git show --format=format: --color=always | head -200'])
  endif

  return s:fzf(a:buffer_local ? 'bcommits' : 'commits', options, a:args)
endfunction

function! fzf#vim#commits(...)
  return s:commits(0, a:000)
endfunction

function! fzf#vim#buffer_commits(...)
  return s:commits(1, a:000)
endfunction

" ------------------------------------------------------------------
" fzf#vim#maps(mode, opts[with count and op])
" ------------------------------------------------------------------
function! s:align_pairs(list)
  let maxlen = 0
  let pairs = []
  for elem in a:list
    let match = matchlist(elem, '^\(\S*\)\s*\(.*\)$')
    let [_, k, v] = match[0:2]
    let maxlen = max([maxlen, len(k)])
    call add(pairs, [k, substitute(v, '^\*\?[@ ]\?', '', '')])
  endfor
  let maxlen = min([maxlen, 35])
  return map(pairs, "printf('%-'.maxlen.'s', v:val[0]).' '.v:val[1]")
endfunction

function! s:highlight_keys(str)
  return substitute(
        \ substitute(a:str, '<[^ >]\+>', s:yellow('\0', 'Special'), 'g'),
        \ '<Plug>', s:blue('<Plug>', 'SpecialKey'), 'g')
endfunction

function! s:key_sink(line)
  let key = matchstr(a:line, '^\S*')
  redraw
  call feedkeys(s:map_gv.s:map_cnt.s:map_reg, 'n')
  call feedkeys(s:map_op.
        \ substitute(key, '<[^ >]\+>', '\=eval("\"\\".submatch(0)."\"")', 'g'))
endfunction

function! fzf#vim#maps(mode, ...)
  let s:map_gv  = a:mode == 'x' ? 'gv' : ''
  let s:map_cnt = v:count == 0 ? '' : v:count
  let s:map_reg = empty(v:register) ? '' : ('"'.v:register)
  let s:map_op  = a:mode == 'o' ? v:operator : ''

  redir => cout
  silent execute 'verbose' a:mode.'map'
  redir END
  let list = []
  let curr = ''
  for line in split(cout, "\n")
    if line =~ "^\t"
      let src = '  '.join(reverse(reverse(split(split(line)[-1], '/'))[0:2]), '/')
      call add(list, printf('%s %s', curr, s:green(src, 'Comment')))
      let curr = ''
    else
      let curr = line[3:]
    endif
  endfor
  if !empty(curr)
    call add(list, curr)
  endif
  let aligned = s:align_pairs(list)
  let sorted  = sort(aligned)
  let colored = map(sorted, 's:highlight_keys(v:val)')
  let pcolor  = a:mode == 'x' ? 9 : a:mode == 'o' ? 10 : 12
  return s:fzf('maps', {
  \ 'source':  colored,
  \ 'sink':    s:function('s:key_sink'),
  \ 'options': '--prompt "Maps ('.a:mode.')> " --ansi --no-hscroll --nth 1,.. --color prompt:'.pcolor}, a:000)
endfunction

" ----------------------------------------------------------------------------
" fzf#vim#complete - completion helper
" ----------------------------------------------------------------------------
inoremap <silent> <Plug>(-fzf-complete-trigger) <c-o>:call <sid>complete_trigger()<cr>

function! s:pluck(dict, key, default)
  return has_key(a:dict, a:key) ? remove(a:dict, a:key) : a:default
endfunction

function! s:complete_trigger()
  let opts = copy(s:opts)
  call s:prepend_opts(opts, ['+m', '-q', s:query])
  let opts['sink*'] = s:function('s:complete_insert')
  let s:reducer = s:pluck(opts, 'reducer', s:function('s:first_line'))
  call fzf#run(opts)
endfunction

" The default reducer
function! s:first_line(lines)
  return a:lines[0]
endfunction

function! s:complete_insert(lines)
  if empty(a:lines)
    return
  endif

  let chars = strchars(s:query)
  if     chars == 0 | let del = ''
  elseif chars == 1 | let del = '"_x'
  else              | let del = (chars - 1).'"_dvh'
  endif

  let data = call(s:reducer, [a:lines])
  let ve = &ve
  set ve=
  execute 'normal!' ((s:eol || empty(chars)) ? '' : 'h').del.(s:eol ? 'a': 'i').data
  let &ve = ve
  if mode() =~ 't'
    call feedkeys('a', 'n')
  else
    execute "normal! \<esc>la"
  endif
endfunction

function! s:eval(dict, key, arg)
  if has_key(a:dict, a:key) && type(a:dict[a:key]) == s:TYPE.funcref
    let ret = copy(a:dict)
    let ret[a:key] = call(a:dict[a:key], [a:arg])
    return ret
  endif
  return a:dict
endfunction

function! fzf#vim#complete(...)
  if a:0 == 0
    let s:opts = fzf#wrap()
  elseif type(a:1) == s:TYPE.dict
    let s:opts = copy(a:1)
  elseif type(a:1) == s:TYPE.string
    let s:opts = extend({'source': a:1}, get(a:000, 1, fzf#wrap()))
  else
    echoerr 'Invalid argument: '.string(a:000)
    return ''
  endif
  for s in ['sink', 'sink*']
    if has_key(s:opts, s)
      call remove(s:opts, s)
    endif
  endfor

  let eol = col('$')
  let ve = &ve
  set ve=all
  let s:eol = col('.') == eol
  let &ve = ve

  let Prefix = s:pluck(s:opts, 'prefix', '\k*$')
  if col('.') == 1
    let s:query = ''
  else
    let full_prefix = getline('.')[0 : col('.')-2]
    if type(Prefix) == s:TYPE.funcref
      let s:query = call(Prefix, [full_prefix])
    else
      let s:query = matchstr(full_prefix, Prefix)
    endif
  endif
  let s:opts = s:eval(s:opts, 'source', s:query)
  let s:opts = s:eval(s:opts, 'options', s:query)
  let s:opts = s:eval(s:opts, 'extra_options', s:query)
  if has_key(s:opts, 'extra_options')
    call s:merge_opts(s:opts, remove(s:opts, 'extra_options'))
  endif
  if has_key(s:opts, 'options')
    if type(s:opts.options) == s:TYPE.list
      call add(s:opts.options, '--no-expect')
    else
      let s:opts.options .= ' --no-expect'
    endif
  endif

  call feedkeys("\<Plug>(-fzf-complete-trigger)")
  return ''
endfunction

function! fzf#vim#session(...)
        let [query, args] = (a:0 && type(a:1) == type('')) ? [a:1, a:000[1:]] : ['', a:000]
        return s:fzf('load_session', {
        \    'source':  s:session_source(query) + [s:new_session_prompt],
        \   'sink*':   s:function('s:session_sink'),
        \   'options': ['+m', '--tiebreak=index', '--prompt', 'Load Session> ', '--ansi', '--extended', '--nth=2..', '--layout=reverse-list', '--tabstop=1'],
        \}, args)
endfunction
let s:new_session_prompt = '      New Session'
let g:session_dir = expand('~/.vim/sessions/')


function! fzf#vim#delete_session(...)
        let [query, args] = (a:0 && type(a:1) == type('')) ? [a:1, a:000[1:]] : ['', a:000]
        return s:fzf('delete_session', {
        \   'source':  s:session_source(query),
        \   'sink*':   s:function('s:delete_session_sink'),
        \   'options': ['+m', '--tiebreak=index', '--multi', '--prompt', 'Delete Session> ', '--ansi', '--extended', '--nth=2..', '--layout=reverse-list', '--tabstop=1'],
        \}, args)
endfunction


function! s:format_session_line(idx, str)
    let mod_time = s:rel_time(getftime(a:str))
    let name = fnamemodify(a:str, ':t:r')
    let fmt_str = s:yellow("%s\t%2d ", "LineNr") . printf("\t%%-%ds%%s", min([80, winwidth('')-12]) - len(mod_time))
    let cur_session = get(g:, 'this_obsession', v:this_session)
    return printf(fmt_str,a:str == cur_session ? '*' : ' ', a:idx+1, name, mod_time)
endfunction
function! s:rel_time(time)
    let t = localtime() - a:time
    let orders = [[60, 'Second'], [60, 'Minute'], [24, 'Hour'], [7, 'Day'], [4, 'Week'], [12, 'Month'], [0, 'Year']]
    for [fits, name] in orders
        let cur_format = printf("%d %s%s Ago", t, name, t == 1 ? '' : 's')
        if t < fits
            break
        endif
        let t = t / fits
    endfor
    return cur_format
endfunction


function! s:session_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let qfl = []
  for line in a:lines[1:]
      if line == s:new_session_prompt
          let session_name =  input('Session Name: ')
          if (empty(session_name))
              return
          endif
          let session_name = g:session_dir . '/' . session_name. '.vim'
      else
          let session_idx = str2nr(split(line, "\t", 1)[1])
          let session_name = s:session_paths[session_idx-1]
      endif
      let cur_session = get(g:, 'this_obsession', v:this_session)
      if (!empty(cur_session))
          Obsession
      endif
      if (session_name != cur_session)
          if filereadable(session_name)
              let mod = map(getbufinfo(), 'v:val.changed')
              if len(filter(mod, 'v:val')) != 0
                  echo 'Warning: Unsaved buffers'
                  return
              endif
              bufdo bd
              exec "source " . session_name
          else
          endif
      endif
      exec 'Obsession  ' . session_name
  endfor
endfunction

function! s:session_source(patt)
    let cur_session = get(g:, 'this_obsession', v:this_session)
    let s:session_paths = split(globpath(g:session_dir, '*.vim'), '\n')
    let paths = split(globpath(g:session_dir, '*.vim'), '\n')
    let formatted = map(paths, 's:format_session_line(v:key, v:val)')
    return formatted
endfunction

function! s:delete_session_sink(lines)
      if len(a:lines) < 2
        return
      endif
      let qfl = []
      let cur_session = get(g:, 'this_obsession', v:this_session)
      for line in a:lines[1:]
          let session_idx = str2nr(split(line, "\t", 1)[1])
          let cur_path = s:session_paths[session_idx-1]
          if cur_session == cur_path
              Obsession!
          else
              call delete(fnameescape(cur_path))
              echo "Deleted session in " . cur_path
          endif
      endfor
endfunction

" ------------------------------------------------------------------
let &cpo = s:cpo_save
unlet s:cpo_save

