@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PATH=%JAVA_HOME%\bin;%PATH%"

echo ==========================================
echo       MoonBazaar 一键打包脚本
echo ==========================================
echo.

:: ---------- 1. 版本号 ----------
set "CUR_CODE=1"
set "CUR_NAME=1.0"
if exist "gradle.properties" (
    for /f "tokens=1,* delims==" %%a in ('findstr /b /c:"VERSION_CODE=" gradle.properties') do set "CUR_CODE=%%b"
    for /f "tokens=1,* delims==" %%a in ('findstr /b /c:"VERSION_NAME=" gradle.properties') do set "CUR_NAME=%%b"
)

echo 当前版本: v%CUR_NAME% (%CUR_CODE%)
set /p "V_NAME=请输入 versionName (回车沿用 %CUR_NAME%): "
if "%V_NAME%"=="" set "V_NAME=%CUR_NAME%"

set /a NEXT_CODE=%CUR_CODE% + 1
set /p "V_CODE=请输入 versionCode (回车沿用 %NEXT_CODE%): "
if "%V_CODE%"=="" set "V_CODE=%NEXT_CODE%"

echo %V_CODE%|findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 ( echo [ERROR] versionCode 必须为正整数！ & pause & exit /b 1 )

:: ---------- 2. ABI ----------
echo.
echo ---------- 选择 ABI ----------
echo   [1] arm_all  (arm64-v8a + armeabi-v7a)
echo   [2] arm64    (仅 arm64-v8a)
echo   [3] arm32    (仅 armeabi-v7a)
echo   [4] x8664    (仅 x86_64)
echo   [5] 全部
choice /c 12345 /m "输入序号"
if errorlevel 5 (set "FLAVOR=ALL")   else ^
if errorlevel 4 (set "FLAVOR=x8664") else ^
if errorlevel 3 (set "FLAVOR=arm32") else ^
if errorlevel 2 (set "FLAVOR=arm64") else ^
if errorlevel 1 (set "FLAVOR=arm_all")

:: ---------- 3. 类型 ----------
echo.
echo ---------- 打包类型 ----------
echo   [1] APK
echo   [2] AAB
choice /c 12 /m "输入序号"
if errorlevel 2 (set "PKG_TYPE=AAB") else (set "PKG_TYPE=APK")

:: ---------- 4. 签名 ----------
echo.
echo ---------- 签名方式 ----------
echo   [1] demo    演示签名 (signature/example.jks)
echo   [2] custom  自定义签名 (keystore.properties)
echo   [3] none    不签名 (仅 APK)
choice /c 123 /m "输入序号"
if errorlevel 3 (set "SIGN_MODE=none")   else ^
if errorlevel 2 (set "SIGN_MODE=custom") else ^
if errorlevel 1 (set "SIGN_MODE=demo")

if /i "%SIGN_MODE%"=="custom" if not exist "keystore.properties" (
    echo [ERROR] 未找到 keystore.properties & pause & exit /b 1
)
if /i "%SIGN_MODE%"=="demo" if not exist "signature\example.jks" (
    echo [ERROR] 未找到 signature\example.jks，请先运行 init_signature.bat
    pause & exit /b 1
)
if /i "%SIGN_MODE%"=="none" if /i "%PKG_TYPE%"=="AAB" (
    echo [ERROR] AAB 必须签名，signMode=none 不适用 & pause & exit /b 1
)

:: ---------- 5. 确认 ----------
echo.
echo ------------------------------------------
echo   版本     : v%V_NAME% (%V_CODE%)
echo   ABI      : %FLAVOR%
echo   类型     : %PKG_TYPE%
echo   签名     : %SIGN_MODE%
echo ------------------------------------------
choice /c YN /m "确认打包"
if errorlevel 2 exit /b 0

:: ---------- 6. 执行 ----------
if /i "%FLAVOR%"=="ALL" (
    call :build arm_all
    call :build arm64
    call :build arm32
    call :build x8664
) else (
    call :build %FLAVOR%
)

:: ---------- 7. 显式收集一次（双保险） ----------
echo.
echo [INFO] 收集产物到 build\dist ...
call gradlew.bat collectDist

:: ---------- 8. 回写版本号 ----------
if exist "gradle.properties" (
    findstr /v /b /c:"VERSION_CODE=" /c:"VERSION_NAME=" gradle.properties > gradle.properties.tmp
    echo VERSION_CODE=%V_CODE%>> gradle.properties.tmp
    echo VERSION_NAME=%V_NAME%>> gradle.properties.tmp
    move /y gradle.properties.tmp gradle.properties >nul
    echo [OK] 版本号已回写
)

set "DIST_DIR=%~dp0build\dist"
echo.
echo ==========================================
echo   打包完成
echo   版本     : v%V_NAME% (%V_CODE%)
echo   签名     : %SIGN_MODE%
echo   产物目录 : %DIST_DIR%
echo ==========================================
if exist "%DIST_DIR%" (
    echo.
    echo 产物清单:
    dir /b "%DIST_DIR%"
    start "" "%DIST_DIR%"
)
pause
exit /b 0


:: ==================== 子过程 ====================
:build
set "F=%~1"

:: 显式映射任务名（比 %F:~0,1% 更可靠）
if /i "%F%"=="arm_all" set "FLAVOR_CAP=Arm_all"
if /i "%F%"=="arm64"   set "FLAVOR_CAP=Arm64"
if /i "%F%"=="arm32"   set "FLAVOR_CAP=Arm32"
if /i "%F%"=="x8664"   set "FLAVOR_CAP=X8664"

if /i "%PKG_TYPE%"=="AAB" (
    set "TASK=bundle%FLAVOR_CAP%Release"
) else (
    set "TASK=assemble%FLAVOR_CAP%Release"
)

echo.
echo [INFO] 打包 !TASK!  signMode=%SIGN_MODE%
call gradlew.bat !TASK! --no-configuration-cache ^
    -PsignMode=%SIGN_MODE% ^
    -PversionCode=%V_CODE% ^
    -PversionName=%V_NAME%
if errorlevel 1 (
    echo [ERROR] !TASK! 打包失败！
    exit /b 1
)
exit /b 0