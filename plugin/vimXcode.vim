" ============================================================================
" File:        vimXcode.vim     
" Description: vim plugin for building and running Xcode projects
" Maintainer:  Harikrishnan Gopalakrishnan <hari.exeption at gmail dot com>
" Last Change: 25 February, 2013
" License:     This program is free software. It comes without any warranty,
"              to the extent permitted by applicable law. You can redistribute
"              it and/or modify it under the terms of the Do What The Fuck You
"              Want To Public License, Version 2, as published by Sam Hocevar.
"              See http://sam.zoy.org/wtfpl/COPYING for more details.
"
" ============================================================================

setlocal noignorecase
setlocal magic

nnoremap <F5> :call g:Xcodebuild()<cr>
nnoremap <F6> :call g:XcodebuildAndRun()<cr>

command! -n=0 XcodeChooseSDK :call g:XcodeChooseSDK()
command! -n=0 XcodeChooseTarget :call g:XcodeChooseTarget()
command! -n=0 XcodeChooseConfiguration :call g:XcodeChooseConfiguration()
command! -n=0 XcodeChooseArchitecture :call g:XcodeChooseArch()

nnoremap <F7> :call g:XcodeChooseSDK()<cr>
nnoremap <F8> :call g:XcodeChooseTarget()<cr>

let s:errNotFound = "Could not locate a *.xcodeproj file. Try with a \".xvim\" file in the root directory of your project."
let s:messMenuTitleNote = "Note: This choice is active only through this vim session."
let s:messMenuFooter = "If no choice (press ESC) is made default/current setting will be used:"

" echom messages
let s:Debug = 1

function! s:FindXrootdir()
  
  " TODO Do this only once per buffer?
  if exists('b:xcode_proj_path')
    return b:xcode_proj_path
  endif

  let s:lastBuildStatus = 0

  " Look in all the subdirectories
  let l:projPath = globpath( expand( '.' ), "**/*.xcodeproj" )
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
    let l:projPath = fnamemodify( l:projPath , ":p:h" )
    let b:xcode_proj_path = l:projPath
  endif

  if s:Debug
    echom "s:FindXrootdir() = " . l:projPath
  endif

  return l:projPath
endfunction

function! s:BuildCmd()
  if !exists('b:xcode_proj_sdk'    ) | let b:xcode_proj_sdk    = ""      | endif
  if !exists('b:xcode_proj_config' ) | let b:xcode_proj_config = "Debug" | endif
  if !exists('b:xcode_proj_target' ) | let b:xcode_proj_target = ""      | endif
  if !exists('b:xcode_proj_arch'   ) | let b:xcode_proj_arch   = ""      | endif

  let l:cmd = 'xcodebuild'
  
  if( b:xcode_proj_sdk    != "" ) | let l:cmd = l:cmd . " -sdk " . b:xcode_proj_sdk              | endif
  if( b:xcode_proj_config != "" ) | let l:cmd = l:cmd . " -configuration " . b:xcode_proj_config | endif
  if( b:xcode_proj_arch   != "" ) | let l:cmd = l:cmd . " -arch " . b:xcode_proj_arch            | endif
  if( b:xcode_proj_target != "" )
    if( b:xcode_proj_target == "All Targets" )
      let l:cmd = l:cmd . " -alltargets"
    else
      let l:cmd = l:cmd . " -target " . b:xcode_proj_target
    endif
  endif

  if s:Debug
    echom "Build Command Generated: " . l:cmd
  endif

  return l:cmd
endfunction

