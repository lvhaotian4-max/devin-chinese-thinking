# 兼容别名：doctor.ps1 已更名为 status.ps1（功能相同并扩展了 hooks/Devin 探测）。
# 保留此文件是为了兼容旧文档与习惯用法。
& (Join-Path $PSScriptRoot 'status.ps1') @args
