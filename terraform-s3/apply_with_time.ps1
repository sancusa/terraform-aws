$startTime = Get-Date
Write-Host "Start time: $startTime"

terraform init
terraform apply -auto-approve

$endTime = Get-Date
Write-Host "End time: $endTime"

$duration = $endTime - $startTime
Write-Host "Script execution time: $($duration.ToString())"
