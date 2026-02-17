@echo off
echo Applying notification service fix...
cd routes\marketplace\notifications
del marketplaceNotificationService.js
rename marketplaceNotificationService_fixed.js marketplaceNotificationService.js
echo ✅ Fixed notification service applied successfully!
echo.
echo Restart server to apply changes.
pause
