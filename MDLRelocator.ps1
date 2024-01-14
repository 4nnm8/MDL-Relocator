Set-StrictMode -Version Latest
Set-ExecutionPolicy RemoteSigned

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function ErrorMsg($errorMessage) {
    [System.Windows.Forms.MessageBox]::Show($errorMessage, "Error", 
    [System.Windows.Forms.MessageBoxButtons]::OK, 
    [System.Windows.Forms.MessageBoxIcon]::Error)
}
function UpdateStatusFilesChecked() {
    $countChk = $listView.CheckedItems.Count
    $countFnd = $listView.Items.Count
    $pl = ""
    if ($countChk -gt 1) { $pl = "s" }
    $statusCol1.Text = "$countChk file$pl selected"
    if ($countChk -eq 0) {
        $selectNoneButton.Enabled = $relocateButton.Enabled = $false
    } else {
        $selectNoneButton.Enabled = $relocateButton.Enabled = $true
    }
    if ($countChk -eq $countFnd) {
        $selectAllButton.Enabled = $false
    } else {
        $selectAllButton.Enabled = $true
    }
}
function UpdateStatusFilesFound() {
    $countFnd = $listView.Items.Count
    $pl = ""
    if ($countFnd -gt 1) { $pl = "s" }
   	$statusCol0.Text = "$countFnd file$pl found"
    if ($countFnd -gt 0) {
        $searchBox.ReadOnly = $false
    } else {
        $searchBox.ReadOnly = $true
    }
    $listView.AutoResizeColumns([System.Windows.Forms.ColumnHeaderAutoResizeStyle]::HeaderSize)
    UpdateStatusFilesChecked
}
function checkList($bool) {
    $listView.SuspendLayout()
    $listView.BeginUpdate()
	foreach ($item in $listView.Items) {
        $item.Checked = $bool
    }
    UpdateStatusFilesChecked
	$listView.EndUpdate()
    $listView.ResumeLayout()
}
function WriteConsole($text, $color) {
    $colorMap = @{
        "G" = 0xFF98FB98
        "R" = 0xFFf63a3a
        "Y" = 0xFFefe02d
    }
    if ($color) {
        $fakeConsole.SelectionColor =  [System.Drawing.Color]::FromArgb($colorMap[$color]) 
    }
	$fakeConsole.AppendText($text+"`r`n")
	$fakeConsole.SelectionColor = $fakeConsole.ForeColor
    $fakeConsole.SelectionStart = $fakeConsole.Text.Length
    $fakeConsole.ScrollToCaret()
}
$global:providedPath = $null
$global:rootModels = $null
$scriptDirectory = $null

if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript"){ # Powershell script
	$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else { # PS2EXE compiled script
	$scriptDirectory = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$scriptDirectory) { $scriptDirectory = "." } 
}
$crowbarExePath = Join-Path -Path $scriptDirectory -ChildPath "CrowbarDecompiler.exe"

