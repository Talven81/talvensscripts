#CANCEL a pending reboot
Remove-Item -path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData';
Remove-Item -path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Updates Management\Handler\UpdatesRebootStatus\*';
Remove-ItemProperty -name * -path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired';
#on PS2.0, "Remove-ItemProperty" doesn't work, so use this.
Remove-Item -path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired';
shutdown -a 
Restart-Service ccmexec -force
