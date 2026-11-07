@echo off
rem Файл сохранён в UTF-8: без chcp 65001 cmd.exe показал бы кириллицу
rem мусором (консоль по умолчанию в кодовой странице 866/1251).
chcp 65001 >nul
rem install-ppe.cmd — запуск install-ppe.ps1 без ручного набора ключей PowerShell.
rem
rem Почему обёртка:
rem   * политика выполнения Windows запрещает .ps1 по двойному клику;
rem   * нужен pwsh (PowerShell 7) — если его нет, cmd подскажет, откуда скачать,
rem     вместо того чтобы молча закрыть окно.
rem
rem Все аргументы передаются в скрипт как есть: install-ppe.cmd -p 8010
setlocal enabledelayedexpansion

set "SCRIPT=%~dp0install-ppe.ps1"
if not exist "%SCRIPT%" (
    echo.
    echo Не найден install-ppe.ps1 рядом с этим файлом.
    echo Положите install-ppe.cmd и install-ppe.ps1 в одну папку.
    echo.
    pause
    exit /b 1
)

where pwsh >nul 2>&1
if errorlevel 1 goto :no_pwsh

pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=!ERRORLEVEL!"
if not "!RC!"=="0" (
    echo.
    echo Установка завершилась с кодом !RC!. Выше — причина и подсказка.
    echo.
    pause
)
exit /b !RC!

:no_pwsh
echo.
echo PowerShell 7 (pwsh) не найден в PATH.
echo Скачать:      https://aka.ms/powershell
echo Или напрямую: https://github.com/PowerShell/PowerShell/releases/latest
echo.
echo После установки закройте это окно, откройте новое и запустите файл снова.
echo.
echo Если PowerShell 7 ставить не хочется, можно запустить установщик
echo на встроенном Windows PowerShell 5.1:
echo     powershell -NoProfile -ExecutionPolicy Bypass -File install-ppe.ps1
echo.
pause
exit /b 1