function Find-StudioMDL {
    $studiomdlPath = Get-Item (Join-Path (Get-Item $global:rootModels).Parent.Parent.FullName "bin\studiomdl.exe")

    if ($null -ne $studiomdlPath -and $studiomdlPath.Exists) {
        $studioMDLPathTextbox.Text = $studiomdlPath
		Find-MDLFiles
    } else {
        ErrorMsg("studiomdl.exe is neccessary and was not found at the expected location.`nPlease provide the location of the executable.")
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.InitialDirectory = "C:\Program Files (x86)\Steam\steamapps\common\"
        $fileDialog.Filter = 'StudioMDL Executable (studiomdl.exe)|studiomdl.exe'
        $fileDialog.Title = 'Select studiomdl.exe'
        if ($fileDialog.ShowDialog() -eq 'OK') {
            $studioMDLPathTextbox.Text = $fileDialog.FileName
	    Find-MDLFiles
        } else {
            ErrorMsg("Unable to continue without StudioMDL.exe")
            return $false
            $form.Close()
        }
    }
}
function Find-ModelFolder($folder) {
    if ($folder -match '^(.*?(?<!materials)\\models).+(?:\\|$)') {
        $global:providedPath = $folder
        $global:rootModels = $Matches[1]
    } else {
        ErrorMsg("The selected folder is neither 'models' nor one of its subfolders.`nA common mistake is to confuse the /materials/models folder with the /models folder.")
        return $false
    }
    $providedPathTextbox.Text = $global:providedPath
    $rootModelsTextbox.Text = $global:rootModels
    Find-StudioMDL
}
function DragDropMDL($files) {
    $pattern = '^(.*?(?<!materials)\\models).+\.mdl'
    foreach ($file in $files) {
        if ($file -match $pattern) {
            $item = New-Object Windows.Forms.ListViewItem
			$filename = [System.IO.Path]::GetFileName($file)
            $item.Text = $filename
			$searchBox.AutoCompleteCustomSource.AddRange($filename)
            $relativePath = $file -replace '^(.*?\\models(?:\\|$))', ''
            $item.SubItems.Add($relativePath)
            $item.Checked = $true
            $listView.Items.Add($item)
        } else {
            WriteConsole "[ERROR] The model file must be in the '/models' folder or one of its subfolder." "R"
        }
    }
    UpdateStatusFilesFound
    $pickedUpFile = $files[0]
    if ($pickedUpFile -match $pattern -and [string]::IsNullOrEmpty($global:rootModels)) {
        $global:rootModels = $Matches[1]
        $rootModelsTextbox.Text = $global:rootModels
    }
    $listView.Add_ItemChecked({ UpdateStatusFilesChecked }) 
    Find-StudioMDL
	
	# TO DO: HANDLE THE CASE WHERE MODELS COME FROM DIFFERENT GAMES FOLDER
}
function Find-MDLFiles () {
    $statusCol0.Text = "Searching for your files..."
    $listView.Remove_ItemChecked({ UpdateStatusFilesChecked }) 
    $form.SuspendLayout()
    $mdlFiles = Get-ChildItem -Path $global:providedPath -Recurse -File -Filter *.mdl
    # TO DO: USE VIRTUAL MODE
    $listView.BeginUpdate()
    foreach ($mdlFile in $mdlFiles) {
        $item = New-Object Windows.Forms.ListViewItem
        $item.Text = $mdlFile.Name
		$item.Tag = ""
		$searchBox.AutoCompleteCustomSource.AddRange($mdlFile.Name)
        $relativePath = $mdlFile.FullName.Substring($global:rootModels.Length)
        $item.SubItems.Add("$relativePath")
        $item.Checked = $true
        $listView.Items.Add($item) | Out-Null
    }
    $listView.EndUpdate()
    $form.ResumeLayout()

    if ($listView.Items.Count -eq 0) {
		WriteConsole "Sorry, no .MDL files found at this location." "R"
    }
    $items = foreach ($item in $listView.Items) {
        $item.Text
    }
    $searchBox.AutoCompleteCustomSource.AddRange($items)
    UpdateStatusFilesFound
    $listView.Add_ItemChecked({ UpdateStatusFilesChecked })
}

