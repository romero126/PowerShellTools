function Get-CoreAdminDatabasePath
{
    [CmdletBinding()]
    param( )

    $path = $MyInvocation.MyCommand.Module.PrivateData.DatabasePath
    if ($env:POWERSHELL_MODULE_COREADMIN_PATH) {
        $path = $env:POWERSHELL_MODULE_COREADMIN_PATH
    }
    else {
        Microsoft.PowerShell.Utility\Write-Warning -Message "The Environment Variable POWERSHELL_MODULE_COREADMIN_PATH is not set. Using default value of '$path'"
        $env:POWERSHELL_MODULE_COREADMIN_PATH = $path
    }

    $pathIsValid = Microsoft.PowerShell.Management\Test-Path -Path $path -PathType Container

    if (-not $pathIsValid) {
        Microsoft.PowerShell.Utility\Write-Error -Message "The path is not found, or is not valid." -Category ObjectNotFound -TargetObject $path -ErrorAction Stop
    }

    return Microsoft.PowerShell.Management\Get-Item -Path $path 
}

function Get-CoreAdminDatabaseTable {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.String] $Table = ""
    )

    $path = Get-CoreAdminDatabasePath
    $items = Get-ChildItem -Path $Path\*.Table.xml

    foreach ($item in $items) {
        if ($item.BaseName -notmatch "^$Table") { continue }
        try {
            [xml]$itemDocument = Get-Content $item.FullName -raw
            [PSCustomObject][Ordered]@{
                Name        = $item.BaseName -replace '.Table$'
                Description = $itemDocument.Table.TableInfo.Description
                RowCount    = $itemDocument.Table.Rows.Row.Count
                Schema      = $itemDocument.Table.Schema
                Rows        = $itemDocument.Table.Rows
                Path        = $item.FullName
            }
        }
        catch {
            Microsoft.PowerShell.Utility\Write-Error -Message "The table $($item.BaseName -replace '.Table$') is not valid." -Category ParserError -TargetObject ($item.BaseName -replace '.Table$') -ErrorAction Continue
        }
    }
}

function Add-CoreAdminDatabaseTable {
    throw "Not Implemented Exception"
}

function Remove-CoreAdminDatabaseTable {
    throw "Not Implemented Exception"
}

function Get-CoreAdminDatabaseTableSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.String] $Table,

        [Parameter()]
        [System.String] $Name = ""
    )

    begin {
        $database = Get-CoreAdminDatabaseTable -Table $Table
        $xml = $database.Schema.OwnerDocument
    }

    process {
        # Check schema against duplicate names
        $database.Schema.Item | Where-Object { $_.Name -match $Name }
    }

    end {

    }
}

function Set-CoreAdminDatabaseTableSchema {
    # Set needs to retrigger validation
    # You cant make an item a Key, or Unique without it first being unique information

    throw "Not Implemented Exception"
}

function Add-CoreAdminDatabaseTableSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.String] $Table,

        [Parameter(Mandatory)]
        [System.String] $Name,

        [Parameter(Mandatory)]
        [ValidateScript({
            $list = @([System.String], [System.Guid], [System.Int32], [System.Boolean], [System.Byte[]])
            #$list = $MyInvocation.MyCommand.Module.PrivateData.Schema_Type
            $_ -in $list
        })]
        [System.Type] $Type,

        [Parameter()]
        [System.Management.Automation.SwitchParameter] $IsKey,

        [Parameter()]
        [System.Management.Automation.SwitchParameter] $IsUnique,

        [Parameter()]
        [switch] $WhatIf

    )

    begin {
        $database = Get-CoreAdminDatabaseTable -Table $Table
        $xml = $database.Schema.OwnerDocument
    }

    process {

        # Check schema against duplicate names
        $containsName = $database.Schema.Item | Where-Object { $_.Name -eq $Name }    
        if ($containsName) {            
            Microsoft.PowerShell.Utility\Write-Error -Message "The schema name already exists" -Category InvalidData -TargetObject $Name -ErrorAction Stop
        }

        if ($IsKey) {
            $containsIsKey = $database.Schema.Item | Where-Object { $_.IsKey -eq $true }
            if ($containsIsKey) {
                Microsoft.PowerShell.Utility\Write-Error -Message "The schema already contains a key" -Category InvalidData -TargetObject $path -ErrorAction Stop
            }
            #$IsUnique = $true
            $PSBoundParameters.Add("IsUnique", $true)
        }

        $node = $xml.CreateElement("Item")

        # Set each attribute defined
        foreach ($i in @("Name", "Type", "IsKey", "IsUnique")) {
            if ($PSBoundParameters.ContainsKey($i)) {
                $xmlAttribute = $xml.CreateAttribute($i)
                $xmlAttribute.Value = $PSBoundParameters.Item($i)
                if ($i -eq "Type") {
                    $xmlAttribute.Value = $PSBoundParameters.Item($i).FullName
                }
                $null = $node.SetAttributeNode($xmlAttribute)
            }
        }
    
        $null = $database.Schema.AppendChild($node)
        Write-Verbose -Message ("Appending item to Schema: {0}" -f $node.OuterXml)
    }

    end {
        if (-not $WhatIf) {
            $xml.Save($database.Path)
        }
        
    }

}

function Remove-CoreAdminDatabaseTableSchema {
    throw "Not Implemented Exception"
}

function Get-CoreAdminDatabaseTableRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Table, 

        [Parameter()]
        [switch] $WhatIf
    )

    dynamicparam {
        # Create dynamic parameters based on the Table's Selected Schema
        $database = Get-CoreAdminDatabaseTable -Table $Table
        $parameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        foreach ($item in $database.Schema.Item) {            
            $itemParam = [System.Management.Automation.RuntimeDefinedParameter]::new(
                $item.Name,
                [System.Reflection.TypeInfo]::GetType($item.Type),
                [System.Management.Automation.ParameterAttribute]@{

                }
            )
            $parameterDictionary.Add($item.Name, $itemParam)
        }
        return $parameterDictionary
    }

    begin {
        $database = Get-CoreAdminDatabaseTable -Table $Table
        $xml = $database.Schema.OwnerDocument
    }

    process {
        if ((-not $database.Rows) -or ($database.Rows.Row.Count -eq 0)) {
            # Return null if there are no tables
            continue;
        }

        foreach ($row in $database.Rows.Row) {
            $isMatch = $false

            foreach ($schemaItem in $database.Schema.Item) {
                # Skip if the item doesnt have a query
                if (-not $PSBoundParameters.ContainsKey($schemaItem.Name)) {
                    continue
                }

                # Skip if the attribute we are querying is null or empty
                if (-not $row.HasAttribute($schemaItem.Name)) {
                    continue
                }

                switch ($schemaItem.Type) {
                    'System.String' {
                        # Strings should always use regex
                        $rowAttributeValue = $row.GetAttribute($schemaItem.Name)
                        $parameterQuery = '^{0}$' -f $PSBoundParameters[$schemaItem.Name]
                        if ($rowAttributeValue -match $parameterQuery) {
                            $isMatch = $true
                            break
                        }
                    }
                    default {
                        # This should always deserialize to an item.
                        $rowAttributeValue = ($row.GetAttribute($schemaItem.Name) -as $schemaItem.Type)
                        $parameterQuery = $PSBoundParameters[$schemaItem.Name]

                        if ($rowAttributeValue -eq $parameterQuery) {
                            $isMatch = $true
                            break
                        }
                    }
                }
            }

            if ($isMatch -eq $false) {
                continue
            }

            # Convert row into PSCustomObject
            $result = [System.Collections.Specialized.OrderedDictionary][System.Collections.Hashtable]::new()

            # Attach metadata
            $result.Add('CoreAdmin_Database_Table', $Table)
            $result.Add('CoreAdmin_Database_TableRow', $row)

            # Attach data to result
            foreach ($schemaItem in $database.Schema.Item) {
                $value = $row.GetAttribute($schemaItem.Name) -as $schemaItem.Type
                $result.Add($schemaItem.Name, $value)
            }

            [PSCustomObject]$result
        }
    }

    end {

    }

}

function Set-CoreAdminDatabaseTableRow {
    throw "Not Implemented Exception"
}

function Add-CoreAdminDatabaseTableRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Table, 

        [Parameter()]
        [switch] $WhatIf
    )

    dynamicparam {
        # Create dynamic parameters based on the Table's Selected Schema
        $database = Get-CoreAdminDatabaseTable -Table $Table
        $parameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        foreach ($item in $database.Schema.Item) {            
            $itemParam = [System.Management.Automation.RuntimeDefinedParameter]::new(
                $item.Name,
                [System.Reflection.TypeInfo]::GetType($item.Type),
                [System.Management.Automation.ParameterAttribute]@{
                    Mandatory = $item.IsKey -eq $true
                }
            )
            $parameterDictionary.Add($item.Name, $itemParam)
        }
        return $parameterDictionary
    }

    begin {
        $database = Get-CoreAdminDatabaseTable -Table $Table
        $xml = $database.Schema.OwnerDocument
    }

    process {
        # Check -IsUnique flag on schema, and check if value of parameter is also unique. Fail if its not unique
        if ($database.Rows -or ($database.Rows.Row.Count -gt 0)) {
            foreach ($schemaItem in $database.Schema.Item) {
                foreach ($row in $database.Rows.Row) {
                    if ($row.HasAttribute($schemaItem.Name)) {
                        if ($row.GetAttribute($schemaItem.Name) -eq $PSBoundParameters[$schemaItem.Name]) {
                            Microsoft.PowerShell.Utility\Write-Error -Message "The parameter '$($schemaItem.Name)' requires a unique value." -Category InvalidData -TargetObject $Name -ErrorAction Stop
                        }
                    }
                }
            }
        }

        $node = $xml.CreateElement("Row")

        # Set each attribute defined
        foreach ($i in $database.Schema.Item.Name) {
            if ($PSBoundParameters.ContainsKey($i)) {
                $xmlAttribute = $xml.CreateAttribute($i)
                $xmlAttribute.Value = $PSBoundParameters.Item($i)
                if ($i -eq "Type") {
                    $xmlAttribute.Value = $PSBoundParameters.Item($i).FullName
                }
                $null = $node.SetAttributeNode($xmlAttribute)
            }
            $null = $database.Rows.AppendChild($node)
            Write-Verbose -Message ("Appending item to Schema: {0}" -f $node.OuterXml)
        }
    }

    end {
        if (-not $WhatIf) {
            $xml.Save($database.Path)
        }
    }
}
function Remove-CoreAdminDatabaseTableRow {
    throw "Not Implemented Exception"
}