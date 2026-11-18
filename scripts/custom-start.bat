@echo off
rem custom-start.bat - runs every time the instance launches, right after the modpack sync.
rem Edit it in the GitHub repo (scripts/custom-start.bat): everyone gets the new version on their next launch.
rem Working folder: the instance's .minecraft folder.  %1 = path to the instance's Java.
rem Its exit code is ignored, so a mistake here never stops the game from launching.

exit /b 0