### PROCESS FILES
function ProcessFiles () {
    $fakeConsole.Text = ""
    $checkedItems = $listView.CheckedItems
    $doBackup = $backupMDLcheckbox.Checked
   
    $CrowbarCMDs = New-Object System.Collections.ArrayList
    $batchCrowbar = Join-Path -Path $scriptDirectory -ChildPath 'crowbar_.bat'

    $StudioCMDs = New-Object System.Collections.ArrayList
    $batchStudioMDL = Join-Path -Path $scriptDirectory -ChildPath 'studiomdl_.bat'

    $DeleteCMDs = New-Object System.Collections.ArrayList

    foreach ($item in $checkedItems) {
        $fullPath = Join-Path -Path $global:rootModels -ChildPath $item.SubItems[1].Text
        if ($doBackup) { 
            $qcPathBackup = $fullPath -replace '\.mdl$', '.mdl.bak'
            try {
                Copy-Item -Path $fullPath -Destination $qcPathBackup
                WriteConsole "[SUCCESS] Backup for $($item.SubItems[0].Text) created." "G"
            } catch {
                WriteConsole"[ERROR]: $_. Unable to create a backup for $($item.SubItems[0].Text)" "R"
            }
        }
        $CrowbarCMDs += "`"$crowbarExePath`" `"$fullPath`""
    }
    $CrowbarCMDs = $CrowbarCMDs | Sort-Object -Unique
    $CrowbarCMDs = $CrowbarCMDs -join "`r`n"
    $CrowbarCMDs = "cd `"$scriptDirectory`"`r`n" + $CrowbarCMDs
   
    $CrowbarCMDs | Set-Content -Path $batchCrowbar -Encoding ASCII
    #same: $CrowbarCMDs | Out-File -FilePath $batchCrowbar -Encoding ASCII

    if (Test-Path $batchCrowbar -PathType Leaf) {
        try {
            $output = Invoke-Expression "& `"$batchCrowbar`""
            WriteConsole "Decompiling model files..." "Y"
            WriteConsole($output -join "`r`n") 
            WriteConsole "Deleting Crowbar batch file..." "Y"
            Remove-Item -Path $batchCrowbar -Force
        } catch {
            WriteConsole "[ERROR] Executing the batch file $_ failed" "R"
        }
    } else {
        WriteConsole "[ERROR] Generated batch file not found at: $batchCrowbar" "R"
    }

### EDITING QC FILES
    WriteConsole "Now editing .QC files..." "Y"
    $pattern = '(?m)^(.*)\$modelname[\t ]+"(.+)\.mdl"'
    $studiomdlPath = $studioMDLPathTextbox.Text
    foreach ($item in $checkedItems) {
        $mdlPathsAbs = Join-Path -Path $global:rootModels -ChildPath $($item.SubItems[1].Text)
        $qcPath = [System.IO.Path]::ChangeExtension($mdlPathsAbs, ".qc")
        $qcName = [System.IO.Path]::GetFileName($qcPath)
        $qcNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($qcPath)
        $mdlFolder = [System.IO.Path]::GetDirectoryName($qcPath)

        if (Test-Path $qcPath -PathType Leaf) {
            
            $qcContent = Get-Content -Path $qcPath -Raw
              
                if ($qcContent -match $pattern) {
                    $replacement = '$modelname "' + $item.SubItems[1].Text + '"'
                    $qcContent = $qcContent -replace $pattern, $replacement
                               
                    try {
                        $qcContent | Set-Content -Path $qcPath -Force
                        WriteConsole "[SUCCESS] Updated `$modelname in $qcName" "G"

                        $StudioCMDs += "`"$studiomdlPath`" -nop4 -nox360 -fastbuild `"$qcPath`""
                    } catch {
                        WriteConsole "[ERROR] Failed to update $qcName : $_" "R"
                    }
              } else {
                    WriteConsole "[ERROR] No match found in $qcName" "R"
              }
        } else {
            WriteConsole "[ERROR] $qcPath is not a valid path" "R"
        }
		$DeleteCMDs += "Get-ChildItem `"$mdlFolder`" -Filter `"${qcNameNoExt}.qc`" | Remove-Item -Force"
		$DeleteCMDs += "Get-ChildItem `"$mdlFolder`" -Filter `"${qcNameNoExt}*.smd`" | Remove-Item -Force"
		$DeleteCMDs += "Get-ChildItem `"$mdlFolder`" -Filter `"${qcNameNoExt}_anims`" | Remove-Item -Force -Recurse"
    } 
### RECOMPILE
	WriteConsole "Recompiling models to .MDL files with StudioMDL.exe..." "Y"
    $StudioCMDs = $StudioCMDs -join "`r`n"
    $StudioCMDs = "cd `"$studiomdlPath`"`r`n" + $StudioCMDs
    $StudioCMDs | Set-Content -Path $batchStudioMDL -Encoding ASCII
    if (Test-Path $batchStudioMDL -PathType Leaf) {
        try {
            $output = Invoke-Expression "& `"$batchStudioMDL`""
            WriteConsole($output -join "`r`n") 
            WriteConsole "Deleting StudioMDL batch file..." "Y"
            Remove-Item -Path $batchStudioMDL -Force
        } catch {
            WriteConsole "[ERROR] Executing the batch file $_ failed" "R"
        }
    } else {
        WriteConsole "[ERROR] Unable to find generated batch file at: $batchStudioMDL" "R"
    }
