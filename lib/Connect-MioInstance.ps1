function Connect-MioInstance {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [Parameter(Mandatory)][string]$Bucket,
        [switch]$EnableException
    )

    Write-PSFMessage -Level Verbose -Message "Creating connection to [$Instance]"

    if ($Instance -notmatch '^([^:]+):(\d+)$') {
        $Instance += ':9000'
    }

    $connectionObject = [PSCustomObject]@{
        PSTypeName = $MyInvocation.MyCommand.Noun
        Instance   = $Instance
        BaseUrl    = "http://$Instance"
        Credential = $Credential
        Bucket     = $Bucket
    }

    Add-Member -InputObject $connectionObject -MemberType ScriptMethod -Name GetAuthorization -Value {
        param(
            [string]$Method,
            [string]$Date,
            [string]$ContentType,
            [string]$Key
        )

        $accessKey = $this.Credential.UserName
        $secretKey = $this.Credential.GetNetworkCredential().Password
        $bucket = $this.Bucket

        $bytesSecret = [Text.Encoding]::ASCII.GetBytes($secretKey)
        $bytesToHash = [Text.Encoding]::ASCII.GetBytes("$Method`n`n$ContentType`n$Date`n/$bucket/$Key")
        $bytesHashed = [System.Security.Cryptography.HMACSHA1]::new($bytesSecret).ComputeHash($bytesToHash)
        $stringHashed = [Convert]::ToBase64String($bytesHashed)
        
        "AWS " + $accessKey + ":" + $stringHashed
    }

    Add-Member -InputObject $connectionObject -MemberType ScriptMethod -Name GetFileListParams -Value {
        $method      = 'GET'
        $date        = [datetime]::Now.ToUniversalTime().ToString('R')
    
        $invokeParams = @{
            Uri     = "$($this.BaseUrl)/$($this.Bucket)/"
            Method  = $method
            Headers = @{
                'Host'          = $this.Instance
                'Date'          = $date
                'Authorization' = $this.GetAuthorization($method, $date)
            }
        }
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $invokeParams.SkipCertificateCheck = $true
        }

        $invokeParams
    }

    Add-Member -InputObject $connectionObject -MemberType ScriptMethod -Name GetFileParams -Value {
        param(
            [string]$ContentType,
            [string]$Key,
            [string]$OutFile
        )

        $method      = 'GET'
        $date        = [datetime]::Now.ToUniversalTime().ToString('R')
    
        $invokeParams = @{
            Uri     = "$($this.BaseUrl)/$($this.Bucket)/$Key"
            Method  = $method
            Headers = @{
                'Host'          = $this.Instance
                'Date'          = $date
                'Authorization' = $this.GetAuthorization($method, $date, $ContentType, $Key)
            }
            OutFile = $OutFile
        }
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $invokeParams.SkipCertificateCheck = $true
            $invokeParams.ContentType = $ContentType
        } else {
            $invokeParams.Headers.'Content-Type' = $ContentType
        }
    
        $invokeParams
    }

    Add-Member -InputObject $connectionObject -MemberType ScriptMethod -Name SetFileParams -Value {
        param(
            [string]$ContentType,
            [string]$Key,
            [string]$InFile
        )

        $method      = 'PUT'
        $date        = [datetime]::Now.ToUniversalTime().ToString('R')
    
        $invokeParams = @{
            Uri     = "$($this.BaseUrl)/$($this.Bucket)/$Key"
            Method  = $method
            Headers = @{
                'Host'          = $this.Instance
                'Date'          = $date
                'Authorization' = $this.GetAuthorization($method, $date, $ContentType, $Key)
            }
            InFile = $InFile
        }
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $invokeParams.SkipCertificateCheck = $true
            $invokeParams.ContentType = $ContentType
        } else {
            $invokeParams.Headers.'Content-Type' = $ContentType
        }
    
        $invokeParams
    }

    Add-Member -InputObject $connectionObject -MemberType ScriptMethod -Name RemoveFileParams -Value {
        param(
            [string]$Key
        )

        $method      = 'DELETE'
        $date        = [datetime]::Now.ToUniversalTime().ToString('R')
    
        $invokeParams = @{
            Uri     = "$($this.BaseUrl)/$($this.Bucket)/$Key"
            Method  = $method
            Headers = @{
                'Host'          = $this.Instance
                'Date'          = $date
                'Authorization' = $this.GetAuthorization($method, $date, '', $Key)
            }
        }
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            $invokeParams.SkipCertificateCheck = $true
        }
    
        $invokeParams
    }

    Update-TypeData -TypeName $MyInvocation.MyCommand.Noun -DefaultDisplayPropertySet Instance, Bucket -Force

    try {
        Write-PSFMessage -Level Verbose -Message "Opening connection"
        $null = Get-MioFileList -Connection $connectionObject

        Write-PSFMessage -Level Verbose -Message "Returning connection object"
        $connectionObject
    } catch {
        Stop-PSFFunction -Message "Connection failed: $($_.Exception.InnerException.Message)" -EnableException $EnableException
    }
}
