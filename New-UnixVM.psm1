function New-UnixVM {
    param (
        [Parameter(Position = 0, Mandatory)]
        [string]
        $VMNamePrefix,

        # Parameter help description
        [Parameter()]
        [Int64]
        $CPUCount,

        # Parameter help description
        [Parameter()]
        [switch]
        $EnableNestedVirtualization,

        # Parameter help description
        [Parameter()]
        [Int64]
        $StartupMemory = 512MB,

        # Parameter help description
        [Parameter(parametersetname = "Dynamic Memory")]
        [switch]
        $DynamicMemory,

        # Parameter help description
        [Parameter(parametersetname = "Dynamic Memory")]
        [Int64]
        $MaxMemory = 4GB,
        
        # Parameter help description
        [Parameter(parametersetname = "Dynamic Memory")]
        [Int64]
        $MinMemory = $StartupMemory,

        # Parameter help description
        [Parameter()]
        [String]
        $SwitchName,

        # Parameter help description
        [Parameter()]
        [ValidateRange(1, 4096)]
        [Int]
        $VLAN,
        
        # Parameter help description
        [Parameter()]
        [Int64]
        $VHDSize,

        # Parameter help description
        [Parameter()]
        [Int64]
        $StorageVHDSize,

        # Parameter help description
        [Parameter()]
        [string]
        $TemplateVM = "Template-CentOS8",
        
        # Parameter help description
        [Parameter()]
        [string]
        $VMDestinationBasePath = "C:\Virtual Machines",

        # Parameter help description
        [Parameter()]
        [Int64]
        $NumberOfVMs = 1
    )

    process {
        $TemplateVHD = Get-VM $TemplateVM | Get-VMHardDiskDrive | Select-Object -ExpandProperty Path
        $results = @()


        for ($i = 1; $i -le $NumberOfVMs; $i++) {
            #Get the name for next VM to create
            $VMName = Get-NextVMNumber $VMNamePrefix
            $VMDestinationPath = Join-Path -Path $VMDestinationBasePath -ChildPath $VMName

            ## Start Region: Setup the VHD for new VM
            Write-Host "Setting up VHD for $VMName ..." 
            $VMVHDPath = "$VMDestinationPath\Virtual Hard Disks\$VMName.vhdx"
            # Check to make sure the VHD does not exist already
            if (!(Test-Path -Path $VMVHDPath)) {
                #Check if VM VHD folder exits and if not create it
                if (!(Test-Path -Path "$VMDestinationPath\Virtual Hard Disks")) {
                    New-Item -Path "$VMDestinationPath\Virtual Hard Disks" -ItemType Directory -Force | Out-Null
                }
                Write-Host "Creating new VHD from parent $TemplateVHD"
                Copy-Item -Path $TemplateVHD -Destination "$VMDestinationPath\Virtual Hard Disks"
                $TemplateVHDName = Split-Path $TemplateVHD -Leaf
                Rename-Item -Path "$VMDestinationPath\Virtual Hard Disks\$TemplateVHDName" -NewName $VMVHDPath
                if (($null -ne $VHDSize) -and ($VHDSize -ne 0)) {
                    if ((Get-VHD -Path $TemplateVHD).Size -le $VHDSize) {
                        Resize-VHD -Path $VMVHDPath -SizeBytes $VHDSize
                        Write-Host "$VMVHDPath resized to $VHDSize" -ForegroundColor Green
                    }
                    else {
                        Write-Host "VHD $VMVHDPath was not resized because provided size was less than template VHD size" -ForegroundColor Red
                    }
                }
                Write-Host "Done." -ForegroundColor Green
                
            }
            else {
                Write-Host "VHD at $VMVHDPath already exits!" -ForegroundColor Red
                break
            }

            ## End Region

            ## Start Region: Setup VM
            Write-Host "Setting up VM $VMName"

            $VMProperties = @{
                Name               = $VMName
                MemoryStartupBytes = $StartupMemory
                Generation         = 2
                BootDevice         = "VHD"
                VHDPath            = $VMVHDPath                
                Path               = $VMDestinationBasePath
                SwitchName         = $SwitchName
            }

            $results += New-VM @VMProperties
            Write-Host "Done." -ForegroundColor Green
            ## End Region

            ## Start Region: Setup Cloud-Init
            Write-Host "Creating cloud-init config for $VMName ..."
            New-CloudInitiConfig -VMName $VMName -DestinationPath $VMDestinationPath
            Write-Host "Done." -ForegroundColor Green
            ## End Region

            ## Start Region: Configure VM
            Write-Host "Configuring VM $VMName..."
            # Enable Dynamic Memory if switch is set
            if ($DynamicMemory) {
                Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes $MinMemory -MaximumBytes $MaxMemory 
            }
            # Setup processor core count
            Set-VM -VMName $VMName -ProcessorCount $CPUCount
            # Disable Secure boot and setup VHD as boot device
            Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -FirstBootDevice (Get-VMHardDiskDrive -VMName $VMName)
            # Enabled Nested Virtualization if enabled
            if ($EnableNestedVirtualization) {
                Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
            }
            # Set VLAN on NIC if a VLAN is provided
            if ($null -ne $VLAN) {
                Set-VMNetworkAdapterVlan -VMName $VMName -VlanId $VLAN -Access
            }
            # Add cloud-init .iso as DVD
            Add-VMDvdDrive -VMName $VMName
            Set-VMDvdDrive -VMName $VMName -Path "$($VMDestinationPath)\cloud-init\metadata.iso"

            Write-Host "Done" -ForegroundColor Green
            ## End Region

            ## Start Region: Add second VHD
            # Check if -StorageVHDSize parameter was set, this will only proceed if that was non zero and not a null
            if (($null -ne $StorageVHDSize) -and ($StorageVHDSize -ne 0)) {
                Write-Host "Setting up Storage VHD for $VMName ..." 
                $StorageVHDPath = "$VMDestinationPath\Virtual Hard Disks\$VMName-Storage.vhdx"
                # Check and make sure Storage VHD does not exist already
                if (!(Test-Path -Path $StorageVHDPath)) {
                    New-VHD -Path $StorageVHDPath -SizeBytes $StorageVHDSize
                    Add-VMHardDiskDrive -VMName $VMName -Path $StorageVHDPath
                }
                else {
                    Write-Host "VHD at $StorageVHDPath already exits! Please review and add storage VHD manually." -ForegroundColor Red
                }
            }
            ## End Region

            ## Start Region: Power on VM
            Start-VM -VMName $VMName
            ## End Region
        }
        Write-Host "Created following $($results.Count) VMs: "
        $results
    }

    <# 
    .SYNOPSIS
    Function to create new Unix VM from a template and provision it using cloud-init

    .DESCRIPTION
    Create new Unix VM from an existing template that has cloud-init installed. This function will copy the VHD of `
    template we chose and attach it to new VM it creates. You can add additional storage VHD as well.
    
    .EXAMPLE
    PS> New-UnixVM -VMNamePrefix Lab-Test -CPUCount 2 -StartupMemory 512MB -SwitchName LAB -StorageVHDSize 10GB

    Created following 1 VMs:
    Name             : Lab-Test01
    State            : Running
    CpuUsage         : 0
    MemoryAssigned   : 536870912
    MemoryDemand     : 0
    MemoryStatus     :
    Uptime           : 00:00:00.1100000
    Status           : Operating normally
    ReplicationState : Disabled
    Generation       : 2

    .EXAMPLE
    PS> New-UnixVM -VMNamePrefix Lab-Test -CPUCount 2 -StartupMemory 512MB -SwitchName LAB -NumberOfVMs 5 -VMDestinationBasePath = "C:\VM"

    This will create 5 VM from Lab-Test01 to Lab-Test05 (If Lab-Test01 exits it'll used next number i.e 02) and place all the related files in respective folder `
    for each VM inside C:\VM  
    #>

}

