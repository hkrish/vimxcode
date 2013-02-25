    
           _          __   __              _      
          (_)         \ \ / /             | |     
    __   ___ _ __ ___  \ V /  ___ ___   __| | ___ 
    \ \ / / | '_ ` _ \ /   \ / __/ _ \ / _` |/ _ \
     \ V /| | | | | | / /^\ \ (_| (_) | (_| |  __/
      \_/ |_|_| |_| |_\/   \/\___\___/ \__,_|\___|
                                                  
    
    /* vim plugin to configure, build, and run Xcode projects */

    /* Using Pathogen */
    git clone https://github.com/hkrish/vimxcode.git ~/.vim/bundle/vimXcode


#vimXcode

*vim plugin to configure, build, and run Xcode projects*

##Installation
###Using Pathogen

```bash
$ git clone https://github.com/hkrish/vimxcode.git ~/.vim/bundle/vimXcode
```

##Using vimXcode

vimXcode should find the Xcode project file automatically, even when they 
are inside a subdirectory of the root folder. if the plugin can't find the 
xcode project ( `*.xcodeproj` ). Then try creating a file 
named **.xvim** in the root folder of your project.

```bash
$ cd <root_folder_of_your_project>
$ touch .xvim
```

###Building and Running
while in NORMAL mode,
 * press `<F5>` to build and see errors if any
 * press `<F6>` to build and run if there are no errors

###Configuring
Following vim commands are currently implemented
 * `:XcodeChooseSDK` - Choose a suported SDK installed on your system
 * `:XcodeChooseTarget` - Choose a build target
 * `:XcodeChooseConfiguration` - Choose a build Configuration. Debug, Release *
 * `:XcodeChooseArchitecture` - Choose an Architecture from the valid architecture list

By default vimXcode builds projects in Debug configuration.

All of the configuration settings last only the current vim session. vimXcode does not 
mess around with your project files.
  