" Read and parse the output of xcodebuild -showsdks, xcodebuild -list
" and xcodebuild -showBuildSettings commands.
" Mainly added for parsing options for the user menu.
" Following are currently read
"   - supported sdks
"   - supported architectures
"   - targets defined in the Xcode project file 
"   - configurations defined in Xcode project file
function! s:ParseXcodeBuildSettings()
  let l:xcodeSDKsPattern               = '^\s\+\zs\(.\{-}\)\s\+-sdk\s\+\(.\{-}\)$'
  let l:xcodeGroupStartPattern         = '^\s\{4}.*:'
  let l:xcodeTargetsGroupStartPattern  = '^\s\{4}Targets:'
  let l:xcodeConfigsGroupStartPattern  = '^\s\{4}Build Configurations:'
  let l:xcodeTargetsConfigsItemPattern = '^\s\{8}\(.*\)$'
  let l:xcodeBuildValidArchsPattern    = '\n\s\{4}VALID_ARCHS\s\+=\s\+\(.\{-}\)\n'
  let l:xcodeBuildCurrentArchsPattern  = '\n\s\{4}CURRENT_ARCH\s\+=\s\+\(.\{-}\)\n'

  let l:sdks           = {}
  let l:configurations = {}
  let l:targets        = {}
  let l:archs          = {}

  let l:projPath = s:FindXrootdir()
  if l:projPath != ""
    let l:projRoot = fnamemodify( l:projPath, ":h" )

    echo "reading and parsing xcodebuild settings"

    " Parse supported SDKs
    let l:xcres = system( "cd " . l:projRoot . '; xcodebuild -showsdks' )
    let l:xcresList = split( l:xcres, '\n' )
    " To keep the same order of items as xcodebuild spits out, let's use a
    " counter as dictionary index
    let l:menuItem = 1
    for item in l:xcresList
      let l:matches = matchlist( item, l:xcodeSDKsPattern )
      if len( l:matches ) > 0
        let l:sdks[l:menuItem] = { "name" : l:matches[1], "value" : l:matches[2] }
        let l:menuItem = l:menuItem + 1
      endif
    endfor

    " Parse supported configurations and targets
    let l:xcres = system( "cd " . l:projRoot . '; xcodebuild -list' )
    let l:xcresList = split( l:xcres, '\n' )
    let l:menuItem = 1
    " Loop over the l:xcresList only once, l:targetOrConfiguration indicates which
    " class (target or config), current property belongs to.
    " l:targetOrConfiguration => 1 - target, 2 - config, any_other_value - none
    let l:targetOrConfiguration = 0
    for item in l:xcresList
      let l:matches = matchlist( item, l:xcodeGroupStartPattern )
      if len( l:matches ) > 0
        " item is a group; findout which one. Pattern matching? I miss Scala! :S
        let l:matches = matchlist( item, l:xcodeTargetsGroupStartPattern )
        if len( l:matches ) > 0
          let l:targetOrConfiguration = 1
          let l:menuItem = 1
        else
          let l:matches = matchlist( item, l:xcodeConfigsGroupStartPattern )
          if len( l:matches ) > 0
            let l:targetOrConfiguration = 2
            let l:menuItem = 1
          else
            let l:targetOrConfiguration = 0
          endif
        endif
      endif

      " Process items in groups
      let l:matches = matchlist( item, l:xcodeTargetsConfigsItemPattern )
      if len( l:matches ) > 0
        
        if l:targetOrConfiguration == 1
          let l:targets[l:menuItem] = { "value" : l:matches[1] }
        elseif l:targetOrConfiguration == 2
          let l:configurations[l:menuItem] = { "value" : l:matches[1] }
        endif
        
        let l:menuItem = l:menuItem + 1
      endif
    endfor

    let l:targetKeys = keys( l:targets )
    if len( l:targetKeys ) > 0
      let l:targets[ l:targetKeys[-1] + 1 ] = { "value" : "All Targets" }
    endif

    " Parse supported architectures
    let l:xcres = system( "cd " . l:projRoot . '; xcodebuild -showBuildSettings' )
    let l:xcres1 = matchlist( l:xcres, l:xcodeBuildCurrentArchsPattern )
    let l:xcres2 = matchlist( l:xcres, l:xcodeBuildValidArchsPattern )

    let l:menuItem = 1
    if len( l:xcres2 ) > 1
      let l:xcresList = split( l:xcres2[1], '\s' )
      for item in l:xcresList
        let l:archs[l:menuItem] = { "value" : item }
        let l:menuItem = l:menuItem + 1
      endfor
    endif

    if len( l:xcres1 ) > 1
      let l:archs[l:menuItem] = { "name" : "Xcode Project Setting", "value" : l:xcres1[1] }
    endif


    let b:parsed_build_settings          = 1
    let b:xcode_supported_sdks           = l:sdks
    let b:xcode_supported_targets        = l:targets
    let b:xcode_supported_configurations = l:configurations
    let b:xcode_supported_archs          = l:archs

    if s:Debug
      echo "SDKS = "
      echo l:sdks
      echo "Targets = "
      echo l:targets
      echo "Configurations = "
      echo l:configurations
      echo "Architectures = "
      echo l:archs
    endif

  endif
endfunction

" Read the build directory from Xcode project file.
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

" Read the build target name from Xcode project file.
function! s:XcodeBuildTarget()
  if exists('b:xcode_build_target')
    return b:xcode_build_target
  endif

  let l:projPath = s:FindXrootdir()
  let l:projBuildTarget = ""

  if l:projPath != ""
    " Find the TARGET_NAME from the xcode project setting
    let l:xcodeBuildTergetPattern = '\s*TARGET_NAME\s*=\s*\(.*\)\n'
    let l:projRoot = fnamemodify( l:projPath, ":h" )
    let l:xcres = system( "cd " . l:projRoot . '; xcodebuild -showBuildSettings | grep -i "\bTARGET_NAME\b"' )
    let l:xcresList = matchlist( l:xcres, l:xcodeBuildTergetPattern )
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
  if s:Debug
    echom "s:ExecuteXCmd( " . a:path . ", " . a:cmd . " )"
  endif

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
    " TODO Needs to validate this errorformat agaist all possible inputs
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