function Get-NextVMNumber {
    param($prefix)
    # Check if existing VM exist with same name if so it'll return suffix+1 ,e.g if test01 is a VM this will return test02
    if ((Get-VM -name "$prefix*").count -gt 0) {
        $prefix += (([int](get-vm -name "$prefix*" | Select-Object @{ Label = 'Number' ; Expression = { $_.VMName.Substring($prefix.length, 2) } } | Sort-Object number | Select-Object -Last 1).number) + 1).tostring().padleft(2, "0")
    }
    else {
        $prefix += "01"
    }
    return $prefix
}

function New-CloudInitiConfig {
    param(
        $VMName,
        $DestinationPath
    )

    $metadata = @"
instance-id: uuid-$([GUID]::NewGuid())
local-hostname: $($VMName)
"@

    $userdata = @"
#cloud-config
users:
  - name: automate
    gecos: Ansible Provisioning Account
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    ssh_import_id: None
    lock_passwd: true
    ssh_pwauth: false
    no_create_home: false
    ssh_authorized_keys:
      - <ssh-rsa AAAA This is example SSH key> 
"@
    <# 
Cloud Init Comments
# We need the home created otherwise /home/ansible's permissions are borked (no_create_home: false)
#>
    $oscdimgPath = "C:\Program Files (x86)\Windows Kits\8.1\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    $metaDataIso = "$($DestinationPath)\cloud-init\metadata.iso"
    $ciPath = "$($DestinationPath)\cloud-init"
    # Output meta and user data to files
    Write-Verbose "Testing cloud-init path at $DestinationPath"
    if (!(Test-Path $ciPath)) { New-Item -ItemType Directory $ciPath -Force | out-null }
    sc "$ciPath\meta-data" ([byte[]][char[]] "$metadata") -Encoding Byte
    sc "$cipath\user-data" ([byte[]][char[]] "$userdata") -Encoding Byte
    Start-Process -FilePath $oscdimgPath -ArgumentList "`"$ciPath`" `"$metaDataIso`" -j2 -lcidata"
}
