@echo off
echo Fixing iOS App Icon - Removing Alpha Channel...
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.x and try again
    pause
    exit /b 1
)

REM Check if PIL/Pillow is installed
python -c "import PIL" >nul 2>&1
if errorlevel 1 (
    echo Installing required package: Pillow...
    pip install Pillow
    if errorlevel 1 (
        echo ERROR: Failed to install Pillow
        echo Please run: pip install Pillow
        pause
        exit /b 1
    )
)

REM Run the Python script
python fix_app_icon.py

echo.
pause