" User interface ( menu ) functions
" Inspired from the awesome NERDTree menus for style and code :)
function! s:ShowMenuAndGetResponse( title, items, footer )
  let s:selection = 1
  let done = 0
  
  let l:itemKeys = keys( a:items )

  while !done
    redraw!
    call s:EchoPrompt( a:title, a:items, a:footer )
    let key = nr2char( getchar() )
    let done = s:HandleKeypress( key, l:itemKeys )
  endwhile

  return s:selection
endfunction

function! s:EchoPrompt( title, items, footer )
  echo "vimXcode menu. Use j/k/enter"
  echo "=============================="
  echo a:title
  echo "---"
  
  for i in keys( a:items )
    let l:disp = get( a:items[i], "name", a:items[i].value )
    if s:selection == i
      echo "> " . l:disp
    else
      echo "  " . l:disp
    endif
  endfor

  if a:footer != ""
    echo "---"
    echo a:footer
  endif
endfunction

"change the selection (if appropriate) and return 1 if the user has made
"their choice, 0 otherwise
function! s:HandleKeypress( key, items )
  if a:key == 'j'
    if s:selection < len( a:items )
      let s:selection += 1
    else
      let s:selection = 1
    endif
  elseif a:key == 'k'
    if s:selection > 1
      let s:selection -= 1
    else
      let s:selection = len( a:items )
    endif
  elseif a:key == nr2char(27) "escape
    let s:selection = -1
    return 1
  elseif a:key == "\r" || a:key == "\n" "enter and ctrl-j
    return 1
  endif

  return 0
endfunction

" User defined functions

"FUNCTION: g:XcodeChooseSDK()"
function! g:XcodeChooseSDK()
  if !exists( 'b:parsed_build_settings' )
    call s:ParseXcodeBuildSettings()
  endif

  let l:title = "Choose a SDK. " . s:messMenuTitleNote

  let l:resp = s:ShowMenuAndGetResponse( l:title, b:xcode_supported_sdks, s:messMenuFooter )
  if l:resp > 0
    try
      let b:xcode_proj_sdk = b:xcode_supported_sdks[l:resp].value
      echo "Using " . b:xcode_supported_sdks[l:resp].name . " [ -sdk " . b:xcode_supported_sdks[l:resp].value . " ]"
    endtry
  endif
endfunction

"FUNCTION: g:XcodeChooseTarget()"
function! g:XcodeChooseTarget()
  if !exists( 'b:parsed_build_settings' )
    call s:ParseXcodeBuildSettings()
  endif

  let l:title = "Choose Target. " . s:messMenuTitleNote

  let l:resp = s:ShowMenuAndGetResponse( l:title, b:xcode_supported_targets, s:messMenuFooter )
  if l:resp > 0
    try
      let b:xcode_proj_target = b:xcode_supported_targets[l:resp].value
      echo "Using "  b:xcode_supported_targets[l:resp].value 
    endtry
  endif
endfunction

"FUNCTION: g:XcodeChooseConfiguration()"
function! g:XcodeChooseConfiguration()
  if !exists( 'b:parsed_build_settings' )
    call s:ParseXcodeBuildSettings()
  endif

  let l:title = "Choose Build Configuration. " . s:messMenuTitleNote

  let l:resp = s:ShowMenuAndGetResponse( l:title, b:xcode_supported_configurations, s:messMenuFooter )
  if l:resp > 0
    try
      let b:xcode_proj_config = b:xcode_supported_configurations[l:resp].value
      echo "Using "  b:xcode_supported_configurations[l:resp].value 
    endtry
  endif
endfunction

"FUNCTION: g:XcodeChooseArch()"
function! g:XcodeChooseArch()
  if !exists( 'b:parsed_build_settings' )
    call s:ParseXcodeBuildSettings()
  endif

  let l:title = "Choose Architecture. " . s:messMenuTitleNote

  let l:resp = s:ShowMenuAndGetResponse( l:title, b:xcode_supported_archs, s:messMenuFooter )
  if l:resp > 0
    try
      let b:xcode_proj_arch = b:xcode_supported_archs[l:resp].value
      echo "Using "  b:xcode_supported_archs[l:resp].value 
    endtry
  endif
endfunction

