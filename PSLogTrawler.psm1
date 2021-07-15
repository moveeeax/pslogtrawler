#Requires -Version 7.1

# Dot-source all public and private function definitions, then export the
# public surface. Keeping the loader dumb means new functions only need a
# file drop under Public/ or Private/.

$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($file.FullName): $_"
    }
}

Export-ModuleMember -Function $public.BaseName
