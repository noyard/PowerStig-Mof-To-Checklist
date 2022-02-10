# PowerStig-Mof-To-Checklist
Generates a STiG Checklist with access to the computer and the MOF.

Requirements are 
  - the computer that the MOF file is targeting is online and able to scanned by the computer running the PowerShell script.
  - Directory of the MOF files that are to be processed. 
  
To run the powershell script:
.\PowerStigCreateChecklist.ps1 -MofLocation C:\dsc\configuration\

Upon initial execution of the PowerShell script the folder structure will be created. 
  - Logs will contain a PowerShell transcript of the script output
  - ManualExceptions contains exceptions to flag the STiG as completed and provide a reason.  See below on how to create the exception rules. 
  - Results - contains output of Test-DscConfiguration against the target computer, in XML format. 
  - Stigs - During initial execution the script will create folders of the different STiG groups, then you place the manual check STiG file in the folders that you would like to create the checklist with.
  - Checklist - output folder where the per machine STiG Checkslist are located. 
