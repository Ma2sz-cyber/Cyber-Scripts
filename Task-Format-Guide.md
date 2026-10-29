# CyberPatriot PowerShell task generator

Generate-CyberPatriotTasks.ps1 reads CyberPatriot-Tasks.txt and writes CyberPatriot-ExecuteTasks.ps1. It does not run the generated script. Review the generated script before running it, and use it only on the intended competition image.

The task file uses a small command format, not unrestricted prose. Blank lines and lines beginning with # are ignored. Every other line must match one of these forms:

    FIREWALL ON
    UAC ON
    GUEST_ACCOUNT DISABLE
    LOCAL_ACCOUNT accountname DISABLE
    SERVICE RemoteRegistry DISABLE
    MIN_PASSWORD_LENGTH 12

Supported actions:

- FIREWALL ON enables Windows Firewall for all profiles.
- UAC ON enables User Account Control.
- GUEST_ACCOUNT DISABLE disables the built-in Guest account, identified by its Windows SID.
- LOCAL_ACCOUNT name DISABLE disables a named local account. The name can contain letters, digits, underscore, period, and hyphen.
- SERVICE name DISABLE stops and disables an allow-listed service. The current list is RemoteRegistry, TlntSvr, FTPSVC, SNMP, SSDPSRV, upnphost, and RemoteAccess.
- MIN_PASSWORD_LENGTH number sets the local minimum password length; supported values are 8 through 14.

To use it, put all files in the same folder, edit the task file, then run:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Generate-CyberPatriotTasks.ps1

Review the generated CyberPatriot-ExecuteTasks.ps1. Run it in an elevated Windows PowerShell prompt; it requires you to type APPLY. Unsupported or malformed task lines cause generation to stop without replacing the output script. New task kinds should be added as explicit validated handlers in the generator; task-file contents are never treated as PowerShell code.

