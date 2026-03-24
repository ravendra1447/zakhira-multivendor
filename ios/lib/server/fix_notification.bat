@echo off
echo Fixing notification service...
copy "routes\marketplace\notifications\marketplaceNotificationService_fixed.js" "routes\marketplace\notifications\marketplaceNotificationService.js" /Y
echo Notification service updated successfully!
echo Restart server to apply changes.
pause
