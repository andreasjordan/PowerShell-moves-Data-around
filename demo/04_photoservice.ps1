break
# This script needs PowerShell 7.5 or later

# cd ./demo ; function prompt { "PS $(if ($NestedPromptLevel -ge 1) { '>>' })> " } ; cls

$ErrorActionPreference = 'Stop'

# Import functions and initialize database connections
. ./init_photoservice.ps1


# To show that we can also upload binary data to databases - in this case PostgreSQL

$files = Get-ChildItem -Path ../data/photoservice
foreach ($file in $files) {
    $invokeParams = @{
        Connection      = $photoservice.PgConnection
        Query           = 'UPDATE photo SET image = :image WHERE name = :name'
        ParameterValues = @{
            name  = $file.Name
            image = Get-Content -Path $file.FullName -AsByteStream -Raw
        }
    }
    try {
        Invoke-PgQuery @invokeParams -EnableException
    } catch {
        Write-PSFMessage -Level Warning -Message "Failed to import [$($file.Name)]: $_"
        break
    }
}


# MORE DEMO CODE WILL BE PUBLISHED LATER...
