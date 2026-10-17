chcp 936 >nul
@echo off
setlocal EnableDelayedExpansion
rem ---------------- 可配置项 ----------------
rem 默认从灵机官方 GitHub Releases 取包；可用 --url 或环境变量 LINGJI_PACKAGE_URL / LINGJI_GITHUB_RELEASE_URL 覆盖。
set "LINGJI_GITHUB_RELEASE_URL=https://github.com/wangduoyu001/lingji-dist/releases/latest/download/lingji-windows-x64.zip"
rem ====================================================================
rem  灵机 Windows 一站式安装器（install_lingji.bat）
rem  适用规则：WIN-INSTALL-DISK-50G / WIN-INSTALL-NO-SYSTEM-WRITE
rem
rem  流程：环境检测 - 选非系统盘 - 备齐安装包（缺失则自动下载）
rem        - Ollama + 三模型（只写非系统盘）
rem        - 启动灵机后端（127.0.0.1:8766）
rem        - 自动查找本机智能体，给出可复制的 MCP 连接指令
rem
rem  用法：install_lingji.bat [--root 安装目录] [--url 安装包zip地址]
rem  退出码：0 成功；2 环境不满足；3 启动失败
rem  全程无需管理员权限；除用户显式解压位置外不写系统盘。
rem ====================================================================
rem ---------------- 参数解析 ----------------
set "ARG_ROOT="
set "ARG_URL="
:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--root" ( set "ARG_ROOT=%~2" & shift /1 & shift /1 & goto :parse_args )
if /i "%~1"=="--url" ( set "ARG_URL=%~2" & shift /1 & shift /1 & goto :parse_args )
if /i "%~1"=="--uninstall" ( set "ARG_UNINSTALL=1" & shift /1 & goto :parse_args )
if /i "%~1"=="--no-link" ( set "ARG_NOLINK=1" & shift /1 & goto :parse_args )
if /i "%~1"=="--i-understand-data-loss" ( set "ARG_FORCE=1" & shift /1 & goto :parse_args )
if /i "%~1"=="--help" ( goto :usage_main )
echo [错误] 未知参数：%~1
goto :usage_main
:extract_zip
set "ZIPPATH=%~1"
set "DESTPATH=%~2"
set "ZIPPATH=%ZIPPATH:'=''%"
set "DESTPATH=%DESTPATH:'=''%"
powershell -NoProfile -Command "Expand-Archive -Force -LiteralPath '%ZIPPATH%' -DestinationPath '%DESTPATH%'"
exit /b 0
:args_done
if defined ARG_UNINSTALL goto :uninstall
rem ---------------- 包目录（本 bat 所在目录） ----------------
set "PKG_ROOT=%~dp0"
set "PKG_ROOT=%PKG_ROOT:~0,-1%"
rem ---------------- 选择安装目录（默认自动选非系统盘） ----------------
if defined ARG_ROOT (
  set "INSTALL_ROOT=%ARG_ROOT%"
  if /i "!INSTALL_ROOT:~0,2!"=="%SystemDrive%" echo [提醒] --root 指定了系统盘目录，安装数据将写入 !INSTALL_ROOT!
) else (
  rem 优先 E: 其次 D: 再其他固定非系统盘；要求剩余空间大于 50G
  for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -and $_.Name -ne $env:SystemDrive -and $_.FreeSpace -gt 50GB } | Sort-Object @{e={@('E:','D:').IndexOf($_.Name)}} | Select-Object -First 1 -ExpandProperty Name"`) do set "INSTALL_DRIVE=%%D"
  if not defined INSTALL_DRIVE (
    echo [错误] 未找到剩余空间大于 50G 的非系统盘。
    echo         请清理磁盘，或用 --root 指定安装目录后重试。
    exit /b 2
  )
  set "INSTALL_ROOT=%INSTALL_DRIVE%\LingJi"
)
if not exist "%INSTALL_ROOT%" (
  md "%INSTALL_ROOT%" 2>nul
  if errorlevel 1 ( echo [错误] 无法创建安装目录：%INSTALL_ROOT% & exit /b 2 )
)
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%T"
set "LOG_DIR=%INSTALL_ROOT%\logs"
if not exist "%LOG_DIR%" md "%LOG_DIR%"
set "LOG_FILE=%LOG_DIR%\install-%TS%.log"
set "SUMMARY_FILE=%INSTALL_ROOT%\install-summary.txt"
echo.
echo ============================================================
echo   灵机 Windows 一站式安装
echo ============================================================
echo   安装目录：%INSTALL_ROOT%
echo   日志文件：%LOG_FILE%
echo ============================================================
echo.
call :log "==== 灵机一站式安装开始 %TS% ===="
rem ---------------- 第 1 步：环境检测 ----------------
call :log "[1/6] 检测电脑环境 ..."
call :log "  系统：%OS% %PROCESSOR_ARCHITECTURE%"
call :log "  系统盘：%SystemDrive%（安装与数据只写非系统盘）"
for /f "usebackq tokens=1,2" %%a in (`powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { '{0} {1}' -f $_.Name, [math]::Round($_.FreeSpace/1GB,1) }"`) do call :log "  磁盘 %%a 剩余 %%b GB"
where curl >nul 2>nul && call :log "  下载工具：curl 可用" || call :log "  下载工具：curl 缺失（将改用 PowerShell 下载）"
where powershell >nul 2>nul && call :log "  解压工具：PowerShell(Expand-Archive) 可用" || call :log "  解压工具：PowerShell 缺失，解压将失败"
call :port_up 8766
if not errorlevel 1 ( call :log "  端口 8766：已有服务在监听" ) else ( call :log "  端口 8766：空闲" )
call :port_up 11434
if not errorlevel 1 ( call :log "  端口 11434：已有服务在监听" ) else ( call :log "  端口 11434：空闲" )
rem ---------------- 第 2 步：备齐安装包 ----------------
call :log "[2/6] 准备灵机安装包 ..."
set "BIN_DIR=%INSTALL_ROOT%\bin"
set "DATA_ROOT=%INSTALL_ROOT%\data"
set "MCP_EXE=%BIN_DIR%\lingji-mcp.exe"
set "CORE_EXE=%BIN_DIR%\lingji-core.exe"
set "SRC_BIN="
if exist "%PKG_ROOT%\bin\lingji-core.exe" (
  set "SRC_BIN=%PKG_ROOT%\bin"
  call :log "  使用本目录自带的安装包：%PKG_ROOT%\bin"
)
if not defined SRC_BIN (
  rem 本目录没有 bin\ 时，找旁边的 zip 包；优先挑 lingji 开头的包
  set "LOCAL_ZIP="
  for %%F in ("%PKG_ROOT%\lingji*.zip") do set "LOCAL_ZIP=%%F"
  if not defined LOCAL_ZIP for %%F in ("%PKG_ROOT%\*.zip") do set "LOCAL_ZIP=%%F"
  if defined LOCAL_ZIP (
    rem 多个候选时提示一声，避免静默挑错包
    set /a ZIP_COUNT=0
    for %%F in ("%PKG_ROOT%\*.zip") do set /a ZIP_COUNT+=1
    if !ZIP_COUNT! gtr 1 call :log "  注意：本目录有 !ZIP_COUNT! 个 zip，将使用 !LOCAL_ZIP!"
  )
  if defined LOCAL_ZIP (
    call :log "  发现本地安装包：!LOCAL_ZIP!，开始解压 ..."
    if not exist "%INSTALL_ROOT%\package" md "%INSTALL_ROOT%\package"
    call :extract_zip "!LOCAL_ZIP!" "%INSTALL_ROOT%\package" >>"%LOG_FILE%" 2>&1
    if exist "%INSTALL_ROOT%\package\bin\lingji-core.exe" (
      set "SRC_BIN=%INSTALL_ROOT%\package\bin"
    ) else if exist "%INSTALL_ROOT%\package\lingji-windows-x64\bin\lingji-core.exe" (
      set "SRC_BIN=%INSTALL_ROOT%\package\lingji-windows-x64\bin"
    )
  )
)
if not defined SRC_BIN (
  set "PKG_URL=%ARG_URL%"
  if not defined PKG_URL if defined LINGJI_PACKAGE_URL set "PKG_URL=%LINGJI_PACKAGE_URL%"
  if not defined PKG_URL (
    rem 地址里仍含 OWNER/REPO 占位符才视为未配置；否则使用内置默认地址
    echo !LINGJI_GITHUB_RELEASE_URL! | findstr /i "OWNER/REPO" >nul
    if errorlevel 1 set "PKG_URL=!LINGJI_GITHUB_RELEASE_URL!"
  )
  if defined PKG_URL (
    call :log "  自动下载安装包：!PKG_URL!"
    if not exist "%INSTALL_ROOT%\downloads" md "%INSTALL_ROOT%\downloads"
    set "PKG_ZIP=%INSTALL_ROOT%\downloads\lingji-windows-x64.zip"
    curl -L --fail --connect-timeout 20 -o "!PKG_ZIP!" "!PKG_URL!" >>"%LOG_FILE%" 2>&1
    if errorlevel 1 (
      echo.
      echo [错误] 自动下载安装包失败。
      echo.
      echo   常见原因与处理方式：
      echo     1）网络不通或需要代理 —— 请确认能正常上网后重试；
      echo     2）公司网络拦截 —— 换手机热点再重试；
      echo     3）直链已更新 —— 请向发放方索取最新版的 install_lingji.bat；
      echo     4）离线安装 —— 手动下载 lingji-windows-x64.zip，
      echo        放到本 bat 同一目录后重新运行，脚本会自动使用本地包；
      echo     5）自定义地址 —— install_lingji.bat --url "zip 的直链地址"
      echo.
      goto :install_abort
    )
    if not exist "%INSTALL_ROOT%\package" md "%INSTALL_ROOT%\package"
    call :extract_zip "!PKG_ZIP!" "%INSTALL_ROOT%\package" >>"%LOG_FILE%" 2>&1
    if exist "%INSTALL_ROOT%\package\bin\lingji-core.exe" (
      set "SRC_BIN=%INSTALL_ROOT%\package\bin"
    ) else if exist "%INSTALL_ROOT%\package\lingji-windows-x64\bin\lingji-core.exe" (
      set "SRC_BIN=%INSTALL_ROOT%\package\lingji-windows-x64\bin"
    )
  )
)
if not defined SRC_BIN (
  echo [错误] 未找到灵机安装包。请确认以下之一：
  echo   1. 本 bat 与 bin 目录在同一文件夹内运行；
  echo   2. 本 bat 旁边有 lingji-windows-x64.zip；
  echo   3. 用 --url 或环境变量 LINGJI_PACKAGE_URL 提供下载地址。
  goto :install_abort
)
rem 复制到安装目录（已存在且校验通过则跳过，重复安装更快）
if not exist "%BIN_DIR%" md "%BIN_DIR%"
set "NEED_COPY=1"
if exist "%CORE_EXE%" if exist "%SRC_BIN%\..\SHA256SUMS" (
  set "EXPECTED_CORE="
  set "EXPECTED_MCP="
  for /f "usebackq tokens=1,2" %%a in ("%SRC_BIN%\..\SHA256SUMS") do (
    if "%%b"=="bin/lingji-core.exe" set "EXPECTED_CORE=%%a"
    if "%%b"=="bin/lingji-mcp.exe" set "EXPECTED_MCP=%%a"
  )
  call :sha256_of "%CORE_EXE%"
  if /i "!FILE_HASH!"=="!EXPECTED_CORE!" (
    call :sha256_of "%MCP_EXE%"
    if /i "!FILE_HASH!"=="!EXPECTED_MCP!" (
      set "NEED_COPY="
      call :log "  安装目录已存在且校验通过，跳过复制"
    )
  )
)
if defined NEED_COPY (
  call :log "  复制安装包到 %BIN_DIR% ..."
  robocopy "%SRC_BIN%" "%BIN_DIR%" /E /NFL /NDL /NJH /NJS /NP >>"%LOG_FILE%" 2>&1
  if errorlevel 8 ( echo [错误] 复制安装包失败，详见日志 %LOG_FILE% & exit /b 2 )
)
if not exist "%CORE_EXE%" ( echo [错误] 安装包不完整：缺少 lingji-core.exe & exit /b 2 )
if not exist "%MCP_EXE%" ( echo [错误] 安装包不完整：缺少 lingji-mcp.exe & exit /b 2 )
call :log "  安装包就绪"
rem ---------------- 第 3 步：准备 Ollama 与模型目录 ----------------
call :log "[3/6] 准备本地大模型（Ollama）..."
set "OLLAMA_EXE="
where ollama >nul 2>nul && for /f "usebackq delims=" %%i in (`where ollama`) do if not defined OLLAMA_EXE set "OLLAMA_EXE=%%i"
rem 便携版优先；系统盘上的 OLLAMA_MODELS 一律改指非系统盘
if exist "%INSTALL_ROOT%\tools\ollama\ollama.exe" set "OLLAMA_EXE=%INSTALL_ROOT%\tools\ollama\ollama.exe"
set "MODELS_DIR="
if defined OLLAMA_MODELS if /i not "%OLLAMA_MODELS:~0,2%"=="%SystemDrive%" set "MODELS_DIR=%OLLAMA_MODELS%"
if not defined MODELS_DIR set "MODELS_DIR=%INSTALL_ROOT%\models"
if not exist "%MODELS_DIR%" md "%MODELS_DIR%" 2>nul
call :port_up 11434
if not errorlevel 1 goto :ollama_already_up
if not defined OLLAMA_EXE (
  call :log "  未检测到 Ollama，自动下载便携版到 %INSTALL_ROOT%\tools ..."
  if not exist "%INSTALL_ROOT%\downloads" md "%INSTALL_ROOT%\downloads"
  set "OLLAMA_ZIP=%INSTALL_ROOT%\downloads\ollama-windows-amd64.zip"
  if not exist "!OLLAMA_ZIP!" (
    curl -L --fail --connect-timeout 20 -o "!OLLAMA_ZIP!" "https://ollama.com/download/ollama-windows-amd64.zip" >>"%LOG_FILE%" 2>&1
    if errorlevel 1 (
      powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://ollama.com/download/ollama-windows-amd64.zip' -OutFile '!OLLAMA_ZIP!'" >>"%LOG_FILE%" 2>&1
    )
  )
  if not exist "!OLLAMA_ZIP!" ( echo [错误] Ollama 便携版下载失败，详见日志 %LOG_FILE% & exit /b 2 )
  if not exist "%INSTALL_ROOT%\tools\ollama" md "%INSTALL_ROOT%\tools\ollama"
  call :extract_zip "!OLLAMA_ZIP!" "%INSTALL_ROOT%\tools\ollama" >>"%LOG_FILE%" 2>&1
  if not exist "%INSTALL_ROOT%\tools\ollama\ollama.exe" ( echo [错误] Ollama 解压失败，详见日志 %LOG_FILE% & exit /b 2 )
  set "OLLAMA_EXE=%INSTALL_ROOT%\tools\ollama\ollama.exe"
)
rem 启动 Ollama 服务：模型目录强制落到非系统盘
call :log "  启动 Ollama 服务（模型目录：%MODELS_DIR%）..."
set "OLLAMA_MODELS=%MODELS_DIR%"
start "LingJi-Ollama" /min "%OLLAMA_EXE%" serve
set "OLLAMA_UP="
for /l %%i in (1,1,60) do (
  call :port_up 11434
  if not errorlevel 1 set "OLLAMA_UP=1"
  if defined OLLAMA_UP goto :ollama_wait_done
  ping -n 2 127.0.0.1 >nul
)
:ollama_wait_done
if not defined OLLAMA_UP (
  echo [错误] Ollama 服务 60 秒内未就绪，详见日志 %LOG_FILE%
  exit /b 3
)
call :log "  Ollama 服务就绪"
goto :ollama_done
:ollama_already_up
call :log "  检测到 Ollama 服务已在运行（11434），模型目录沿用现有实例"
if not defined OLLAMA_EXE set "OLLAMA_EXE=ollama"
:ollama_done
rem ---------------- 第 4 步：拉取缺失模型 ----------------
call :log "[4/6] 检查并拉取模型（qwen3:8b / qwen3-embedding:0.6b / nomic-embed-text）..."
for %%M in (qwen3:8b qwen3-embedding:0.6b nomic-embed-text) do (
  "%OLLAMA_EXE%" list 2>nul | findstr /b /c:"%%M" >nul
  if errorlevel 1 (
    call :log "  拉取模型 %%M（大文件，请耐心等待）..."
    "%OLLAMA_EXE%" pull %%M >>"%LOG_FILE%" 2>&1
    if errorlevel 1 (
      call :log "  [警告] 模型 %%M 拉取失败；可稍后手动执行 %OLLAMA_EXE% pull %%M"
    ) else (
      call :log "  模型 %%M 就绪"
    )
  ) else (
    call :log "  模型 %%M 已存在，跳过"
  )
)
rem ---------------- 第 5 步：启动灵机后端 ----------------
call :log "[5/6] 启动灵机本地后端（数据根：%DATA_ROOT%）..."
call :port_up 8766
if not errorlevel 1 goto :core_already_up
if not exist "%DATA_ROOT%" md "%DATA_ROOT%"
start "" "%CORE_EXE%" --data-root "%DATA_ROOT%"
set "CORE_UP="
for /l %%i in (1,1,120) do (
  if exist "%DATA_ROOT%\storage\control_api_token" set "CORE_UP=1"
  if defined CORE_UP goto :core_wait_done
  ping -n 2 127.0.0.1 >nul
)
:core_wait_done
if not defined CORE_UP (
  echo [错误] 灵机后端 120 秒内未就绪，详见日志 %LOG_FILE%
  exit /b 3
)
set "CORE_PID=未知"
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "(Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess"`) do set "CORE_PID=%%P"
call :log "  灵机后端就绪：http://127.0.0.1:8766（PID %CORE_PID%）"
goto :core_done
:core_already_up
call :log "  8766 已有服务在监听，跳过启动（重复安装可直接用）"
set "CORE_PID=已在运行"
:core_done
rem ---------------- 第 6 步：查找本机智能体，给出 MCP 连接指令 ----------------
call :log "[6/6] 查找本机已安装的智能体 ..."
set "F_CLAUDE="
set "F_CODEX="
set "F_GEMINI="
set "F_WORKBUDDY="
where claude >nul 2>nul && set "F_CLAUDE=1"
if exist "%USERPROFILE%\.claude" set "F_CLAUDE=1"
where codex >nul 2>nul && set "F_CODEX=1"
if exist "%USERPROFILE%\.codex" set "F_CODEX=1"
where gemini >nul 2>nul && set "F_GEMINI=1"
if exist "%USERPROFILE%\.gemini" set "F_GEMINI=1"
where workbuddy >nul 2>nul && set "F_WORKBUDDY=1"
if exist "%USERPROFILE%\.workbuddy" set "F_WORKBUDDY=1"
set "AGENT_NAMES="
if defined F_CLAUDE set "AGENT_NAMES=!AGENT_NAMES! Claude-Code"
if defined F_CODEX set "AGENT_NAMES=!AGENT_NAMES! Codex-CLI"
if defined F_GEMINI set "AGENT_NAMES=!AGENT_NAMES! Gemini-CLI"
if defined F_WORKBUDDY set "AGENT_NAMES=!AGENT_NAMES! WorkBuddy"
rem 各智能体一键指令（打包形态：智能体直拉 lingji-mcp.exe，零 Python 依赖）
set "CMD_CLAUDE=claude mcp add --scope user lingji-memory -- "%MCP_EXE%" "--data-root" "%DATA_ROOT%" "--agent" "claude""
set "CMD_CODEX_L1=[mcp_servers.lingji_memory]"
set "CMD_CODEX_L2=command = "%MCP_EXE%""
set "CMD_CODEX_L3=args = ["--data-root", "%DATA_ROOT%", "--agent", "codex"]"
set "CMD_CODEX_L4=cwd = "%BIN_DIR%""
set "CMD_CODEX_L5=enabled = true"
set "CMD_GEMINI=gemini mcp add --scope user --transport stdio lingji-memory "%MCP_EXE%" "--data-root" "%DATA_ROOT%" "--agent" "gemini""
set "CMD_WB_L1={"
set "CMD_WB_L2=  "mcpServers": {"
set "CMD_WB_L3=    "lingji-memory": {"
set "CMD_WB_L4=      "command": "%MCP_EXE%","
set "CMD_WB_L5=      "args": ["--data-root", "%DATA_ROOT%", "--agent", "workbuddy"]"
set "CMD_WB_L6=    }"
set "CMD_WB_L7=  }"
set "CMD_WB_L8=}"
if defined ARG_NOLINK ( call :log "  跳过自动 MCP 注册（--no-link）" ) else ( call :log "  主动为已安装的 AI 注册灵机 MCP ..." & call :link_agents )
> "%SUMMARY_FILE%" echo 安装摘要：%TS%
>>"%SUMMARY_FILE%" echo 安装目录：%INSTALL_ROOT%
>>"%SUMMARY_FILE%" echo 数据根：%DATA_ROOT%
>>"%SUMMARY_FILE%" echo 灵机后端：http://127.0.0.1:8766
>>"%SUMMARY_FILE%" echo 模型目录：%MODELS_DIR%
>>"%SUMMARY_FILE%" echo.
>>"%SUMMARY_FILE%" echo 本机检测到的智能体：%AGENT_NAMES%
>>"%SUMMARY_FILE%" echo.
echo.
echo ============================================================
echo   安装完成
echo ============================================================
echo   安装目录：%INSTALL_ROOT%
echo   数据根：  %DATA_ROOT%
echo   模型目录：%MODELS_DIR%
echo   灵机后端：http://127.0.0.1:8766（PID %CORE_PID%）
echo   新手引导：%DATA_ROOT%\runtime\first-run-guide.txt
echo   完整摘要：%SUMMARY_FILE%
echo ------------------------------------------------------------
if defined AGENT_NAMES (
  echo   本机智能体：%AGENT_NAMES%
) else (
  echo   本机未检测到已知智能体，以下给出通用连接指令。
)
echo ------------------------------------------------------------
echo   MCP 一键连接指令（第一条已复制到剪贴板，可直接粘贴执行）：
echo.
if defined F_CLAUDE (
  echo   [Claude Code] 终端执行即注册：
  echo   !CMD_CLAUDE!
  >>"%SUMMARY_FILE%" echo [Claude Code]
  >>"%SUMMARY_FILE%" echo !CMD_CLAUDE!
  >>"%SUMMARY_FILE%" echo.
)
if defined F_CODEX (
  echo   [Codex CLI] 追加到 %USERPROFILE%\.codex\config.toml：
  echo   !CMD_CODEX_L1!
  echo   !CMD_CODEX_L2!
  echo   !CMD_CODEX_L3!
  echo   !CMD_CODEX_L4!
  echo   !CMD_CODEX_L5!
  >>"%SUMMARY_FILE%" echo [Codex CLI] 追加到 ~/.codex/config.toml：
  >>"%SUMMARY_FILE%" echo !CMD_CODEX_L1!
  >>"%SUMMARY_FILE%" echo !CMD_CODEX_L2!
  >>"%SUMMARY_FILE%" echo !CMD_CODEX_L3!
  >>"%SUMMARY_FILE%" echo !CMD_CODEX_L4!
  >>"%SUMMARY_FILE%" echo !CMD_CODEX_L5!
  >>"%SUMMARY_FILE%" echo.
)
if defined F_GEMINI (
  echo   [Gemini CLI] 终端执行即注册：
  echo   !CMD_GEMINI!
  >>"%SUMMARY_FILE%" echo [Gemini CLI]
  >>"%SUMMARY_FILE%" echo !CMD_GEMINI!
  >>"%SUMMARY_FILE%" echo.
)
if defined F_WORKBUDDY (
  echo   [WorkBuddy] 合并进 %USERPROFILE%\.workbuddy\mcp.json 的 mcpServers：
  echo   !CMD_WB_L1!
  echo   !CMD_WB_L2!
  echo   !CMD_WB_L3!
  echo   !CMD_WB_L4!
  echo   !CMD_WB_L5!
  echo   !CMD_WB_L6!
  echo   !CMD_WB_L7!
  echo   !CMD_WB_L8!
  >>"%SUMMARY_FILE%" echo [WorkBuddy] 合并进 ~/.workbuddy/mcp.json：
  >>"%SUMMARY_FILE%" echo !CMD_WB_L1!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L2!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L3!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L4!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L5!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L6!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L7!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L8!
  >>"%SUMMARY_FILE%" echo.
)
if not defined F_CLAUDE if not defined F_CODEX if not defined F_GEMINI if not defined F_WORKBUDDY (
  echo   [通用 JSON] 合并进任意支持 MCP 的客户端：
  echo   !CMD_WB_L1!
  echo   !CMD_WB_L2!
  echo   !CMD_WB_L3!
  echo   !CMD_WB_L4!
  echo   !CMD_WB_L5!
  echo   !CMD_WB_L6!
  echo   !CMD_WB_L7!
  echo   !CMD_WB_L8!
  >>"%SUMMARY_FILE%" echo [通用 JSON]
  >>"%SUMMARY_FILE%" echo !CMD_WB_L1!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L2!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L3!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L4!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L5!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L6!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L7!
  >>"%SUMMARY_FILE%" echo !CMD_WB_L8!
)
rem 复制第一条指令到剪贴板（优先单行命令）
call :clip_first
>>"%SUMMARY_FILE%" echo.
>>"%SUMMARY_FILE%" echo 停止灵机：结束 lingji-core.exe 进程即可；重启：bin\lingji-core.exe --data-root %DATA_ROOT%
echo ============================================================
call :log "==== 安装结束：成功 ===="
exit /b 0
rem ====================================================================
rem  子程序区（主流程以 exit /b 收尾，不会穿窗落入此处）
rem ====================================================================
:clip_first
if defined F_CLAUDE (
  (echo !CMD_CLAUDE!)|clip
  exit /b 0
)
if defined F_GEMINI (
  (echo !CMD_GEMINI!)|clip
  exit /b 0
)
if defined F_CODEX (
  (echo !CMD_CODEX_L1!&echo !CMD_CODEX_L2!&echo !CMD_CODEX_L3!&echo !CMD_CODEX_L4!&echo !CMD_CODEX_L5!)|clip
  exit /b 0
)
(echo !CMD_WB_L1!&echo !CMD_WB_L2!&echo !CMD_WB_L3!&echo !CMD_WB_L4!&echo !CMD_WB_L5!&echo !CMD_WB_L6!&echo !CMD_WB_L7!&echo !CMD_WB_L8!)|clip
exit /b 0
:log
echo [%TIME%] %~1
>>"%LOG_FILE%" echo [%TIME%] %~1
exit /b 0
:port_up
netstat -ano 2>nul | findstr ":%1 " 2>nul | findstr "LISTENING" >nul 2>nul
exit /b %errorlevel%
:sha256_of
set "FILE_HASH="
for /f "usebackq skip=1 tokens=* delims=" %%H in (`certutil -hashfile "%~1" SHA256 2^>nul`) do if not defined FILE_HASH set "FILE_HASH=%%H"
set "FILE_HASH=!FILE_HASH: =!"
exit /b 0
:install_abort
exit /b 2

:usage_main
echo 用法：install_lingji.bat [选项]
echo   （无参数）        正常安装，自动选剩余空间大于 50G 的非系统盘
echo   --root ^<目录^>     指定安装目录（默认自动选 E 盘/D 盘非系统盘）
echo   --url ^<zip地址^>  指定安装包 zip 下载地址
echo   --no-link        安装但跳过自动 MCP 注册
echo   --uninstall      一键卸载（清除灵机记忆与数据，不删其他文件）
echo   --i-understand-data-loss  卸载时强制越过生产数据守卫
echo   --help           显示本帮助
echo.
echo   安装方法（只需两步）：
echo     1）下载本文件 install_lingji.bat；
echo     2）双击运行。
echo.
echo   脚本会自动下载安装包、准备本地模型、启动后端，
echo   并自动把灵机 MCP 注册到本机已安装的 AI 工具。
echo   若同目录已有 lingji-windows-x64.zip，会优先使用本地包。
echo.
echo   退出码：0 成功；2 参数/资源错误；3 运行失败
exit /b 2

rem ====================================================================
rem  主动注册 MCP（真正写入各 AI 配置，而不是只打印命令）
rem ====================================================================
:link_agents
if defined F_CLAUDE (
  call :log "  注册 Claude Code MCP ..."
  claude mcp add --scope user lingji-memory -- "%MCP_EXE%" "--data-root" "%DATA_ROOT%" "--agent" "claude" >>"%LOG_FILE%" 2>&1
  if errorlevel 1 ( call :log "  [警告] Claude 注册失败，请手动执行摘要中的命令" ) else ( call :log "  Claude 注册成功" )
)
if defined F_GEMINI (
  call :log "  注册 Gemini CLI MCP ..."
  gemini mcp add --scope user --transport stdio lingji-memory "%MCP_EXE%" "--data-root" "%DATA_ROOT%" "--agent" "gemini" >>"%LOG_FILE%" 2>&1
  if errorlevel 1 ( call :log "  [警告] Gemini 注册失败" ) else ( call :log "  Gemini 注册成功" )
)
if defined F_CODEX ( call :link_codex )
if defined F_WORKBUDDY ( call :link_workbuddy )
exit /b 0

:link_codex
set "CODEX_CFG=%USERPROFILE%\.codex\config.toml"
if not exist "%CODEX_CFG%" ( echo # LingJi MCP config > "%CODEX_CFG%" )
findstr /i "lingji_memory" "%CODEX_CFG%" >nul
if not errorlevel 1 (
  call :log "  Codex 已存在 lingji_memory 配置，跳过"
  exit /b 0
)
>>"%CODEX_CFG%" echo.
>>"%CODEX_CFG%" echo [mcp_servers.lingji_memory]
>>"%CODEX_CFG%" echo command = "%MCP_EXE%"
>>"%CODEX_CFG%" echo args = ["--data-root", "%DATA_ROOT%", "--agent", "codex"]
>>"%CODEX_CFG%" echo cwd = "%BIN_DIR%"
>>"%CODEX_CFG%" echo enabled = true
>>"%CODEX_CFG%" echo startup_timeout_ms = 30000
>>"%CODEX_CFG%" echo tool_timeout_sec = 60
call :log "  Codex 配置已写入 %CODEX_CFG%"
exit /b 0

:link_workbuddy
set "WB_CFG=%USERPROFILE%\.workbuddy\mcp.json"
powershell -NoProfile -Command "$p='%WB_CFG%'; $cmd='%MCP_EXE%'; $dr='%DATA_ROOT%'; $bin='%BIN_DIR%'; $o=$null; if(Test-Path $p){ try{ $o=Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json }catch{ $o=$null } }; if($null -eq $o){ $o=New-Object PSObject }; if(-not $o.mcpServers){ $o|Add-Member -MemberType NoteProperty -Name mcpServers -Value (New-Object PSObject) }; $entry=New-Object PSObject; $entry|Add-Member -MemberType NoteProperty -Name command -Value $cmd; $entry|Add-Member -MemberType NoteProperty -Name args -Value @('--data-root',$dr,'--agent','workbuddy'); $entry|Add-Member -MemberType NoteProperty -Name cwd -Value $bin; $o.mcpServers|Add-Member -MemberType NoteProperty -Name 'lingji-memory' -Value $entry -Force; $dir=Split-Path $p; if($dir -and -not(Test-Path $dir)){ New-Item -ItemType Directory -Path $dir -Force|Out-Null }; [IO.File]::WriteAllText($p,(ConvertTo-Json $o -Depth 5),[Text.Encoding]::UTF8); Write-Host 'wb-written'"
exit /b 0

rem ====================================================================
rem  一键卸载（清除灵机记忆与数据，绝不删除其他文件）
rem ====================================================================
:uninstall
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%T"
set "UNINSTALL_LOG=%TEMP%\lingji-uninstall-%TS%.log"
set "LOG_FILE=%UNINSTALL_LOG%"
call :log "==== 灵机一键卸载开始 %TS% ===="
rem 确定安装目录
set "INSTALL_ROOT="
if defined ARG_ROOT ( set "INSTALL_ROOT=%ARG_ROOT%" )
if not defined INSTALL_ROOT if exist "%SystemDrive%\LingJi" ( set "INSTALL_ROOT=%SystemDrive%\LingJi" )
if not defined INSTALL_ROOT if exist "E:\LingJi" ( set "INSTALL_ROOT=E:\LingJi" )
if not defined INSTALL_ROOT if exist "D:\LingJi" ( set "INSTALL_ROOT=D:\LingJi" )
if not defined INSTALL_ROOT (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$p=Join-Path $env:APPDATA 'LingJi\desktop-bootstrap.json'; if(Test-Path $p){ try{ (Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json).base_data_root }catch{} }"`) do set "INSTALL_ROOT=%%R"
)
if not defined INSTALL_ROOT (
  echo [错误] 无法确定灵机安装目录，请用 --root 指定，例如：
  echo        install_lingji.bat --uninstall --root E:\LingJi
  exit /b 2
)
if not exist "%INSTALL_ROOT%" ( echo [错误] 安装目录不存在：%INSTALL_ROOT% & exit /b 2 )
echo.
echo ====================================================================
echo                        灵机一键卸载 风险确认
echo ====================================================================
echo.
echo   即将卸载灵机，安装目录为：
echo     %INSTALL_ROOT%
echo.
echo   本操作将【永久删除】该目录下的所有内容，包括：
echo     - 全部记忆数据（storage/ 中的数据库与索引）
echo     - 向量索引（qdrant/）
echo     - 知识库正文（vault/）
echo     - 程序文件（bin/）、日志（logs/）、Ollama 模型（models/）
echo     - 同时移除 Claude / Codex / Gemini / WorkBuddy 中的灵机 MCP 注册
echo     - 清理 Ollama 中灵机专用的 3 个模型（qwen3:8b 等）
echo.
echo   此操作【不可恢复】。请确保已备份重要记忆。
echo   本操作【只删除上述灵机目录】，绝不会删除该目录之外的任何文件。
echo.
echo ====================================================================
echo.
set "CONFIRM="
set /p "CONFIRM=请输入“卸载”二字以确认删除（其他任意输入取消）："
if /i not "%CONFIRM%"=="卸载" ( echo 已取消卸载，未做任何改动。 & exit /b 2 )
call :log "  用户已确认卸载，安装目录：%INSTALL_ROOT%"
rem 1. 停止灵机核心（仅按 8766 端口定位的进程，不杀其他）
call :log "  停止灵机核心（端口 8766）..."
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "(Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1).OwningProcess"`) do set "CORE_PID=%%P"
if defined CORE_PID if not "%CORE_PID%"=="" ( taskkill /PID %CORE_PID% /T /F >nul 2>nul & call :log "  已请求停止灵机核心进程 PID=%CORE_PID%" )
rem 2. 移除各 AI 的 MCP 注册
call :log "  移除各 AI 的灵机 MCP 注册 ..."
call :unlink_agents
rem 3. 清理 Ollama 中灵机专用模型（仅这 3 个，不删其他模型/共享目录）
where ollama >nul 2>nul && (
  call :log "  清理 Ollama 中灵机专用模型 ..."
  for %%M in (qwen3:8b qwen3-embedding:0.6b nomic-embed-text) do ( ollama rm %%M >nul 2>nul & call :log "  移除模型 %%M（仅灵机专用，不影响其他模型与共享目录）" )
)
rem 4. 安全守卫：是否为生产数据根（命中则默认拒绝）
call :log "  执行删除前安全守卫 ..."
call :uninstall_guard
if errorlevel 1 (
  if not defined ARG_FORCE (
    echo.
    echo [拒绝] 检测到 %INSTALL_ROOT% 命中生产数据根特征，可能包含正式记忆数据。
    echo   如需强制卸载，请加参数：install_lingji.bat --uninstall --i-understand-data-loss
    echo   强制卸载会永久清除该目录下的全部记忆，请确认已备份。
    echo   详细日志：%UNINSTALL_LOG%
  )
)
if errorlevel 1 if not defined ARG_FORCE goto :uninstall_abort
if errorlevel 1 if defined ARG_FORCE echo [警告] 已收到 --i-understand-data-loss，强制卸载生产数据根。
rem 5. 删除安装目录
call :log "  删除安装目录：%INSTALL_ROOT%"
rd /s /q "%INSTALL_ROOT%" >nul 2>nul
if exist "%INSTALL_ROOT%" ( echo [错误] 删除失败，请检查权限或进程占用。日志：%UNINSTALL_LOG% & exit /b 3 )
echo.
echo [完成] 灵机已卸载：
echo   安装目录 %INSTALL_ROOT% 已删除。
echo   各 AI 的灵机 MCP 注册已移除，Ollama 中灵机专用模型已清理。
echo   仅删除了灵机自有文件，电脑上其他文件未受影响。
echo   详细日志：%UNINSTALL_LOG%
exit /b 0

:uninstall_abort
exit /b 2

:unlink_agents
where claude >nul 2>nul && ( claude mcp remove lingji-memory --scope user >nul 2>nul & call :log "  已移除 Claude MCP 注册" )
where gemini >nul 2>nul && ( gemini mcp remove lingji-memory --scope user >nul 2>nul & call :log "  已移除 Gemini MCP 注册" )
set "CODEX_CFG=%USERPROFILE%\.codex\config.toml"
if exist "%CODEX_CFG%" (
  powershell -NoProfile -Command "$p='%CODEX_CFG%'; if(Test-Path $p){ $lines=[IO.File]::ReadAllLines($p); $out=@(); $skip=$false; $hit=$false; foreach($ln in $lines){ if($ln -match '^\\[mcp_servers\\.lingji_memory\\]'){ $skip=$true; $hit=$true; continue } if($skip -and $ln -match '^\\['){ $skip=$false } if(-not $skip){ $out+=$ln } } if($hit){ [IO.File]::WriteAllLines($p,$out); Write-Host 'codex-removed' } }" >>"%LOG_FILE%" 2>&1
  call :log "  已清理 Codex config.toml 中的 lingji_memory 配置"
)
set "WB_CFG=%USERPROFILE%\.workbuddy\mcp.json"
if exist "%WB_CFG%" (
  powershell -NoProfile -Command "$p='%WB_CFG%'; if(Test-Path $p){ $o=Get-Content $p -Raw -Encoding UTF8|ConvertFrom-Json; if($o -and $o.mcpServers -and $o.mcpServers.PSObject.Properties['lingji-memory']){ $o.mcpServers.PSObject.Properties.Remove('lingji-memory'); [IO.File]::WriteAllText($p,(ConvertTo-Json $o -Depth 5),[Text.Encoding]::UTF8); Write-Host 'wb-removed' } }" >>"%LOG_FILE%" 2>&1
  call :log "  已清理 WorkBuddy mcp.json 中的 lingji-memory 配置"
)
exit /b 0

:uninstall_guard
powershell -NoProfile -Command "$root='%INSTALL_ROOT%'; $refuse=$false; if(Test-Path (Join-Path $root 'PRODUCTION_DATA_ROOT.md')){ $refuse=$true }; $st=Join-Path $root 'runtime\\sidecar-state.json'; if(Test-Path $st){ try{ $w=(Get-Content $st -Raw -Encoding UTF8|ConvertFrom-Json).workspace }catch{ $w=$null }; if($w -ne 'acceptance'){ $refuse=$true } }; if((Test-Path (Join-Path $root 'storage\\lingji_memory.db')) -and (Test-Path (Join-Path $root 'storage\\control_api_token'))){ $refuse=$true }; if($refuse){ Write-Host 'REFUSE'; exit 2 } else { Write-Host 'SAFE'; exit 0 }"
exit /b %errorlevel%
