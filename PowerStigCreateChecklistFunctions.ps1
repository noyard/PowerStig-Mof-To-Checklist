Function Get-MOFMetadata {
	[cmdletbinding()]
	Param(
		[Parameter(Position=0,
		Mandatory,
		HelpMessage="Enter the path to a MOF file",
		ValueFromPipeline,
		ValueFromPipelineByPropertyName)]
		[ValidateNotNullorEmpty()]
		[ValidateScript({Test-Path $_})]
		[Alias("PSPath")]
		[string]$Path
	)
	Begin {
		Write-Verbose "Starting $($MyInvocation.Mycommand)"
	} #begin
	Process {
		Write-Verbose "Processing $path"
		#read the MOF file into a variable
		$content = Get-Content -Path $Path -ReadCount 0
		#create an ordered hashtable
		$hashProperties = [ordered]@{}
		#get first 4 lines
		Write-Verbose "Getting comment header"
		$meta = $content | Select -Skip 1 -first 4
		foreach ($item in $meta) {
			#split each line
			$split = $item.split("=")
			$Name = $split[0].Replace("@","")
			$value = $split[1].Replace("'","")
			#test if a value is a datetime
			[ref]$r = Get-Date
			if ([datetime]::TryParse($value,$r)) {
				#replace value with $r which will now be the
				#value from the MOF treated as a datetime object
				$value = $r.value
			}
			#add each element to the hashtable removing extra characters
			$hashProperties.Add($name,$value)
		}
		#get version information
		#getting more context than necessary in case you want to include
		#other information
		$OMIDoc = $Content| Select-String "OMI_ConfigurationDocument" -Context 6 |
		Select -ExpandProperty Context
		#get version string
		if (($OMIDoc.PostContext | Select-String version).ToString().trim() -match "\d+\.\d+\.\d") {
			$Version = $($matches.Values[0])
		}
		else {
			$version = "Unknown"
		}
		$hashProperties.add("Version",$Version)
		#add file information
		Write-Verbose "Getting file information"
		$file = Get-Item -Path $Path
		$hashProperties.Add("LastModified",$file.LastWriteTime)
		$hashProperties.Add("Name",$file.name)
		$hashProperties.Add("Size",$file.Length)
		$hashProperties.Add("Path",$file.FullName)
		Write-Verbose "Creating output object"
		New-Object -TypeName PSObject -Property $hashProperties
	} #end process
	End {
		Write-Verbose "Ending $($MyInvocation.Mycommand)"
	} #end
} #end Get-MOFMetadata