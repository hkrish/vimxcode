
setlocal noignorecase

nnoremap <F5> :call g:Xcodebuild()<cr>
nnoremap <F6> :call g:XcodebuildAndRun()<cr>

let s:errNotFound = "Could not locate a *.xcodeproj file. Try with a \".xvim\" file in the root directory of your project."

function! s:FindXrootdir()
  
  " TODO Do this only once per buffer?
  if exists('b:xcode_proj_path')
    return b:xcode_proj_path
  endif

  let s:lastBuildStatus = 0

  let l:projPath = globpath( expand( '.' ), "*.xcodeproj" )
  if l:projPath == ""
    " Look in all the subdirectories starting from one directory above
    let l:projPath = globpath( expand( '..' ), "**/*.xcodeproj" )
    if l:projPath == ""
      " Try to find the closest git repository and look from there 
      let l:projPath = finddir( ".git", ".;" )
      if l:projPath == ""
        " Try to find the .xvim file. 
        let l:projPath = findfile( ".xvim", ".;" )
      endif

      " In case of a git repository or a .xvim file, look for a *.xcodeproj
      if l:projPath != ""
        let l:projPath = globpath( fnamemodify( l:projPath, ':h' ), "**/*.xcodeproj" )
      endif

    endif
  endif

  if l:projPath == ""
    echo s:errNotFound
  else
    let b:xcode_proj_path = l:projPath
  endif

  return l:projPath
endfunction

function! s:BuildCmd()
  if !exists('b:xcode_proj_sdk'    ) | let b:xcode_proj_sdk    = ""      | endif
  if !exists('b:xcode_proj_config' ) | let b:xcode_proj_config = "Debug" | endif
  if !exists('b:xcode_proj_target' ) | let b:xcode_proj_target = ""      | endif

  let l:cmd = 'xcodebuild'
  
  if( b:xcode_proj_sdk    != "" ) | let l:cmd = l:cmd . " -sdk " . b:xcode_proj_sdk              | endif
  if( b:xcode_proj_config != "" ) | let l:cmd = l:cmd . " -configuration " . b:xcode_proj_config | endif
  if( b:xcode_proj_target != "" ) | let l:cmd = l:cmd . " -target " . b:xcode_proj_target        | endif

  return l:cmd
endfunction

function! s:XcodeBuildDir()
  if exists('b:xcode_build_dir')
    return b:xcode_build_dir
  endif

  let l:projPath = s:FindXrootdir()
  let l:projBuildDir = ""

  if l:projPath != ""
    " Find the BUILD_DIR from the xcode project setting
    let l:xcodeBuildDirPattern = '\s*BUILD_DIR\s*=\s*\(.*\)\n'
    let l:projRoot = fnamemodify( l:projPath, ":h" )
    let l:xcres = system( "cd " . l:projRoot . '; xcodebuild -showBuildSettings | grep -i "\bBUILD_DIR\b"' )
    let l:xcresList = matchlist( l:xcres, l:xcodeBuildDirPattern )
    if len( l:xcresList ) > 1
      let l:projBuildDir = simplify( l:xcresList[1] )
      let b:xcode_build_dir = l:projBuildDir
    endif
  endif

  return l:projBuildDir
endfunction

function! s:XcodeBuildTarget()
  if exists('b:xcode_build_target')
    return b:xcode_build_target
  endif

  let l:projPath = s:FindXrootdir()
  let l:projBuildTarget = ""

  if l:projPath != ""
    " Find the TARGET_NAME from the xcode project setting
    let l:xcodeBuildDirPattern = '\s*TARGET_NAME\s*=\s*\(.*\)\n'
    let l:projRoot = fnamemodify( l:projPath, ":h" )
    let l:xcres = system( "cd " . l:projRoot . '; xcodebuild -showBuildSettings | grep -i "\bTARGET_NAME\b"' )
    let l:xcresList = matchlist( l:xcres, l:xcodeBuildDirPattern )
    if len( l:xcresList ) > 1
      let l:projBuildTarget = l:xcresList[1]
      let b:xcode_build_target = l:projBuildTarget
    endif
  endif

  return l:projBuildTarget
endfunction

function! g:Xcodebuild()
  let l:projPath = s:FindXrootdir()
  let l:cmd = s:BuildCmd()

  if l:projPath != ""
    let l:projRoot = fnamemodify( l:projPath, ":h" )
    execute s:ExecuteXCmd( l:projRoot, l:cmd )
  endif
endfunction

function! g:XcodebuildAndRun()
  execute g:Xcodebuild()

  if s:lastBuildStatus
    echo "running..."
    let l:buildPath = s:XcodeBuildDir()
    let l:buildTarget = s:XcodeBuildTarget()
    if l:buildPath != "" && l:buildTarget != ""
      let l:runnable = fnamemodify( globpath( finddir( b:xcode_proj_config, l:buildPath ), '**/*.app/**/' . l:buildTarget ), ":p" )
      if l:runnable != ""
        silent execute "! " . l:runnable . " &"
        " call system( l:runnable ) 
      endif
    endif
  endif
endfunction

" ExecuteXCmd() runs xcodebuild command after correctly resolving
" the .xcodeproj file path. This is useful when the .xcodeproj file
" is not in the Project's root directory; 
" for example [Cinder](http://libcinder.org), creates the xcode files
" in <project_name>/xcode directory.
"   Some parts are directly copied from jerrymarino's xcodebuild.vim project
"   [xcodebuild](https://github.com/jerrymarino/xcodebuild.vim, "thanks! :)")
function! s:ExecuteXCmd( path, cmd )
  let l:xcodeSuccessPattern = '\*\*\s\+BUILD SUCCEEDED\s\+\*\*'
  let l:xcodeErrorPattern = '/\(.*:\s*fatal error\s*:.*\)\|\(.*:\s*error\s*:.*\)\|\(.*:\s*warning\s*:.*\)/ig'

  let s:lastBuildStatus = 0

  echo "building..."
  " let l:xcres = system( "cd " . a:path . "; " . a:cmd . " 2>&1" )
  let l:xcres = system( "cd " . a:path . "; " . a:cmd )

  let l:res = match( l:xcres, l:xcodeSuccessPattern )

  if( l:res >= 0 )
    echom 'Build successful.'
    let s:lastBuildStatus = 1
    execute "cclose"
  else
    echom 'Build failed!'
    let l:resList = split( l:xcres, "\n" )
    let l:errList = []

    for i in l:resList
      let l:mtch = match( i, l:xcodeErrorPattern )
      if( l:mtch >= 0 )
        call add( l:errList, "\"" . i . "\"" )
      endif
    endfor

    let s:efm = escape(&errorformat, "\" ") 
    set errorformat=
          \%A%f:%l:%c:{%*[^}]}:\ error:\ %m,
          \%A%f:%l:%c:{%*[^}]}:\ fatal\ error:\ %m,
          \%A%f:%l:%c:{%*[^}]}:\ warning:\ %m,
          \%A%f:%l:%c:\ error:\ %m,
          \%A%f:%l:%c:\ fatal\ error:\ %m,
          \%A%f:%l:%c:\ warning:\ %m,
          \%A%f:%l:\ Error:\ %m,
          \%A%f:%l:\ error:\ %m,
          \%A%f:%l:\ fatal\ error:\ %m,
          \%A%f:%l:\ warning:\ %m

    execute "cexpr! " . "[" . join( l:errList, "," ) . "]"
    execute "set errorformat=" . s:efm
    execute "cw"

  endif
  return ""
endfunction

" call ExecuteXCmd( "xcodebuild" )

