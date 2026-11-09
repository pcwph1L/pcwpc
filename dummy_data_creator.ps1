# Parameters
$baseFolder = (Get-Location).Path # Use the current directory as the base directory
$fileCount = 5000                # Number of files for each extension

# Array of file extensions
$fileExtensions = @(".doc", ".docx", ".pdf", ".ppt", ".pptx", ".txt", ".xls")

# Generate dummy files
foreach ($extension in $fileExtensions) {
    # Create a subfolder for each file type
    $subfolderName = $extension.TrimStart('.').ToUpper() # Use extension as folder name
    $subfolderPath = Join-Path -Path $baseFolder -ChildPath $subfolderName

    if (-Not (Test-Path -Path $subfolderPath)) {
        New-Item -ItemType Directory -Path $subfolderPath | Out-Null
    }

    # Generate files within the subfolder
    for ($i = 1; $i -le $fileCount; $i++) {
        $fileName = "DummyFile_$i$extension"
        $filePath = Join-Path -Path $subfolderPath -ChildPath $fileName

        # Create a random file size between 100KB and 3MB
        $randomSize = Get-Random -Minimum 102400 -Maximum 3145728 # Size in bytes
        $dummyContent = "A" * $randomSize # Generate dummy content of the required size

        try {
            # Write the content to the file
            Set-Content -Path $filePath -Value $dummyContent -Encoding UTF8
        } catch {
            Write-Host "Error creating file ${filePath}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "Dummy files created successfully in $baseFolder"
