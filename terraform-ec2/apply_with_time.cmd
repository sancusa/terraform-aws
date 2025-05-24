@echo off
echo Start time: %date% %time%

terraform init
terraform apply -auto-approve

echo End time: %date% %time%
pause