### DELETE TEMP FILES
	WriteConsole "Deleting obsolete extracted files..." "Y"
	foreach ($command in $DeleteCMDs) {
		Invoke-Expression $command
	}
	WriteConsole "WORK DONE!" "G"
    $listView.Items.Clear()
    $relocateButton.Enabled = $false
}                                                      

# UI Creation
function New-UI {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Source 1 MDL Relocator"
    $form.Anchor = 'Left, Top, Right, Bottom'
    $form.Dock = [Windows.Forms.DockStyle]::Fill
    $form.ClientSize = New-Object Drawing.Size @(930, 700) 
	$form.FormBorderStyle = 'FixedSingle'
	$form.MaximizeBox = $false
    #$form.DoubleBuffeR = $true
    #$form.WindowState = [Windows.Forms.FormWindowState]::Maximized
    
# STATUS BAR
    $statusBar = New-Object Windows.Forms.StatusStrip
	$statusBar.ShowItemToolTips = $true
    $statusBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
	$statusBar.SizingGrip = $false
    $statusCol0 = New-Object Windows.Forms.ToolStripStatusLabel 
	$statusCol1 = New-Object Windows.Forms.ToolStripStatusLabel 
	$statusCol0.Text = "Pending..."
    $statusCol0.Width = 400
    $statusCol1.Width = 400
    $statusBar.Items.Add($statusCol0)
	$statusBar.Items.Add($statusCol1)
    $form.Controls.Add($statusBar)

# TEXTBOX : Browsed folder path
    $providedPathLabel = New-Object Windows.Forms.Label
    $providedPathLabel.Text = "Selected folder:"
    $providedPathLabel.Size = New-Object Drawing.Size @(170, 20)
    $providedPathLabel.Location = New-Object Drawing.Point 20, 20
    $form.Controls.Add($providedPathLabel)
    $providedPathTextbox = New-Object Windows.Forms.TextBox
    $providedPathTextbox.Size = New-Object Drawing.Size @(550, 20)
    $providedPathTextbox.Location = New-Object Drawing.Point 200, 20
    $providedPathTextbox.Text = ''
    $providedPathTextbox.ReadOnly = $true
    $providedPathTextbox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($providedPathTextbox)

# TEXTBOX : StudioMDL.exe path
    $studioMDLPathLabel = New-Object Windows.Forms.Label
    $studioMDLPathLabel.Text = "StudioMDL.exe:"
    $studioMDLPathLabel.Size = New-Object Drawing.Size @(170, 20)
    $studioMDLPathLabel.Location = New-Object Drawing.Point 20, 100
    $form.Controls.Add($studioMDLPathLabel)
    $studioMDLPathTextbox = New-Object Windows.Forms.TextBox
    $studioMDLPathTextbox.Size = New-Object Drawing.Size @(550, 20)
    $studioMDLPathTextbox.Location = New-Object Drawing.Point 200, 100
    $studioMDLPathTextbox.Text = ''
    $studioMDLPathTextbox.ReadOnly = $true
    $studioMDLPathTextbox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($studioMDLPathTextbox)

# BUTTON : Browse folder
    $browseButton = New-Object Windows.Forms.Button
    $browseButton.Size = New-Object Drawing.Size @(150, 30)
    $browseButton.Location = New-Object Drawing.Point ($providedPathTextbox.Right + 10), 20
    $browseButton.Text = "&Select a folder"
    $browseButton.UseMnemonic = $true
    $browseButton.Add_Click({
        if ($listView.Items.Count -gt 0) {
            $choice = [System.Windows.Forms.MessageBox]::Show("Starting a new search will remove the previously found files from the list.`n`nProceed?", "Attention!", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($choice -eq [System.Windows.Forms.DialogResult]::No) {
                return $false
            }
        }
        $listView.Items.Clear()
		$searchBox.AutoCompleteCustomSource.Clear()
        UpdateStatusFilesFound
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.SelectedPath = "C:\Program Files (x86)\Steam\steamapps\common\"
        if ($folderBrowser.ShowDialog() -eq 'OK') {
            Find-ModelFolder($folderBrowser.SelectedPath)        
        }
    })
    $form.Controls.Add($browseButton)

# TEXTBOX : Root models path
    $rootPathLabel = New-Object Windows.Forms.Label
    $rootPathLabel.Text = "Root models folder:"
    $rootPathLabel.Size = New-Object Drawing.Size @(170, 20)
    $rootPathLabel.Location = New-Object Drawing.Point 20, 60
    $form.Controls.Add($rootPathLabel)
    $rootModelsTextbox = New-Object Windows.Forms.TextBox
    $rootModelsTextbox.Size = New-Object Drawing.Size @(550, 20)
    $rootModelsTextbox.Location = New-Object Drawing.Point 200, 60
    $rootModelsTextbox.ReadOnly = $true
    $rootModelsTextbox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($rootModelsTextbox)

# TEXTBOX : Search box (autocomplete)
	$searchBoxLabel = New-Object Windows.Forms.Label
    $searchBoxLabel.Text = "Find a file in the list:"
	$searchBoxLabel.Size = New-Object Drawing.Size @(180,20)
	$searchBoxLabel.Location = New-Object System.Drawing.Size(20,465)
	$form.Controls.Add($searchBoxLabel)
	$searchBox = New-Object System.Windows.Forms.TextBox
	$searchBox.Location = New-Object System.Drawing.Size(210,460)
	$searchBox.Size = New-Object System.Drawing.Size(560,20)
    $searchBox.ReadOnly = $true
	$searchBox.AutoCompleteMode='SuggestAppend'
	$searchBox.AutoCompleteSource = 'CustomSource' 
	$searchBox.Add_TextChanged({
		$matchingItem = $listView.Items | Where-Object { $_.Text -eq $searchBox.Text }
		if ($matchingItem) {
			$listView.SelectedItems.Clear()
			$matchingItem.Selected = $true
            $matchingItem.EnsureVisible()
		}
	})
	$Form.Controls.Add($searchBox)
	
# LIST VIEW
    $listView = New-Object Windows.Forms.ListView
    $listView.Size = New-Object Drawing.Size @(750, 300)
    $listView.Location = New-Object Drawing.Point 20, 150
    $listView.View = 'Details'
    $listView.CheckBoxes = $true
    $listView.Columns.Add('File', 150)
    $listView.Columns.Add('$modelname new value', 300)
    $listView.AllowDrop = $true
	$listView.Add_DragEnter({
		param($sender, $e)
		if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
			$files = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
			$mdlFiles = $files | Where-Object { $_ -like "*.mdl" }
			if ($mdlFiles) {
				$listView.BackColor = [System.Drawing.Color]::FromArgb(0xFFDAF291)
				$e.Effect = [Windows.Forms.DragDropEffects]::Copy
			}
		}
    })
    $listView.Add_DragDrop({
        param($sender, $e)
        $files = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
        DragDropMDL($files)
        $listView.BackColor = [System.Drawing.Color]::FromArgb(0xFFFFFFFF)
		$e.Effect = [Windows.Forms.DragDropEffects]::None
    })
	$listView.Add_DragLeave({
		param($sender, $e)
		$listView.BackColor = [System.Drawing.Color]::FromArgb(0xFFFFFFFF)
		$e.Effect = [Windows.Forms.DragDropEffects]::None
	})
    $form.Controls.Add($listView)

# BUTTON : Select all items
    $selectAllButton = New-Object Windows.Forms.Button
    $selectAllButton.Text = " Select &All"
    $selectAllButton.UseMnemonic = $true
    $selectAllButton.Size = New-Object Drawing.Size @(130, 30)
    $selectAllButton.Location = New-Object Drawing.Point 780, 150
    $selectAllButton.Enabled = $false 
    $selectAllButton.Add_Click({ checkList($true) })
    $form.Controls.Add($selectAllButton)

# BUTTON : Select none items
    $selectNoneButton = New-Object Windows.Forms.Button
    $selectNoneButton.Text = " Select &None"
    $selectNoneButton.UseMnemonic = $true
    $selectNoneButton.Size = New-Object Drawing.Size @(130, 30)
    $selectNoneButton.Location = New-Object Drawing.Point 780, 185
    $selectNoneButton.Enabled = $false
    $selectNoneButton.Add_Click({ checkList($false) })
    $form.Controls.Add($selectNoneButton)

# CHECKBOX : Keep backup
    $backupMDLcheckbox = New-Object Windows.Forms.CheckBox
    $backupMDLcheckbox.Text = "&Backup my MDL files"
    $backupMDLcheckbox.UseMnemonic = $true
	$backupMDLcheckbox.AutoSize = $false
    $backupMDLcheckbox.AutoEllipsis = $true
    $backupMDLcheckbox.Size = New-Object Drawing.Size @(150, 50)
    $backupMDLcheckbox.Location = New-Object Drawing.Point 780, 290
    $form.Controls.Add($backupMDLcheckbox)

# CHECKBOX : Attune materials path
    <# Create "Change Materials" checkbox
    $changeMaterialscheckbox = New-Object Windows.Forms.CheckBox
    $changeMaterialscheckbox.Text = "Attune &texture path with model path"
    $changeMaterialscheckbox.UseMnemonic = $true
    $changeMaterialscheckbox.AutoSize = $false
    $changeMaterialscheckbox.AutoEllipsis = $true
    $changeMaterialscheckbox.Size = New-Object Drawing.Size @(150, 130)
    #$changeMaterialscheckbox.Location = New-Object Drawing.Point 780, 250
    $form.Controls.Add($changeMaterialscheckbox)
    #>

# BUTTON : Relocate MDL files
    $relocateButton = New-Object Windows.Forms.Button
    $relocateButton.Text = "&Relocate`nMDL files!"
    $relocateButton.UseMnemonic = $true
    $relocateButton.Size = New-Object Drawing.Size @(130, 60)
    $relocateButton.Location = New-Object Drawing.Point 780, 428
    $relocateButton.Enabled = $false
    $relocateButton.Add_Click({ ProcessFiles })
    $form.Controls.Add($relocateButton)

# RICH TEXTBOX : Fake Console
    $fakeConsole = New-Object Windows.Forms.RichTextBox
    $fakeConsole.Name = "fakeConsole"
    $fakeConsole.Multiline = $true
    $fakeConsole.ScrollBars = "Vertical"
    $fakeConsole.ReadOnly = $true
    $fakeConsole.WordWrap = $true
	$fakeConsole.Text = "Remember that :`r`n* MDL files can be dependencies of other MDL files.`r`n`* MDL files won't be at the same location if you share your maps.`r`nIf you're a modder or a mapper, don't forget to embed your custom resources in your .BSP file with BSPZIP for instance.`r`nIn any case, proceed with caution :)`r`n"
    $fakeConsole.Size = New-Object Drawing.Size @(890, 150)
    $fakeConsole.Location = New-Object Drawing.Point 20, 520
    $fakeConsole.BackColor = [System.Drawing.Color]::FromArgb(0xFF222222)
    $fakeConsole.ForeColor = [System.Drawing.Color]::FromArgb(0xFFEEEEEE)
    $form.Controls.Add($fakeConsole)

    foreach ($control in $form.Controls) {
        $control.Font = New-Object System.Drawing.Font("Verdana", 12)
    }
    $fakeConsole.Font = New-Object System.Drawing.Font("Consolas", 12)

# WINDOW POSITION CENTER
    $screen = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $formWidth = $form.Width
    $formHeight = $form.Height
    $x = ($screen.Width - $formWidth) / 2
    $y = ($screen.Height - $formHeight) / 2
    $form.StartPosition = 'Manual'
    $form.Location = [System.Drawing.Point]::new($x, $y)

    $form.ShowDialog() | Out-Null
}

New-UI
