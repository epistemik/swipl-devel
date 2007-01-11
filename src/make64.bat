@echo off

SETLOCAL

rem ****************************************************************
rem Configuration section

set CVSROOT=:pserver:jan@gollem:/usr/local/plcvs
set HOME=%USERPROFILE%
set WINDIR=C:\WINDOWS
set SDK=C:\Program Files\Microsoft Platform SDK for Windows Server 2003 R2
set JAVA_HOME=C:\j2sdk1.4.2_04
set JUNIT=%HOME%\lib\junit.jar

CALL "%SDK%\Setenv.cmd" /XP64 /RETAIL

set LIB=%HOME%\lib64;%LIB%
set INCLUDE=%HOME%\include;%INCLUDE%
rem ****************************************************************

rem Build default multi-threaded version 
rem nmake MD=WIN64 /f makefile.mak %*
nmake GMP=false MD=WIN64 /f makefile.mak %*

rem Build for multi-threading and debugging
rem nmake DBG=true /f makefile.mak %*

rem Enable this line to build for single-threading.
rem nmake MT=false /f makefile.mak %*

ENDLOCAL
