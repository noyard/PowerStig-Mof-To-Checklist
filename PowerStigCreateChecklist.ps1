Param(
	[Parameter(Mandatory=$true, HelpMessage="The location of the MOF files to create checklists")]
	[string]$MofLocation
)

#Locations for folder structures
$ScanResults       = ".\Results"
$ChecklistLocation = ".\Checklists"
$ManualExceptions  = ".\ManualExceptions"
$DISAStigs         = ".\Stigs"
$LogLocation       = ".\Logs"

#Prepare Log folder and start logging.
If (!(Test-Path $LogLocation))		{[void](New-Item $LogLocation -itemType Directory)}
get-childitem $loglocation -Recurse | where{-not $_.PsIsContainer}| sort CreationTime -desc | Select -Skip 10 |Remove-Item -Force
Start-Transcript -Path "$($LogLocation)\Log_$(get-date -format yyyyMMdd-HHmmss).log"

#Make sure folder structures exist. 
if (!(Test-Path $ScanResults))		{[void](New-Item $ScanResults -itemType Directory)}
if (!(Test-Path $ChecklistLocation)){[void](New-Item $ChecklistLocation -itemType Directory)}
if (!(Test-Path $ManualExceptions)) {[void](New-Item $ManualExceptions -itemType Directory)}
if (!(Test-Path $DISAStigs))		{[void](New-Item $DISAStigs -itemType Directory)}

# Make sure all XCCDF files are not blocked becuase they were possibly downloaded from the internet. 
dir $DISAStigs -Recurse |Unblock-File

#get the *.mof files to process
if (!(test-path -Path $MofLocation)) {"---MOF file Location does not exist - $($MofLocation)"; Stop-Transcript ;Exit}
$MofFiles = Get-ChildItem -Path $MofLocation -Filter "*.mof"-Exclude "*.meta.mof"-Recurse -ErrorAction SilentlyContinue| %{$_.FullName}
"$($MofFiles.count) MOF File to process"

#Import functions
. .\PowerStigCreateChecklistFunctions.ps1

#Process MOF files
Foreach ($file in $MofFiles)	 
	{
		"`r`nProcessing $($File)"
		##Find Target of MOF
		$TargetNode = (Get-MOFMetadata $file).TargetNode	
		"Testing to see if $($TargetNode) is online"
		if(Test-Connection -ComputerName $($TargetNode) -Quiet -Count 1)
			{
			"Running MOF against $($TargetNode)"
			$DscResult = Test-DscConfiguration -ComputerName $TargetNode -path $MofLocation
			If ($DscResult) 
				{
				"Test Configuration was successful"
				$DscResult | Export-Clixml "$($ScanResults)\$($TargetNode).xml"
				$DscResultRehydrated = Import-Clixml "$($ScanResults)\$($TargetNode).xml"

				##Find Stigs in the MOF
				$Stigs = @()
				$lines = get-content $file |where {$_ -match "ResourceID = "}
				foreach ($line in $lines)
					{
					$r = [regex] "\[([^\[]*)\]"
					$match = $r.match($line.split("::")[2])
					$Stigs += $match.groups[1].value
					}
				$stigs = $stigs  | Where { $_ -match '\S' }| select -uniq

				if($Stigs -contains "WindowsServer")
					{
					try {
						$ServerOS = $((get-wmiobject -class win32_operatingsystem -computer $($TargetNode)).name)
						#$DomainController = get-service -name "kdc" -ComputerName "cmdc01" -ErrorAction 0
						switch -wildcard ($ServerOS) {
							"*Windows Server 2016*" {$Stigs = $Stigs -replace "WindowsServer","WindowsServer2016"}
							"*Windows Server 2019*" {$Stigs = $Stigs -replace "WindowsServer","WindowsServer2019"}
							"*Windows Server 2022*" {$Stigs = $Stigs -replace "WindowsServer","WindowsServer2022"}
							Default {"---Unable to determine OS"}
							}
						}catch {
						"---Error Unable to query Operating System on $($TargetNode)"
						}	
					}

				if($Stigs -contains "IisServer" -or $Stigs -contains "IisSite")
					{
					try {
						$reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $($TargetNode))
						$regkey = $reg.OpenSubkey("SOFTWARE\\Microsoft\\InetStp")
						$IISVersion = $regkey.GetValue("VersionString")
						$IISVersion
						
						switch -wildcard ($IISVersion) {
							"*8.5*" {$Stigs = $Stigs -replace "IisServer","IisServer85";$Stigs = $Stigs -replace "IisSite","IisSite85"}
							"*10*" {$Stigs = $Stigs -replace "IisServer","IisServer10";$Stigs = $Stigs -replace "IisSite","IisSite10"}
							Default {"---Unable to determine IIS Version"}
							}
						}catch {
						"---Error Unable to query registry on $($TargetNode) to determine IIS Version"
						}	
					}

				##Remove known DSC items that do not contain STiG items.
				$Stigs = $Stigs | Where-Object { $_ -ne "SharePointServerEnforceTLS12" }

				##Find the DISA STiG Files for each Stig
				$XCCDFPath = @()
				$ManualCheckFile = @()
				[void](New-Item -Path '$($ScanResults )\' -Name "$($TargetNode).txt" -ItemType File -Force)
				foreach ($Stig in $Stigs)
					{
						"MOF has $($Stig) Stig"
						if (!(Test-Path "$($DISAStigs)\$($Stig)")){[void](New-Item "$($DISAStigs)\$($Stig)" -itemType Directory)}
						Get-ChildItem "$($DISAStigs)\$($Stig)" -Filter *xccdf.xml |
						Foreach-Object { 
							"Adding $($_.FullName) to Stig list"
							Add-Content -Path "$($ScanResults )\$($TargetNode).txt" -Value "$($_.FullName)" 
						}
						if(Test-path "$($DISAStigs)\$($Stig)\ManualExceptions.xml")
							{
								Add-Content -Path "$($ScanResults )\$($TargetNode)_Manual.txt" -Value "$($DISAStigs)\$($Stig)\ManualExceptions.xml"
							}
					}
				if (Test-Path "$($ManualExceptions)\$($TargetNode).xml")
					{
						Add-Content -Path "$($ScanResults )\$($TargetNode)_Manual.txt" -Value "$($ManualExceptions)\$($TargetNode).xml"
					}
					
				$XccdfPath = Get-Content "$($ScanResults )\$($TargetNode).txt"
				$ManualCheckFile =  Get-Content "$($ScanResults )\$($TargetNode)_Manual.txt"

				"Generating Checklist"
				if( $ManualCheckFile.Count -ge 1)
					{
					New-StigCheckList -DscResult $DscResultRehydrated -XccdfPath $XCCDFPath -ManualChecklistEntriesFile $ManualCheckFile -OutputPath "$($ChecklistLocation)\$($TargetNode).ckl"
					}
				else {
					New-StigCheckList -DscResult $DscResultRehydrated -XccdfPath $XCCDFPath -OutputPath "$($ChecklistLocation)\$($TargetNode).ckl"
					}
			}
			Else {
				"Unable to test configuration"
			}
		}
		Else {
			"---$($TargetNode) is offline"	
		}
		"Processing $($File) Completed"
    } 
"`r`nScript Completed"
Stop-Transcript