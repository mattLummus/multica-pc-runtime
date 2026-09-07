Option Explicit

Dim shell, scriptDirectory, supervisorPath, command, exitCode
Set shell = CreateObject("WScript.Shell")

scriptDirectory = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\") - 1)
supervisorPath = scriptDirectory & "\Manage-MulticaPcRuntime.ps1"
command = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & supervisorPath & """ -Action RunForeground"

exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
